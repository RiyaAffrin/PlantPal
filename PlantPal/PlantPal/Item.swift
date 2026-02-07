//
//  Item.swift
//  PlantPal
//
//  Created by Agnes Huang on 2/5/26.
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
