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
public final class QueryResultsController<T where T: CloudKitDecodable, T: CoreDataEncodable> {
    
    // MARK: - Properties
    
    @NSCopying public private(set) var query: CKQuery
    
    @NSCopying public private(set) var fetchRequest: NSFetchRequest
    
    public let store: CloudKitStore
    
    public var queryResultsLimit: Int?
    
    public var zoneID: RecordZoneID?
    
    /// The cached search results.
    public private(set) var searchResults = [NSManagedObject]()
    
    public private(set) var event = QueryResultsControllerEvent()
    
    public private(set) var state = QueryResultsControllerState()
    
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
            
            defer { self.state = .Loaded }
            
            // fetch from cache
            do { try self.fetchedResultsController.performFetch() }
                
            catch { fatalError("Could not fetch from managed object context. \(error)") }
            
            // fetch from server
            self.store.search(.Query(query), resultsLimit: queryResultsLimit, zoneID: zoneID) { [weak self] (response: ErrorValue<([T], CKQueryCursor?)>) in
                
                guard let controller = self else { return }
                
                switch response {
                    
                case let .Error(error):
                    
                    controller.event.didExecuteQuery(error: error)
                    
                case let .Value(results, cursor):
                    
                    controller.queryCursor = cursor
                    
                    controller.event.didExecuteQuery(error: nil)
                }
            }
            
        case .Loaded: break
            
            
            
        }
    }
}

// MARK: - Supporting Types

public struct QueryResultsControllerEvent {
    
    // Request Callback
    
    /// Informs the delegate that a search request has completed with the specified error (if any).
    public var didExecuteQuery: ((error: ErrorType?) -> ()) = { (error) in }
    
    // Change Notification Callbacks
    
    public var willChangeContent: (() -> ()) = { }
    
    public var didChangeContent: (() -> ()) = { }
    
    public var didInsert: ((index: Int) -> ()) = { (index) in }
    
    public var didDelete: ((index: Int) -> ()) = { (index) in }
    
    public var didUpdate: ((index: Int, error: ErrorType?) -> ()) = { (index, error) in }
    
    public var didMove: ((index: Int, newIndex: Int) -> ()) = { (index, newIndex) in }
    
    private init() { }
}

public enum QueryResultsControllerState {
    
    case Initial
    
    case Loaded
    
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

