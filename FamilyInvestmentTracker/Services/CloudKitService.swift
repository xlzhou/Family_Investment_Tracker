import Foundation
import CloudKit
import CoreData

class CloudKitService: ObservableObject {
    static let shared = CloudKitService()
    
    @Published var isEnabled = false
    @Published var isSyncing = false
    @Published var lastSyncDate: Date?
    @Published var syncError: String?
    
    private let container: CKContainer?
    private let database: CKDatabase?
    
    private init() {
        if CloudKitService.isCloudKitAvailable {
            let container = CKContainer.default()
            self.container = container
            self.database = container.privateCloudDatabase
            checkAccountStatus()
        } else {
            self.container = nil
            self.database = nil
            isEnabled = false
            syncError = "CloudKit is not configured or iCloud is unavailable on this device."
        }
    }

    func checkAccountStatus() {
        guard let container = container else {
            isEnabled = false
            return
        }
        container.accountStatus { [weak self] status, error in
            DispatchQueue.main.async {
                switch status {
                case .available:
                    self?.isEnabled = true
                    self?.syncError = nil
                case .noAccount:
                    self?.isEnabled = false
                    self?.syncError = "No iCloud account signed in"
                case .restricted:
                    self?.isEnabled = false
                    self?.syncError = "iCloud account is restricted"
                case .couldNotDetermine:
                    self?.isEnabled = false
                    self?.syncError = "Could not determine iCloud status"
                case .temporarilyUnavailable:
                    self?.isEnabled = false
                    self?.syncError = "iCloud is temporarily unavailable"
                @unknown default:
                    self?.isEnabled = false
                    self?.syncError = "Unknown iCloud status"
                }
            }
        }
    }
    
    func requestPermission() {
        // User discoverability permissions are no longer required for CloudKit
        // CloudKit access is automatically granted when user signs in to iCloud
        checkAccountStatus()
    }
    
    func enableCloudSync() {
        guard isEnabled else {
            requestPermission()
            return
        }
        
        // CloudKit sync is automatically handled by NSPersistentCloudKitContainer
        // when properly configured in the Core Data stack
        UserDefaults.standard.set(true, forKey: "CloudSyncEnabled")
        
        // Trigger initial sync
        performManualSync()
    }
    
    func disableCloudSync() {
        UserDefaults.standard.set(false, forKey: "CloudSyncEnabled")
    }
    
    func performManualSync() {
        guard isEnabled, container != nil else { return }
        
        isSyncing = true
        syncError = nil
        
        // CloudKit sync is handled automatically by Core Data
        // This is just for UI feedback
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.isSyncing = false
            self?.lastSyncDate = Date()
        }
    }
}

// MARK: - CloudKit Configuration
extension CloudKitService {
    var isCloudSyncEnabled: Bool {
        return UserDefaults.standard.bool(forKey: "CloudSyncEnabled") && isEnabled
    }
    
    func configureCloudKitContainer() {
        // This is handled in the PersistenceController
        // CloudKit configuration is done when creating NSPersistentCloudKitContainer
    }
}

// MARK: - Sync Status Monitoring
extension CloudKitService {
    func startMonitoringSync() {
        // CloudKit sync monitoring is now handled automatically by Core Data
        // No need for manual notification observation in newer iOS versions
        print("CloudKit sync monitoring started - sync is handled automatically")
    }
    
    private func handleCloudKitNotification(_ notification: Notification) {
        // This method is no longer needed as CloudKit sync events
        // are handled automatically by Core Data in newer iOS versions
        
        // For manual sync status, we can use periodic checks or
        // observe Core Data context changes instead
        DispatchQueue.main.async {
            self.lastSyncDate = Date()
            self.isSyncing = false
        }
    }
}

// MARK: - Data Migration
extension CloudKitService {
    func migrateToCloudKit(context: NSManagedObjectContext) {
        // CloudKit migration is handled automatically by Core Data
        // when NSPersistentCloudKitContainer is configured
        
        guard isCloudSyncEnabled, container != nil else { return }
        
        isSyncing = true
        
        // Save any pending changes to trigger sync
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                syncError = "Failed to save changes: \(error.localizedDescription)"
                isSyncing = false
            }
        }
    }
}

// MARK: - Availability Helpers
extension CloudKitService {
    private static var isCloudKitAvailable: Bool {
        #if targetEnvironment(macCatalyst)
        // CloudKit is not supported in this build configuration without additional setup
        return false
        #else
        return FileManager.default.ubiquityIdentityToken != nil
        #endif
    }
}
