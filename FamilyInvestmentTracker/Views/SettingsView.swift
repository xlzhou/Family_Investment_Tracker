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
    @ObservedObject private var dashboardSettings = DashboardSettingsService.shared
    @State private var displayName: String = ""
    @State private var selectedDashboardCurrency: Currency = .usd
    @StateObject private var currencyService = CurrencyService.shared
    @State private var showAllExchangeRates = false
    @State private var showingChangePassword = false
    @State private var showingMigration = false
    @State private var isRepairingRealizedGains = false
    @State private var realizedGainRepairMessage: String?
    @State private var realizedGainRepairError: String?
    
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
               
                Section(header: Text("Dashboard"), footer: Text("Choose the currency used for totals in the Investment Portfolios view.")) {
                    Picker("Summary Currency", selection: $selectedDashboardCurrency) {
                        ForEach(Currency.allCases, id: \.self) { currency in
                            Text(currency.displayName).tag(currency)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                }

                // Currency Exchange Rates Section
                Section(header: Text("Currency Exchange Rates"), footer: Text("Real-time exchange rates are fetched from Yahoo Finance API and cached locally for offline use.")) {
                    HStack {
                        Button(action: {
                            withAnimation {
                                showAllExchangeRates.toggle()
                            }
                        }) {
                            Image(systemName: showAllExchangeRates ? "minus.circle" : "plus.circle")
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Exchange Rates")
                                .font(.headline)

                            if currencyService.isLoading {
                                Text("Updating...")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            } else if currencyService.lastUpdateDate != nil {
                                Text("Updated \(currencyService.getRateAge() ?? "recently")")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else {
                                Text("No data")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }

                            if let errorMessage = currencyService.errorMessage {
                                Text(errorMessage)
                                    .font(.caption)
                                    .foregroundColor(.red)
                                    .lineLimit(2)
                            }
                        }

                        Spacer()

                        Button(action: {
                            currencyService.refreshRates()
                        }) {
                            Image(systemName: "arrow.clockwise")
                                .foregroundColor(.blue)
                        }
                        .disabled(currencyService.isLoading)
                    }

                    // Display all exchange rates organized by base currency
                    if showAllExchangeRates && !currencyService.exchangeRates.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Currency.allCases, id: \.self) { baseCurrency in
                                if let rates = currencyService.exchangeRates[baseCurrency.rawValue] {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("From \(baseCurrency.rawValue)")
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.primary)

                                        LazyVGrid(columns: [
                                            GridItem(.flexible()),
                                            GridItem(.flexible())
                                        ], spacing: 4) {
                                            ForEach(Currency.allCases.filter { $0 != baseCurrency }, id: \.self) { targetCurrency in
                                                if let rate = rates[targetCurrency.rawValue] {
                                                    HStack {
                                                        Text("1 \(baseCurrency.rawValue) → \(String(format: "%.3f", rate)) \(targetCurrency.rawValue)")
                                                            .font(.caption2)
                                                            .foregroundColor(.secondary)
                                                        Spacer()
                                                    }
                                                }
                                            }
                                        }
                                    }
                                    .padding(.vertical, 2)

                                    if baseCurrency != Currency.allCases.last {
                                        Divider()
                                            .padding(.vertical, 2)
                                    }
                                }
                            }
                        }
                        .padding(.top, 8)
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

                    Button(action: {
                        FixedDepositMigrationService.shared.resetMigrationStatus()
                        showingMigration = true
                    }) {
                        HStack {
                            Image(systemName: "wand.and.stars")
                                .foregroundColor(.purple)
                            Text("Start Fixed Deposit Migration")
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    }
                    .disabled(isCreatingBackup || isRestoring)

                    Button(action: triggerRealizedGainRepair) {
                        HStack {
                            if isRepairingRealizedGains {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "hammer.circle")
                                    .foregroundColor(.green)
                            }
                            Text(isRepairingRealizedGains ? "Rebuilding Realized P&L..." : "Rebuild Realized P&L")
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    }
                    .disabled(isCreatingBackup || isRestoring || isRepairingRealizedGains)

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
                    if let realizedMessage = realizedGainRepairMessage {
                        Text(realizedMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    if let realizedError = realizedGainRepairError {
                        Text(realizedError)
                            .font(.caption)
                            .foregroundColor(.red)
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
                        showingChangePassword = true
                    }) {
                        HStack {
                            Image(systemName: "key.horizontal")
                                .foregroundColor(.blue)

                            Text("Change Password")
                                .foregroundColor(.primary)

                            Spacer()

                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    }

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
        .sheet(isPresented: $showingChangePassword) {
            ChangePasswordView()
        }
        .sheet(isPresented: $showingMigration) {
            FixedDepositMigrationView()
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
            selectedDashboardCurrency = dashboardSettings.dashboardCurrency
        }
        .onChange(of: selectedDashboardCurrency) { _, newValue in
            dashboardSettings.updateCurrency(newValue)
        }
    }

    private func triggerRealizedGainRepair() {
        guard !isRepairingRealizedGains else { return }
        isRepairingRealizedGains = true
        realizedGainRepairMessage = nil
        realizedGainRepairError = nil

        Task {
            do {
                let summary = try await RealizedGainRepairService.shared.repairAllPortfolios(in: viewContext)
                let message: String
                if summary.updatedHoldingsCount == 0 {
                    message = "All holdings are already up to date."
                    print("[RealizedGainRepair] No adjustments required.")
                } else {
                    let deltaText = Formatters.signedCurrency(summary.totalDelta)
                    message = "Updated \(summary.updatedHoldingsCount) holdings (net adjustment: \(deltaText))."
                    for holding in summary.holdings {
                        let institutionSuffix = holding.institutionName.map { " (\($0))" } ?? ""
                        let detail = "[RealizedGainRepair] \(holding.portfolioName) — \(holding.assetName)\(institutionSuffix): was \(Formatters.signedCurrency(holding.previousValue)), now \(Formatters.signedCurrency(holding.recalculatedValue)) (delta \(Formatters.signedCurrency(holding.delta)))"
                        print(detail)
                    }
                }

                await MainActor.run {
                    realizedGainRepairMessage = message
                    realizedGainRepairError = nil
                    isRepairingRealizedGains = false
                }
            } catch {
                await MainActor.run {
                    realizedGainRepairError = error.localizedDescription
                    realizedGainRepairMessage = nil
                    isRepairingRealizedGains = false
                }
            }
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

struct ChangePasswordView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @Environment(\.dismiss) private var dismiss
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var error: String?
    @State private var isChangingPassword = false
    @State private var step: ChangePasswordStep = .current

    enum ChangePasswordStep {
        case current, new, confirm
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                Spacer()

                VStack(spacing: 20) {
                    Image(systemName: "key.horizontal")
                        .font(.system(size: 60))
                        .foregroundColor(.blue)

                    Text("Change Password")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text(stepDescription)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }

                Spacer()

                VStack(spacing: 20) {
                    Group {
                        switch step {
                        case .current:
                            SecureField("Current Password", text: $currentPassword)
                                .textContentType(.password)
                        case .new:
                            VStack(alignment: .leading, spacing: 8) {
                                SecureField("New Password", text: $newPassword)
                                    .textContentType(.newPassword)
                                    .autocapitalization(.none)
                                    .disableAutocorrection(true)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("• Minimum 8 characters")
                                        .font(.caption)
                                        .foregroundColor(newPassword.count >= 8 ? .green : .secondary)

                                    Text("• Letters, numbers, and special characters")
                                        .font(.caption)
                                        .foregroundColor(containsRequiredCharacterTypes(newPassword) ? .green : .secondary)
                                }
                            }
                        case .confirm:
                            SecureField("Confirm New Password", text: $confirmPassword)
                                .textContentType(.newPassword)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                        }
                    }
                    .textFieldStyle(RoundedBorderTextFieldStyle())

                    if let error = error {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                            .multilineTextAlignment(.center)
                    }

                    Button(action: handleStepAction) {
                        HStack {
                            if isChangingPassword {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .foregroundColor(.white)
                            }

                            Text(stepButtonTitle)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(isStepValid ? Color.blue : Color.gray)
                        .cornerRadius(12)
                    }
                    .disabled(!isStepValid || isChangingPassword)
                }
                .padding(.horizontal, 40)

                Spacer()
            }
            .navigationTitle("Change Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isChangingPassword)
                }
            }
        }
    }

    private var stepDescription: String {
        switch step {
        case .current: return "Enter your current password to continue"
        case .new: return "Create a strong new password"
        case .confirm: return "Confirm your new password"
        }
    }

    private var stepButtonTitle: String {
        switch step {
        case .current: return "Continue"
        case .new: return "Continue"
        case .confirm: return "Change Password"
        }
    }

    private var isStepValid: Bool {
        switch step {
        case .current:
            return currentPassword.count >= 8
        case .new:
            return newPassword.count >= 8 && containsRequiredCharacterTypes(newPassword)
        case .confirm:
            return confirmPassword == newPassword && !confirmPassword.isEmpty
        }
    }

    private func containsRequiredCharacterTypes(_ password: String) -> Bool {
        let hasLetter = password.contains { $0.isLetter }
        let hasNumber = password.contains { $0.isNumber }
        let hasSpecial = password.contains { "!@#$%^&*()_+-=[]{}|;:,.<>?".contains($0) }

        return hasLetter && (hasNumber || hasSpecial)
    }

    private func handleStepAction() {
        guard isStepValid && !isChangingPassword else { return }

        switch step {
        case .current:
            step = .new
            error = nil

        case .new:
            step = .confirm
            error = nil

        case .confirm:
            changePassword()
        }
    }

    private func changePassword() {
        guard newPassword == confirmPassword else {
            error = "Passwords don't match"
            return
        }

        guard containsRequiredCharacterTypes(newPassword) && newPassword.count >= 8 else {
            error = "Password doesn't meet requirements"
            return
        }

        isChangingPassword = true
        error = nil

        // Use the AuthenticationManager's change password method
        let success = authManager.changeAppPassword(currentPassword: currentPassword, newPassword: newPassword)

        isChangingPassword = false

        if success {
            dismiss()
        } else {
            // Go back to current password step if verification failed
            step = .current
            currentPassword = ""
            newPassword = ""
            confirmPassword = ""
            error = authManager.authenticationError ?? "Failed to change password"
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
