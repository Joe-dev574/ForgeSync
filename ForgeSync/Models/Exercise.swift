//
//  Exercise.swift
//  ForgeSync
//
//  Created by Joseph DeWeese on 8/21/25.
//

import SwiftData

@Model
class Exercise {
    var name: String
    var order: Int
    var splitTimes: [SplitTime] = []
    
    init(name: String, order: Int = 0) {
        self.name = name
        self.order = order
    }
}


