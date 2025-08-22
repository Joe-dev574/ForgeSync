//
//  SplitTime.swift
//  ForgeSync
//
//  Created by Joseph DeWeese on 8/21/25.
//

import SwiftData

/// Represents the duration of an exercise segment within a workout session.
/// Conforms to SwiftData’s `@Model` for persistence.
@Model
class SplitTime {
    /// The duration of the exercise segment in seconds.
    var durationInSeconds: Double
    var order: Int //property to track order
    /// The associated exercise, linked inversely.
    @Relationship(inverse: \Exercise.splitTimes) var exercise: Exercise?
    
    /// The associated workout history entry, linked inversely.
    @Relationship(inverse: \History.splitTimes) var history: History?
    
    /// Initializes a new split time with the specified properties.
    /// - Parameters:
    ///   - durationInSeconds: The duration of the exercise segment in seconds.
    ///   - exercise: The associated exercise (defaults to nil).
    ///   - history: The associated workout history entry (defaults to nil).
    init(durationInSeconds: Double, exercise: Exercise? = nil, history: History? = nil, order: Int = 0) {
        self.durationInSeconds = durationInSeconds
        self.exercise = exercise
        self.history = history
        self.order = order
    }
}


