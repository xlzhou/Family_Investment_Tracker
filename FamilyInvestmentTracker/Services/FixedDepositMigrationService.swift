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

    /// Reset migration status (for testing or restoring from backup)
    func resetMigrationStatus() {
        userDefaults.removeObject(forKey: migrationKey)
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
            let assets = try context.fetch(request)
            print("🔍 Debug: Found \(assets.count) fixed deposit assets with symbol 'Fixed Deposit'")
            for (index, asset) in assets.enumerated() {
                print("🔍 Debug: Asset \(index + 1): ID=\(asset.id?.uuidString ?? "nil"), Name=\(asset.name ?? "nil"), Symbol=\(asset.symbol ?? "nil")")
            }
            return assets
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
            let transactions = try context.fetch(request)
            print("🔍 Debug: Found \(transactions.count) deposit transactions for asset \(asset.id?.uuidString ?? "nil")")
            for (index, transaction) in transactions.enumerated() {
                print("🔍 Debug: Transaction \(index + 1): ID=\(transaction.id?.uuidString ?? "nil"), Amount=\(transaction.amount), Date=\(transaction.transactionDate?.description ?? "nil"), MaturityDate=\(transaction.maturityDate?.description ?? "nil"), Institution=\(transaction.institution?.name ?? "nil")")
            }
            return transactions
        } catch {
            print("Error fetching transactions for fixed deposit: \(error)")
            return []
        }
    }

    /// Analyze transaction patterns to determine if a fixed deposit is still active or matured
    func analyzeFixedDepositStatus(asset: Asset, context: NSManagedObjectContext) -> FixedDepositStatus {
        let transactions = getTransactionsForFixedDeposit(asset: asset, context: context)
        print("🔍 Debug: Analyzing fixed deposit status for asset \(asset.id?.uuidString ?? "nil")")

        // Group transactions by institution
        let transactionsByInstitution = Dictionary(grouping: transactions) { $0.institution }
        print("🔍 Debug: Transactions grouped into \(transactionsByInstitution.count) institutions")

        for (institution, institutionTransactions) in transactionsByInstitution {
            guard let institution = institution else {
                print("🔍 Debug: Skipping transactions with nil institution")
                continue
            }

            print("🔍 Debug: Analyzing \(institutionTransactions.count) transactions for institution: \(institution.name ?? "Unknown")")

            // Group transactions by maturity date (using only date part, not time)
            let calendar = Calendar.current
            let transactionsByMaturityDate = Dictionary(grouping: institutionTransactions) { transaction in
                guard let maturityDate = transaction.maturityDate else { return "NoMaturityDate" }
                let dateOnly = calendar.startOfDay(for: maturityDate)
                return String(describing: dateOnly)
            }

            print("🔍 Debug: Found \(transactionsByMaturityDate.count) distinct maturity dates")

            // Analyze each maturity date group separately
            for (maturityDateString, maturityDateTransactions) in transactionsByMaturityDate {
                print("🔍 Debug: Analyzing maturity date group: \(maturityDateString)")

                let sortedTransactions = maturityDateTransactions.sorted { $0.transactionDate ?? Date() < $1.transactionDate ?? Date() }

                var depositAmounts: [Double] = []
                var withdrawalAmounts: [Double] = []

                for transaction in sortedTransactions {
                    if transaction.amount > 0 {
                        depositAmounts.append(transaction.amount)
                        print("🔍 Debug: Found deposit: \(transaction.amount) (Maturity: \(transaction.maturityDate?.description ?? "nil"))")
                    } else {
                        withdrawalAmounts.append(abs(transaction.amount))
                        print("🔍 Debug: Found withdrawal: \(abs(transaction.amount)) (Maturity: \(transaction.maturityDate?.description ?? "nil"))")
                    }
                }

                print("🔍 Debug: Maturity date \(maturityDateString): \(depositAmounts.count) deposits, \(withdrawalAmounts.count) withdrawals")
                print("🔍 Debug: Deposit amounts: \(depositAmounts)")
                print("🔍 Debug: Withdrawal amounts: \(withdrawalAmounts)")

                // Check for matching deposit/withdrawal pairs within the same maturity date
                var remainingDeposits = depositAmounts
                for withdrawal in withdrawalAmounts {
                    if let matchingIndex = remainingDeposits.firstIndex(of: withdrawal) {
                        print("🔍 Debug: Found matching pair: deposit \(withdrawal) ↔ withdrawal \(withdrawal) (same maturity date)")
                        remainingDeposits.remove(at: matchingIndex)
                    } else {
                        print("🔍 Debug: No matching deposit found for withdrawal \(withdrawal) (same maturity date)")
                    }
                }

                print("🔍 Debug: Remaining unpaired deposits for maturity date \(maturityDateString): \(remainingDeposits)")

                // If there are remaining deposits without matching withdrawals for any maturity date, the asset has active deposits
                if !remainingDeposits.isEmpty {
                    print("🔍 Debug: Asset \(asset.id?.uuidString ?? "nil") status: ACTIVE (has unpaired deposits for maturity date \(maturityDateString))")
                    return .active
                }
            }
        }

        // If all deposits have matching withdrawals across all maturity dates, the asset is matured
        print("🔍 Debug: Asset \(asset.id?.uuidString ?? "nil") status: MATURED (all deposits have matching withdrawals across all maturity dates)")
        return .matured
    }

    // MARK: - Automatic Migration

    /// Migrate existing fixed deposit assets to the new system
    func performAutomaticMigration(context: NSManagedObjectContext) throws {
        let fixedDepositAssets = getFixedDepositAssets(context: context)

        print("🔄 Starting migration of \(fixedDepositAssets.count) fixed deposit assets...")

        for asset in fixedDepositAssets {
            print("🔄 Migrating asset: \(asset.name ?? "Fixed Deposit") (ID: \(asset.id?.uuidString ?? "nil"))")

            let transactions = getTransactionsForFixedDeposit(asset: asset, context: context)

            // Group transactions by institution and currency to identify distinct fixed deposits
            let transactionsByInstitutionCurrency = Dictionary(grouping: transactions) { transaction in
                let institutionName = transaction.institution?.name ?? "Unknown"
                let currency = transaction.currency ?? "Unknown"
                return "\(institutionName)-\(currency)"
            }

            print("🔄 Found \(transactionsByInstitutionCurrency.count) institution-currency pairs to migrate")

            // For each institution-currency group, create a separate fixed deposit asset
            for (institutionCurrencyKey, institutionCurrencyTransactions) in transactionsByInstitutionCurrency {
                let deposits = institutionCurrencyTransactions.filter { $0.amount > 0 }
                let withdrawals = institutionCurrencyTransactions.filter { $0.amount < 0 }

                let totalDeposit = deposits.reduce(0, { $0 + $1.amount })
                let totalWithdrawal = withdrawals.reduce(0, { $0 + abs($1.amount) })

                print("🔄 Analyzing \(institutionCurrencyKey): Deposits=\(totalDeposit), Withdrawals=\(totalWithdrawal)")

                // Only create new fixed deposit assets for active deposits
                if totalDeposit > totalWithdrawal {
                    guard let firstDeposit = deposits.first,
                          let institution = firstDeposit.institution,
                          let portfolio = firstDeposit.portfolio else {
                        continue
                    }

                    let currency = Currency(rawValue: firstDeposit.currency ?? "USD") ?? .usd
                    let maturityDate = firstDeposit.maturityDate
                    let interestRate = (firstDeposit.value(forKey: "interestRate") as? Double) ?? 0.0

                    print("🔄 Creating new fixed deposit: \(institution.name ?? "Unknown") - \(currency.rawValue) \(totalDeposit - totalWithdrawal)")

                    // Calculate actual term from maturity date and transaction date
                    let (termMonths, termString) = calculateTermFromTransaction(firstDeposit)

                    // Generate standardized symbol
                    let symbol = generateStandardizedSymbol(termMonths: termMonths, currency: currency, institution: institution)

                    let currencyString = currency.rawValue
                    let currencySymbol = currency.symbol
                    let newFixedDeposit = FixedDepositService.shared.createFixedDeposit(
                        name: "\(termString) \(currencyString) \(currencySymbol) Fixed Deposit - \(institution.name ?? "Bank")",
                        symbol: symbol,
                        institution: institution,
                        portfolio: portfolio,
                        amount: totalDeposit - totalWithdrawal,
                        currency: currency,
                        termMonths: termMonths,
                        interestRate: interestRate,
                        allowEarlyWithdrawal: false, // Don't allow early withdrawal for migrated deposits
                        valueDate: firstDeposit.transactionDate ?? firstDeposit.createdAt ?? Date(),
                        context: context
                    )

                    // Set the maturity date if available
                    if let maturityDate = maturityDate {
                        newFixedDeposit.maturityDate = maturityDate
                    }

                    // Create a deposit transaction for the fixed deposit
                    let transaction = Transaction(context: context)
                    transaction.id = UUID()
                    // Use the original transaction date from the first deposit to preserve historical accuracy
                    transaction.transactionDate = firstDeposit.transactionDate ?? firstDeposit.createdAt ?? Date()
                    transaction.amount = totalDeposit - totalWithdrawal
                    transaction.currency = currency.rawValue
                    transaction.type = TransactionType.deposit.rawValue
                    transaction.asset = newFixedDeposit
                    transaction.portfolio = portfolio
                    transaction.institution = institution
                    transaction.maturityDate = maturityDate
                    transaction.setValue(interestRate, forKey: "interestRate")

                    // Reduce cash balance by the fixed deposit amount
                    let fixedDepositAmount = totalDeposit - totalWithdrawal
                    institution.addToCashBalance(for: portfolio, currency: currency, delta: -fixedDepositAmount)

                    print("✅ Created new fixed deposit: \(newFixedDeposit.name ?? "Fixed Deposit") with currency \(currency.rawValue) and transaction amount \(transaction.amount) in currency '\(transaction.currency ?? "nil")'")
                    print("✅ Reduced cash balance by \(fixedDepositAmount)")
                }
            }

            // Mark the original asset as migrated
            asset.depositSubtypeEnum = .demand
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

        print("Migrated fixed deposit asset: \(asset.name ?? "Fixed Deposit")")
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

        // Calculate actual term from transaction data
        let (termMonths, termString) = calculateTermFromTransaction(firstTransaction)

        // Generate standardized symbol
        let symbol = generateStandardizedSymbol(termMonths: termMonths, currency: currency, institution: institution)

        // Create a fixed deposit asset
        let fixedDeposit = FixedDepositService.shared.createFixedDeposit(
            name: "\(termString) \(currency.rawValue) \(currency.symbol) Fixed Deposit - \(institution.name ?? "Bank")",
            symbol: symbol,
            institution: institution,
            portfolio: portfolio,
            amount: totalAmount,
            currency: currency,
            termMonths: termMonths,
            interestRate: 2.5, // Default interest rate
            allowEarlyWithdrawal: true, // Allow early withdrawal for migrated deposits
            valueDate: firstTransaction.transactionDate ?? firstTransaction.createdAt ?? Date(),
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

    // MARK: - Symbol Generation

    /// Generate standardized symbol format: "short form term"-"currency"-"FD"-"short form institution"
    private func generateStandardizedSymbol(termMonths: Int, currency: Currency, institution: Institution) -> String {
        let termShortForm = getTermShortForm(termMonths)
        let institutionShortForm = getInstitutionShortForm(institution)
        return "\(termShortForm)-\(currency.rawValue)-FD-\(institutionShortForm)"
    }

    /// Get short form for term (e.g., "1Y" for 12 months, "3M" for 3 months)
    private func getTermShortForm(_ termMonths: Int) -> String {
        if termMonths >= 12 {
            let years = termMonths / 12
            let remainingMonths = termMonths % 12
            if remainingMonths > 0 {
                return "\(years)Y\(remainingMonths)M"
            } else {
                return "\(years)Y"
            }
        } else {
            return "\(termMonths)M"
        }
    }

    /// Get short form for institution name (first 3 characters, uppercase)
    private func getInstitutionShortForm(_ institution: Institution) -> String {
        guard let name = institution.name else { return "BNK" }

        // Remove spaces and special characters, take first 3 characters
        let cleanedName = name.replacingOccurrences(of: "[^a-zA-Z0-9]", with: "", options: .regularExpression)
        let shortForm = String(cleanedName.prefix(3)).uppercased()

        return shortForm.isEmpty ? "BNK" : shortForm
    }

    // MARK: - Term Calculation

    /// Calculate term from transaction maturity date and transaction date
    private func calculateTermFromTransaction(_ transaction: Transaction) -> (months: Int, displayString: String) {
        let calendar = Calendar.current

        guard let maturityDate = transaction.maturityDate else {
            print("🔍 Debug: No maturity date found for transaction, using default 12-month term")
            return (12, "1-Year")
        }

        // Use transactionDate if available, otherwise use createdAt
        let transactionDate = transaction.transactionDate ?? transaction.createdAt ?? Date()

        print("🔍 Debug: Calculating term from transactionDate: \(transactionDate) to maturityDate: \(maturityDate)")

        let components = calendar.dateComponents([.month, .day], from: transactionDate, to: maturityDate)

        guard let months = components.month else {
            print("🔍 Debug: Could not calculate months, using default 12-month term")
            return (12, "1-Year")
        }

        // Round to nearest whole month (add extra month if there are significant remaining days)
        let days = components.day ?? 0
        let adjustedMonths = days > 15 ? months + 1 : months

        let termMonths = max(1, adjustedMonths) // Ensure at least 1 month

        // Generate display string
        let termString: String
        if termMonths >= 12 {
            let years = termMonths / 12
            let remainingMonths = termMonths % 12
            if remainingMonths > 0 {
                termString = "\(years)-Year \(remainingMonths)-Month"
            } else {
                termString = "\(years)-Year"
            }
        } else {
            termString = "\(termMonths)-Month"
        }

        print("🔍 Debug: Calculated term: \(termMonths) months (\(termString))")
        return (termMonths, termString)
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
        print("🔍 Debug: Starting migration summary analysis...")
        let fixedDepositAssets = getFixedDepositAssets(context: context)

        var fixedDepositCount = 0
        var demandDepositCount = 0

        print("🔍 Debug: Found \(fixedDepositAssets.count) fixed deposit assets")

        // For each fixed deposit asset, analyze its transactions to identify distinct fixed deposits
        for asset in fixedDepositAssets {
            print("🔍 Debug: Analyzing asset: \(asset.name ?? "nil") (ID: \(asset.id?.uuidString ?? "nil"))")

            let transactions = getTransactionsForFixedDeposit(asset: asset, context: context)

            // Group transactions by institution and currency first
            let transactionsByInstitutionCurrency = Dictionary(grouping: transactions) { transaction in
                let institutionName = transaction.institution?.name ?? "Unknown"
                let currency = transaction.currency ?? "Unknown"
                return "\(institutionName)-\(currency)"
            }

            print("🔍 Debug: Found \(transactionsByInstitutionCurrency.count) institution-currency pairs")

            // Analyze each institution-currency group
            for (institutionCurrencyKey, institutionCurrencyTransactions) in transactionsByInstitutionCurrency {
                print("🔍 Debug: Analyzing \(institutionCurrencyKey): \(institutionCurrencyTransactions.count) transactions")

                let deposits = institutionCurrencyTransactions.filter { $0.amount > 0 }
                let withdrawals = institutionCurrencyTransactions.filter { $0.amount < 0 }

                print("🔍 Debug:   Deposits: \(deposits.count), Withdrawals: \(withdrawals.count)")

                // Show detailed transaction info for debugging
                for deposit in deposits {
                    print("🔍 Debug:     Deposit: \(deposit.amount) on \(deposit.transactionDate?.description ?? "nil") (Maturity: \(deposit.maturityDate?.description ?? "nil"))")
                }
                for withdrawal in withdrawals {
                    print("🔍 Debug:     Withdrawal: \(withdrawal.amount) on \(withdrawal.transactionDate?.description ?? "nil") (Maturity: \(withdrawal.maturityDate?.description ?? "nil"))")
                }

                let totalDeposits = deposits.reduce(0, { $0 + $1.amount })
                let totalWithdrawals = withdrawals.reduce(0, { $0 + abs($1.amount) })

                print("🔍 Debug:   Total deposits: \(totalDeposits), Total withdrawals: \(totalWithdrawals)")

                // If there are deposits without matching withdrawals, it's an active fixed deposit
                if totalDeposits > totalWithdrawals {
                    fixedDepositCount += 1
                    print("🔍 Debug:   Institution-currency group classified as ACTIVE fixed deposit")
                } else {
                    demandDepositCount += 1
                    print("🔍 Debug:   Institution-currency group classified as MATURED (demand deposit)")
                }
            }
        }

        print("🔍 Debug: Migration Summary:")
        print("🔍 Debug: - Total assets to migrate: \(fixedDepositAssets.count)")
        print("🔍 Debug: - Active fixed deposits: \(fixedDepositCount)")
        print("🔍 Debug: - Matured deposits (demand): \(demandDepositCount)")

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
