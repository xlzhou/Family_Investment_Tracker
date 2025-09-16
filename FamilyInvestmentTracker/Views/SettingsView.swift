import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var cloudKitService = CloudKitService.shared
    @EnvironmentObject var authManager: AuthenticationManager
    
    @State private var showingExportSheet = false
    @State private var selectedExportFormat = ExportFormat.csv
    
    var body: some View {
        NavigationView {
            Form {
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
                        dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $showingExportSheet) {
            ExportDataView(selectedFormat: $selectedExportFormat)
        }
        .onAppear {
            cloudKitService.checkAccountStatus()
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