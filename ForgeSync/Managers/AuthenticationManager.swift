//
//  AuthenticationManager.swift
//  ForgeSync
//
//  Created by Joseph DeWeese on 8/21/25.
//

import SwiftUI
import AuthenticationServices
import SwiftData
import OSLog
import Security

/// Manages user authentication using Sign In with Apple, handling user sessions, Keychain storage, SwiftData integration, and HealthKit triggers.
@MainActor
final class AuthenticationManager: NSObject, ObservableObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    
    /// The currently authenticated user, updated on sign-in, sign-out, or profile refresh. Triggers HealthKit data fetching when set.
    @Published var currentAppleUser: User? {
        didSet {
            healthKitManager.setCurrentAppleUserId(currentAppleUser?.appleUserId)
            if let user = currentAppleUser {
                healthDataFetchTask?.cancel()
                healthDataFetchTask = Task {
                    await self.fetchHealthDataForCurrentUserIfNeeded(user: user)
                }
            }
        }
    }
    
    private let modelContext: ModelContext
    private let errorManager: ErrorManager
    private let healthKitManager: HealthKitManager
    private let keychainService: String
    private let appleUserIdKeychainAccount = "appleUserId"
    private let logger: Logger
    private var healthDataFetchTask: Task<Void, Never>?
    
    /// Errors that can occur during authentication or Keychain operations.
    enum AuthError: LocalizedError {
        case invalidBundleId
        case profileLoadFailed
        case keychainSaveFailed(status: OSStatus)
        case keychainLoadFailed(status: OSStatus)
        case keychainInvalidData
        var errorDescription: String? {
            switch self {
            case .invalidBundleId: "Configuration Error"
            case .profileLoadFailed: "Profile Error"
            case .keychainSaveFailed, .keychainLoadFailed, .keychainInvalidData: "Keychain Error"
            }
        }
        var failureReason: String? {
            switch self {
            case .invalidBundleId: "Application bundle identifier is missing."
            case .profileLoadFailed: "Could not load or create your user profile."
            case .keychainSaveFailed: "Failed to save user ID to Keychain."
            case .keychainLoadFailed: "Failed to load user ID from Keychain."
            case .keychainInvalidData: "Invalid data retrieved from Keychain."
            }
        }
        var recoverySuggestion: String? {
            switch self {
            case .invalidBundleId: "Contact support to resolve this issue."
            case .profileLoadFailed, .keychainSaveFailed, .keychainLoadFailed, .keychainInvalidData:
                "Please sign out and sign back in, or contact support."
            }
        }
    }
    
    /// Initializes the authentication manager with required dependencies.
    /// - Parameters:
    ///   - modelContext: The SwiftData context for user persistence.
    ///   - errorManager: The manager for presenting error alerts.
    ///   - healthKitManager: The manager for HealthKit interactions.
    init(modelContext: ModelContext, errorManager: ErrorManager, healthKitManager: HealthKitManager) {
        self.modelContext = modelContext
        self.errorManager = errorManager
        self.healthKitManager = healthKitManager
        guard let bundleId = Bundle.main.bundleIdentifier else {
            let logger = Logger(subsystem: "com.movesync.default.subsystem", category: "AuthenticationManager")
            logger.critical("Bundle identifier is nil. Cannot initialize AuthenticationManager.")
            fatalError("AuthenticationManager requires a valid bundle identifier.")
        }
        self.keychainService = bundleId
        self.logger = Logger(subsystem: bundleId, category: "AuthenticationManager")
        super.init()
        
        // Observe app resume for periodic credential checks
        NotificationCenter.default.addObserver(self, selector: #selector(appWillEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
    }
    
    /// Loads the user from storage after initialization. Safe to call post-init.
    func loadUserAfterInitialization() {
        attemptToLoadUserFromStorage()
    }
    
    /// Configures the Apple Sign-In request with desired scopes.
    /// - Parameter request: The Apple ID authorization request to configure.
    func handleSignInWithAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        request.requestedScopes = [.fullName, .email]
        logger.info("Handling Sign In With Apple request, scopes: fullName, email.")
    }
    
    /// Handles the result of a Sign In with Apple attempt.
    /// - Parameter result: The result of the authorization attempt.
    func handleSignInWithAppleCompletion(_ result: Result<ASAuthorization, Error>) {
        logger.info("Handling Sign In With Apple completion at \(Date()).")
        switch result {
        case .success(let authorization):
            guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                let errorMsg = "Failed to get Apple ID Credential."
                logger.error("\(errorMsg)")
                errorManager.presentAlert(
                    title: "Authentication Error",
                    message: "\(errorMsg) Open Settings to verify your Apple ID or try again later."
                )
                return
            }
            
            let userId = appleIDCredential.user
            let email = appleIDCredential.email
            let fullName = appleIDCredential.fullName
            
            logger.info("Sign In With Apple success for user ID: \(userId.prefix(4))...")
            
            do {
                try saveUserIdToKeychain(userId)
                logger.info("Apple User ID stored in Keychain.")
                try fetchOrCreateUser(userId: userId, email: email, fullName: fullName)
                checkCredentialState() // Verify credential state after sign-in
            } catch {
                logger.error("Authentication failed: \(error.localizedDescription)")
                errorManager.presentError(error as? LocalizedError ?? AuthError.keychainSaveFailed(status: -1))
                return
            }
            logger.info("Finished Sign In With Apple completion at \(Date()).")
            
        case .failure(let error):
            if let asError = error as? ASAuthorizationError {
                var specificErrorMessage = "An unknown Sign In With Apple error occurred."
                logger.error("Sign In With Apple ASAuthorizationError Code: \(asError.code.rawValue) - \(asError.localizedDescription)")
                switch asError.code {
                case .canceled:
                    specificErrorMessage = "Sign in with Apple was canceled by the user."
                    logger.info("\(specificErrorMessage)")
                    return
                case .failed:
                    specificErrorMessage = "Sign in with Apple failed."
                case .invalidResponse:
                    specificErrorMessage = "Sign in with Apple received an invalid response."
                case .notHandled:
                    specificErrorMessage = "Sign in with Apple was not handled."
                case .unknown:
                    specificErrorMessage = "An unknown Sign In With Apple error occurred."
                case .notInteractive:
                    specificErrorMessage = "Sign in with Apple was not interactive. Ensure the app is in the foreground."
                case .credentialImport:
                    specificErrorMessage = "Sign in with Apple encountered an issue importing credentials."
                case .matchedExcludedCredential:
                    specificErrorMessage = "Sign in with Apple matched a credential that has been excluded."
                case .credentialExport:
                    specificErrorMessage = "Sign in with Apple encountered an issue exporting credentials."
                @unknown default:
                    logger.error("Unexpected ASAuthorizationError.Code (\(asError.code.rawValue)) occurred.")
                    specificErrorMessage = "An unexpected error occurred during Sign in with Apple."
                }
                errorManager.presentAlert(
                    title: "Sign-In Failed",
                    message: "\(specificErrorMessage) Open Settings to verify your Apple ID or try again later."
                )
            } else {
                logger.error("Sign In With Apple failed with error: \(error.localizedDescription)")
                errorManager.presentAlert(
                    title: "Sign-In Error",
                    message: "An unexpected error occurred during sign in: \(error.localizedDescription). Open Settings to verify your Apple ID or try again later."
                )
            }
        }
    }
    
    /// Verifies the Apple ID credential state to handle revocations or transfers.
    func checkCredentialState() {
        guard let userId = currentAppleUser?.appleUserId ?? (try? loadUserIdFromKeychain()) else {
            logger.info("No user ID to check credential state.")
            return
        }
        let provider = ASAuthorizationAppleIDProvider()
        provider.getCredentialState(forUserID: userId) { state, error in
            if let error {
                self.logger.error("Credential state check failed: \(error.localizedDescription)")
                return
            }
            switch state {
            case .revoked, .transferred:
                self.logger.warning("Credential state is \(state.rawValue). Signing out.")
                self.signOut()
                self.errorManager.presentAlert(
                    title: "Session Expired",
                    message: "Your Apple ID session is no longer valid. Please sign in again."
                )
            case .authorized:
                self.logger.info("Credential state is authorized.")
            case .notFound:
                self.logger.warning("Credential not found. Signing out.")
                self.signOut()
            @unknown default:
                self.logger.error("Unknown credential state: \(state.rawValue)")
            }
        }
    }
    
    /// Fetches an existing user from SwiftData or creates a new one.
    /// - Parameters:
    ///   - userId: The Apple user ID.
    ///   - email: The user’s email, if provided.
    ///   - fullName: The user’s full name, if provided.
    /// - Throws: `AuthError` if fetching or saving fails.
    private func fetchOrCreateUser(userId: String, email: String?, fullName: PersonNameComponents?) throws {
        logger.info("Fetching or creating user with ID: \(userId.prefix(4))...")
        
        let fetchDescriptor = FetchDescriptor<User>(
            predicate: #Predicate { $0.appleUserId == userId },
            sortBy: [] // Lightweight fetch
        )
        
        // Check for existing user in SwiftData
        if let existingUser = try modelContext.fetch(fetchDescriptor).first {
            logger.info("Found existing user in SwiftData.")
            var userNeedsSave = false
            
            // Update email if new, non-empty email is provided
            if let newEmail = email, !newEmail.isEmpty, existingUser.email != newEmail {
                existingUser.email = newEmail
                logger.info("Updating user email.")
                userNeedsSave = true
            }
            
            // Update name if new, non-empty name is provided
            if let personName = fullName {
                let formattedName = PersonNameComponentsFormatter().string(from: personName)
                if !formattedName.isEmpty, existingUser.displayName != formattedName {
                    existingUser.displayName = formattedName
                    logger.info("Updating user name.")
                    userNeedsSave = true
                } else if formattedName.isEmpty {
                    logger.warning("Received empty formatted name from PersonNameComponents.")
                }
            }
            
            // Save changes if needed
            if userNeedsSave {
                try modelContext.save()
                logger.info("Saved updated user to SwiftData.")
            }
            self.currentAppleUser = existingUser
            
        } else {
            // Create new user
            let newUser = User(appleUserId: userId)
            newUser.email = email
            if let personName = fullName {
                let formattedName = PersonNameComponentsFormatter().string(from: personName)
                if !formattedName.isEmpty {
                    newUser.displayName = formattedName
                }
            }
            newUser.isOnboardingComplete = false
            logger.info("Created new user in SwiftData.")
            
            modelContext.insert(newUser)
            try modelContext.save()
            self.currentAppleUser = newUser
        }
    }
    
    //MARK: Signs out the current user, clearing session and Keychain data.
    func signOut() {
        logger.info("Signing out user.")
        healthDataFetchTask?.cancel()
        do {
            try deleteUserIdFromKeychain()
            logger.info("Apple User ID removed from Keychain.")
        } catch {
            logger.error("Failed to remove Apple User ID from Keychain: \(error.localizedDescription)")
        }
        self.currentAppleUser = nil
        logger.info("User signed out.")
    }
    
    /// Loads a user from Keychain and SwiftData if available.
    func attemptToLoadUserFromStorage() {
        logger.info("Attempting to load user from Keychain and SwiftData.")
        
        guard let userId = try? loadUserIdFromKeychain() else {
            logger.info("No stored Apple User ID found in Keychain.")
            self.currentAppleUser = nil
            return
        }
        
        Task {
            await loadUserWithRetry(userId: userId)
        }
    }
    
    /// Loads user with retry logic to handle potential SwiftData sync delays.
    private func loadUserWithRetry(userId: String, retryCount: Int = 3, delay: TimeInterval = 1.0) async {
        let fetchDescriptor = FetchDescriptor<User>(
            predicate: #Predicate { $0.appleUserId == userId },
            sortBy: [] // Lightweight fetch
        )
        do {
            if let existingUser = try modelContext.fetch(fetchDescriptor).first {
                logger.info("User found in SwiftData.")
                self.currentAppleUser = existingUser
                if existingUser.displayName == nil || existingUser.displayName!.isEmpty {
                    logger.warning("User has missing name in profile.")
                }
            } else if retryCount > 0 {
                logger.warning("User ID found in Keychain but no matching user in SwiftData. Retrying after delay.")
                try? await Task.sleep(for: .seconds(delay)) // Async delay with backoff
                await loadUserWithRetry(userId: userId, retryCount: retryCount - 1, delay: delay * 2) // Exponential backoff
            } else {
                logger.info("No user found after retries. Clearing Keychain.")
                try? self.deleteUserIdFromKeychain()
                self.currentAppleUser = nil
            }
        } catch {
            logger.error("Error fetching user from SwiftData: \(error.localizedDescription)")
            self.currentAppleUser = nil
            self.errorManager.presentError(AuthError.profileLoadFailed)
        }
    }
    
    /// Fetches HealthKit data for the current user if conditions are met.
    /// - Parameter user: The user to fetch data for.
    private func fetchHealthDataForCurrentUserIfNeeded(user: User) async {
        guard user.isOnboardingComplete else {
            logger.info("Onboarding not complete for user. Prompting user.")
            errorManager.presentAlert(
                title: "Complete Onboarding",
                message: "Please complete onboarding to enable HealthKit data syncing."
            )
            return
        }
        
        if healthKitManager.isAuthorized {
            logger.info("User logged in, onboarding complete, and HealthKit authorized. Fetching profile data.")
            healthKitManager.fetchAllUserProfileData() // Remove try await if not async/throwing
        } else {
            logger.info("HealthKit not authorized. Awaiting user authorization.")
        }
    }
    
    /// Provides the presentation anchor for the authorization controller.
    /// - Parameter controller: The authorization controller requesting the anchor.
    /// - Returns: The window to use for presentation.
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        guard let window = UIWindow.current else {
            logger.critical("No window available for ASAuthorizationController presentation.")
            errorManager.presentAlert(
                title: "Authentication Error",
                message: "Unable to present sign-in interface. Ensure the app is active and try again."
            )
            return UIWindow(frame: UIScreen.main.bounds)
        }
        logger.info("Providing presentation anchor window.")
        return window
    }
    
    /// Refreshes the current user’s data from SwiftData.
    func refreshCurrentAppleUser() {
        logger.info("Refreshing current user data.")
        guard let userId = self.currentAppleUser?.appleUserId ?? (try? loadUserIdFromKeychain()) else {
            logger.warning("No user ID available for refresh.")
            if self.currentAppleUser != nil {
                signOut()
            }
            errorManager.presentAlert(
                title: "Session Error",
                message: "Your session data is inconsistent. Please sign out and sign back in."
            )
            return
        }
        
        let fetchDescriptor = FetchDescriptor<User>(
            predicate: #Predicate { $0.appleUserId == userId },
            sortBy: []
        )
        do {
            if let refreshedUser = try modelContext.fetch(fetchDescriptor).first {
                self.currentAppleUser = refreshedUser
                logger.info("User data refreshed.")
                checkCredentialState() // Verify credential state on refresh
            } else {
                logger.error("User data not found in database during refresh.")
                errorManager.presentError(AuthError.profileLoadFailed)
            }
        } catch {
            logger.error("Error refreshing user: \(error.localizedDescription)")
            errorManager.presentError(AuthError.profileLoadFailed)
        }
    }
    
    //MARK: Saves the Apple user ID to the Keychain.
    /// - Parameter userId: The user ID to store.
    /// - Throws: `AuthError` if the operation fails.
    private func saveUserIdToKeychain(_ userId: String) throws {
        guard let data = userId.data(using: .utf8) else {
            logger.error("Failed to convert userId to Data for Keychain.")
            throw AuthError.keychainInvalidData
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: appleUserIdKeychainAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock // Allows iCloud Keychain syncing
        ]
        
        // Unconditionally delete before add to handle updates
        SecItemDelete(query as CFDictionary)
        
        let addStatus = SecItemAdd(query as CFDictionary, nil)
        if addStatus == errSecSuccess {
            logger.info("Successfully saved userId to Keychain.")
        } else {
            logger.error("Failed to save userId to Keychain. Status: \(addStatus)")
            throw AuthError.keychainSaveFailed(status: addStatus)
        }
    }
    
    /// Loads the Apple user ID from the Keychain.
    /// - Returns: The user ID if found, `nil` otherwise.
    /// - Throws: `AuthError` if the operation fails.
    private func loadUserIdFromKeychain() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: appleUserIdKeychainAccount,
            kSecReturnData as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        
        if status == errSecSuccess {
            guard let retrievedData = dataTypeRef as? Data,
                  let userId = String(data: retrievedData, encoding: .utf8) else {
                logger.error("Failed to convert Keychain data to String.")
                try? deleteUserIdFromKeychain()
                throw AuthError.keychainInvalidData
            }
            logger.info("Successfully loaded userId from Keychain.")
            return userId
        } else if status == errSecItemNotFound {
            logger.info("UserId not found in Keychain.")
            return nil
        } else {
            logger.error("Failed to load userId from Keychain. Status: \(status)")
            throw AuthError.keychainLoadFailed(status: status)
        }
    }
    
    /// Deletes the Apple user ID from the Keychain.
    /// - Throws: `AuthError` if the operation fails.
    private func deleteUserIdFromKeychain() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: appleUserIdKeychainAccount
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        if status == errSecSuccess || status == errSecItemNotFound {
            logger.info("Successfully deleted userId from Keychain.")
        } else {
            logger.error("Failed to delete userId from Keychain. Status: \(status)")
            throw AuthError.keychainSaveFailed(status: status)
        }
    }
    
    // MARK: - Notification Handlers
    @objc private func appWillEnterForeground() {
        if currentAppleUser != nil {
            checkCredentialState()
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

/// Extension to retrieve the currently active UIWindow.
extension UIWindow {
    /// Returns the key window from the foreground active scene, or the first window from a foreground or connected scene if none is active.
    static var current: UIWindow? {
        let activeScene = UIApplication.shared.connectedScenes
            .first { $0.activationState == .foregroundActive } as? UIWindowScene
        
        if let activeScene {
            return activeScene.windows.first { $0.isKeyWindow } ?? activeScene.windows.first
        }
        
        let foregroundScene = UIApplication.shared.connectedScenes
            .first { $0.activationState == .foregroundInactive } as? UIWindowScene
        
        if let foregroundScene {
            return foregroundScene.windows.first { $0.isKeyWindow } ?? foregroundScene.windows.first
        }
        
        let anyScene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first
        
        if let window = anyScene?.windows.first(where: { $0.isKeyWindow }) ?? anyScene?.windows.first {
            return window
        }
        
        Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.movesync.default.subsystem", category: "UIWindow")
            .warning("No valid window found for presentation.")
        return nil
    }
}
