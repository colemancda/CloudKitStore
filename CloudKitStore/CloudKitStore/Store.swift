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
    
    /// Fetches and caches records from the server with the specified identifiers.
    public func fetch <T where T: CloudKitCacheable, T: CloudKitDecodable, T: CoreDataEncodable> (recordID: RecordID, completionBlock: ErrorValue<T> -> () ) {
        
        let operation = CKFetchRecordsOperation(recordIDs: [recordID.toCloudKit()])
        
        operation.database = cloudDatabase
        
        operation.fetchRecordsCompletionBlock = { [weak self] (recordsByID, error) in
            
            guard let store = self else { return }
            
            guard error == nil else {
                
                /// 404 not found error
                if (error! as NSError).domain == CKErrorDomain &&
                    (error! as NSError).code == CKErrorCode.UnknownItem.rawValue {
                    
                    store.deleteCache(T.self, recordID: recordID)
                }
                
                completionBlock(.Error(error!))
                return
            }
            
            let record = recordsByID![recordID.toCloudKit()]!
            
            guard let cacheable = T(record: record) else {
                
                completionBlock(.Error(Error.CouldNotDecode))
                return
            }
            
            do { try store.privateQueue { try cacheable.save(store.privateQueueManagedObjectContext) } }
                
            catch { fatalError("Could not encode to CoreData. \(error)") }
            
            completionBlock(.Value(cacheable))
        }
        
        requestQueue.addOperation(operation)
    }
    
    public func create <T where T: CloudKitDecodable, T: CoreDataEncodable> (recordType: String, newID: NewID = .None, values: [String: CKRecordValue] = [:], completionBlock: ErrorValue<T> -> () ) {
        
        let newRecord: CKRecord
    
        switch newID {
            
        case .None: newRecord = CKRecord(recordType: recordType)
            
        case let .RecordID(recordID): newRecord = CKRecord(recordType: recordType, recordID: recordID.toCloudKit())
            
        case let .RecordZoneID(zoneID): newRecord = CKRecord(recordType: recordType, zoneID: zoneID.toCloudKit())
        }
        
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
            guard let resource = T(record: savedRecord) else {
                
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
    
    public func edit <T where T: CloudKitCacheable, T: CloudKitEncodable, T: CloudKitDecodable, T: CoreDataEncodable, T: CoreDataDecodable> (type: T.Type, recordID: RecordID, changes: [String: CKRecordValue], policy: CKRecordSavePolicy = .ChangedKeys, completionBlock: ErrorType? -> () ) {
        
        let operationQueue = requestQueue
        
        let database = cloudDatabase
        
        let fetchOperation = CKFetchRecordsOperation(recordIDs: [recordID.toCloudKit()])
        
        fetchOperation.database = database
        
        fetchOperation.desiredKeys = Array(changes.keys)
        
        fetchOperation.fetchRecordsCompletionBlock = { [weak self] (recordsByID, error) in
            
            guard let store = self else { return }
            
            guard error == nil else {
                
                /// 404 not found error
                if (error! as NSError).domain == CKErrorDomain &&
                    (error! as NSError).code == CKErrorCode.UnknownItem.rawValue {
                        
                        store.deleteCache(T.self, recordID: recordID)
                }
                
                completionBlock(error!)
                return
            }
            
            let record = recordsByID![recordID.toCloudKit()]!
            
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
                            
                            store.deleteCache(T.self, recordID: recordID)
                    }
                    
                    completionBlock(error!)
                    
                    return
                }
                
                // already cached, update values
                do {
                    if let managedObject = try T.fetchFromCache(recordID, context: store.privateQueueManagedObjectContext) {
                        
                        let decoded = T(managedObject: managedObject)
                        
                        let cachedCloudKitRecord = decoded.toCloudKit()
                        
                        // set new values
                        for (key, value) in changes {
                            
                            cachedCloudKitRecord[key] = value
                        }
                        
                        guard let resource = T(record: cachedCloudKitRecord) else {
                            
                            completionBlock(Error.CouldNotDecode)
                            return
                        }
                        
                        try store.privateQueue { try resource.save(store.privateQueueManagedObjectContext) }
                    }
                }
                    
                catch { fatalError("Could not update CoreData cache. \(error)") }
                
                completionBlock(nil)
            }
            
            operationQueue.addOperation(saveOperation)
        }
        
        operationQueue.addOperation(fetchOperation)
    }
    
    public func delete<T: CloudKitCacheable>(type: T.Type, recordID: RecordID, completionBlock: ErrorType? -> () ) {
        
        let operation = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: [recordID.toCloudKit()])
        
        operation.database = cloudDatabase
        
        operation.modifyRecordsCompletionBlock = { [weak self] (savedRecords, deletedRecordIDs, error) in
            
            guard let store = self else { return }
            
            guard error == nil else {
                
                /// 404 not found error
                if (error! as NSError).domain == CKErrorDomain &&
                    (error! as NSError).code == CKErrorCode.UnknownItem.rawValue {
                        
                        store.deleteCache(T.self, recordID: recordID)
                }
                
                completionBlock(error)
                return
            }
            
            // delete from cache
            store.deleteCache(type, recordID: recordID)
        }
        
        requestQueue.addOperation(operation)
    }
    
    public func search<T where T: CloudKitDecodable, T: CoreDataEncodable>
        (type: T.Type, queryType: QueryType, resultsLimit: Int? = nil, zoneID: RecordZoneID? = nil, completionBlock: ErrorValue<([T], CKQueryCursor?)> -> () ) {
        
        let operation: CKQueryOperation
        
        switch queryType {
            
        case let .Query(query): operation = CKQueryOperation(query: query)
        case let .Cursor(cursor): operation = CKQueryOperation(cursor: cursor)
        }
        
        if let limit = resultsLimit {
            
            operation.resultsLimit = limit
        }
        
        operation.zoneID = zoneID?.toCloudKit()
        
        var results = [T]()
        
        var decodeError = false
        
        operation.recordFetchedBlock = { [weak self] (record) in
            
            guard let store = self where decodeError == false else { return }
            
            // decode
            guard let resource = T(record: record) else {
                
                decodeError = true
                
                completionBlock(.Error(Error.CouldNotDecode))
                return
            }
            
            // cache
            do { try store.privateQueue { try resource.save(store.privateQueueManagedObjectContext) } }
                
            catch { fatalError("Could not encode to CoreData. \(error)") }
            
            results.append(resource)
        }
        
        operation.queryCompletionBlock = { [weak self] (cursor, error) in
            
            guard let _ = self where decodeError == false else { return }
            
            guard error == nil else {
                
                completionBlock(.Error(error!))
                return
            }
            
            let value = (results, cursor)
            
            completionBlock(.Value(value))
        }
        
        requestQueue.addOperation(operation)
    }
    
    // MARK: - Private Methods
    
    private func privateQueue(block: () throws -> ()) throws {
        
        try self.privateQueueManagedObjectContext.performErrorBlockAndWait(block)
    }
    
    private func deleteCache<T: CloudKitCacheable>(type: T.Type, recordID: RecordID) {
        
        do {
            
            try self.privateQueue {
                
                if let managedObject = try T.fetchFromCache(recordID, context: self.privateQueueManagedObjectContext) {
                
                self.privateQueueManagedObjectContext.deleteObject(managedObject)
                
                try self.privateQueueManagedObjectContext.save()
                    
                }
            }
        }
            
        catch { fatalError("Could not delete from CoreData. \(error)") }
    }
}

// MARK: - Supporting Types

public extension CloudKitStore {
    
    /// CloudKit query type.
    public enum QueryType {
        
        case Query(CKQuery)
        
        case Cursor(CKQueryCursor)
    }
    
    /// CloudKit new record identifier option
    public enum NewID {
        
        case None
        case RecordID(RecordIDValue)
        case RecordZoneID(RecordZoneIDValue)
    }
}

/// Basic wrapper for error / value pairs.
public enum ErrorValue<T> {
    
    case Error(ErrorType)
    case Value(T)
}

// MARK: - Typealiases

// Fixes compiler error with associated values in enums

public typealias RecordIDValue = RecordID

public typealias RecordZoneIDValue = RecordZoneID



