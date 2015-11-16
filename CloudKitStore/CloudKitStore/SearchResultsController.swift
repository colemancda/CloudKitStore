//
//  SearchResultsController.swift
//  CloudKitStore
//
//  Created by Alsey Coleman Miller on 11/15/15.
//  Copyright © 2015 ColemanCDA. All rights reserved.
//

import Foundation
import UIKit
import CoreData
import CloudKit
import CoreDataStruct
import CloudKitStruct

/// Executes a search request on the server and delegates the results,
/// merges with local cache to the delegate for display in the UI.
///
/// - Note: Does not support sections.
///
public final class SearchResultsController<T where T: CloudKitDecodable, T: CoreDataEncodable> {
    
    // MARK: - Properties
    
    /// Store that will execute and cache the search request.
    public let store: CloudKitStore
    
    /// The search controller's delegate.
    public var event = SearchResultsControllerEvent()
    
    /// The cached search results.
    public private(set) var searchResults = [T]()
    
    // MARK: Query
    
    @NSCopying public private(set) var query: CKQuery
    
    @NSCopying public private(set) var fetchRequest: NSFetchRequest
    
    // MARK: - Private Properties
    
    /// Internal fetched results controller.
    private let fetchedResultsController: NSFetchedResultsController!
    
    private lazy var fetchedResultsControllerDelegate: FetchedResultsControllerDelegateWrapper = FetchedResultsControllerDelegateWrapper(delegate: self)
    
    // MARK: - Initialization
    
    public init(query: CKQuery, fetchRequest: NSFetchRequest, store: CloudKitStore) {
        
        self.query = query
        self.fetchRequest = fetchRequest
        self.store = store
        
    }
    
    // MARK: - Methods
    
    public func performFetch() throws {
    
        try self.fetchedResultsController.performFetch()
    }
    
    /// Fetches search results from server.
    @IBAction public func performSearch(sender: AnyObject? = nil) {
        
        
    }
}

// MARK: - Supporting Types

public struct SearchResultsControllerEvent {
    
    // Request Callback
    
    /// Informs the delegate that a search request has completed with the specified error (if any).
    public var didPerformSearch: ((error: ErrorType?) -> ()) = { (error) in }
    
    // Change Notification Callbacks
    
    public var willChangeContent: (() -> ()) = { }
    
    public var didChangeContent: (() -> ()) = { }
    
    public var didInsert: ((index: Int) -> ()) = { (index) in }
    
    public var didDelete: ((index: Int) -> ()) = { (index) in }
    
    public var didUpdate: ((index: Int, error: ErrorType?) -> ()) = { (index, error) in }
    
    public var didMove: ((index: Int, newIndex: Int) -> ()) = { (index, newIndex) in }
    
    private init() { }
}

// MARK: - Private



