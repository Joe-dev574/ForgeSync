//
//  UnitSystem.swift
//  ForgeSync
//
//  Created by Joseph DeWeese on 8/21/25.
//

import Foundation


/// An enumeration of unit systems for weight and height measurements, used in the settings picker.
/// Conforms to `CaseIterable` and `Identifiable` for SwiftUI picker compatibility.
enum UnitSystem: String, CaseIterable, Identifiable {
    /// Metric system using kilograms and meters.
    case metric = "Metric (kg, m)"
    /// Imperial system using pounds and feet.
    case imperial = "Imperial (lbs, ft)"
    
    /// A unique identifier for the unit system.
    var id: String { self.rawValue }
    
    /// The display name for the picker UI.
    var displayName: String {
        switch self {
        case .metric:
            return "Metric (kg, m)"
        case .imperial:
            return "Imperial (lbs, ft)"
        }
    }
}
