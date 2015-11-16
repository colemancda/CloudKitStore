//
//  Cacheable.swift
//  CloudKitStore
//
//  Created by Alsey Coleman Miller on 11/15/15.
//  Copyright © 2015 ColemanCDA. All rights reserved.
//

import Foundation
import CoreData
import CloudKit
import CoreDataStruct
import CloudKitStruct

/// Type can be cached with ```CloudKitStore```.
public protocol CloudKitCacheable {
    
    /// Fetches the cacheable type (if it exists) from the managed object context.
    ///
    /// - Note: No need to wrap calls to the context with ```-performWithBlock:```. 
    /// This method is assumed to be called from the context's queue.
    static func fetchFromCache(recordName: String, context: NSManagedObjectContext) throws -> NSManagedObject?
}
