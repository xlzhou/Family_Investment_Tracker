import CoreData
import Foundation

enum InsurancePaymentService {
    private static let migrationDefaultsKey = "InsurancePaymentLinkedIDsBackfilled"

    static func paymentTransactions(for asset: Asset, in portfolio: Portfolio, context: NSManagedObjectContext) -> [Transaction] {
        guard let assetID = asset.id else { return [] }

        let transactions = (portfolio.transactions?.allObjects as? [Transaction]) ?? []
        let hadChangesBefore = context.hasChanges
        let linkedMatches = transactions.filter { transaction in
            guard transaction.portfolio?.objectID == portfolio.objectID else { return false }
            guard transaction.type == TransactionType.deposit.rawValue else { return false }
            if let linkedID = transaction.value(forKey: "linkedInsuranceAssetID") as? UUID {
                return linkedID == assetID
            }
            return false
        }

        if !linkedMatches.isEmpty {
            return linkedMatches.sorted { ($0.transactionDate ?? .distantPast) < ($1.transactionDate ?? .distantPast) }
        }

        let originalTransaction = (asset.transactions?.allObjects as? [Transaction] ?? [])
            .filter { $0.portfolio?.objectID == portfolio.objectID && $0.type == TransactionType.insurance.rawValue }
            .sorted { ($0.transactionDate ?? .distantPast) < ($1.transactionDate ?? .distantPast) }
            .first

        let fallbackMatches = transactions.filter { transaction in
            guard transaction.portfolio?.objectID == portfolio.objectID else { return false }
            guard transaction.type == TransactionType.deposit.rawValue else { return false }
            if transaction.value(forKey: "linkedInsuranceAssetID") as? UUID != nil {
                return false
            }
            return matchesLegacyHeuristic(transaction, asset: asset, originalTransaction: originalTransaction)
        }

        guard !fallbackMatches.isEmpty else { return [] }

        fallbackMatches.forEach { transaction in
            transaction.setValue(assetID, forKey: "linkedInsuranceAssetID")
        }

        if !hadChangesBefore && context.hasChanges {
            try? context.save()
        }

        return fallbackMatches.sorted { ($0.transactionDate ?? .distantPast) < ($1.transactionDate ?? .distantPast) }
    }

    static func totalPaidAmount(for asset: Asset, in portfolio: Portfolio, context: NSManagedObjectContext) -> Double {
        let currencyService = CurrencyService.shared
        let portfolioCurrency = Currency(rawValue: portfolio.mainCurrency ?? "USD") ?? .usd

        let deposits = paymentTransactions(for: asset, in: portfolio, context: context)
        var total: Double = 0

        let originalTransaction = (asset.transactions?.allObjects as? [Transaction])?
            .first(where: { $0.portfolio?.objectID == portfolio.objectID && $0.type == TransactionType.insurance.rawValue })

        let initialPremiumDepositCandidate = Self.initialPremiumDeposit(for: originalTransaction, deposits: deposits)

        for deposit in deposits where deposit.type == TransactionType.deposit.rawValue {
            let depositCurrency = Currency(rawValue: deposit.currency ?? portfolioCurrency.rawValue) ?? portfolioCurrency
            let absoluteAmount = abs(deposit.amount)

            if absoluteAmount > 1e-6 {
                total += currencyService.convertAmount(absoluteAmount, from: depositCurrency, to: portfolioCurrency)
            } else if let stored = deposit.value(forKey: "paymentDeductedAmount") as? Double, stored > 1e-6 {
                total += stored
            }
        }

        if let original = originalTransaction {
            let hasCompanionDeposit = CashDisciplineService.findCompanionDeposit(for: original, in: context) != nil
            let initialPremiumHandledByDeposit = initialPremiumDepositCandidate != nil

            if !hasCompanionDeposit && !initialPremiumHandledByDeposit {
                if let deductedPortfolioAmount = original.value(forKey: "paymentDeductedAmount") as? Double, deductedPortfolioAmount > 1e-6 {
                    total += deductedPortfolioAmount
                } else {
                    let insuranceCurrency = Currency(rawValue: original.currency ?? portfolioCurrency.rawValue) ?? portfolioCurrency
                    let absolute = abs(original.amount)
                    if absolute > 1e-6 {
                        total += currencyService.convertAmount(absolute, from: insuranceCurrency, to: portfolioCurrency)
                    }
                }
            }

        }

        return total
    }

    static func updatePaymentStatusIfNeeded(for asset: Asset, in portfolio: Portfolio, context: NSManagedObjectContext) {
        guard let insurance = asset.value(forKey: "insurance") as? NSManagedObject else { return }

        let currencyService = CurrencyService.shared
        let portfolioCurrency = Currency(rawValue: portfolio.mainCurrency ?? "USD") ?? .usd

        let totalPremium = insurance.value(forKey: "totalPremium") as? Double ?? 0
        guard totalPremium > 0 else { return }

        let originalTransaction = (asset.transactions?.allObjects as? [Transaction])?
            .first(where: { $0.portfolio?.objectID == portfolio.objectID && $0.type == TransactionType.insurance.rawValue })

        let insuranceCurrency = Currency(rawValue: originalTransaction?.currency ?? portfolioCurrency.rawValue) ?? portfolioCurrency
        let totalPremiumInPortfolio = currencyService.convertAmount(totalPremium, from: insuranceCurrency, to: portfolioCurrency)
        guard totalPremiumInPortfolio > 0 else { return }

        let paidAmount = totalPaidAmount(for: asset, in: portfolio, context: context)

        if paidAmount + 0.01 >= totalPremiumInPortfolio {
            if insurance.value(forKey: "premiumPaymentStatus") as? String != "Paid" {
                insurance.setValue("Paid", forKey: "premiumPaymentStatus")
            }
        }
    }

    private static func matchesLegacyHeuristic(_ transaction: Transaction,
                                               asset: Asset,
                                               originalTransaction: Transaction?) -> Bool {
        guard let notesLowercased = transaction.notes?.lowercased() else { return false }

        if let originalTransaction,
           let identifier = CashDisciplineService.companionNoteIdentifier(for: originalTransaction)?.lowercased(),
           notesLowercased.hasPrefix(identifier) {
            return true
        }

        if notesLowercased.contains("premium payment") {
            return true
        }

        if let symbol = asset.symbol?.lowercased(), !symbol.isEmpty, notesLowercased.contains(symbol) {
            return true
        }

        if let name = asset.name?.lowercased(), !name.isEmpty, notesLowercased.contains(name) {
            return true
        }

        return false
    }

    static func backfillMissingLinkedInsuranceIDsIfNeeded(using container: NSPersistentContainer) {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: migrationDefaultsKey) == false else { return }

        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        context.perform {
            do {
                let fetchRequest: NSFetchRequest<Asset> = Asset.fetchRequest()
                fetchRequest.predicate = NSPredicate(format: "insurance != nil")

                let insuranceAssets = try context.fetch(fetchRequest)

                for asset in insuranceAssets {
                    guard let transactions = asset.transactions?.allObjects as? [Transaction] else { continue }

                    let portfoliosByID = Dictionary(grouping: transactions.compactMap { $0.portfolio }) { $0.objectID }

                    for portfolio in portfoliosByID.values.compactMap({ $0.first }) {
                        _ = paymentTransactions(for: asset, in: portfolio, context: context)
                    }
                }

                if context.hasChanges {
                    try context.save()
                }

                defaults.set(true, forKey: migrationDefaultsKey)
            } catch {
                print("InsurancePaymentService: failed to backfill linked insurance IDs: \(error)")
            }
        }
    }

    private static func initialPremiumDeposit(for originalTransaction: Transaction?, deposits: [Transaction]) -> Transaction? {
        guard let originalTransaction,
              let originalID = originalTransaction.id else { return nil }

        let candidates = deposits.filter { deposit in
            guard deposit.type == TransactionType.deposit.rawValue else { return false }

            if let linkedID = deposit.value(forKey: "linkedTransactionID") as? UUID,
               linkedID == originalID {
                return true
            }

            return depositOccursDuringInitialWindow(deposit, original: originalTransaction)
        }

        guard !candidates.isEmpty else { return nil }

        return candidates.sorted { depositDate($0) < depositDate($1) }.first
    }

    private static func depositOccursDuringInitialWindow(_ deposit: Transaction, original: Transaction) -> Bool {
        guard let originalDate = original.transactionDate ?? original.createdAt else { return false }

        let depositDate = self.depositDate(deposit)
        let components = Calendar.current.dateComponents([.day], from: originalDate, to: depositDate)
        guard let dayDelta = components.day else { return false }

        let hasMeaningfulAmount = significantDepositValue(deposit) != nil
        return hasMeaningfulAmount && dayDelta >= -7 && dayDelta <= 180
    }

    private static func significantDepositValue(_ deposit: Transaction) -> Double? {
        let absoluteAmount = abs(deposit.amount)
        if absoluteAmount > 1e-6 {
            return absoluteAmount
        }

        if let stored = deposit.value(forKey: "paymentDeductedAmount") as? Double, stored > 1e-6 {
            return stored
        }

        return nil
    }

    private static func depositDate(_ deposit: Transaction) -> Date {
        deposit.transactionDate ?? deposit.createdAt ?? Date.distantPast
    }
}
