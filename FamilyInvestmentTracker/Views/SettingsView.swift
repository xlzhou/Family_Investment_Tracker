import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var cloudKitService = CloudKitService.shared
    @EnvironmentObject var authManager: AuthenticationManager
    @Environment(\.managedObjectContext) private var viewContext
    
    @State private var showingExportSheet = false
    @State private var selectedExportFormat = ExportFormat.csv
    @State private var isCreatingBackup = false
    @State private var backupURL: URL?
    @State private var showingBackupShareSheet = false
    @State private var showingRestoreImporter = false
    @State private var restoreMessage: String?
    @State private var isRestoring = false
    @State private var showRestoreAlert = false
    @State private var restoreError: String?
    @StateObject private var ownershipService = PortfolioOwnershipService.shared
    @State private var displayName: String = ""
    
    var body: some View {
        NavigationView {
            Form {
                // User Profile Section
                Section(header: Text("Profile"), footer: Text("This name will be shown to family members when you share portfolios.")) {
                    HStack {
                        Text("Display Name")
                        TextField("Enter your name", text: $displayName)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .onSubmit {
                                ownershipService.setUserDisplayName(displayName)
                            }
                    }
                }

                // iCloud Sync Section
                Section(header: Text("iCloud Sync"), footer: Text("Securely sync your portfolio data across all your devices using iCloud.")) {
                    HStack {
                        Image(systemName: "icloud.fill")
                            .foregroundColor(.blue)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("iCloud Sync")
                                .font(.headline)
                            
                            if cloudKitService.isEnabled {
                                if cloudKitService.isCloudSyncEnabled {
                                    Text("Enabled")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                } else {
                                    Text("Available")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            } else {
                                Text(cloudKitService.syncError ?? "Not Available")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        }
                        
                        Spacer()
                        
                        Toggle("", isOn: Binding(
                            get: { cloudKitService.isCloudSyncEnabled },
                            set: { enabled in
                                if enabled {
                                    cloudKitService.enableCloudSync()
                                } else {
                                    cloudKitService.disableCloudSync()
                                }
                            }
                        ))
                        .disabled(!cloudKitService.isEnabled)
                    }
                    
                    if cloudKitService.isCloudSyncEnabled {
                        HStack {
                            Text("Last Sync")
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            if let lastSync = cloudKitService.lastSyncDate {
                                Text(lastSync, style: .relative)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else {
                                Text("Never")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Button(action: {
                            cloudKitService.performManualSync()
                        }) {
                            HStack {
                                if cloudKitService.isSyncing {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                }
                                
                                Text("Sync Now")
                            }
                        }
                        .disabled(cloudKitService.isSyncing)
                    }
                }
                
                // Data Export Section
                Section(header: Text("Data Export"), footer: Text("Export your portfolio data for backup or analysis.")) {
                    Button(action: {
                        showingExportSheet = true
                    }) {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundColor(.blue)
                            
                            Text("Export Portfolio Data")
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    }
                }

                // Backup & Restore Section
                Section(header: Text("Backup & Restore"), footer: Text("Create a full JSON backup of all portfolios, transactions, holdings, and institutions or restore from a previous backup.")) {
                    Button(action: createBackup) {
                        HStack {
                            if isCreatingBackup {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "externaldrive.badge.icloud")
                                    .foregroundColor(.blue)
                            }
                            Text(isCreatingBackup ? "Creating Backup..." : "Create Full Backup")
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    }
                    .disabled(isCreatingBackup || isRestoring)

                    Button(action: {
                        showingRestoreImporter = true
                    }) {
                        HStack {
                            if isRestoring {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "arrow.clockwise.circle")
                                    .foregroundColor(.orange)
                            }
                            Text(isRestoring ? "Restoring Backup..." : "Restore From Backup")
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    }
                    .disabled(isCreatingBackup || isRestoring)

                    if let message = restoreMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    if let errorMessage = restoreError {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }

                // App Information Section
                Section(header: Text("App Information")) {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Build")
                        Spacer()
                        Text("1")
                            .foregroundColor(.secondary)
                    }
                }
                
                // Security Section
                Section(header: Text("Security")) {
                    Button(action: {
                        authManager.logout()
                    }) {
                        HStack {
                            Image(systemName: "lock.fill")
                                .foregroundColor(.red)
                            
                            Text("Sign Out")
                                .foregroundColor(.red)
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        // Save display name before dismissing
                        ownershipService.setUserDisplayName(displayName)
                        dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $showingExportSheet) {
            ExportDataView(selectedFormat: $selectedExportFormat)
        }
        .sheet(isPresented: $showingBackupShareSheet) {
            if let backupURL = backupURL {
                ShareSheet(activityItems: [backupURL])
            }
        }
        .fileImporter(isPresented: $showingRestoreImporter, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                restoreBackup(from: url)
            case .failure(let error):
                restoreError = "Failed to access backup: \(error.localizedDescription)"
                restoreMessage = nil
            }
        }
        .alert("Restore Complete", isPresented: $showRestoreAlert, actions: {
            Button("OK", role: .cancel) { }
        }, message: {
            Text("Your data has been restored successfully.")
        })
        .onAppear {
            cloudKitService.checkAccountStatus()
            displayName = ownershipService.userDisplayName
        }
    }

    private func createBackup() {
        guard !isCreatingBackup else { return }
        restoreMessage = nil
        restoreError = nil
        isCreatingBackup = true

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let url = try BackupService.shared.createBackup(context: viewContext)
                DispatchQueue.main.async {
                    backupURL = url
                    showingBackupShareSheet = true
                    isCreatingBackup = false
                }
            } catch {
                DispatchQueue.main.async {
                    restoreError = "Backup failed: \(error.localizedDescription)"
                    isCreatingBackup = false
                }
            }
        }
    }

    private func restoreBackup(from url: URL) {
        guard !isRestoring else { return }
        restoreError = nil
        restoreMessage = nil
        isRestoring = true

        DispatchQueue.global(qos: .userInitiated).async {
            let shouldStopAccess = url.startAccessingSecurityScopedResource()
            defer {
                if shouldStopAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            do {
                try BackupService.shared.restoreBackup(from: url, context: viewContext)
                DispatchQueue.main.async {
                    restoreMessage = "Restore completed on \(DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .short))."
                    showRestoreAlert = true
                    isRestoring = false
                }
            } catch {
                DispatchQueue.main.async {
                    restoreError = "Restore failed: \(error.localizedDescription)"
                    isRestoring = false
                }
            }
        }
    }
}

enum ExportFormat: String, CaseIterable {
    case csv = "CSV"
    case pdf = "PDF"
    
    var displayName: String {
        return self.rawValue
    }
    
    var fileExtension: String {
        switch self {
        case .csv:
            return "csv"
        case .pdf:
            return "pdf"
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AuthenticationManager())
}
