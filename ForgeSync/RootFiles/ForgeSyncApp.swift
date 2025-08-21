//
//  ForgeSyncApp.swift
//  ForgeSync
//
//  Created by Joseph DeWeese on 8/21/25.
//

/// The main entry point for the ForgeSync app, configuring the SwiftUI app lifecycle.
/// Sets up the SwiftData model container, authentication, health integration, and appearance settings.
/// Manages environment objects for authentication, health data, and error handling.
import SwiftUI
import SwiftData
import UserNotifications

/// The main app struct for ForgeSync, conforming to the `App` protocol.
/// Initializes the data model, core managers, and UI scene, applying user-selected appearance settings.
/// Populates initial workout categories if none exist in the data store.
@main
struct ForgeSyncApp: App {
    /// The authentication manager, initialized with dependencies for user management.
    @StateObject private var authManager: AuthenticationManager
    /// The health manager.
    @StateObject private var healthKitManager = HealthKitManager.shared
    /// The error manager, responsible for centralized error handling and alerts.
    @StateObject private var errorManager = ErrorManager.shared

    /// The user’s preferred appearance setting (system, light, or dark), stored persistently.
    @AppStorage("appearanceSetting") private var appearanceSetting: AppearanceSetting = .system

    /// The SwiftData model container for managing User, Profile, Workout categories, Workout, Exercise and SplitTime data of exercises, History as well as App Settings and preferences.
    let modelContainer: ModelContainer

    /// Initializes the app, setting up the model container and core managers.
    /// Configures HealthKit, authentication, and initial data population.
    /// - Note: Terminates the app with a fatal error if the model container cannot be initialized.
    init() {
        do {
            modelContainer = try ModelContainer(for: Workout.self, User.self, Category.self, Exercise.self, History.self, SplitTime.self)
            
            let errorManager = ErrorManager.shared
            let healthKitManager = HealthKitManager.shared
            
            healthKitManager.configureWithModelContext(modelContainer.mainContext)
            
            let authManagerInstance = AuthenticationManager(
                modelContext: modelContainer.mainContext,
                errorManager: errorManager,
                healthKitManager: healthKitManager
            )
            
            self._authManager = StateObject(wrappedValue: authManagerInstance)
            
            authManagerInstance.loadUserAfterInitialization()
            
            healthKitManager.setCurrentAppleUserId(authManagerInstance.currentAppleUser?.appleUserId)
            
            populateCategories(context: modelContainer.mainContext)
            
            print("[App init] ModelContainer and core managers initialized.")
        } catch {
            fatalError("Could not initialize ModelContainer: \(error)")
        }
    }

    /// Defines the app’s scene, providing the main content view and environment objects.
    /// - Returns: A `WindowGroup` scene with `ContentView` configured with environment objects and appearance settings.
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authManager)
                .environmentObject(healthKitManager)
                .environmentObject(errorManager)
                .preferredColorScheme(appearanceSetting.colorScheme)
                .alert(item: $errorManager.currentAlert) { appAlert in
                    if let secondaryButton = appAlert.secondaryButton {
                        Alert(
                            title: Text(appAlert.title),
                            message: Text(appAlert.message),
                            primaryButton: appAlert.primaryButton,
                            secondaryButton: secondaryButton
                        )
                    } else {
                        Alert(
                            title: Text(appAlert.title),
                            message: Text(appAlert.message),
                            dismissButton: appAlert.primaryButton
                        )
                    }
                }
        }
        .modelContainer(modelContainer)
    }
    
    /// Populates the data store with initial workout categories if none exist.
    /// - Parameter context: The SwiftData model context to insert categories into.
    private func populateCategories(context: ModelContext) {
        print("[populateCategories] Checking if initial category population is needed.")
        let fetchDescriptor = FetchDescriptor<Category>()
        
        do {
            let count = try context.fetchCount(fetchDescriptor)
            guard count == 0 else {
                print("[populateCategories] Categories already exist (count: \(count)). Skipping initial population.")
                return
            }
            
            print("[populateCategories] Store is empty. Populating all initial categories.")
            let categories = [
                Category(categoryName: "HIIT", symbol: "dumbbell.fill", categoryColor: .HIIT),
                Category(categoryName: "Strength", symbol: "figure.strengthtraining.traditional", categoryColor: .STRENGTH),
                Category(categoryName: "Run", symbol: "figure.run", categoryColor: .RUN),
                Category(categoryName: "Yoga", symbol: "figure.yoga", categoryColor: .YOGA),
                Category(categoryName: "Cycling", symbol: "figure.outdoor.cycle", categoryColor: .CYCLING),
                Category(categoryName: "Swimming", symbol: "figure.pool.swim", categoryColor: .SWIMMING),
                Category(categoryName: "Wrestling", symbol: "figure.wrestling", categoryColor: .GRAPPLING),
                Category(categoryName: "Recovery", symbol: "figure.mind.and.body", categoryColor: .RECOVERY),
                Category(categoryName: "Walk", symbol: "figure.walk.motion", categoryColor: .WALK),
                Category(categoryName: "Stretch", symbol: "figure.cooldown", categoryColor: .STRETCH),
                Category(categoryName: "Cross-Train", symbol: "figure.cross.training", categoryColor: .CROSSTRAIN),
                Category(categoryName: "Power", symbol: "figure.strengthtraining.traditional", categoryColor: .POWER),
                Category(categoryName: "Pilates", symbol: "figure.pilates", categoryColor: .PILATES),
                Category(categoryName: "Cardio", symbol: "figure.mixed.cardio", categoryColor: .CARDIO),
                Category(categoryName: "Test", symbol: "stopwatch", categoryColor: .TEST),
                Category(categoryName: "Hiking", symbol: "figure.hiking", categoryColor: .HIKING),
                Category(categoryName: "Rowing", symbol: "figure.outdoor.rowing", categoryColor: .ROWING)
            ]
            
            for category in categories {
                context.insert(category)
            }
            
            try context.save()
            print("[populateCategories] Successfully populated all initial categories.")
        } catch {
            print("[populateCategories] Error during category population: \(error)")
        }
        print("[populateCategories] Finished initial category population.")
    }
}
