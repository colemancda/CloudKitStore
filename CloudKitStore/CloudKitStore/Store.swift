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
    
    /** The managed object context used for caching. */
    public let managedObjectContext: NSManagedObjectContext
    
    /** A convenience variable for the managed object model. */
    public let managedObjectModel: NSManagedObjectModel
    
    /** The name of the string attribute that holds that resource identifier. */
    public let resourceIDAttributeName: String
    
    /// The name of a for the date attribute that can be optionally added at runtime for cache validation.
    public let dateCachedAttributeName: String?
    
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
    
    /** Fetches the entity from the server using the specified ```entityName``` and ```resourceID```. */
    public func fetch<T where T: CloudKitDecodable, T: CoreDataEncodable>(entityName: String, identifier: String, completionBlock: (ErrorValue<T> -> ()) {
        
        guard let entity = self.managedObjectModel.entitiesByName[resource.entityName]
            else { fatalError("Entity \(resource.entityName) not found on managed object model") }
        
        let recordID = CKrecor
    }
}


// MARK: - Supporting Types



