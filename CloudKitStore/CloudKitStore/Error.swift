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
        
        /// The server returned an invalid response.
        case InvalidServerResponse
    }
}