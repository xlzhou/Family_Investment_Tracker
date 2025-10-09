import CoreData

struct CompanionLinkRepairSummary {
    let linkedCount: Int
    let alreadyLinkedCount: Int
    let failedCount: Int
}

final class CompanionLinkRepairService {
    static let shared = CompanionLinkRepairService()

    private init() {}

    func linkLegacyCompanions(in context: NSManagedObjectContext) async throws -> CompanionLinkRepairSummary {
        try await context.perform {
            let fetchRequest: NSFetchRequest<Transaction> = Transaction.fetchRequest()
            fetchRequest.returnsObjectsAsFaults = false

            let transactions = try context.fetch(fetchRequest)
            var transactionsByID: [UUID: Transaction] = [:]
            for transaction in transactions {
                if let id = transaction.id {
                    transactionsByID[id] = transaction
                }
            }

            var linked = 0
            var alreadyLinked = 0

            for companion in transactions {
                guard companion.value(forKey: "linkedTransactionID") as? UUID == nil else {
                    alreadyLinked += 1
                    continue
                }

                guard let typeRaw = companion.type,
                      let type = TransactionType(rawValue: typeRaw),
                      type == .deposit || type == .depositWithdrawal else {
                    continue
                }

                if CompanionLinkRepairService.linkCashDisciplineCompanion(companion, transactionsByID: transactionsByID) {
                    linked += 1
                    continue
                }

                if CompanionLinkRepairService.linkFixedDepositCompanion(companion, allTransactions: transactions) {
                    linked += 1
                    continue
                }
            }

            if context.hasChanges {
                try context.save()
            }

            return CompanionLinkRepairSummary(linkedCount: linked,
                                             alreadyLinkedCount: alreadyLinked,
                                             failedCount: 0)
        }
    }

    private static func linkCashDisciplineCompanion(_ companion: Transaction,
                                                    transactionsByID: [UUID: Transaction]) -> Bool {
        guard let notes = companion.notes,
              let linkedID = CashDisciplineService.extractLinkedTransactionID(from: notes),
              let mainTransaction = transactionsByID[linkedID] else {
            return false
        }

        companion.setValue(linkedID, forKey: "linkedTransactionID")
        if companion.institution == nil {
            companion.institution = mainTransaction.institution
        }
        return true
    }

    private static func linkFixedDepositCompanion(_ companion: Transaction,
                                                  allTransactions: [Transaction]) -> Bool {
        guard let notes = companion.notes,
              notes.lowercased().contains("transfer to fixed deposit"),
              let portfolio = companion.portfolio else {
            return false
        }

        let depositName = notes.split(separator: ":", maxSplits: 1).last.map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
        let companionAmount = abs(companion.amount)
        let companionDate = companion.transactionDate.map { Calendar.current.startOfDay(for: $0) }

        let candidates = allTransactions.filter { txn in
            guard txn !== companion,
                  txn.portfolio?.objectID == portfolio.objectID,
                  txn.type == TransactionType.deposit.rawValue,
                  txn.asset?.depositSubtypeEnum == .fixed else { return false }

            if let companionDate, let txnDate = txn.transactionDate.map({ Calendar.current.startOfDay(for: $0) }), companionDate != txnDate {
                return false
            }

            let amountMatches = abs(abs(txn.amount) - companionAmount) < 0.01
            let noteMatches = (txn.notes ?? "").contains(depositName)
                || (txn.asset?.name?.localizedCaseInsensitiveContains(depositName) ?? false)
                || (txn.asset?.symbol?.localizedCaseInsensitiveContains(depositName) ?? false)

            return amountMatches && noteMatches
        }

        guard let mainTransaction = candidates.first,
              let mainID = mainTransaction.id else {
            return false
        }

        companion.setValue(mainID, forKey: "linkedTransactionID")
        return true
    }
}
