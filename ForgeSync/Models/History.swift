//
//  History.swift
//  ForgeSync
//
//  Created by Joseph DeWeese on 8/21/25.
//

import SwiftUI
import SwiftData

/// Represents a workout session’s history, storing details such as date, duration, metrics, and journal notes.
/// Conforms to SwiftData’s `@Model` for persistence.
@Model
class History {
    /// A unique identifier for the history entry.
    var id: UUID
    
    /// The date and time the workout session occurred.
    var date: Date
    
    /// Optional notes or journal entry for the session.
    var notes: String?
    
    /// The exercises completed during the session.
    var exercisesCompleted: [Exercise]
    
    /// The split times recorded for exercises, with a cascade delete rule.
    @Relationship(deleteRule: .cascade, inverse: \SplitTime.exercise) var splitTimes: [SplitTime]
    
    /// The total duration of the last session in minutes.
    var lastSessionDuration: Double
    
    /// The associated workout, linked inversely.
    @Relationship(inverse: \Workout.history) var workout: Workout?
    
    /// The intensity score (0–100) based on heart rate, available with premium features.
    var intensityScore: Double?
    
    /// The progress pulse score (0–100) indicating workout effectiveness, available with premium features.
    var progressPulseScore: Double?
    
    /// The dominant heart rate zone (1–5) for the session, available with premium features.
    var dominantZone: Int?
    
    /// Initializes a new history entry with the specified properties.
    /// - Parameters:
    ///   - id: A unique identifier (defaults to a new

    init(
        id: UUID = UUID(),
        date: Date = .now,
        notes: String? = nil,
        exercisesCompleted: [Exercise] = [],
        splitTimes: [SplitTime] = [],
        lastSessionDuration: Double = 0.0,
        intensityScore: Double? = nil,
        progressPulseScore: Double? = nil,
        dominantZone: Int? = nil
    ) {
        self.id = id
        self.date = date
        self.notes = notes
        self.exercisesCompleted = exercisesCompleted
        self.splitTimes = splitTimes
        self.lastSessionDuration = lastSessionDuration
        self.intensityScore = intensityScore
        self.progressPulseScore = progressPulseScore
        self.dominantZone = dominantZone
    }
}


