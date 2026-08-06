//
//  Item.swift
//  Orchestrator
//
//  Created by Saba Abesadze on 06/08/2026.
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
