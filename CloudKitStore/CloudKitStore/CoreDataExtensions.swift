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

