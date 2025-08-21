//
//  ErrorManager.swift
//  ForgeSync
//
//  Created by Joseph DeWeese on 8/21/25.
//

import SwiftUI
import os.log

/// Defines the properties of an alert to be displayed in the app.
/// Conforms to `Identifiable` for use in SwiftUI alert presentations.
struct AppAlert: Identifiable {
    /// A unique identifier for the alert.
    let id = UUID()
    
    /// The title of the alert.
    let title: String
    
    /// The message body of the alert.
    let message: String
    
    /// The primary button for the alert, defaulting to an "OK" button.
    let primaryButton: Alert.Button
    
    /// An optional secondary button for the alert.
    let secondaryButton: Alert.Button?
    
    /// Accessibility label for the alert, combining title and message for VoiceOver.
    var accessibilityLabel: String {
        "\(title). \(message)"
    }
    
    /// Accessibility hint for the alert, describing available actions.
    var accessibilityHint: String {
        secondaryButton != nil ? "Tap OK to dismiss or choose the secondary action." : "Tap OK to dismiss."
    }
}

/// Manages the presentation of error alerts in the app.
/// This class is a singleton, accessible via `shared`, and operates on the main actor to ensure thread safety.
/// It uses structured logging to track alert presentation and dismissal.
@MainActor
class ErrorManager: ObservableObject {
    /// The shared singleton instance of `ErrorManager`.
    static let shared = ErrorManager()
    
    /// The currently displayed alert, if any.
    /// Published to notify SwiftUI views of changes.
    @Published var currentAlert: AppAlert?
    
    /// Logger for debugging and monitoring alert operations.
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.forgeSync.default.subsystem", category: "ErrorManager")
    
    /// Initializes the `ErrorManager` singleton.
    /// This is private to enforce singleton usage via `shared`.
    private init() {}
    
    /// Presents an alert with a custom title and message.
    /// - Parameters:
    ///   - title: The title of the alert.
    ///   - message: The message body of the alert.
    ///   - primaryButton: The primary button, defaulting to "OK".
    ///   - secondaryButton: An optional secondary button.
    func presentAlert(title: String, message: String, primaryButton: Alert.Button = .default(Text("OK")), secondaryButton: Alert.Button? = nil) {
        logger.info("Presenting alert: \(title) - \(message)")
        currentAlert = AppAlert(title: title, message: message, primaryButton: primaryButton, secondaryButton: secondaryButton)
    }
    
    /// Presents an error conforming to `LocalizedError`.
    /// Combines the error’s description, failure reason, and recovery suggestion into the alert message.
    /// - Parameters:
    ///   - error: The error to display.
    ///   - primaryButton: The primary button, defaulting to "OK".
    ///   - secondaryButton: An optional secondary button.
    func presentError(_ error: LocalizedError, primaryButton: Alert.Button = .default(Text("OK")), secondaryButton: Alert.Button? = nil) {
        let title = error.errorDescription ?? "Error"
        var detailedMessage = error.failureReason ?? error.localizedDescription
        if let recovery = error.recoverySuggestion, !recovery.isEmpty {
            detailedMessage += "\n\n\(recovery)"
        }
        logger.info("Presenting error: \(title) - \(detailedMessage)")
        currentAlert = AppAlert(title: title, message: detailedMessage, primaryButton: primaryButton, secondaryButton: secondaryButton)
    }
    
    /// Presents a generic unknown error alert.
    /// - Parameter underlyingError: An optional underlying error to include in the message details.
    func presentUnknownError(_ underlyingError: Error? = nil) {
        var message = "An unexpected error occurred. Please try again."
        if let underlyingError {
            message += "\n\nDetails: \(underlyingError.localizedDescription)"
        }
        logger.info("Presenting unknown error: \(message)")
        presentAlert(title: "Error", message: message)
    }
    
    /// Dismisses the current alert, if any.
    func dismissAlert() {
        logger.info("Dismissing current alert.")
        currentAlert = nil
    }
}

/// Errors that can occur during HealthKit operations, conforming to `LocalizedError` for user-facing messages.
enum HealthKitError: LocalizedError {
    /// HealthKit is not available on the device.
    case healthDataUnavailable
    /// Authorization request failed with a specific message.
    case authorizationFailed(String)
    /// The workout duration is invalid (e.g., zero or negative).
    case invalidWorkoutDuration
    /// Failed to save a workout to HealthKit with a specific message.
    case workoutSaveFailed(String)
    /// Heart rate data is not available.
    case heartRateDataUnavailable
    /// General query failure with a specific message.
    case queryFailed(String)
    /// Expected data (e.g., height samples) not found, with type-specific message.
    case dataNotFound(String)
    /// HealthKit permission was explicitly denied.
    case permissionDenied
    
    /// A localized description of the error, suitable for display to the user.
    var errorDescription: String? {
        switch self {
        case .healthDataUnavailable:
            return "HealthKit is not available on this device."
        case .authorizationFailed(let message):
            return "Failed to authorize HealthKit: \(message)"
        case .invalidWorkoutDuration:
            return "Workout duration is too short. Must be at least 5 minutes long."
        case .workoutSaveFailed(let message):
            return "Failed to save workout to HealthKit: \(message)"
        case .heartRateDataUnavailable:
            return "Heart rate data is not available."
        case .queryFailed(let message):
            return "HealthKit query failed: \(message)"
        case .dataNotFound(let type):
            return "No \(type) data found in HealthKit."
        case .permissionDenied:
            return "HealthKit permission was denied."
        }
    }
    
    /// A suggestion for recovering from the error, if applicable.
    var recoverySuggestion: String? {
        switch self {
        case .healthDataUnavailable:
            return "Please ensure your device supports HealthKit."
        case .authorizationFailed:
            return "Please enable HealthKit permissions in the Health app."
        case .invalidWorkoutDuration, .workoutSaveFailed, .heartRateDataUnavailable:
            return "Please try again or contact support if the issue persists."
        case .queryFailed, .dataNotFound:
            return "Please ensure data exists in the Health app and try again."
        case .permissionDenied:
            return "You can grant permissions in the Settings app under Privacy > Health."
        }
    }
}
