//
//  Dictionary+Extensions.swift
//  Theo
//
//  Created by Cory D. Wiles on 5/16/17.
//
//

import Foundation

extension Dictionary where Key: StringProtocol {
    
    func decodingKey<ReturnType: DecodableType>(_ key: Key) throws -> ReturnType {
        
        guard let value = self[key] as? ReturnType else {
            throw DecodeError.noValueForKey(key)
        }
        
        return value
    }
    
    func decodingKey<ReturnType: DecodableType>(_ key: Key) -> ReturnType? {
        return self[key] as? ReturnType
    }
}
