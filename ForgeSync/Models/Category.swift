//
//  Category.swift
//  ForgeSync
//
//  Created by Joseph DeWeese on 8/21/25.
//

import SwiftUI
import SwiftData
import HealthKit
import os.log

/// Defines the color, HealthKit activity type, and MET value for workout categories.
/// Conforms to `Codable` for SwiftData persistence.
enum CategoryColor: String, Codable, CaseIterable {
    /// Cardio-based workouts (e.g., mixed cardio).
    case CARDIO
    /// Cross-training workouts.
    case CROSSTRAIN
    /// Cycling workouts.
    case CYCLING
    /// Grappling or martial arts workouts.
    case GRAPPLING
    /// High-intensity interval training workouts.
    case HIIT
    /// Hiking workouts.
    case HIKING
    /// Pilates workouts.
    case PILATES
    /// Power-based strength workouts.
    case POWER
    /// Recovery or flexibility workouts.
    case RECOVERY
    /// Rowing workouts.
    case ROWING
    /// Running workouts.
    case RUN
    /// Stretching workouts.
    case STRETCH
    /// Strength training workouts.
    case STRENGTH
    /// Swimming workouts.
    case SWIMMING
    /// Test or miscellaneous workouts.
    case TEST
    /// Walking workouts.
    case WALK
    /// Yoga workouts.
    case YOGA
    
    /// The SwiftUI color associated with the category, defined in the asset catalog.
    var color: Color {
        Color(rawValue)
    }
    
    /// The HealthKit workout activity type corresponding to the category.
    var hkActivityType: HKWorkoutActivityType {
        switch self {
        case .CARDIO: .mixedCardio
        case .CROSSTRAIN: .crossTraining
        case .CYCLING: .cycling
        case .GRAPPLING: .martialArts
        case .HIIT: .highIntensityIntervalTraining
        case .HIKING: .hiking
        case .PILATES: .pilates
        case .POWER: .traditionalStrengthTraining
        case .RECOVERY: .flexibility
        case .ROWING: .rowing
        case .RUN: .running
        case .STRETCH: .flexibility
        case .STRENGTH: .traditionalStrengthTraining
        case .SWIMMING: .swimming
        case .TEST: .other
        case .WALK: .walking
        case .YOGA: .yoga
        }
    }
    
    /// The MET (Metabolic Equivalent of Task) value for energy expenditure calculations, based on the Compendium of Physical Activities.
    var metValue: Double {
        switch self {
        case .CARDIO: 8.0  // Mixed cardio or circuit training
        case .CROSSTRAIN: 8.0
        case .CYCLING: 8.0  // Moderate effort
        case .GRAPPLING: 10.3  // Martial arts
        case .HIIT: 8.0
        case .HIKING: 7.3
        case .PILATES: 3.0
        case .POWER: 6.0  // Vigorous weight lifting
        case .RECOVERY: 2.5  // Flexibility exercises
        case .ROWING: 7.0  // Moderate effort
        case .RUN: 10.0  // General running
        case .STRETCH: 2.3
        case .STRENGTH: 3.5  // Light to moderate weight lifting
        case .SWIMMING: 6.0  // General swimming
        case .TEST: 5.0
        case .WALK: 3.5  // Moderate pace
        case .YOGA: 3.0
        }
    }
}

/// Represents a workout category, such as Strength or Yoga, with a unique name, symbol, and color.
/// Conforms to SwiftData’s `@Model` for persistence and `Identifiable` for UI usage.
@Model
class Category: Identifiable {
    /// The unique name of the category.
    @Attribute(.unique) var categoryName: String
    
    /// The SF Symbol name for the category icon.
    var symbol: String
    
    /// The color and HealthKit activity type associated with the category.
    var categoryColor: CategoryColor
    
    /// Logger for debugging and monitoring category operations.
    @Transient
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.forgeSync.default.subsystem", category: "Category")
    
    /// Initializes a new category with the specified properties.
    /// - Parameters:
    ///   - categoryName: The unique name of the category.
    ///   - symbol: The SF Symbol name for the category icon.
    ///   - categoryColor: The color and HealthKit activity type (defaults to `.STRENGTH`).
    init(categoryName: String, symbol: String, categoryColor: CategoryColor = .STRENGTH) {
        let trimmedName = categoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            logger.error("Attempted to create category with empty name")
            fatalError("Category name cannot be empty or whitespace-only")
        }
        self.categoryName = trimmedName
        self.symbol = symbol
        self.categoryColor = categoryColor
    }
}
