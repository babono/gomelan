//
//  Item.swift
//  gomelan
//
//  Created by Muhammad Nurul Akbar on 03/08/26.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
