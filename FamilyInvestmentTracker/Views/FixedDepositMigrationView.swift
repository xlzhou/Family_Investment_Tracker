import SwiftUI
import CoreData

struct FixedDepositMigrationView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

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
            .navigationTitle("Fixed Deposit Enhancement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Reset") {
                        // Reset migration status for testing
                        FixedDepositMigrationService.shared.resetMigrationStatus()
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Skip") {
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

            Text("Analyzing your deposit assets...")
                .font(.headline)
                .foregroundColor(.secondary)
        }
    }

    private var completedView: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.green)

            Text("Migration Complete!")
                .font(.title)
                .fontWeight(.bold)

            Text("Your deposit assets have been successfully updated to use the new fixed deposit system.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            Button("Continue") {
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
                    Text("Enhanced Fixed Deposit Support")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("We've improved how the app handles fixed deposits! Your existing deposit transactions will remain as cash deposits. You can now create dedicated fixed deposits using the new system.")
                        .font(.body)
                        .foregroundColor(.secondary)
                }

                // What's New Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("What's New")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 8) {
                        FeatureRow(
                            icon: "lock.circle.fill",
                            title: "Fixed Deposit Tracking",
                            description: "Properly track time-locked deposits separate from available cash"
                        )

                        FeatureRow(
                            icon: "percent",
                            title: "Interest Rate Tracking",
                            description: "Track interest rates and maturity dates for fixed deposits"
                        )

                        FeatureRow(
                            icon: "calendar.circle.fill",
                            title: "Maturity Management",
                            description: "Get notified when your fixed deposits mature"
                        )

                        FeatureRow(
                            icon: "arrow.up.circle.fill",
                            title: "Early Withdrawal Support",
                            description: "Handle early withdrawals with penalty tracking"
                        )
                    }
                }

                // Migration Summary
                VStack(alignment: .leading, spacing: 12) {
                    Text("Migration Summary")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Total deposit assets to update:")
                            Spacer()
                            Text("\(summary.totalAssetsToMigrate)")
                                .fontWeight(.semibold)
                        }

                        HStack {
                            Text("Likely fixed deposits:")
                            Spacer()
                            Text("\(summary.fixedDepositCandidates)")
                                .fontWeight(.semibold)
                                .foregroundColor(.blue)
                        }

                        HStack {
                            Text("Likely demand deposits:")
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
                        Text("Suggested Actions")
                            .font(.headline)

                        ForEach(Array(summary.suggestions.enumerated()), id: \.offset) { index, suggestion in
                            SuggestionRow(suggestion: suggestion)
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
                            Text(isPerformingMigration ? "Enabling..." : "Enable Fixed Deposits")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(isPerformingMigration)

                    Text("This will enable the new fixed deposit features. Your existing deposit transactions will remain unchanged as cash deposits.")
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
                    self.errorMessage = "Migration failed: \(error.localizedDescription)"
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

    private var actionDescription: String {
        switch suggestion.action {
        case .convertToFixedDeposit(let months, let rate, _):
            return "Convert to \(months)-month fixed deposit (\(String(format: "%.1f", rate))% interest)"
        case .convertToDemandDeposit:
            return "Keep as demand deposit"
        case .requiresManualReview:
            return "Requires manual review"
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
                Text(suggestion.asset.name ?? suggestion.asset.symbol ?? "Unknown Asset")
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