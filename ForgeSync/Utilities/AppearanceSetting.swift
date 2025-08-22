//
//  AppearanceSetting.swift
//  ForgeSync
//
//  Created by Joseph DeWeese on 8/21/25.
//

import Foundation
import SwiftUI

/// An enumeration of appearance settings for the app’s color scheme, used in the settings picker.
/// Conforms to `CaseIterable` and `Identifiable` for SwiftUI picker compatibility.
enum AppearanceSetting: String, CaseIterable, Identifiable {
    /// Follows the system’s light or dark mode.
    case system = "System Default"
    /// Forces light mode.
    case light = "Light Mode"
    /// Forces dark mode.
    case dark = "Dark Mode"
    
    /// A unique identifier for the appearance setting.
    var id: String { self.rawValue }
    
    /// The display name for the picker UI.
    var displayName: String {
        return self.rawValue
    }
    /// The corresponding SwiftUI color scheme, or nil for system default.
    var colorScheme: ColorScheme? {
        switch self {
        case .light:
            return .light
        case .dark:
            return .dark
        case .system:
            return nil
        }
    }
}
