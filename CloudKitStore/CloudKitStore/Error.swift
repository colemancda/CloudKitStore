//
//  Error.swift
//  CloudKitStore
//
//  Created by Alsey Coleman Miller on 11/14/15.
//  Copyright © 2015 ColemanCDA. All rights reserved.
//

public extension CloudKitStore {
    
    /// Errors returned with ```CloudKitStore```.
    public enum Error: ErrorType {
        
        /// Could not decode with the provided values. Similar to Invalid Server Response.
        case CouldNotDecode
    }
}