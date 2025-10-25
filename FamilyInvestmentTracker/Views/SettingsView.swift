import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let fibackup: UTType = {
        if let type = UTType(filenameExtension: "fibackup") {
            return type
        }
        return .data
    }()
}

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
    @State private var showingBackupPasswordPrompt = false
    @State private var backupPassword = ""
    @State private var backupPasswordError: String?
    @State private var showingRestoreImporter = false
    @State private var showingRestorePasswordPrompt = false
    @State private var restorePassword = ""
    @State private var restorePasswordError: String?
    @State private var pendingRestoreURL: URL?
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
    @State private var showingSecurityQuestions = false
    @State private var showingMigration = false
    @State private var isRepairingRealizedGains = false
    @State private var realizedGainRepairMessage: String?
    @State private var realizedGainRepairError: String?
    @State private var isLinkingCompanions = false
    @State private var companionLinkMessage: String?
    @State private var companionLinkError: String?
    @EnvironmentObject private var localizationManager: LocalizationManager
    @State private var showingLanguageChangeAlert = false
    @State private var initialLanguage = AppLanguage.system.rawValue
    @State private var pendingLanguageChange: String?
    @State private var selectedLanguage = AppLanguage.system.rawValue
    
    var body: some View {
        NavigationView {
            Form {
                // User Profile Section
                Section(header: localizationManager.text("settings.profile.title"), footer: localizationManager.text("settings.profile.footer")) {
                    HStack {
                        localizationManager.text("settings.profile.displayName")
                        TextField("Enter your name", text: $displayName)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .onSubmit {
                                ownershipService.setUserDisplayName(displayName)
                            }
                    }
                }

                Section(header: localizationManager.text("settings.language.sectionTitle"),
                        footer: localizationManager.text("settings.language.sectionFooter")) {
                    Picker(localizationManager.localizedString(for: "settings.language.pickerLabel"), selection: $selectedLanguage) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(localizationManager.localizedString(for: language.localizationKey)).tag(language.rawValue)
                        }
                    }
                    .pickerStyle(.inline)
                }
               
                Section(header: localizationManager.text("settings.dashboard.title"), footer: localizationManager.text("settings.dashboard.footer")) {
                    Picker(localizationManager.localizedString(for: "settings.dashboard.summaryCurrency"), selection: $selectedDashboardCurrency) {
                        ForEach(Currency.allCases, id: \.self) { currency in
                            Text(currency.displayName).tag(currency)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                }

                // Currency Exchange Rates Section
                Section(header: localizationManager.text("settings.exchangeRates.title"), footer: localizationManager.text("settings.exchangeRates.footer")) {
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
                            localizationManager.text("settings.exchangeRates.label")
                                .font(.headline)

                            if currencyService.isLoading {
                                localizationManager.text("settings.exchangeRates.updating")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            } else if currencyService.lastUpdateDate != nil {
                                Text(localizationManager.localizedString(for: "settings.exchangeRates.updated", arguments: currencyService.getRateAge() ?? "recently"))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else {
                                localizationManager.text("settings.exchangeRates.noData")
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
                                        Text(localizationManager.localizedString(for: "settings.exchangeRates.from", arguments: baseCurrency.rawValue))
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
                Section(header: localizationManager.text("settings.icloud.title"), footer: localizationManager.text("settings.icloud.footer")) {
                    HStack {
                        Image(systemName: "icloud.fill")
                            .foregroundColor(.blue)

                        VStack(alignment: .leading, spacing: 2) {
                            localizationManager.text("settings.icloud.sync")
                                .font(.headline)

                            if cloudKitService.isEnabled {
                                if cloudKitService.isCloudSyncEnabled {
                                    localizationManager.text("settings.icloud.enabled")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                } else {
                                    localizationManager.text("settings.icloud.available")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            } else {
                                Text(cloudKitService.syncError ?? localizationManager.localizedString(for: "settings.icloud.notAvailable"))
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
                            localizationManager.text("settings.icloud.lastSync")
                                .foregroundColor(.secondary)

                            Spacer()

                            if let lastSync = cloudKitService.lastSyncDate {
                                Text(lastSync, style: .relative)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else {
                                localizationManager.text("settings.icloud.never")
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
                                
                                localizationManager.text("settings.icloud.syncNow")
                            }
                        }
                        .disabled(cloudKitService.isSyncing)
                    }
                }

                // Backup & Restore Section
                Section(header: localizationManager.text("settings.backup.title"), footer: localizationManager.text("settings.backup.footer")) {
                    Button(action: createBackup) {
                        HStack {
                            if isCreatingBackup {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "externaldrive.badge.icloud")
                                    .foregroundColor(.blue)
                            }
                            Text(isCreatingBackup ? localizationManager.localizedString(for: "settings.backup.creating") : localizationManager.localizedString(for: "settings.backup.create"))
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
                            Text(isRestoring ? localizationManager.localizedString(for: "settings.backup.restoring") : localizationManager.localizedString(for: "settings.backup.restore"))
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
                            localizationManager.text("settings.migration.fdMigration")
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
                            Text(isRepairingRealizedGains ? localizationManager.localizedString(for: "settings.migration.rebuilding") : localizationManager.localizedString(for: "settings.migration.rebuildGains"))
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    }
                    .disabled(isCreatingBackup || isRestoring || isRepairingRealizedGains)

                    Button(action: triggerCompanionLinkRepair) {
                        HStack {
                            if isLinkingCompanions {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "link.circle")
                                    .foregroundColor(.teal)
                            }
                            Text(isLinkingCompanions ? localizationManager.localizedString(for: "settings.migration.linking") : localizationManager.localizedString(for: "settings.migration.linkCompanions"))
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    }
                    .disabled(isCreatingBackup || isRestoring || isRepairingRealizedGains || isLinkingCompanions)

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
                    if let companionMessage = companionLinkMessage {
                        Text(companionMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    if let companionError = companionLinkError {
                        Text(companionError)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }

                // Data Export Section
                Section(header: localizationManager.text("settings.export.title"), footer: localizationManager.text("settings.export.footer")) {
                    Button(action: {
                        showingExportSheet = true
                    }) {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundColor(.blue)
                            
                            localizationManager.text("settings.export.button")
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    }
                }
 
                // App Information Section
                Section(header: localizationManager.text("settings.info.title")) {
                    HStack {
                        localizationManager.text("settings.info.version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        localizationManager.text("settings.info.build")
                        Spacer()
                        Text("1")
                            .foregroundColor(.secondary)
                    }
                }
                
                // Security Section
                Section(header: localizationManager.text("settings.security.title")) {
                    Button(action: {
                        showingChangePassword = true
                    }) {
                        HStack {
                            Image(systemName: "key.horizontal")
                                .foregroundColor(.blue)

                            localizationManager.text("settings.security.changePassword")
                                .foregroundColor(.primary)

                            Spacer()

                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    }

                    Button(action: {
                        showingSecurityQuestions = true
                    }) {
                        HStack {
                            Image(systemName: "questionmark.circle")
                                .foregroundColor(.blue)

                            VStack(alignment: .leading, spacing: 2) {
                                localizationManager.text("settings.security.securityQuestions")
                                    .foregroundColor(.primary)

                                Text(authManager.hasSecurityQuestionsSetup() ? localizationManager.localizedString(for: "settings.security.questionsChange") : localizationManager.localizedString(for: "settings.security.questionsSetup"))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

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

                            localizationManager.text("settings.security.signOut")
                                .foregroundColor(.red)
                        }
                    }
                }
            }
            .navigationTitle(localizationManager.localizedString(for: "settings.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(localizationManager.localizedString(for: "common.done")) {
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
        .sheet(isPresented: $showingBackupPasswordPrompt) {
            PasswordPromptView(
                title: "Encrypt Backup",
                message: "Enter a password to encrypt your backup file.",
                password: $backupPassword,
                errorMessage: backupPasswordError,
                isProcessing: isCreatingBackup,
                confirmTitle: "Create Backup",
                onConfirm: {
                    if backupPassword.isEmpty {
                        backupPasswordError = BackupServiceError.emptyPassword.localizedDescription
                        return
                    }
                    backupPasswordError = nil
                    showingBackupPasswordPrompt = false
                    performBackup(with: backupPassword)
                },
                onCancel: {
                    showingBackupPasswordPrompt = false
                    self.resetBackupPasswordState()
                }
            )
        }
        .sheet(isPresented: $showingRestorePasswordPrompt) {
            PasswordPromptView(
                title: "Decrypt Backup",
                message: "Enter the password used when this backup was created.",
                password: $restorePassword,
                errorMessage: restorePasswordError,
                isProcessing: isRestoring,
                confirmTitle: "Restore Backup",
                onConfirm: {
                    guard let url = pendingRestoreURL else { return }
                    if restorePassword.isEmpty {
                        restorePasswordError = BackupServiceError.emptyPassword.localizedDescription
                        return
                    }
                    restorePasswordError = nil
                    showingRestorePasswordPrompt = false
                    restoreBackup(from: url, password: restorePassword)
                },
                onCancel: {
                    showingRestorePasswordPrompt = false
                    self.resetRestorePasswordState(clearURL: true)
                }
            )
        }
        .sheet(isPresented: $showingChangePassword) {
            ChangePasswordView()
        }
        .sheet(isPresented: $showingSecurityQuestions) {
            SecurityQuestionsManagementView(authManager: authManager, isPresented: $showingSecurityQuestions)
        }
        .sheet(isPresented: $showingMigration) {
            FixedDepositMigrationView()
        }
        .fileImporter(isPresented: $showingRestoreImporter, allowedContentTypes: [.json, .fibackup]) { result in
            switch result {
            case .success(let url):
                restoreBackup(from: url)
            case .failure(let error):
                restoreError = "Failed to access backup: \(error.localizedDescription)"
                restoreMessage = nil
            }
        }
        .alert(localizationManager.localizedString(for: "settings.restore.title"), isPresented: $showRestoreAlert, actions: {
            Button(localizationManager.localizedString(for: "common.ok"), role: .cancel) { }
        }, message: {
            Text(localizationManager.localizedString(for: "settings.restore.success"))
        })
        .onAppear {
            cloudKitService.checkAccountStatus()
            displayName = ownershipService.userDisplayName
            selectedDashboardCurrency = dashboardSettings.dashboardCurrency
            selectedLanguage = localizationManager.currentLanguage.rawValue
            initialLanguage = selectedLanguage
        }
        .onChange(of: selectedDashboardCurrency) { _, newValue in
            dashboardSettings.updateCurrency(newValue)
        }
        .onChange(of: selectedLanguage) { _, newValue in
            if initialLanguage != newValue {
                pendingLanguageChange = newValue
                showingLanguageChangeAlert = true
            }
        }
        .alert(localizationManager.localizedString(for: "settings.language.restart.title"), isPresented: $showingLanguageChangeAlert, actions: {
            Button(localizationManager.localizedString(for: "settings.language.restart.cancel"), role: .cancel) {
                // Revert to the initial language selection
                selectedLanguage = initialLanguage
                pendingLanguageChange = nil
            }
            Button(localizationManager.localizedString(for: "settings.language.restart.confirm"), role: .destructive) {
                applyLanguageChange()
            }
        }, message: {
            Text(localizationManager.localizedString(for: "settings.language.restart.message"))
        })
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

    private func triggerCompanionLinkRepair() {
        guard !isLinkingCompanions else { return }
        isLinkingCompanions = true
        companionLinkMessage = nil
        companionLinkError = nil

        Task {
            do {
                let summary = try await CompanionLinkRepairService.shared.linkLegacyCompanions(in: viewContext)
                await MainActor.run {
                    if summary.linkedCount == 0 {
                        companionLinkMessage = "All companion transactions are already linked."
                    } else {
                        companionLinkMessage = "Linked \(summary.linkedCount) companion transaction(s)."
                    }

                    if summary.failedCount > 0 {
                        companionLinkError = "Failed to link \(summary.failedCount) transaction(s)."
                    }

                    isLinkingCompanions = false
                }
            } catch {
                await MainActor.run {
                    companionLinkError = error.localizedDescription
                    isLinkingCompanions = false
                }
            }
        }
    }

    private func createBackup() {
        guard !isCreatingBackup else { return }
        restoreMessage = nil
        restoreError = nil
        resetBackupPasswordState()
        showingBackupPasswordPrompt = true
    }

    private func performBackup(with password: String) {
        guard !isCreatingBackup else { return }
        restoreMessage = nil
        restoreError = nil
        isCreatingBackup = true

        let passwordToUse = password

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let url = try BackupService.shared.createBackup(context: viewContext, password: passwordToUse)
                DispatchQueue.main.async {
                    backupURL = url
                    showingBackupShareSheet = true
                    isCreatingBackup = false
                    self.resetBackupPasswordState()
                }
            } catch {
                DispatchQueue.main.async {
                    restoreError = "Backup failed: \(error.localizedDescription)"
                    isCreatingBackup = false
                    self.resetBackupPasswordState()
                }
            }
        }
    }

    private func restoreBackup(from url: URL, password: String? = nil) {
        guard !isRestoring else { return }
        restoreError = nil
        restoreMessage = nil
        if password == nil {
            resetRestorePasswordState(clearURL: false)
        }
        pendingRestoreURL = url
        isRestoring = true

        let providedPassword = password

        DispatchQueue.global(qos: .userInitiated).async {
            let shouldStopAccess = url.startAccessingSecurityScopedResource()
            defer {
                if shouldStopAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            do {
                try BackupService.shared.restoreBackup(from: url, context: viewContext, password: providedPassword)
                DispatchQueue.main.async {
                    restoreMessage = "Restore completed on \(DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .short))."
                    showRestoreAlert = true
                    isRestoring = false
                    self.resetRestorePasswordState(clearURL: true)
                }
            } catch let serviceError as BackupServiceError {
                DispatchQueue.main.async {
                    handleRestoreServiceError(serviceError, for: url)
                }
            } catch {
                DispatchQueue.main.async {
                    restoreError = "Restore failed: \(error.localizedDescription)"
                    isRestoring = false
                }
            }
        }
    }

    private func handleRestoreServiceError(_ error: BackupServiceError, for url: URL) {
        switch error {
        case .passwordRequired, .emptyPassword:
            isRestoring = false
            restorePassword = ""
            restorePasswordError = nil
            pendingRestoreURL = url
            showingRestorePasswordPrompt = true
        case .invalidPasswordOrCorrupted:
            isRestoring = false
            pendingRestoreURL = url
            restorePasswordError = error.localizedDescription
            showingRestorePasswordPrompt = true
        case .corruptedBackup, .unsupportedEncryptedVersion, .encryptionFailed:
            restoreError = "Restore failed: \(error.localizedDescription)"
            isRestoring = false
            self.resetRestorePasswordState(clearURL: true)
        }
    }

    private func resetBackupPasswordState() {
        backupPassword = ""
        backupPasswordError = nil
    }

    private func resetRestorePasswordState(clearURL: Bool) {
        restorePasswordError = nil
        restorePassword = ""
        if clearURL {
            pendingRestoreURL = nil
        }
    }

    private func applyLanguageChange() {
        guard let pendingLanguage = pendingLanguageChange,
              let newLanguage = AppLanguage(rawValue: pendingLanguage) else { return }

        // Apply the language change immediately using LocalizationManager
        localizationManager.setLanguage(newLanguage)

        // Update the initial language to the new one
        initialLanguage = pendingLanguage
        pendingLanguageChange = nil
    }
}

struct PasswordPromptView: View {
    let title: String
    let message: String
    @Binding var password: String
    let errorMessage: String?
    let isProcessing: Bool
    let confirmTitle: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @State private var isPasswordVisible = false

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 24) {
                Text(message)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)

                VStack(alignment: .leading, spacing: 12) {
                    if isPasswordVisible {
                        TextField("Password", text: $password)
                            .textContentType(.password)
                            .disableAutocorrection(true)
                            .autocapitalization(.none)
                    } else {
                        SecureField("Password", text: $password)
                            .textContentType(.password)
                            .disableAutocorrection(true)
                            .autocapitalization(.none)
                    }

                    Button(action: { isPasswordVisible.toggle() }) {
                        Label(isPasswordVisible ? "Hide Password" : "Show Password", systemImage: isPasswordVisible ? "eye.slash" : "eye")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)

                    if let errorMessage = errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.red)
                    } else {
                        Text("Password must contain at least one character.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Button(action: onConfirm) {
                    HStack {
                        if isProcessing {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                        Text(confirmTitle)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(password.isEmpty || isProcessing ? Color.gray : Color.blue)
                    .cornerRadius(12)
                }
                .disabled(password.isEmpty || isProcessing)

                Spacer()
            }
            .padding()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        onCancel()
                    }
                    .disabled(isProcessing)
                }
            }
        }
    }
}

struct ChangePasswordView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var localizationManager: LocalizationManager
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

                    localizationManager.text("changePassword.title")
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
                            SecureField(localizationManager.localizedString(for: "changePassword.placeholder.current"), text: $currentPassword)
                                .textContentType(.password)
                        case .new:
                            VStack(alignment: .leading, spacing: 8) {
                                SecureField(localizationManager.localizedString(for: "changePassword.placeholder.new"), text: $newPassword)
                                    .textContentType(.newPassword)
                                    .autocapitalization(.none)
                                    .disableAutocorrection(true)

                                VStack(alignment: .leading, spacing: 4) {
                                    localizationManager.text("changePassword.requirement.length")
                                        .font(.caption)
                                        .foregroundColor(newPassword.count >= 8 ? .green : .secondary)

                                    localizationManager.text("changePassword.requirement.complexity")
                                        .font(.caption)
                                        .foregroundColor(containsRequiredCharacterTypes(newPassword) ? .green : .secondary)
                                }
                            }
                        case .confirm:
                            SecureField(localizationManager.localizedString(for: "changePassword.placeholder.confirm"), text: $confirmPassword)
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
            .navigationTitle(localizationManager.localizedString(for: "changePassword.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(localizationManager.localizedString(for: "common.cancel")) {
                        dismiss()
                    }
                    .disabled(isChangingPassword)
                }
            }
        }
    }

    private var stepDescription: String {
        switch step {
        case .current: return localizationManager.localizedString(for: "changePassword.step.current")
        case .new: return localizationManager.localizedString(for: "changePassword.step.new")
        case .confirm: return localizationManager.localizedString(for: "changePassword.step.confirm")
        }
    }

    private var stepButtonTitle: String {
        switch step {
        case .current, .new:
            return localizationManager.localizedString(for: "changePassword.button.continue")
        case .confirm:
            return localizationManager.localizedString(for: "changePassword.button.submit")
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
