//
//  CoreDataExtensions.swift
//  CloudKitStore
//
//  Created by Alsey Coleman Miller on 11/14/15.
//  Copyright © 2015 ColemanCDA. All rights reserved.
//

import Foundation
import CoreData

public extension NSManagedObjectContext {
    
    /// Wraps the block to allow for error throwing.
    @available(OSX 10.7, *)
    func performErrorBlockAndWait(block: () throws -> Void) throws {
        
        var blockError: ErrorType?
        
        self.performBlockAndWait { () -> Void in
            
            do {
                try block()
            }
            catch {
                
                blockError = error
            }
        }
        
        if blockError != nil {
            
            throw blockError!
        }
        
        return
    }
}

public extension NSManagedObject {
    
    /// Get an array from a to-many relationship.
    func arrayValueForToManyRelationship(relationship key: String) -> [NSManagedObject]? {
        
        // assert relationship exists
        assert(self.entity.relationshipsByName[key] != nil, "Relationship \(key) doesnt exist on \(self.entity.name)")
        
        // get relationship
        let relationship = self.entity.relationshipsByName[key]!
        
        // assert that relationship is to-many
        assert(relationship.toMany, "Relationship \(key) on \(self.entity.name) is not to-many")
        
        let value: AnyObject? = self.valueForKey(key)
        
        if value == nil {
            
            return nil
        }
        
        // ordered set
        if relationship.ordered {
            
            let orderedSet = value as! NSOrderedSet
            
            return orderedSet.array as? [NSManagedObject]
        }
        
        // set
        let set = value as! NSSet
        
        return set.allObjects as? [NSManagedObject]
    }
    
    /// Wraps the ```-valueForKey:``` method in the context's queue.
    func valueForKey(key: String, managedObjectContext: NSManagedObjectContext) -> AnyObject? {
        
        var value: AnyObject?
        
        managedObjectContext.performBlockAndWait { () -> Void in
            
            value = self.valueForKey(key)
        }
        
        return value
    }
}

public extension NSManagedObjectModel {
    
    /// Programatically adds a unique resource identifier attribute to each entity in the managed object model.
    func addResourceIDAttribute(resourceIDAttributeName: String) {
        
        // add a resourceID attribute to managed object model
        for (_, entity) in self.entitiesByName {
            
            if entity.superentity == nil {
                
                // create new (runtime) attribute
                let resourceIDAttribute = NSAttributeDescription()
                resourceIDAttribute.attributeType = NSAttributeType.StringAttributeType
                resourceIDAttribute.name = resourceIDAttributeName
                resourceIDAttribute.optional = false
                
                // add to entity
                entity.properties.append(resourceIDAttribute)
            }
        }
    }
    
    /// Programatically adds a date attribute to each entity in the managed object model.
    func addDateCachedAttribute(dateCachedAttributeName: String) {
        
        // add a date attribute to managed object model
        for (_, entity) in self.entitiesByName as [String: NSEntityDescription] {
            
            if entity.superentity == nil {
                
                // create new (runtime) attribute
                let dateAttribute = NSAttributeDescription()
                dateAttribute.attributeType = NSAttributeType.DateAttributeType
                dateAttribute.name = dateCachedAttributeName
                
                // add to entity
                entity.properties.append(dateAttribute)
            }
        }
    }
    
    /// Marks all properties as optional.
    func markAllPropertiesAsOptional() {
        
        // add a date attribute to managed object model
        for (_, entity) in self.entitiesByName as [String: NSEntityDescription] {
            
            for (_, property) in entity.propertiesByName as [String: NSPropertyDescription] {
                
                property.optional = true
            }
        }
    }
}

