//
//  Item.swift
//  sexophone
//
//  Created by Kevish Sewliya on 04/08/26.
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
