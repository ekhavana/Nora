//
//  DatabaseProvider.swift
//  Nora
//
//  Created by Steven on 4/4/17.
//  Copyright © 2017 NoraFirebase. All rights reserved.
//

import Foundation
import FirebaseDatabase

public typealias DatabaseCompletion = (Result<DatabaseResponse>) -> Void
public typealias TransactionBlock = (FIRMutableData) -> FIRTransactionResult

public class DatabaseProvider<Target: DatabaseTarget> {
    
    /// Make a request to FirebaseDatabase
    /// - Parameter target: target for the request
    /// - Parameter completion: completion block with result of the request
    /// - Returns: a handle in the case of an observe request, used to deregister the observer (optional)
    @discardableResult
    public func request(_ target: Target, completion: @escaping DatabaseCompletion = { _ in }) -> UInt? {
        
        var handle: UInt?
        
        switch target.task {
        case .observe, .observeOnce:
            let request = DatabaseQueryRequest(target)
            handle = processObserve(request, completion)
        case .setValue, .updateChildValues, .removeValue:
            let request = DatabaseRequest(target)
            processWrite(request, completion)
        case .transaction:
            let request = DatabaseRequest(target)
            processTransaction(request, completion)
        }
        return handle
    }
    
    private func processObserve(_ request: DatabaseQueryRequest, _ completion: @escaping DatabaseCompletion) -> UInt? {
        
        let successMapping = { (snapshot: FIRDataSnapshot) in
            let result = self.convertResponseToResult(snapshot: snapshot, reference: request.query.ref, error: nil)
            completion(result)
        }
        
        let failureMapping = { (error: Error?) in
            let result = self.convertResponseToResult(snapshot: nil, reference: nil, error: error)
            completion(result)
        }
        
        var handle: UInt?
        
        switch request.task {
        case .observe(let event):
            handle = request.query.observe(event, with: successMapping, withCancel: failureMapping)
        case .observeOnce(let event):
            request.query.observeSingleEvent(of: event, with: successMapping, withCancel: failureMapping)
        default:
            completion(.failure(NoraError.requestMapping))
        }
        
        return handle
    }
    
    private func processWrite(_ request: DatabaseRequest, _ completion: @escaping DatabaseCompletion) {
        
        let completionBlock = { (error: Error?, reference: FIRDatabaseReference) in
            let result = self.convertResponseToResult(snapshot: nil, reference: reference, error: error)
            completion(result)
        }
        
        switch request.task {
        case .setValue(let value):
            
            if request.onDisconnect {
                request.reference.onDisconnectSetValue(value, withCompletionBlock: completionBlock)
            } else {
                request.reference.setValue(value, withCompletionBlock: completionBlock)
            }
            
        case .updateChildValues(let values):
            
            if request.onDisconnect {
                request.reference.onDisconnectUpdateChildValues(values, withCompletionBlock: completionBlock)
            } else {
                request.reference.updateChildValues(values, withCompletionBlock: completionBlock)
            }
            
        case .removeValue:
            
            if request.onDisconnect {
                request.reference.onDisconnectRemoveValue(completionBlock: completionBlock)
            } else {
                request.reference.removeValue(completionBlock: completionBlock)
            }
            
        default:
            completion(.failure(NoraError.requestMapping))
        }
    }
    
    private func processTransaction(_ request: DatabaseRequest, _ completion: @escaping DatabaseCompletion) {
        
        let transactionCompletion = { (error: Error?, committed: Bool, snapshot: FIRDataSnapshot?) in
            let result = self.convertResponseToResult(snapshot: snapshot, reference: request.reference, error: error, committed: committed)
            completion(result)
        }
        
        request.reference.runTransactionBlock(request.transactionBlock, andCompletionBlock: transactionCompletion, withLocalEvents: request.localEvents)
    }
}

private extension DatabaseProvider {
    
    
    func convertResponseToResult(snapshot: FIRDataSnapshot?, reference: FIRDatabaseReference?, error: Error?, committed: Bool? = nil) -> Result<DatabaseResponse> {
        
        switch (snapshot, reference, error, committed) {
        case let (snapshot, .some(reference), .none, .some(committed)):
            let response = DatabaseResponse(reference: reference, snapshot: snapshot, isCommitted: committed)
            return .success(response)
        case let (.some(snapshot), .some(reference), .none, _):
            let response = DatabaseResponse(reference: reference, snapshot: snapshot, isCommitted: true)
            return .success(response)
        case let (.none, .some(reference), .none, _):
            let response = DatabaseResponse(reference: reference, isCommitted: true)
            return .success(response)
        case let (.none, _, .some(error), _):
            return .failure(NoraError.underlying(error))
        default:
            return .failure(NoraError.resultConversion)
        }
    }
    
}
