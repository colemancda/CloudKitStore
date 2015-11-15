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

/// Fetches CloudKit data and caches the response in CoreData models.
public final class CloudKitStore {
    
    // MARK: - Properties
    
    // MARK: Cache
    
    /// The managed object context used for caching.
    public let managedObjectContext: NSManagedObjectContext
    
    /// Whether to treat ```CoreData``` errors as fatal errors, or to throw them.
    public var throwCoreDataError = false
    
    // MARK: CloudKit
    
    /// The CloudKit database this class with connect to.
    public var cloudDatabase: CKDatabase = CKContainer.defaultContainer().publicCloudDatabase
    
    public var zoneID: CKRecordZoneID?
    
    // MARK: - Private Properties
    
    /** The managed object context running on a background thread for asyncronous caching. */
    private let privateQueueManagedObjectContext: NSManagedObjectContext = NSManagedObjectContext(concurrencyType: NSManagedObjectContextConcurrencyType.PrivateQueueConcurrencyType)
    
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
    public func fetch<T where T: CloudKitDecodable, T: CoreDataEncodable>(identifiers: [String], completionBlock: ErrorValue<[T]> -> () ) {
        
        let recordIDs = identifiers.map { (identifier) -> CKRecordID in
            
            let recordID: CKRecordID
            
            if let zoneID = zoneID {
                
                recordID = CKRecordID(recordName: identifier, zoneID: zoneID)
            }
            else { recordID = CKRecordID(recordName: identifier) }
            
            return recordID
        }
        
        let operation = CKFetchRecordsOperation(recordIDs: recordIDs)
        
        operation.database = cloudDatabase
        
        operation.fetchRecordsCompletionBlock = { [weak self] (recordsByID, error) in
            
            guard let store = self else { return }
            
            guard error == nil else {
                
                /// 404 not found error
                if (error! as NSError).domain == CKErrorDomain &&
                    (error! as NSError).code == CKErrorCode.UnknownItem.rawValue {
                    
                        do { try store.privateQueueManagedObjectContext }
                        
                        catch { fatalError("Could save to CoreData. \(error)") }
                }
                
                completionBlock(.Error(error!))
                
                return
            }
            
            let records = recordsByID!.map { (key, value) -> CKRecord in return value }
            
            guard let decodables = T.fromCloudKit(records) else {
                
                completionBlock(.Error(Error.InvalidServerResponse))
                
                return
            }
            
            do { try store.privateQueue { try decodables.save(store.privateQueueManagedObjectContext) } }
                
            catch { fatalError("Could not encode to CoreData. \(error)") }
            
            completionBlock(.Value(decodables))
        }
        
        requestQueue.addOperation(operation)
    }
    
    public func save<T where T: CloudKitEncodable, T: CoreDataEncodable>(encodable: T, completionBlock: (ErrorType? -> ())) {
        
        let record = encodable.toRecord()
        
        self.cloudDatabase.saveRecord(record) { [weak self] (record, error) in
            
            guard let store = self else { return }
            
            guard error == nil else {
                
                completionBlock(error)
                
                return
            }
            
            do { try store.privateQueue { try encodable.save(store.privateQueueManagedObjectContext) } }
                
            catch { fatalError("Could not encode to CoreData. \(error)") }
            
            completionBlock(nil)
        }
    }
    
    //public func edit(identifier: String, changes: ValuesObject, completionBlock: (ErrorType? -> ())) {
        
        
    
    
    public func delete(identifier: String, completionBlock: ErrorType? -> ()) {
        
        let recordID: CKRecordID
        
        if let zoneID = zoneID {
            
            recordID = CKRecordID(recordName: identifier, zoneID: zoneID)
        }
        else { recordID = CKRecordID(recordName: identifier) }
        
        let operation = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: [recordID])
        
        operation.database = cloudDatabase
        
        operation.modifyRecordsCompletionBlock = { (savedRecords, deletedRecords, error) in
            
            guard error == nil else {
                
                completionBlock(error)
                
                return
            }
            
            // delete from cache
            
        }
        
        requestQueue.addOperation(operation)
    }
    
    // MARK: - Private Methods
    
    private func privateQueue(block: () throws -> ()) throws {
        
        try self.privateQueueManagedObjectContext.performErrorBlockAndWait(block)
    }
    
    private func CoreDataQueue(block: () throws -> ()) throws {
        
        if throwCoreDataError {
            
            try block()
        }
        else {
            
            do { try block() }
            
            catch { fatalError("Core Data error: \(error)") }
        }
    }
}

// MARK: - Supporting Types

/** Basic wrapper for error / value pairs. */
public enum ErrorValue<T> {
    
    case Error(ErrorType)
    case Value(T)
}


