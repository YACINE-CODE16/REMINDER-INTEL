//
//  Item.swift
//  RemindersInt
//
//  Created by Yacine Bask on 08/10/2026.
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
