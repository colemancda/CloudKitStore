//
//  QueryResultsController.swift
//  CloudKitStore
//
//  Created by Alsey Coleman Miller on 11/22/15.
//  Copyright © 2015 ColemanCDA. All rights reserved.
//

import Foundation
import CloudKit
import CloudKitStruct
import CoreData
import CoreDataStruct

/// Controller for CloudKit queries.
public final class QueryResultsController<T where T: CloudKitDecodable, T: CoreDataEncodable, T: CoreDataDecodable> {
    
    // MARK: - Properties
    
    @NSCopying public private(set) var query: CKQuery
    
    @NSCopying public private(set) var fetchRequest: NSFetchRequest
    
    public let store: CloudKitStore
    
    public var queryResultsLimit: Int?
    
    public var zoneID: RecordZoneID?
    
    /// The cached search results.
    public private(set) var searchResults = [NSManagedObject]()
    
    public private(set) var state = QueryResultsControllerState()
    
    public var event = QueryResultsControllerEvent<T>()
    
    // MARK: - Private Properties
    
    private var queryCursor: CKQueryCursor?
    
    /// Internal fetched results controller.
    private let fetchedResultsController: NSFetchedResultsController
    
    private lazy var fetchedResultsControllerDelegate: FetchedResultsControllerDelegateWrapper = FetchedResultsControllerDelegateWrapper(delegate: self)
    
    // MARK: - Initialization
    
    public init(query: CKQuery, fetchRequest: NSFetchRequest, store: CloudKitStore) {
        
        self.query = query
        self.fetchRequest = fetchRequest
        self.store = store
        
        self.fetchedResultsController = NSFetchedResultsController(fetchRequest: fetchRequest, managedObjectContext: store.managedObjectContext, sectionNameKeyPath: nil, cacheName: nil)
        
        self.fetchedResultsController.delegate = self.fetchedResultsControllerDelegate
    }
    
    // MARK: - Methods
    
    public func refresh() {
        
        switch self.state {
            
        case .Initial:
            
            // fetch from cache
            do { try self.fetchedResultsController.performFetch() }
                
            catch { fatalError("Could not fetch from managed object context. \(error)") }
            
            // set initial values
            self.searchResults = self.fetchedResultsController.fetchedObjects as! [NSManagedObject]
            
            // send events
            self.event.willChangeContent()
            
            for (index, _) in self.searchResults.enumerate() {
                
                self.event.didInsert(index: index)
            }
            
            self.state = .Loaded
            
            fallthrough
            
        case .Loaded:
            
            // reset cursor
            self.queryCursor = nil
            
            self.state = .Refreshing
            
            // fetch from server
            self.store.search(.Query(query), resultsLimit: queryResultsLimit, zoneID: zoneID) { [weak self] (response: ErrorValue<([T], CKQueryCursor?)>) in
                
                guard let controller = self else { return }
                
                switch response {
                    
                case let .Error(error):
                    
                    controller.event.didRefresh(.Error(error))
                    
                    controller.state = .Loaded
                    
                case let .Value(results, cursor):
                    
                    // set cursor
                    controller.queryCursor = cursor
                    
                    controller.event.didRefresh(.Value(results))
                    
                    controller.state = .Loaded
                }
            }
            
        case .Refreshing: return // ignore, already refreshing
            
        case .LoadingCursor: return // ignore, loading more
        }
    }
    
    /// - Returns: The number of rows to show in the UI, including extra rows for placeholder cells.
    public func numberOfRows() -> Int {
        
        var count = self.searchResults.count
        
        if let _ = self.queryCursor { count++ }
        
        return count
    }
    
    /// - Returns: The cached value to show for a row, or a placeholder value.
    ///
    /// - Note: Makes requests in the background if the returned value is a placeholder.
    public func valueAtRow(row: Int) -> QueryResultsControllerValue<T> {
        
        // load more (for last row)
        if let _ = self.queryCursor where row == self.searchResults.count {
            
            switch self.state {
             
            case .Loaded:
                
                self.state = .LoadingCursor
                
                // make request to load more
                self.store.search(.Query(query), resultsLimit: queryResultsLimit, zoneID: zoneID) { [weak self] (response: ErrorValue<([T], CKQueryCursor?)>) in
                    
                    guard let controller = self else { return }
                    
                    controller.state = .Loaded
                    
                    switch response {
                        
                    case let .Error(error):
                        
                        controller.event.didLoadCursor(error: error)
                        
                    case let .Value(_, cursor):
                        
                        controller.queryCursor = cursor
                        
                        controller.event.didLoadCursor(error: nil)
                    }
                }
                
            default: break
            }
            
            return .Loading
        }
        
        // return value
        let managedObject = self.searchResults[row]
        
        let decodable = T(managedObject: managedObject)
        
        return .Value(decodable)
    }
}

// MARK: - Supporting Types

public enum QueryResultsControllerValue<T> {
    
    case Value(T)
    
    case Loading
}

public struct QueryResultsControllerEvent<T> {
    
    // Request Callback
    
    /// Informs the delegate that a search request has completed with the specified error (if any).
    public var didRefresh: (ErrorValue<[T]>) -> () = { (error) in }
    
    public var didLoadCursor: (ErrorValue<[T]>) -> () = { (error) in }
    
    // Change Notification Callbacks
    
    public var willChangeContent: () -> () = { }
    
    public var didChangeContent: () -> () = { }
    
    public var didInsert: ((index: Int) -> ()) = { (index) in }
    
    public var didDelete: ((index: Int) -> ()) = { (index) in }
    
    public var didUpdate: ((index: Int, error: ErrorType?) -> ()) = { (index, error) in }
    
    public var didMove: ((index: Int, newIndex: Int) -> ()) = { (index, newIndex) in }
    
    private init() { }
}

public enum QueryResultsControllerState {
    
    case Initial
    
    case Loaded
    
    case Refreshing
    
    case LoadingCursor
    
    private init() { self = .Initial }
}

// MARK: - Private

/// Swift wrapper for ```NSFetchedResultsControllerDelegate```.
@objc private final class FetchedResultsControllerDelegateWrapper: NSObject, NSFetchedResultsControllerDelegate {
    
    private weak var delegate: InternalFetchedResultsControllerDelegate!
    
    private init(delegate: InternalFetchedResultsControllerDelegate) {
        
        self.delegate = delegate
    }
    
    @objc private func controllerWillChangeContent(controller: NSFetchedResultsController) {
        
        self.delegate.controllerWillChangeContent(controller)
    }
    
    @objc private func controllerDidChangeContent(controller: NSFetchedResultsController) {
        
        self.delegate.controllerDidChangeContent(controller)
    }
    
    @objc private func controller(controller: NSFetchedResultsController, didChangeObject anObject: AnyObject, atIndexPath indexPath: NSIndexPath?, forChangeType type: NSFetchedResultsChangeType, newIndexPath: NSIndexPath?) {
        
        let managedObject = anObject as! NSManagedObject
        
        self.delegate.controller(controller, didChangeObject: managedObject, atIndexPath: indexPath, forChangeType: type, newIndexPath: newIndexPath)
    }
}

private protocol InternalFetchedResultsControllerDelegate: class {
    
    func controller(controller: NSFetchedResultsController, didChangeObject managedObject: NSManagedObject, atIndexPath indexPath: NSIndexPath?, forChangeType type: NSFetchedResultsChangeType, newIndexPath: NSIndexPath?)
    
    func controllerWillChangeContent(controller: NSFetchedResultsController)
    
    func controllerDidChangeContent(controller: NSFetchedResultsController)
}

extension QueryResultsController: InternalFetchedResultsControllerDelegate {
    
    func controllerWillChangeContent(controller: NSFetchedResultsController) {
        
        self.event.willChangeContent()
    }
    
    func controller(controller: NSFetchedResultsController,
        didChangeObject managedObject: NSManagedObject,
        atIndexPath indexPath: NSIndexPath?,
        forChangeType type: NSFetchedResultsChangeType,
        newIndexPath: NSIndexPath?) {
            
            switch self.state {
                
            case .Initial: break // ignore, events will be called manually
                
            case .Loaded: break // no ongoing requests, should update from cache
                
            case .Refreshing: break // provide update animations
                
            case .LoadingCursor: return // ignore, will load more from server
            }
            
            switch type {
                
            case .Insert:
                
                // already inserted
                if (self.searchResults as NSArray).containsObject(managedObject) {
                    
                    return
                }
                
                self.searchResults.append(managedObject)
                
                self.searchResults = (self.searchResults as NSArray).sortedArrayUsingDescriptors(self.fetchRequest.sortDescriptors!) as! [NSManagedObject]
                
                let row = (self.searchResults as NSArray).indexOfObject(managedObject)
                
                self.event.didInsert(index: row)
                
            case .Update:
                
                let row = (self.searchResults as NSArray).indexOfObject(managedObject)
                
                self.event.didUpdate(index: row, error: nil)
                
            case .Move:
                
                // get old row
                
                let oldRow = (self.searchResults as NSArray).indexOfObject(managedObject)
                
                self.searchResults = (self.searchResults as NSArray).sortedArrayUsingDescriptors(self.fetchRequest.sortDescriptors!) as! [NSManagedObject]
                
                let newRow = (self.searchResults as NSArray).indexOfObject(managedObject)
                
                if newRow != oldRow {
                    
                    self.event.didMove(index: oldRow, newIndex: newRow)
                }
                
            case .Delete:
                
                // already deleted
                if !(self.searchResults as NSArray).containsObject(managedObject) {
                    
                    return
                }
                
                let row = (self.searchResults as NSArray).indexOfObject(managedObject)
                
                self.searchResults.removeAtIndex(row)
                
                self.event.didDelete(index: row)
            }
    }
    
    func controllerDidChangeContent(controller: NSFetchedResultsController) {
        
        self.event.didChangeContent()
    }
}

