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
}
