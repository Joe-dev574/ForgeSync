//
//  Formatter.swift
//  ForgeSync
//
//  Created by Joseph DeWeese on 8/21/25.
//

import Foundation
import os.log

/// A utility struct providing formatting functions for time, weight, height, and dates.
/// Supports imperial and metric units via `UnitSystem` and ensures accessibility-friendly output.
/// Used across MoveSync for consistent formatting in views like `HealthMetricsSectionView` and `StatsSectionView`.
struct Formatters {
    /// Logger for debugging and monitoring formatting operations.
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.moveSync.default.subsystem", category: "Formatters")
    
    /// Shared formatter for time durations, reused for performance.
    private static let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .pad
        return formatter
    }()
    
    /// Shared formatter for short time strings (e.g., "10:30 AM").
    private static let shortTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
    
    /// Shared formatter for medium date strings (e.g., "Sep 12, 2023").
    private static let mediumDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
    
    /// Formats a duration in minutes into a string representation.
    /// - Parameters:
    ///   - minutes: The duration in minutes.
    ///   - concise: If `true`, uses a compact format (e.g., "1.5m"); otherwise, uses a detailed format (e.g., "1h 30m 00s").
    /// - Returns: A formatted string representing the duration, or "0s" for invalid inputs.
    static func formatTime(minutes: Double, concise: Bool = false) -> String {
        guard minutes >= 0 else {
            logger.warning("Invalid duration: \(minutes) minutes")
            return "0s"
        }
        
        let totalSeconds = Int(minutes * 60)
        
        if concise {
            if totalSeconds < 60 {
                return String(format: "%.1fs", Double(totalSeconds))
            } else if totalSeconds < 3600 {
                return String(format: "%.1fm", minutes)
            } else {
                return String(format: "%.1fh", minutes / 60)
            }
        } else {
            let hours = totalSeconds / 3600
            let minutesPart = (totalSeconds % 3600) / 60
            let secondsPart = totalSeconds % 60
            
            if hours > 0 {
                return String(format: "%dh %02dm %02ds", hours, minutesPart, secondsPart)
            } else if minutesPart > 0 {
                return String(format: "%dm %02ds", minutesPart, secondsPart)
            } else {
                return String(format: "%ds", secondsPart)
            }
        }
    }
    
    /// Formats a duration in seconds into a positional string (e.g., "01:30:45" or "30:45").
    /// - Parameter seconds: The duration in seconds.
    /// - Returns: A formatted string, or "00:00" for invalid inputs.
    static func formatDuration(_ seconds: TimeInterval) -> String {
        guard seconds >= 0 else {
            logger.warning("Invalid duration: \(seconds) seconds")
            return "00:00"
        }
        
        durationFormatter.allowedUnits = seconds < 3600 ? [.minute, .second] : [.hour, .minute, .second]
        return durationFormatter.string(from: seconds) ?? "00:00"
    }
    
    /// Formats a weight in kilograms for the specified unit system.
    /// - Parameters:
    ///   - weightInKg: The weight in kilograms, or `nil` if unavailable.
    ///   - system: The unit system (imperial or metric).
    ///   - forInput: If `true`, omits unit suffix for text input fields; otherwise, includes units (e.g., "lbs").
    /// - Returns: A formatted string (e.g., "150.5 lbs" or "" for input), or "–" for nil/invalid inputs.
    static func formattedWeight(for weightInKg: Double?, in system: UnitSystem, forInput: Bool = false) -> String {
        guard let weightInKg = weightInKg, weightInKg >= 0 else {
            logger.warning("Invalid weight: \(String(describing: weightInKg)) kg")
            return forInput ? "" : "–"
        }
        
        if system == .imperial {
            let weightInLbs = weightInKg * 2.20462
            return String(format: "%.1f", weightInLbs) + (forInput ? "" : " lbs")
        } else {
            return String(format: "%.1f", weightInKg) + (forInput ? "" : " kg")
        }
    }
    
    /// Formats a height in meters for the specified unit system.
    /// - Parameters:
    ///   - heightInMeters: The height in meters, or `nil` if unavailable.
    ///   - system: The unit system (imperial or metric).
    ///   - forInput: If `true`, formats for text input (e.g., "5,10" for feet,inches); otherwise, includes units (e.g., "5 ft 10 in").
    /// - Returns: A formatted string (e.g., "5 ft 10 in" or "" for input), or "–" for nil/invalid inputs.
    static func formattedHeight(for heightInMeters: Double?, in system: UnitSystem, forInput: Bool = false) -> String {
        guard let heightInMeters = heightInMeters, heightInMeters >= 0 else {
            logger.warning("Invalid height: \(String(describing: heightInMeters)) meters")
            return forInput ? "" : "–"
        }
        
        if system == .imperial {
            let totalInches = heightInMeters / 0.0254
            let feet = Int(totalInches / 12)
            let inches = Int(round(totalInches.truncatingRemainder(dividingBy: 12)))
            return forInput ? "\(feet),\(inches)" : "\(feet) ft \(inches) in"
        } else {
            return String(format: "%.2f", heightInMeters) + (forInput ? "" : " m")
        }
    }
    
    /// Formats a date into a short time string (e.g., "10:30 AM").
    /// - Parameter date: The date to format.
    /// - Returns: A formatted time string.
    static func shortTime(from date: Date) -> String {
        shortTimeFormatter.string(from: date)
    }
    
    /// Formats a date into a medium date string (e.g., "Sep 12, 2023").
    /// - Parameter date: The date to format.
    /// - Returns: A formatted date string.
    static func mediumDate(from date: Date) -> String {
        mediumDateFormatter.string(from: date)
    }
}


