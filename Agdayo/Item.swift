//
//  Item.swift
//  Agdayo
//
//  Created by Jan Albert Sobreo on 9/22/26.
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
