import SwiftUI
import CoreData

struct FixedDepositMigrationView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var localizationManager: LocalizationManager

    @State private var migrationSummary: MigrationSummary?
    @State private var isPerformingMigration = false
    @State private var migrationCompleted = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                if migrationCompleted {
                    completedView
                } else if let summary = migrationSummary {
                    migrationContentView(summary: summary)
                } else {
                    loadingView
                }
            }
            .padding()
            .navigationTitle(localizationManager.localizedString(for: "fixedDepositMigration.navigation.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(localizationManager.localizedString(for: "fixedDepositMigration.navigation.reset")) {
                        // Reset migration status for testing
                        FixedDepositMigrationService.shared.resetMigrationStatus()
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(localizationManager.localizedString(for: "fixedDepositMigration.navigation.skip")) {
                        // Perform automatic migration and close
                        performAutomaticMigration()
                    }
                    .disabled(isPerformingMigration)
                }
            }
            .onAppear {
                loadMigrationSummary()
            }
        }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)

            Text(localizationManager.localizedString(for: "fixedDepositMigration.loading.analyzing"))
                .font(.headline)
                .foregroundColor(.secondary)
        }
    }

    private var completedView: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.green)

            Text(localizationManager.localizedString(for: "fixedDepositMigration.completed.title"))
                .font(.title)
                .fontWeight(.bold)

            Text(localizationManager.localizedString(for: "fixedDepositMigration.completed.description"))
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            Button(localizationManager.localizedString(for: "fixedDepositMigration.completed.continue")) {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .padding(.top)
        }
    }

    private func migrationContentView(summary: MigrationSummary) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text(localizationManager.localizedString(for: "fixedDepositMigration.header.title"))
                        .font(.title2)
                        .fontWeight(.bold)

                    Text(localizationManager.localizedString(for: "fixedDepositMigration.header.description"))
                        .font(.body)
                        .foregroundColor(.secondary)
                }

                // What's New Section
                VStack(alignment: .leading, spacing: 12) {
                    Text(localizationManager.localizedString(for: "fixedDepositMigration.whatsNew.title"))
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 8) {
                        FeatureRow(
                            icon: "lock.circle.fill",
                            title: localizationManager.localizedString(for: "fixedDepositMigration.feature.tracking.title"),
                            description: localizationManager.localizedString(for: "fixedDepositMigration.feature.tracking.description")
                        )

                        FeatureRow(
                            icon: "percent",
                            title: localizationManager.localizedString(for: "fixedDepositMigration.feature.interestRate.title"),
                            description: localizationManager.localizedString(for: "fixedDepositMigration.feature.interestRate.description")
                        )

                        FeatureRow(
                            icon: "calendar.circle.fill",
                            title: localizationManager.localizedString(for: "fixedDepositMigration.feature.maturity.title"),
                            description: localizationManager.localizedString(for: "fixedDepositMigration.feature.maturity.description")
                        )

                        FeatureRow(
                            icon: "arrow.up.circle.fill",
                            title: localizationManager.localizedString(for: "fixedDepositMigration.feature.earlyWithdrawal.title"),
                            description: localizationManager.localizedString(for: "fixedDepositMigration.feature.earlyWithdrawal.description")
                        )
                    }
                }

                // Migration Summary
                VStack(alignment: .leading, spacing: 12) {
                    Text(localizationManager.localizedString(for: "fixedDepositMigration.summary.title"))
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(localizationManager.localizedString(for: "fixedDepositMigration.summary.totalAssets"))
                            Spacer()
                            Text("\(summary.totalAssetsToMigrate)")
                                .fontWeight(.semibold)
                        }

                        HStack {
                            Text(localizationManager.localizedString(for: "fixedDepositMigration.summary.fixedDeposits"))
                            Spacer()
                            Text("\(summary.fixedDepositCandidates)")
                                .fontWeight(.semibold)
                                .foregroundColor(.blue)
                        }

                        HStack {
                            Text(localizationManager.localizedString(for: "fixedDepositMigration.summary.demandDeposits"))
                            Spacer()
                            Text("\(summary.demandDepositCandidates)")
                                .fontWeight(.semibold)
                                .foregroundColor(.green)
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                }

                // Suggestions
                if !summary.suggestions.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(localizationManager.localizedString(for: "fixedDepositMigration.suggestions.title"))
                            .font(.headline)

                        ForEach(Array(summary.suggestions.enumerated()), id: \.offset) { index, suggestion in
                            SuggestionRow(suggestion: suggestion, localizationManager: localizationManager)
                        }
                    }
                }

                // Action Buttons
                VStack(spacing: 12) {
                    Button(action: {
                        performAutomaticMigration()
                    }) {
                        HStack {
                            if isPerformingMigration {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .foregroundColor(.white)
                            } else {
                                Image(systemName: "wand.and.stars")
                            }
                            Text(isPerformingMigration ? localizationManager.localizedString(for: "fixedDepositMigration.button.enabling") : localizationManager.localizedString(for: "fixedDepositMigration.button.enable"))
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(isPerformingMigration)

                    Text(localizationManager.localizedString(for: "fixedDepositMigration.button.description"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }

                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                }
            }
        }
    }

    private func loadMigrationSummary() {
        DispatchQueue.global(qos: .userInitiated).async {
            let summary = FixedDepositMigrationService.shared.getMigrationSummary(context: viewContext)

            DispatchQueue.main.async {
                self.migrationSummary = summary
            }
        }
    }

    private func performAutomaticMigration() {
        isPerformingMigration = true
        errorMessage = ""

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try FixedDepositMigrationService.shared.performAutomaticMigration(context: viewContext)

                DispatchQueue.main.async {
                    self.isPerformingMigration = false
                    self.migrationCompleted = true
                }
            } catch {
                DispatchQueue.main.async {
                    self.isPerformingMigration = false
                    self.errorMessage = String(format: self.localizationManager.localizedString(for: "fixedDepositMigration.error.migrationFailed"), error.localizedDescription)
                }
            }
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.blue)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
    }
}

struct SuggestionRow: View {
    let suggestion: MigrationSuggestion
    let localizationManager: LocalizationManager

    private var actionDescription: String {
        switch suggestion.action {
        case .convertToFixedDeposit(let months, let rate, _):
            return String(format: localizationManager.localizedString(for: "fixedDepositMigration.suggestion.convertToFixed"), months, rate)
        case .convertToDemandDeposit:
            return localizationManager.localizedString(for: "fixedDepositMigration.suggestion.convertToDemand")
        case .requiresManualReview:
            return localizationManager.localizedString(for: "fixedDepositMigration.suggestion.manualReview")
        }
    }

    private var confidenceColor: Color {
        if suggestion.confidence >= 0.7 {
            return .green
        } else if suggestion.confidence >= 0.5 {
            return .orange
        } else {
            return .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(suggestion.asset.name ?? suggestion.asset.symbol ?? localizationManager.localizedString(for: "fixedDepositMigration.suggestion.unknownAsset"))
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Spacer()

                HStack(spacing: 4) {
                    Circle()
                        .fill(confidenceColor)
                        .frame(width: 8, height: 8)

                    Text("\(Int(suggestion.confidence * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Text(actionDescription)
                .font(.caption)
                .foregroundColor(.blue)

            Text(suggestion.reasoning)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(8)
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

#Preview {
    FixedDepositMigrationView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}