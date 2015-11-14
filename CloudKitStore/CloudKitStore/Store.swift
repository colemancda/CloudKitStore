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
    
    /** The managed object context used for caching. */
    public let managedObjectContext: NSManagedObjectContext
    
    /** A convenience variable for the managed object model. */
    public let managedObjectModel: NSManagedObjectModel
    
    /** The name of the string attribute that holds that resource identifier. */
    public let resourceIDAttributeName: String
    
    /// The name of a for the date attribute that can be optionally added at runtime for cache validation.
    public let dateCachedAttributeName: String?
    
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
    
    /// Creates the Store using the specified options.
    ///
    /// - Note: The created ```NSManagedObjectContext``` will need a persistent store added
    /// to its persistent store coordinator.
    public init(managedObjectModel: NSManagedObjectModel, concurrencyType: NSManagedObjectContextConcurrencyType = .MainQueueConcurrencyType,
        resourceIDAttributeName: String = "id",
        dateCachedAttributeName: String? = "dateCached") {
            
            self.resourceIDAttributeName = resourceIDAttributeName
            self.dateCachedAttributeName = dateCachedAttributeName
            self.managedObjectModel = managedObjectModel.copy() as! NSManagedObjectModel
            
            // setup Core Data stack
            
            // edit model
            
            if self.dateCachedAttributeName != nil {
                
                self.managedObjectModel.addDateCachedAttribute(dateCachedAttributeName!)
            }
            
            self.managedObjectModel.markAllPropertiesAsOptional()
            self.managedObjectModel.addResourceIDAttribute(resourceIDAttributeName)
            
            // setup managed object contexts
            
            self.managedObjectContext = NSManagedObjectContext(concurrencyType: concurrencyType)
            self.managedObjectContext.undoManager = nil
            self.managedObjectContext.persistentStoreCoordinator = NSPersistentStoreCoordinator(managedObjectModel: self.managedObjectModel)
            
            self.privateQueueManagedObjectContext.undoManager = nil
            self.privateQueueManagedObjectContext.persistentStoreCoordinator = self.managedObjectContext.persistentStoreCoordinator
            
            // set private context name
            self.privateQueueManagedObjectContext.name = "CloudKitStore Private Managed Object Context"
            
            // listen for notifications (for merging changes)
            NSNotificationCenter.defaultCenter().addObserver(self, selector: "mergeChangesFromContextDidSaveNotification:", name: NSManagedObjectContextDidSaveNotification, object: self.privateQueueManagedObjectContext)
    }
    
    // MARK: - Methods
    
    /// Fetches the a record from the server with the specified identifier.
    public func fetch<T where T: CloudKitDecodable, T: CoreDataEncodable>(identifier: String, completionBlock: (ErrorValue<T> -> ())) {
        
        let recordID: CKRecordID
        
        if let zoneID = zoneID {
            
            recordID = CKRecordID(recordName: identifier, zoneID: zoneID)
        }
        else { recordID = CKRecordID(recordName: identifier) }
        
        let operation = CKFetchRecordsOperation(recordIDs: [recordID])
        
        operation.database = cloudDatabase
        
        operation.fetchRecordsCompletionBlock = { (records, error) in
            
            guard error == nil else {
                
                completionBlock(.Error(error!))
                
                return
            }
            
            let record = records![recordID]
            
            guard let decodable = T(record: record!) else {
                
                completionBlock(.Error(Error.InvalidResponse))
                
                return
            }
            
            do {
                
                try self.privateQueueManagedObjectContext.performErrorBlockAndWait {
                    
                    try decodable.save(self.privateQueueManagedObjectContext)
                }
            }
                
            catch { fatalError("Could not encode to CoreData. \(error)") }
            
            completionBlock(.Value(decodable))
        }
        
        requestQueue.addOperation(operation)
    }
    
    public func save<T where T: CloudKitEncodable, T: CoreDataEncodable>(encodable: T, completionBlock: (ErrorType? -> ())) {
        
        let record = encodable.toRecord()
        
        self.cloudDatabase.saveRecord(record) { (record, error) in
            
            guard error == nil else {
                
                completionBlock(error)
                
                return
            }
            
            do {
                
                try self.privateQueueManagedObjectContext.performErrorBlockAndWait {
                    
                    try encodable.save(self.privateQueueManagedObjectContext)
                }
            }
                
            catch { fatalError("Could not encode to CoreData. \(error)") }
            
            completionBlock(nil)
        }
    }
    
    public func edit(identifier: String, changes: ValuesObject, completionBlock: (ErrorType? -> ())) {
        
        
    }
    
    public func delete(identifier: String, completionBlock: (ErrorType? -> ())) {
        
        let recordID: CKRecordID
        
        if let zoneID = zoneID {
            
            recordID = CKRecordID(recordName: identifier, zoneID: zoneID)
        }
        else { recordID = CKRecordID(recordName: identifier) }
        
        self.cloudDatabase.deleteRecordWithID(recordID) { (recordID, error) in
            
            
        }
    }
}

// MARK: - Supporting Types

/** Basic wrapper for error / value pairs. */
public enum ErrorValue<T> {
    
    case Error(ErrorType)
    case Value(T)
}


