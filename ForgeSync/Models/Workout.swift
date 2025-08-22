//
//  Workout.swift
//  ForgeSync
//
//  Created by Joseph DeWeese on 8/21/25.
//

import SwiftUI
import SwiftData
import os.log

/// Represents a workout with exercises, history, and scheduling details.
/// Conforms to SwiftData’s `@Model` for persistence, used in MoveSync to manage user workouts.
@Model
class Workout {
    /// The unique title of the workout.
    @Attribute(.unique) var title: String
    
    /// The exercises included in the workout.
    var exercises: [Exercise]
    
    /// The duration of the last session in minutes.
    var lastSessionDuration: Double
    
    /// The date the workout was created.
    var dateCreated: Date
    
    /// The date the workout was last completed, if any.
    var dateCompleted: Date?
    
    /// The category associated with the workout, if any.
    var category: Category?
    
    /// The history of sessions for the workout, with a cascade delete rule.
    @Relationship(deleteRule: .cascade) var history: [History]
    
    /// The personal best duration in minutes, if any.
    var fastestTime: Double?
    
    /// A  summary of the workout’s history, if any.
    var GeneratedSummary: String?
    ///  repeats of exercise list consecutively..like rounds in boxing
    var roundsEnabled: Bool
    /// qty of rounds user desires for workout
    var roundsQuantity: Int
    
    /// The scheduled date for the workout, encrypted for cloud storage.
    @Attribute(.allowsCloudEncryption) var scheduleDate: Date?
    
    /// The notification time for the workout, encrypted for cloud storage.
    @Attribute(.allowsCloudEncryption) var notificationTime: Date?
    
    /// The repeat option for the workout’s schedule, encrypted for cloud storage.
    @Attribute(.allowsCloudEncryption) var repeatOption: RepeatOption?
    
    
    /// Logger for debugging and monitoring workout operations.
    @Transient
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.movesync.default.subsystem", category: "Workout")
    
    /// The exercises sorted by their order.
    var sortedExercises: [Exercise] {
        exercises.sorted { $0.order < $1.order }
    }
    
    /// Initializes a new workout with the specified properties.
    /// - Parameters:
    ///   - title: The unique title of the workout.
    ///   - exercises: The exercises included in the workout (defaults to empty).
    ///   - lastSessionDuration: The duration of the last session in minutes (defaults to 0).
    ///   - dateCreated: The date the workout was created (defaults to now).
    ///   - dateCompleted: The date the workout was last completed (defaults to nil).
    ///   - category: The category associated with the workout (defaults to nil).
    ///   - history: The history of sessions for the workout (defaults to empty).
    ///   - fastestTime: The personal best duration in minutes (defaults to nil).
    ///   - GeneratedSummary: The AI-generated summary (defaults to nil).
    ///   - scheduleDate: The scheduled date (defaultssono: The scheduled date (defaults to nil).
    ///   - notificationTime: The notification time (defaults to nil).
    ///   - repeatOption: The repeat option for the schedule (defaults to nil).
    init(
        title: String,
        exercises: [Exercise] = [],
        lastSessionDuration: Double = 0,
        dateCreated: Date = .now,
        dateCompleted: Date? = nil,
        category: Category? = nil,
        history: [History] = [],
        fastestTime: Double? = nil,
        aiGeneratedSummary: String? = nil,
        scheduleDate: Date? = nil,
        notificationTime: Date? = nil,
        repeatOption: RepeatOption? = nil,
        roundsEnabled: Bool = false,
        roundsQuantity: Int = 1
    ) {
        self.title = title
        self.exercises = exercises
        self.lastSessionDuration = lastSessionDuration
        self.dateCreated = dateCreated
        self.dateCompleted = dateCompleted
        self.category = category
        self.history = history
        self.fastestTime = fastestTime
        self.GeneratedSummary = aiGeneratedSummary
        self.scheduleDate = scheduleDate
        self.notificationTime = notificationTime
        self.repeatOption = repeatOption
        self.roundsEnabled = roundsEnabled
        self.roundsQuantity = roundsQuantity
    }
    
    /// Updates the fastest time duration based on the shortest valid session duration in history.
    func updateFastestTime() {
        logger.info("Updating fastest time for workout: \(self.title)")
        if history.isEmpty {
            fastestTime = nil
            logger.info("History is empty, fastestTime set to nil.")
        } else {
            let allDurations = history.map { $0.lastSessionDuration }
            logger.debug("All history durations (minutes): \(allDurations)")
            let validDurations = allDurations.filter { $0 > 0 }
            logger.debug("Valid (> 0) history durations (minutes): \(validDurations)")
            
            let newFastestTime = validDurations.isEmpty ? nil : validDurations.min()
            logger.info("Calculated new fastest time (minutes): \(String(describing: newFastestTime))")
            
            if let currentFT = self.fastestTime {
                logger.debug("Current fastestTime before update (minutes): \(currentFT)")
            } else {
                logger.debug("Current fastestTime before update is nil.")
            }
            
            fastestTime = newFastestTime
            logger.info("Final fastestTime after update (minutes): \(String(describing: self.fastestTime))")
        }
    }
    
    // Computed property to return exercises repeated by rounds
        var effectiveExercises: [Exercise] {
            if roundsEnabled && roundsQuantity > 1 {
                return Array(repeating: exercises.sorted(by: { $0.order < $1.order }), count: roundsQuantity).flatMap { $0 }
            }
            return exercises.sorted(by: { $0.order < $1.order })
        }
        
    /// The fastest session duration in minutes from the workout’s history.
    var fastestDuration: Double {
        history.map { $0.lastSessionDuration }.min() ?? 0.0
    }
    
    /// Returns the default duration for the workout, prioritizing personal best or the fastest duration.
    /// - Returns: The default duration in minutes.
    func getDefaultDuration() -> Double {
        fastestTime ?? fastestDuration
    }
    //MARK:  SUMMARY REPORT
    /// Updates the generated summary based on the workout’s history.
    /// - Parameter context: The SwiftData model context for persistence.
    func updateAISummary(context: ModelContext) {
        logger.info("Updating AI summary for workout: \(self.title)")
        guard !history.isEmpty else {
            GeneratedSummary = nil
            logger.info("History is empty, GeneratedSummary set to nil.")
            return
        }
        let averageDurationInMinutes = history.map { $0.lastSessionDuration }.reduce(0.0, +) / Double(history.count)
        let averageDurationInSeconds = averageDurationInMinutes * 60
        guard averageDurationInSeconds >= 0 else {
            logger.warning("Invalid average duration: \(averageDurationInSeconds) seconds")
            GeneratedSummary = nil
            DispatchQueue.main.async {
                ErrorManager.shared.presentAlert(
                    title: "Summary Error",
                    message: "Unable to generate workout summary due to invalid duration."
                )
            }
            return
        }
        let exerciseNames = sortedExercises.map { $0.name }.joined(separator: ", ")
        GeneratedSummary = "Completed \(history.count) session(s) with an average duration of \(Formatters.formatDuration(averageDurationInSeconds)). Exercises: \(exerciseNames)."
        logger.info("Updated GeneratedSummary: \(self.GeneratedSummary ?? "nil")")
        
        if context.hasChanges {
            do {
                try context.save()
                logger.info("Saved ModelContext after updating GeneratedSummary.")
            } catch {
                logger.error("Failed to save ModelContext after updating GeneratedSummary: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    ErrorManager.shared.presentAlert(
                        title: "Save Error",
                        message: "Failed to save workout summary: \(error.localizedDescription)"
                    )
                }
            }
        }
    }
    
    /// Defines the repeat options for workout scheduling.
    enum RepeatOption: String, CaseIterable, Codable, Identifiable {
        /// No repeat schedule.
        case none = "None"
        /// Daily repeat schedule.
        case daily = "Daily"
        /// Weekly repeat schedule.
        case weekly = "Weekly"
        /// Monthly repeat schedule.
        case monthly = "Monthly"
        
        /// A unique identifier for the repeat option.
        var id: String { rawValue }
    }
}

