//
//  HealthKitManager.swift
//  ForgeSync
//
//  Created by Joseph DeWeese on 8/21/25.
//

import HealthKit
import SwiftData
import os.log

@MainActor
class HealthKitManager: ObservableObject {
    static let shared = HealthKitManager()
    let healthStore: HKHealthStore
   
    @Published var isAuthorized: Bool = false
    private var currentAppleUserId: String?
    private var modelContext: ModelContext?
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.forgesync.default.subsystem", category: "HealthKitManager")
    
    private init() {
        self.healthStore = HKHealthStore()
        logger.info("Initializing HealthKitManager")
    }
    
    @MainActor
    init(mockHealthStore: HKHealthStore) {
        self.healthStore = mockHealthStore
        logger.info("Initializing HealthKitManager with mock health store")
    }
    
    func updateCurrentAuthorizationStatusForTesting(authorized: Bool) {
        guard ProcessInfo.processInfo.arguments.contains("-testMode") else {
            logger.warning("Attempted to set authorization status outside test mode")
            return
        }
        isAuthorized = authorized
        logger.info("Test mode: Set isAuthorized to \(authorized)")
    }
    
    func configureWithModelContext(_ context: ModelContext) {
        self.modelContext = context
        updateCurrentAuthorizationStatus()
        logger.info("HealthKitManager configured with ModelContext. Current auth status updated.")
    }
    
    func setCurrentAppleUserId(_ appleUserId: String?) {
        self.currentAppleUserId = appleUserId
        if let id = appleUserId {
            logger.info("HealthKitManager: Current Apple User ID set to \(id.prefix(8))")
        } else {
            logger.info("HealthKitManager: Current Apple User ID cleared.")
        }
    }
    
    private func fetchUser() -> User? {
        guard let context = modelContext, let appleUserId = currentAppleUserId else {
            logger.error("ModelContext or currentAppleUserId not available in HealthKitManager for fetchUser")
            return nil
        }
        let predicate = #Predicate<User> { $0.appleUserId == appleUserId }
        let descriptor = FetchDescriptor<User>(predicate: predicate)
        do {
            let users = try context.fetch(descriptor)
            if let user = users.first {
                logger.info("User for Apple ID \(appleUserId.prefix(8)) fetched in HealthKitManager.")
                return user
            } else {
                logger.info("User for Apple ID \(appleUserId.prefix(8)) not found in HealthKitManager.")
                return nil
            }
        } catch {
            logger.error("Failed to fetch user with Apple ID \(appleUserId.prefix(8)): \(error.localizedDescription)")
            return nil
        }
    }
    
    func updateCurrentAuthorizationStatus() {
        guard HKHealthStore.isHealthDataAvailable() else {
            DispatchQueue.main.async { self.isAuthorized = false }
            return
        }
        let workoutType = HKObjectType.workoutType()
        healthStore.getRequestStatusForAuthorization(toShare: [workoutType], read: []) { [weak self] (status, error) in
            DispatchQueue.main.async {
                if let error = error {
                    self?.logger.error("Error checking HealthKit request status: \(error.localizedDescription)")
                    self?.isAuthorized = false
                    return
                }
                switch status {
                case .unnecessary:
                    self?.logger.info("HealthKit authorization status for workouts: unnecessary (likely already authorized).")
                    self?.isAuthorized = true
                case .shouldRequest:
                    self?.logger.info("HealthKit authorization status for workouts: shouldRequest (not yet prompted or user can change).")
                    self?.isAuthorized = false
                case .unknown:
                    self?.logger.info("HealthKit authorization status for workouts: unknown.")
                    self?.isAuthorized = false
                @unknown default:
                    self?.logger.info("HealthKit authorization status for workouts: unknown default case.")
                    self?.isAuthorized = false
                }
            }
        }
    }
    
    func requestHealthKitPermissions(completion: @escaping (Bool, Error?) -> Void = { _, _ in }) {
        guard HKHealthStore.isHealthDataAvailable() else {
            logger.error("HealthKit is not available on this device.")
            DispatchQueue.main.async {
                self.isAuthorized = false
                completion(false, HealthKitError.healthDataUnavailable)
            }
            return
        }
        let typesToShare: Set<HKSampleType> = [
            HKObjectType.workoutType(),
            HKQuantityType.quantityType(forIdentifier: .heartRate)!,
            HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!
        ]
        let typesToRead: Set = [
            HKObjectType.workoutType(),
            HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKQuantityType.quantityType(forIdentifier: .bodyMass)!,
            HKQuantityType.quantityType(forIdentifier: .height)!,
            HKCharacteristicType.characteristicType(forIdentifier: .dateOfBirth)!,
            HKCharacteristicType.characteristicType(forIdentifier: .biologicalSex)!,
            HKQuantityType.quantityType(forIdentifier: .restingHeartRate)!,
            HKQuantityType.quantityType(forIdentifier: .heartRate)!
        ]
        
        healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead) { [weak self] success, error in
            DispatchQueue.main.async {
                self?.isAuthorized = success
                if success {
                    self?.logger.info("HealthKit authorization successful for types: \(typesToShare.map { $0.identifier }.joined(separator: ", "))")
                } else {
                    let message = error?.localizedDescription ?? "Unknown error"
                    self?.logger.error("HealthKit authorization failed: \(message)")
                }
                completion(success, error)
            }
        }
    }
    
    func saveWorkout(_ workout: Workout, history: History, samples: [HKSample]) async throws -> Bool {
        guard isAuthorized else {
            logger.error("Cannot save workout: HealthKit not authorized.")
            throw HealthKitError.authorizationFailed("Permission not granted to save workout.")
        }
        
        guard history.lastSessionDuration > 0 else {
            logger.error("Invalid workout duration: \(history.lastSessionDuration)")
            throw HealthKitError.invalidWorkoutDuration
        }
        
        let workoutConfiguration = HKWorkoutConfiguration()
        if let category = workout.category {
            workoutConfiguration.activityType = category.categoryColor.hkActivityType
        } else {
            workoutConfiguration.activityType = .other
        }
        
        let startDate = history.date
        let endDate = startDate.addingTimeInterval(history.lastSessionDuration * 60.0)
        
        let workoutBuilder = HKWorkoutBuilder(
            healthStore: healthStore,
            configuration: workoutConfiguration,
            device: nil
        )
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            workoutBuilder.beginCollection(withStart: startDate) { success, error in
                if let error = error {
                    self.logger.error("Failed to begin workout collection: \(error.localizedDescription)")
                    continuation.resume(throwing: HealthKitError.workoutSaveFailed(error.localizedDescription))
                    return
                }
                guard success else {
                    self.logger.error("Failed to begin workout collection (success=false)")
                    continuation.resume(throwing: HealthKitError.workoutSaveFailed("Failed to begin workout collection"))
                    return
                }
                continuation.resume()
            }
        }
        
        if !samples.isEmpty {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                workoutBuilder.add(samples) { success, error in
                    if let error = error {
                        self.logger.error("Failed to add samples: \(error.localizedDescription)")
                        continuation.resume(throwing: HealthKitError.workoutSaveFailed("Failed to add samples: \(error.localizedDescription)"))
                        return
                    }
                    guard success else {
                        self.logger.error("Failed to add samples (success=false)")
                        continuation.resume(throwing: HealthKitError.workoutSaveFailed("Failed to add samples"))
                        return
                    }
                    continuation.resume()
                }
            }
        }
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            workoutBuilder.endCollection(withEnd: endDate) { success, error in
                if let error = error {
                    self.logger.error("Failed to end workout collection: \(error.localizedDescription)")
                    continuation.resume(throwing: HealthKitError.workoutSaveFailed(error.localizedDescription))
                    return
                }
                guard success else {
                    self.logger.error("Failed to end workout collection (success=false)")
                    continuation.resume(throwing: HealthKitError.workoutSaveFailed("Failed to end workout collection"))
                    return
                }
                continuation.resume()
            }
        }
        
        let savedWorkout = try await workoutBuilder.finishWorkout()
        logger.info("Successfully saved workout to HealthKit: \(workout.title)")
        return savedWorkout != nil
    }
    
    func fetchAllUserProfileData() {
        guard isAuthorized else {
            logger.warning("Cannot fetch user profile data: HealthKit is not authorized.")
            return
        }
        logger.info("Attempting to fetch all user profile data from HealthKit...")
        
        fetchDateOfBirthAndAge { [weak self] age, error in
            guard let self else { return }
            DispatchQueue.main.async {
                if let error = error {
                    self.logger.error("Failed to fetch age: \(error.localizedDescription)")
                    return
                }
                if let age = age, let user = self.fetchUser() {
                    if user.age != age {
                     //  user.age = age
                        self.saveContext()
                        self.logger.info("Updated user age: \(age)")
                    } else {
                        self.logger.trace("Fetched age (\(age)) matches existing user data. No update needed.")
                    }
                } else if age == nil {
                    self.logger.info("No age data found in HealthKit.")
                } else if self.fetchUser() == nil {
                    self.logger.warning("No user found to update age.")
                }
            }
        }
        
        fetchLatestRestingHeartRate { [weak self] heartRate, error in
            guard let self else { return }
            DispatchQueue.main.async {
                if let error = error {
                    self.logger.error("Failed to fetch resting heart rate: \(error.localizedDescription)")
                    return
                }
                if let heartRate = heartRate, let user = self.fetchUser() {
                    if user.restingHeartRate != heartRate {
                        user.restingHeartRate = heartRate
                        self.saveContext()
                        self.logger.info("Updated user resting heart rate: \(heartRate) bpm")
                    } else {
                        self.logger.trace("Fetched RHR (\(heartRate)) matches existing user data. No update needed.")
                    }
                } else if heartRate == nil {
                    self.logger.info("No resting heart rate data found in HealthKit.")
                } else if self.fetchUser() == nil {
                    self.logger.warning("No user found to update resting heart rate.")
                }
            }
        }
        
        fetchLatestWeight { [weak self] weightKg, error in
            guard let self else { return }
            DispatchQueue.main.async {
                if let error = error {
                    self.logger.error("Failed to fetch weight: \(error.localizedDescription)")
                    return
                }
                if let weightKg = weightKg, let user = self.fetchUser() {
                    let tolerance = 0.01
                    if abs((user.weight ?? 0.0) - weightKg) > tolerance {
                        user.weight = weightKg
                        self.saveContext()
                        self.logger.info("Updated user weight: \(weightKg) kg")
                    } else {
                        self.logger.trace("Fetched weight (\(weightKg) kg) matches existing user data (within tolerance). No update needed.")
                    }
                } else if weightKg == nil {
                    self.logger.info("No weight data found in HealthKit.")
                } else if self.fetchUser() == nil {
                    self.logger.warning("No user found to update weight.")
                }
            }
        }
        
        fetchLatestHeight { [weak self] heightMeters, error in
            guard let self else { return }
            DispatchQueue.main.async {
                if let error = error {
                    self.logger.error("Failed to fetch height: \(error.localizedDescription)")
                    return
                }
                if let heightMeters = heightMeters, let user = self.fetchUser() {
                    let tolerance = 0.001
                    if abs((user.height ?? 0.0) - heightMeters) > tolerance {
                        user.height = heightMeters
                        self.saveContext()
                        self.logger.info("Updated user height: \(heightMeters) m")
                    } else {
                        self.logger.trace("Fetched height (\(heightMeters) m) matches existing user data (within tolerance). No update needed.")
                    }
                } else if heightMeters == nil {
                    self.logger.info("No height data found in HealthKit.")
                } else if self.fetchUser() == nil {
                    self.logger.warning("No user found to update height.")
                }
            }
        }
    }
    
    func fetchLatestRestingHeartRate(completion: @escaping (Double?, Error?) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            logger.error("HealthKit is not available on this device")
            completion(nil, HealthKitError.healthDataUnavailable)
            return
        }
        
        guard let heartRateType = HKObjectType.quantityType(forIdentifier: .restingHeartRate) else {
            logger.error("Resting heart rate type is not available")
            completion(nil, HealthKitError.heartRateDataUnavailable)
            return
        }
        
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let query = HKSampleQuery(sampleType: heartRateType, predicate: nil, limit: 1, sortDescriptors: [sortDescriptor]) { [weak self] _, samples, error in
            if let error = error {
                self?.logger.error("Failed to fetch resting heart rate: \(error.localizedDescription)")
                completion(nil, error)
                return
            }
            
            guard let sample = samples?.first as? HKQuantitySample else {
                self?.logger.info("No resting heart rate samples found")
                completion(nil, nil)
                return
            }
            
            let heartRate = sample.quantity.doubleValue(for: HKUnit(from: "count/min"))
            self?.logger.info("Fetched resting heart rate: \(heartRate) bpm")
            completion(heartRate, nil)
        }
        
        logger.debug("Executing resting heart rate query")
        healthStore.execute(query)
    }
    
    func fetchDateOfBirthAndAge(completion: @escaping (Int?, Error?) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            logger.error("HealthKit is not available on this device")
            completion(nil, HealthKitError.healthDataUnavailable)
            return
        }
        
        do {
            let dateOfBirthComponents = try healthStore.dateOfBirthComponents()
            guard let birthDate = dateOfBirthComponents.date else {
                logger.error("No birth date available in HealthKit")
                completion(nil, NSError(domain: "HealthKit", code: -1, userInfo: [NSLocalizedDescriptionKey: "No birth date available"]))
                return
            }
            
            let age = Calendar.current.dateComponents([.year], from: birthDate, to: Date()).year
            logger.info("Fetched user age: \(age ?? -1)")
            completion(age, nil)
        } catch {
            logger.error("Failed to fetch date of birth: \(error.localizedDescription)")
            completion(nil, error)
        }
    }
    
    func fetchLatestWeight(completion: @escaping (Double?, Error?) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            logger.error("[fetchLatestWeight] HealthKit is not available.")
            completion(nil, HealthKitError.healthDataUnavailable)
            return
        }
        guard let weightType = HKObjectType.quantityType(forIdentifier: .bodyMass) else {
            logger.error("[fetchLatestWeight] Body mass type is not available.")
            completion(nil, NSError(domain: "HealthKit", code: -1, userInfo: [NSLocalizedDescriptionKey: "Body mass type unavailable"]))
            return
        }
        
        logger.debug("[fetchLatestWeight] Preparing HKSampleQuery for bodyMass.")
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let query = HKSampleQuery(sampleType: weightType, predicate: nil, limit: 1, sortDescriptors: [sortDescriptor]) { [weak self] _, samples, error in
            if let error = error {
                self?.logger.error("[fetchLatestWeight] Failed query: \(error.localizedDescription)")
                completion(nil, error)
                return
            }
            guard let sample = samples?.first as? HKQuantitySample else {
                self?.logger.info("[fetchLatestWeight] No bodyMass samples found in HealthKit.")
                completion(nil, nil)
                return
            }
            let weightInKg = sample.quantity.doubleValue(for: .gramUnit(with: .kilo))
            self?.logger.info("[fetchLatestWeight] Successfully fetched weight: \(weightInKg) kg from HealthKit.")
            completion(weightInKg, nil)
        }
        logger.debug("[fetchLatestWeight] Executing HKSampleQuery for bodyMass.")
        healthStore.execute(query)
    }
    
    func fetchLatestHeight(completion: @escaping (Double?, Error?) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            logger.error("[fetchLatestHeight] HealthKit is not available.")
            completion(nil, HealthKitError.healthDataUnavailable)
            return
        }
        guard let heightType = HKObjectType.quantityType(forIdentifier: .height) else {
            logger.error("[fetchLatestHeight] Height type is not available.")
            completion(nil, NSError(domain: "HealthKit", code: -1, userInfo: [NSLocalizedDescriptionKey: "Height type unavailable"]))
            return
        }
        
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let query = HKSampleQuery(sampleType: heightType, predicate: nil, limit: 1, sortDescriptors: [sortDescriptor]) { [weak self] _, samples, error in
            if let error = error {
                self?.logger.error("[fetchLatestHeight] Failed query: \(error.localizedDescription)")
                completion(nil, error)
                return
            }
            guard let sample = samples?.first as? HKQuantitySample else {
                self?.logger.info("[fetchLatestHeight] No samples found.")
                completion(nil, nil)
                return
            }
            let heightInMeters = sample.quantity.doubleValue(for: .meter())
            self?.logger.info("[fetchLatestHeight] Fetched: \(heightInMeters) m")
            completion(heightInMeters, nil)
        }
        logger.debug("[fetchLatestHeight] Executing query.")
        healthStore.execute(query)
    }
    
    private func saveContext() {
        guard let context = modelContext else {
            logger.error("ModelContext is nil. Cannot save HealthKit updates.")
            ErrorManager.shared.presentAlert(
                title: "Save Error",
                message: "Unable to save profile data due to missing database context."
            )
            return
        }
        if context.hasChanges {
            logger.info("[saveContext] ModelContext has changes. Attempting to save updates from HealthKit.")
            do {
                try context.save()
                logger.info("Saved ModelContext after HealthKitManager operations (update user from HealthKit or other metric calculations).")
            } catch {
                logger.error("Failed to save ModelContext after HealthKit update: \(error.localizedDescription)")
                ErrorManager.shared.presentAlert(
                    title: "Save Error",
                    message: "Failed to save profile data: \(error.localizedDescription)"
                )
            }
        } else {
            logger.trace("[saveContext] No changes detected in ModelContext before potential save operation for HealthKit data.")
        }
    }
    
    func calculateIntensityScore(dateInterval: DateInterval, restingHeartRate: Double?, completion: @escaping (Double?, Error?) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            logger.error("HealthKit is not available on this device")
            completion(nil, HealthKitError.healthDataUnavailable)
            return
        }
        
        guard let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate) else {
            logger.error("Heart rate type is not available")
            completion(nil, HealthKitError.heartRateDataUnavailable)
            return
        }
        
        guard let user = fetchUser(), let maxHR = user.maxHeartRate ?? (user.age != nil ? Double(220 - user.age!) : nil) else {
            logger.error("Cannot calculate intensity: missing user data or max heart rate")
            completion(nil, NSError(domain: "HealthKitManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "User data or max heart rate unavailable"]))
            return
        }
        
        let predicate = HKQuery.predicateForSamples(withStart: dateInterval.start, end: dateInterval.end, options: .strictStartDate)
        let query = HKStatisticsQuery(quantityType: heartRateType, quantitySamplePredicate: predicate, options: .discreteAverage) { [weak self] _, result, error in
            guard let self else { return }
            if let error = error {
                self.logger.error("Failed to fetch average heart rate: \(error.localizedDescription)")
                completion(nil, error)
                return
            }
            
            guard let avgHR = result?.averageQuantity()?.doubleValue(for: HKUnit(from: "count/min")) else {
                self.logger.info("No heart rate samples found for intensity calculation")
                completion(nil, nil)
                return
            }
            
            guard let restingHR = restingHeartRate, restingHR > 0, maxHR > restingHR else {
                self.logger.error("Invalid resting heart rate (\(restingHeartRate ?? -1)) or max heart rate (\(maxHR)) for intensity calculation")
                completion(nil, NSError(domain: "HealthKitManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid heart rate data"]))
                return
            }
            
            let score = ((avgHR - restingHR) / (maxHR - restingHR)) * 100
            let clampedScore = max(0, min(100, score))
            self.logger.info("Calculated intensity score: \(clampedScore)% (avgHR: \(avgHR), restingHR: \(restingHR), maxHR: \(maxHR))")
            completion(clampedScore, nil)
        }
        
        logger.debug("Executing intensity score query")
        healthStore.execute(query)
    }
    
    func calculateTimeInZones(dateInterval: DateInterval, maxHeartRate: Double?, completion: @escaping ([Int: Double]?, Int?, Error?) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            logger.error("HealthKit is not available on this device")
            completion(nil, nil, HealthKitError.healthDataUnavailable)
            return
        }
        
        guard let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate) else {
            logger.error("Heart rate type is not available")
            completion(nil, nil, HealthKitError.heartRateDataUnavailable)
            return
        }
        
        guard let maxHR = maxHeartRate, maxHR > 0 else {
            logger.error("Max heart rate unavailable or invalid (\(maxHeartRate ?? -1))")
            completion(nil, nil, NSError(domain: "HealthKitManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Max heart rate unavailable"]))
            return
        }
        
        let predicate = HKQuery.predicateForSamples(withStart: dateInterval.start, end: dateInterval.end, options: .strictStartDate)
        let query = HKSampleQuery(sampleType: heartRateType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { [weak self] _, samples, error in
            guard let self else { return }
            if let error = error {
                self.logger.error("Failed to fetch heart rate samples: \(error.localizedDescription)")
                completion(nil, nil, error)
                return
            }
            
            guard let heartRateSamples = samples as? [HKQuantitySample], !heartRateSamples.isEmpty else {
                self.logger.info("No heart rate samples found for zone calculation")
                completion(nil, nil, nil)
                return
            }
            
            var timeInZones: [Int: Double] = [1: 0, 2: 0, 3: 0, 4: 0, 5: 0]
            for i in 0..<heartRateSamples.count - 1 {
                let sample = heartRateSamples[i]
                let nextSample = heartRateSamples[i + 1]
                let hr = sample.quantity.doubleValue(for: HKUnit(from: "count/min"))
                let duration = nextSample.startDate.timeIntervalSince(sample.startDate)
                
                let percentage = hr / maxHR
                let zone: Int
                if percentage < 0.5 { zone = 1 }
                else if percentage < 0.6 { zone = 2 }
                else if percentage < 0.7 { zone = 3 }
                else if percentage < 0.8 { zone = 4 }
                else { zone = 5 }
                
                timeInZones[zone, default: 0] += duration
            }
            
            let dominantZone = timeInZones.max(by: { $0.value < $1.value })?.key
            self.logger.info("Calculated time in zones: \(timeInZones), dominant zone: \(dominantZone ?? -1)")
            completion(timeInZones, dominantZone, nil)
        }
        
        logger.debug("Executing time in zones query")
        healthStore.execute(query)
    }
    
    func calculateProgressPulseScore(fastestTime: Double, currentDuration: Double, workoutsPerWeek: Int, targetWorkoutsPerWeek: Int, dominantZone: Int?) -> Double? {
        logger.info("[HealthKitManager] calculateProgressPulseScore called.")
        var score = 50.0
        
        if currentDuration <= fastestTime {
            score += 15
            logger.debug("[ProgressPulse] Beat or matched PR: +15 points. Current: \(currentDuration), FT: \(fastestTime)")
        } else {
            logger.debug("[ProgressPulse] Slower than PR. Current: \(currentDuration), FT: \(fastestTime)")
        }
        
        let frequencyPoints = Double(min(workoutsPerWeek, targetWorkoutsPerWeek) * 5)
        score += frequencyPoints
        logger.debug("[ProgressPulse] Frequency points: +\(frequencyPoints) (Workouts this week: \(workoutsPerWeek), Target: \(targetWorkoutsPerWeek))")
        
        if let zone = dominantZone {
            if zone >= 4 {
                score += 10
                logger.debug("[ProgressPulse] High intensity (Zone \(zone)): +10 points")
            } else if zone == 3 {
                score += 5
                logger.debug("[ProgressPulse] Moderate intensity (Zone \(zone)): +5 points")
            } else {
                logger.debug("[ProgressPulse] Low intensity (Zone \(zone)): +0 points")
            }
        } else {
            logger.debug("[ProgressPulse] Dominant zone not available: +0 points for intensity.")
        }
        
        let finalScore = min(max(score, 0), 100)
        logger.info("[HealthKitManager] Progress Pulse score calculated: \(finalScore)")
        return finalScore
    }
    
    struct HKFetchedWorkout: Identifiable {
        let id: UUID
        let activityType: HKWorkoutActivityType
        let startDate: Date
        let endDate: Date
        let duration: TimeInterval
        let totalEnergyBurned: Double?
        let totalDistance: Double?
        let sourceName: String
    }
    
    func fetchWorkoutsFromHealthKit(from queryStartDate: Date = .distantPast, to queryEndDate: Date = .now) async throws -> [HKFetchedWorkout] {
        guard HKHealthStore.isHealthDataAvailable() else {
            logger.error("[fetchWorkoutsFromHealthKit] HealthKit is not available.")
            throw HealthKitError.healthDataUnavailable
        }
        
        let workoutType = HKObjectType.workoutType()
        let predicate = HKQuery.predicateForSamples(withStart: queryStartDate, end: queryEndDate, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        
        logger.info("[fetchWorkoutsFromHealthKit] Fetching workouts from \(queryStartDate) to \(queryEndDate).")
        
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: workoutType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sortDescriptor]) { [weak self] _, samples, error in
                guard let strongSelf = self else {
                    continuation.resume(throwing: NSError(domain: "HealthKitManager", code: 0, userInfo: [NSLocalizedDescriptionKey: "Self deallocated"]))
                    return
                }
                
                if let error = error {
                    strongSelf.logger.error("[fetchWorkoutsFromHealthKit] Error fetching workouts: \(error.localizedDescription)")
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let workouts = samples as? [HKWorkout] else {
                    strongSelf.logger.info("[fetchWorkoutsFromHealthKit] No workouts found or samples are not HKWorkout type.")
                    continuation.resume(returning: [])
                    return
                }
                
                let fetchedWorkouts = workouts.map { workout -> HKFetchedWorkout in
                    // Use statisticsForType to fetch active energy burned (iOS 18+)
                    var energyBurned: Double?
                    if let stats = workout.statistics(for: HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!) {
                        energyBurned = stats.sumQuantity()?.doubleValue(for: .kilocalorie())
                    }
                    let distance = workout.totalDistance?.doubleValue(for: .meter())
                    
                    return HKFetchedWorkout(
                        id: workout.uuid,
                        activityType: workout.workoutActivityType,
                        startDate: workout.startDate,
                        endDate: workout.endDate,
                        duration: workout.duration,
                        totalEnergyBurned: energyBurned,
                        totalDistance: distance,
                        sourceName: workout.sourceRevision.source.name
                    )
                }
                strongSelf.logger.info("[fetchWorkoutsFromHealthKit] Successfully fetched \(fetchedWorkouts.count) workouts.")
                continuation.resume(returning: fetchedWorkouts)
            }
            self.healthStore.execute(query)
        }
    }
}


