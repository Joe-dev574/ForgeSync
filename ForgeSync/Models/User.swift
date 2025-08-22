//
//  User.swift
//  ForgeSync
//
//  Created by Joseph DeWeese on 8/21/25.
//

import SwiftData
import HealthKit // For HKBiologicalSex mapping and queries
import OSLog // Renamed from os.log for consistency with other files

/// Represents a single progress selfie taken by the user.
/// This struct is Codable and Hashable for easy persistence and comparison.
struct ProgressSelfie: Identifiable, Codable, Hashable {
    let id: UUID
    var imageData: Data
    var dateAdded: Date

    /// Formatted display name for the selfie, e.g., "May '25".
    /// Uses a localized date formatter for better internationalization.
    var displayName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yy"
        formatter.locale = Locale.current // Added for localization
        return formatter.string(from: dateAdded)
    }

    init(id: UUID = UUID(), imageData: Data, dateAdded: Date = Date()) {
        self.id = id
        self.imageData = imageData
        self.dateAdded = dateAdded
    }
}

/// A SwiftData model representing a user’s onboarding status and health metrics for MoveSync.
/// Stores whether the user has completed onboarding, their Apple ID, and health data from HealthKit.
/// All health metrics are stored in SI units (e.g., kg, meters) for consistency.
@Model
final class User {
    // MARK: - Properties
    @Attribute(.unique) var appleUserId: String? // Unique identifier from Apple
    var email: String? // Email provided by Apple (can be private relay)
    var displayName: String? // User's editable display name (renamed from 'name' for clarity and consistency)
    var isOnboardingComplete: Bool
    
    // Health Metrics
    var weight: Double? // in kilograms
    var height: Double? // in meters
    var birthDate: Date? // Replaced 'age' with birthDate for dynamic, accurate age calculation over time
    var restingHeartRate: Double? // in beats per minute
    var maxHeartRate: Double? // in beats per minute. Can be user-entered or estimated.
    var biologicalSexString: String? // Storing HKBiologicalSex.description or a custom string
    // Options: "Male", "Female", "Other", "Not Set"
    
    // Profile Details
    var fitnessGoal: String?
    @Attribute(.externalStorage) var profileImageData: Data?
    var progressSelfies: [ProgressSelfie] = []
    
    // MARK: - Computed Properties
    // User's current age in years, derived from birthDate.
  // Returns nil if birthDate is not set.
    var age: Int? {
        guard let birthDate = birthDate else { return nil }
        let calendar = Calendar.current
        let now = Date()
        let ageComponents = calendar.dateComponents([.year], from: birthDate, to: now)
        return ageComponents.year
    }
    func fetchBirthDate(completion: @escaping (Date?, Int?, Error?) -> Void) {
        let healthStore = HKHealthStore()
        do {
            let birthComponents = try healthStore.dateOfBirthComponents()
            let birthDate = Calendar.current.date(from: birthComponents)
            let age = birthDate.map { Calendar.current.dateComponents([.year], from: $0, to: Date()).year }
            completion(birthDate, age as? Int, nil)
        } catch {
            completion(nil, nil, error)
        }
    }
    /// Estimated max heart rate based on age (220 - age).
    /// Returns nil if age is not available.
    var estimatedMaxHeartRate: Double? {
        guard let age = age, age >= 0 else { return nil }
        return 220.0 - Double(age)
    }
    
    /// Initializes a User instance with default values.
    init(appleUserId: String? = nil,
         email: String? = nil,
         displayName: String? = nil,
         isOnboardingComplete: Bool = false,
         fitnessGoal: String? = "General Fitness",
         profileImageData: Data? = nil,
         biologicalSexString: String? = nil,
         progressSelfies: [ProgressSelfie] = []
    ) {
        self.appleUserId = appleUserId
        self.email = email
        self.displayName = displayName
        self.isOnboardingComplete = isOnboardingComplete
        self.fitnessGoal = fitnessGoal
        self.profileImageData = profileImageData
        
        // Initialize health metrics
        self.weight = nil
        self.height = nil
        self.birthDate = nil // Replaced age
        self.restingHeartRate = nil
        self.maxHeartRate = nil
        self.biologicalSexString = biologicalSexString
        self.progressSelfies = progressSelfies
    }
}

// Extension for HealthKit integration and utilities
extension User {
    /// Enum for displaying and mapping HKBiologicalSex, with conversion to/from HealthKit values.
    /// This ensures type-safety and easy Picker integration in views.
    enum BiologicalSexDisplay: String, CaseIterable, Codable {
        case female = "Female"
        case male = "Male"
        case other = "Other"
        case notSet = "Not Set"
        
        init(hkBiologicalSex: HKBiologicalSex?) {
            guard let hkSex = hkBiologicalSex else {
                self = .notSet
                return
            }
            switch hkSex {
            case .female: self = .female
            case .male: self = .male
            case .other: self = .other
            case .notSet: self = .notSet
            @unknown default: self = .notSet
            }
        }
        
        var hkValue: HKBiologicalSex {
            switch self {
            case .female: return .female
            case .male: return .male
            case .other: return .other
            case .notSet: return .notSet
            }
        }
    }
    
    /// Computed property for biological sex, mapping to/from string storage.
    var biologicalSex: BiologicalSexDisplay? {
        get {
            guard let sexString = biologicalSexString else { return nil }
            return BiologicalSexDisplay(rawValue: sexString)
        }
        set {
            biologicalSexString = newValue?.rawValue
        }
    }
    
    /// Asynchronously updates the user's health metrics from HealthKit.
    /// Throws errors if HealthKit is unavailable or queries fail.
    /// This centralizes HealthKit fetching logic, making it reusable across the app.
    @MainActor
    func updateFromHealthKit() async throws {
        let healthStore = HKHealthStore()
        guard HKHealthStore.isHealthDataAvailable() else {
            throw NSError(domain: "HealthKit", code: -1, userInfo: [NSLocalizedDescriptionKey: "HealthKit not available"])
        }
        
        // Fetch birth date for age
        if let birthComponents = try? healthStore.dateOfBirthComponents() {
            self.birthDate = Calendar.current.date(from: birthComponents)
        }
        
        // Fetch biological sex
        if let hkSex = try? healthStore.biologicalSex().biologicalSex {
            self.biologicalSex = BiologicalSexDisplay(hkBiologicalSex: hkSex)
        }
        
        // Fetch other metrics (weight, height, RHR, maxHR) via samples/queries
        // Assuming HealthKitManager handles detailed queries; integrate as needed
        // For example:
        // self.weight = try await fetchLatestWeight(from: healthStore)
        // etc.
    }
}
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.forgesync1_0.default", category: "User")

