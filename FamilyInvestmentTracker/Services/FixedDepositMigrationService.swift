import Foundation
import CoreData

final class FixedDepositMigrationService {
    static let shared = FixedDepositMigrationService()
    private init() {}

    private let userDefaults = UserDefaults.standard
    private let migrationKey = "FixedDepositMigrationCompleted_v1"

    // MARK: - Migration Status

    /// Check if migration has been completed
    var isMigrationCompleted: Bool {
        return userDefaults.bool(forKey: migrationKey)
    }

    /// Mark migration as completed
    func markMigrationCompleted() {
        userDefaults.set(true, forKey: migrationKey)
    }

    // MARK: - Migration Detection

    /// Detect if there are existing fixed deposit assets that need migration
    func hasAssetsNeedingMigration(context: NSManagedObjectContext) -> Bool {
        let request: NSFetchRequest<Asset> = Asset.fetchRequest()
        request.predicate = NSPredicate(format: "symbol == %@", "Fixed Deposit")
        request.fetchLimit = 1

        do {
            let count = try context.count(for: request)
            return count > 0
        } catch {
            print("Error checking for fixed deposit assets: \(error)")
            return false
        }
    }

    /// Get all fixed deposit assets
    func getFixedDepositAssets(context: NSManagedObjectContext) -> [Asset] {
        let request: NSFetchRequest<Asset> = Asset.fetchRequest()
        request.predicate = NSPredicate(format: "symbol == %@", "Fixed Deposit")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Asset.createdAt, ascending: true)]

        do {
            return try context.fetch(request)
        } catch {
            print("Error fetching fixed deposit assets: \(error)")
            return []
        }
    }

    /// Get transactions for a specific fixed deposit asset
    func getTransactionsForFixedDeposit(asset: Asset, context: NSManagedObjectContext) -> [Transaction] {
        let request: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        request.predicate = NSPredicate(format: "asset == %@ AND type == %@", asset, TransactionType.deposit.rawValue)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Transaction.transactionDate, ascending: true)]

        do {
            return try context.fetch(request)
        } catch {
            print("Error fetching transactions for fixed deposit: \(error)")
            return []
        }
    }

    /// Analyze transaction patterns to determine if a fixed deposit is still active or matured
    func analyzeFixedDepositStatus(asset: Asset, context: NSManagedObjectContext) -> FixedDepositStatus {
        let transactions = getTransactionsForFixedDeposit(asset: asset, context: context)

        // Group transactions by institution
        let transactionsByInstitution = Dictionary(grouping: transactions) { $0.institution }

        for (institution, institutionTransactions) in transactionsByInstitution {
            guard let institution = institution else { continue }

            // Analyze transaction patterns for this institution
            let sortedTransactions = institutionTransactions.sorted { $0.transactionDate ?? Date() < $1.transactionDate ?? Date() }

            var depositAmounts: [Double] = []
            var withdrawalAmounts: [Double] = []

            for transaction in sortedTransactions {
                if transaction.amount > 0 {
                    depositAmounts.append(transaction.amount)
                } else {
                    withdrawalAmounts.append(abs(transaction.amount))
                }
            }

            // Check for matching deposit/withdrawal pairs
            var remainingDeposits = depositAmounts
            for withdrawal in withdrawalAmounts {
                if let matchingIndex = remainingDeposits.firstIndex(of: withdrawal) {
                    remainingDeposits.remove(at: matchingIndex)
                }
            }

            // If there are remaining deposits without matching withdrawals, the deposit is still active
            if !remainingDeposits.isEmpty {
                return .active
            }
        }

        // If all deposits have matching withdrawals, the deposit is matured
        return .matured
    }

    // MARK: - Automatic Migration

    /// Migrate existing fixed deposit assets to the new system
    func performAutomaticMigration(context: NSManagedObjectContext) throws {
        let fixedDepositAssets = getFixedDepositAssets(context: context)

        print("🔄 Starting migration of \(fixedDepositAssets.count) fixed deposit assets...")

        for asset in fixedDepositAssets {
            try migrateFixedDepositAsset(asset, context: context)
        }

        try context.save()
        markMigrationCompleted()

        print("✅ Fixed deposit migration completed successfully")
    }

    /// Migrate a single fixed deposit asset to the new system
    private func migrateFixedDepositAsset(_ asset: Asset, context: NSManagedObjectContext) throws {
        // Set deposit subtype as fixed
        asset.depositSubtypeEnum = .fixed

        // Set allowEarlyWithdrawal to false for existing fixed deposits
        asset.allowEarlyWithdrawal = false

        // Ensure the asset has an ID
        if asset.id == nil {
            asset.id = UUID()
        }

        print("Migrated fixed deposit asset: \(asset.name ?? \"Fixed Deposit\")")
    }

    /// Create a fixed deposit asset from existing deposit transactions
    private func createFixedDepositFromTransactions(_ transactions: [Transaction], context: NSManagedObjectContext) throws {
        guard let firstTransaction = transactions.first,
              let institution = firstTransaction.institution,
              let portfolio = firstTransaction.portfolio else {
            return
        }

        let totalAmount = transactions.reduce(0.0) { $0 + $1.amount }
        let currency = Currency(rawValue: firstTransaction.currency ?? "USD") ?? .usd

        // Create a fixed deposit asset
        let fixedDeposit = FixedDepositService.shared.createFixedDeposit(
            name: "Migrated Fixed Deposit - \(institution.name ?? "Bank")",
            symbol: "FD-\(institution.name?.prefix(3) ?? "BNK")",
            institution: institution,
            portfolio: portfolio,
            amount: totalAmount,
            currency: currency,
            termMonths: 12, // Default 1-year term for migrated deposits
            interestRate: 2.5, // Default interest rate
            allowEarlyWithdrawal: true, // Allow early withdrawal for migrated deposits
            context: context
        )

        // Update transactions to reference the new fixed deposit asset
        for transaction in transactions {
            transaction.asset = fixedDeposit
        }
    }

    // MARK: - Manual Migration Tools

    /// Convert an existing demand deposit to a fixed deposit
    func convertToFixedDeposit(
        asset: Asset,
        termMonths: Int,
        interestRate: Double,
        allowEarlyWithdrawal: Bool = false,
        context: NSManagedObjectContext
    ) throws {
        guard asset.assetType == AssetType.deposit.rawValue else {
            throw MigrationError.invalidAssetType
        }

        // Update asset to fixed deposit
        asset.depositSubtypeEnum = .fixed
        asset.setValue(interestRate, forKey: "interestRate")
        asset.allowEarlyWithdrawal = allowEarlyWithdrawal

        // Calculate maturity date
        let calendar = Calendar.current
        if let maturityDate = calendar.date(byAdding: .month, value: termMonths, to: Date()) {
            asset.maturityDate = maturityDate
        }

        // Update asset name if needed
        if let currentName = asset.name, !currentName.contains("Fixed Deposit") {
            let termString: String
            if termMonths >= 12 {
                let years = termMonths / 12
                termString = "\(years)-Year"
            } else {
                termString = "\(termMonths)-Month"
            }
            asset.name = "\(termString) Fixed Deposit - \(currentName)"
        }

        try context.save()
        print("🔄 Converted \(asset.name ?? "Unknown") to fixed deposit")
    }

}

// MARK: - Supporting Types

enum MigrationError: LocalizedError {
    case invalidAssetType
    case migrationAlreadyCompleted
    case contextNotAvailable

    var errorDescription: String? {
        switch self {
        case .invalidAssetType:
            return "Asset is not a deposit type"
        case .migrationAlreadyCompleted:
            return "Migration has already been completed"
        case .contextNotAvailable:
            return "Core Data context is not available"
        }
    }
}

enum FixedDepositStatus {
    case active
    case matured
}

struct MigrationSuggestion {
    let asset: Asset
    let action: MigrationAction
    let confidence: Float // 0.0 to 1.0
    let reasoning: String
}

enum MigrationAction {
    case convertToFixedDeposit(suggestedTermMonths: Int, suggestedInterestRate: Double, allowEarlyWithdrawal: Bool)
    case convertToDemandDeposit
    case requiresManualReview
}

// MARK: - Migration UI Support

extension FixedDepositMigrationService {
    /// Check if the app should show migration prompts to the user
    func shouldShowMigrationPrompt(context: NSManagedObjectContext) -> Bool {
        return !isMigrationCompleted && hasAssetsNeedingMigration(context: context)
    }

    /// Get a summary of what will be migrated
    func getMigrationSummary(context: NSManagedObjectContext) -> MigrationSummary {
        let fixedDepositAssets = getFixedDepositAssets(context: context)

        var fixedDepositCount = 0
        var demandDepositCount = 0

        // Analyze each fixed deposit asset to determine if it's still active
        for asset in fixedDepositAssets {
            let status = analyzeFixedDepositStatus(asset: asset, context: context)
            switch status {
            case .active:
                fixedDepositCount += 1
            case .matured:
                demandDepositCount += 1
            }
        }

        return MigrationSummary(
            totalAssetsToMigrate: fixedDepositAssets.count,
            fixedDepositCandidates: fixedDepositCount,
            demandDepositCandidates: demandDepositCount,
            suggestions: []
        )
    }
}

struct MigrationSummary {
    let totalAssetsToMigrate: Int
    let fixedDepositCandidates: Int
    let demandDepositCandidates: Int
    let suggestions: [MigrationSuggestion]
}
