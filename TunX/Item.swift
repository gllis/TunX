//
//  Item.swift
//  TunX
//
//  Created by liguilong on 2026/8/13.
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
