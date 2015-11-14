//
//  CloudKitValue.swift
//  CloudKitStore
//
//  Created by Alsey Coleman Miller on 11/14/15.
//  Copyright © 2015 ColemanCDA. All rights reserved.
//

import Foundation
import CloudKit
import CoreLocation

/// The type of values CloudKit can store.
public enum CloudKitValue {
    
    case Date(NSDate)
    case Number(NSNumber)
    case Data(NSData)
    case String(NSString)
    case Location(CLLocation)
    case Reference(CKReference)
    case Asset(CKAsset)
    
    case DateList
}