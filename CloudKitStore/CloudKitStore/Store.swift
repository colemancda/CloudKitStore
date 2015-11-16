//
//  Store.swift
//  CloudKitStore
//
//  Created by Alsey Coleman Miller on 11/13/15.
//  Copyright © 2015 ColemanCDA. All rights reserved.
//

import Foundation
import CoreData
import CloudKit
import CoreDataStruct
import CloudKitStruct

/// Fetches ```CloudKit``` data and caches the response in ```CoreData```.
public final class CloudKitStore {
    
    // MARK: - Properties
    
    // MARK: Cache
    
    /// The managed object context used for caching.
    public let managedObjectContext: NSManagedObjectContext
    
    // MARK: CloudKit
    
    /// The CloudKit database this class with connect to.
    public var cloudDatabase: CKDatabase = CKContainer.defaultContainer().publicCloudDatabase
    
    // MARK: State
    
    public var busy: Bool { return requestQueue.operationCount > 0 }
    
    // MARK: - Private Properties
    
    /** The managed object context running on a background thread for asyncronous caching. */
    private let privateQueueManagedObjectContext = NSManagedObjectContext(concurrencyType: NSManagedObjectContextConcurrencyType.PrivateQueueConcurrencyType)
    
    /// Request queue
    private let requestQueue: NSOperationQueue = {
        
        let queue = NSOperationQueue()
        
        queue.name = "CloudKitStore Request Queue"
        
        return queue
    }()
    
    // MARK: - Initialization
    
    deinit {
        // stop recieving 'didSave' notifications from private context
        NSNotificationCenter.defaultCenter().removeObserver(self, name: NSManagedObjectContextDidSaveNotification, object: self.privateQueueManagedObjectContext)
    }
    
    /// Creates the store using the specified options.
    ///
    /// - Precondition: The provided ```NSManagedObjectContext``` should have its persistent store coordinator configured.
    public init(context: NSManagedObjectContext) {
        
        guard let persistentStoreCoordinator = context.persistentStoreCoordinator
            else { fatalError("Provided managed object context should have its persistent store coordinator setup") }
        
            // setup managed object contexts
            self.managedObjectContext = context
            self.managedObjectContext.undoManager = nil
            
            self.privateQueueManagedObjectContext.undoManager = nil
            self.privateQueueManagedObjectContext.persistentStoreCoordinator = persistentStoreCoordinator
            
            // set private context name
            self.privateQueueManagedObjectContext.name = "CloudKitStore Private Managed Object Context"
            
            // listen for notifications (for merging changes)
            NSNotificationCenter.defaultCenter().addObserver(self, selector: "mergeChangesFromContextDidSaveNotification:", name: NSManagedObjectContextDidSaveNotification, object: self.privateQueueManagedObjectContext)
    }
    
    // MARK: - Methods
    
    public func fetch<T where T: CloudKitCacheable, T: CloudKitDecodable, T: CoreDataEncodable>(cacheable: T, completionBlock: ErrorValue<T> -> () ) {
        
        self.fetch(cacheable.identifier, completionBlock: completionBlock)
    }
    
    /// Fetches and caches records from the server with the specified identifiers.
    public func fetch<T where T: CloudKitCacheable, T: CloudKitDecodable, T: CoreDataEncodable>(identifier: T.Identifier, completionBlock: ErrorValue<T> -> () ) {
        
        let recordID = identifier.toRecordID()
        
        let operation = CKFetchRecordsOperation(recordIDs: [recordID])
        
        operation.database = cloudDatabase
        
        operation.fetchRecordsCompletionBlock = { [weak self] (recordsByID, error) in
            
            guard let store = self else { return }
            
            guard error == nil else {
                
                /// 404 not found error
                if (error! as NSError).domain == CKErrorDomain &&
                    (error! as NSError).code == CKErrorCode.UnknownItem.rawValue {
                    
                    store.deleteCacheWithIdentifier(T.self, identifier: identifier)
                }
                
                completionBlock(.Error(error!))
                
                return
            }
            
            let record = recordsByID![recordID]!
            
            guard let cacheable = T.init(recordID: record.recordID, values: record.toCloudKitValues()) else {
                
                completionBlock(.Error(Error.CouldNotDecode))
                
                return
            }
            
            do { try store.privateQueue { try cacheable.save(store.privateQueueManagedObjectContext) } }
                
            catch { fatalError("Could not encode to CoreData. \(error)") }
            
            completionBlock(.Value(cacheable))
        }
        
        requestQueue.addOperation(operation)
    }
    
    public func create<T where T: CloudKitDecodable, T: CoreDataEncodable>(recordType: String, identifier: CloudKitIdentifier? = nil, values: [String: CKRecordValue] = [:], completionBlock: ErrorValue<T> -> () ) {
        
        let newRecord: CKRecord
        
        if let identifier = identifier {
            
            newRecord = CKRecord(recordType: recordType, recordID: identifier.toRecordID())
        }
        else { newRecord = CKRecord(recordType: recordType) }
        
        /// set values
        for (key, value) in values {
            
            newRecord[key] = value
        }
        
        let operation = CKModifyRecordsOperation(recordsToSave: [newRecord], recordIDsToDelete: nil)
        
        operation.database = cloudDatabase
        
        operation.modifyRecordsCompletionBlock = { [weak self] (savedRecords, deletedRecordIDs, error) in
            
            guard let store = self else { return }
            
            guard error == nil else {
                
                completionBlock(.Error(error!))
                
                return
            }
            
            let savedRecord = savedRecords!.first!
            
            /// could not decode (invalid input values)
            guard let resource = T(recordID: savedRecord.recordID, values: values) else {
                
                completionBlock(.Error(Error.CouldNotDecode))
                
                return
            }
            
            // cache
            do { try store.privateQueue { try resource.save(store.privateQueueManagedObjectContext) } }
                
            catch { fatalError("Could not encode to CoreData. \(error)") }
            
            completionBlock(.Value(resource))
        }

        requestQueue.addOperation(operation)
    }
    
    public func edit<T where T: CloudKitCacheable, T: CloudKitEncodable, T: CloudKitDecodable, T: CoreDataEncodable, T: CoreDataDecodable>(type: T.Type, identifier: T.Identifier, changes: [String: CKRecordValue], policy: CKRecordSavePolicy = .ChangedKeys, completionBlock: (ErrorType? -> ())) {
        
        let operationQueue = requestQueue
        
        let recordID = identifier.toRecordID()
        
        let database = cloudDatabase
        
        let fetchOperation = CKFetchRecordsOperation(recordIDs: [recordID])
        
        fetchOperation.database = database
        
        fetchOperation.desiredKeys = Array(changes.keys)
        
        fetchOperation.fetchRecordsCompletionBlock = { [weak self] (recordsByID, error) in
            
            guard let store = self else { return }
            
            guard error == nil else {
                
                /// 404 not found error
                if (error! as NSError).domain == CKErrorDomain &&
                    (error! as NSError).code == CKErrorCode.UnknownItem.rawValue {
                        
                        store.deleteCacheWithIdentifier(T.self, identifier: identifier)
                }
                
                completionBlock(error!)
                
                return
            }
            
            let record = recordsByID![recordID]!
            
            // set values
            for (key, value) in changes {
                
                record[key] = value
            }
            
            // save changes
            let saveOperation = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
            
            saveOperation.savePolicy = policy
            
            saveOperation.modifyRecordsCompletionBlock = { (savedRecords, deletedRecords, error) in
                
                guard error == nil else {
                    
                    /// 404 not found error
                    if (error! as NSError).domain == CKErrorDomain &&
                        (error! as NSError).code == CKErrorCode.UnknownItem.rawValue {
                            
                            store.deleteCacheWithIdentifier(T.self, identifier: identifier)
                    }
                    
                    completionBlock(error!)
                    
                    return
                }
                
                // already cached, update values
                do {
                    if let managedObject = try T.fetchFromCache(identifier, context: store.privateQueueManagedObjectContext) {
                        
                        let decoded = T(managedObject: managedObject)
                        
                        let currentValues = decoded.toCloudKitValues()
                        
                        var newValues = currentValues
                        
                        // set values
                        for (key, value) in changes {
                            
                            newValues[key] = value
                        }
                        
                        guard let encodable = T(recordID: record.recordID, values: newValues) else {
                            
                            completionBlock(Error.CouldNotDecode)
                            
                            return
                        }
                        
                        try store.privateQueue { try encodable.save(store.privateQueueManagedObjectContext) }
                    }
                }
                    
                catch { fatalError("Could not update CoreData cache. \(error)") }
                
                completionBlock(nil)
            }
            
            operationQueue.addOperation(saveOperation)
        }
        
        operationQueue.addOperation(fetchOperation)
    }
    
    public func delete<T: CloudKitCacheable>(type: T.Type, identifier: T.Identifier, completionBlock: ErrorType? -> ()) {
        
        let recordID = identifier.toRecordID()
        
        let operation = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: [recordID])
        
        operation.database = cloudDatabase
        
        operation.modifyRecordsCompletionBlock = { [weak self] (savedRecords, deletedRecordIDs, error) in
            
            guard let store = self else { return }
            
            guard error == nil else {
                
                completionBlock(error)
                
                return
            }
            
            // delete from cache
            store.deleteCacheWithIdentifier(type, identifier: identifier)
        }
        
        requestQueue.addOperation(operation)
    }
    
    // MARK: - Private Methods
    
    private func privateQueue(block: () throws -> ()) throws {
        
        try self.privateQueueManagedObjectContext.performErrorBlockAndWait(block)
    }
    
    private func deleteCacheWithIdentifier<T: CloudKitCacheable>(type: T.Type, identifier: T.Identifier) {
        
        do {
            
            try self.privateQueue {
                
                if let managedObject = try T.fetchFromCache(identifier, context: self.privateQueueManagedObjectContext) {
                
                self.privateQueueManagedObjectContext.deleteObject(managedObject)
                
                try self.privateQueueManagedObjectContext.save()
                    
                }
            }
        }
            
        catch { fatalError("Could not delete from CoreData. \(error)") }
    }
}

// MARK: - Supporting Types

/** Basic wrapper for error / value pairs. */
public enum ErrorValue<T> {
    
    case Error(ErrorType)
    case Value(T)
}


