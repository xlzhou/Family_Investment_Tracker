import Foundation
import CoreData

extension Transaction {

    // MARK: - Parent Deposit Asset

    var parentDepositAsset: Asset? {
        get {
            guard let parentID = parentDepositAssetID else { return nil }
            let request: NSFetchRequest<Asset> = Asset.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", parentID as CVarArg)
            return try? managedObjectContext?.fetch(request).first
        }
        set {
            parentDepositAssetID = newValue?.id
        }
    }

    var isLinkedToFixedDeposit: Bool {
        return parentDepositAssetID != nil
    }

    // MARK: - Early Withdrawal Properties

    var netWithdrawalAmount: Double {
        guard type == TransactionType.depositWithdrawal.rawValue else { return 0 }
        return amount - institutionPenalty
    }

    var hasEarlyWithdrawalPenalty: Bool {
        return institutionPenalty > 0
    }

    // MARK: - Validation

    func validateForFixedDepositLink() -> Bool {
        guard let parentAsset = parentDepositAsset else { return true }
        return parentAsset.isFixedDeposit
    }

    // MARK: - Interest Payment Helpers

    static func createInterestPayment(
        for fixedDeposit: Asset,
        amount: Double,
        date: Date,
        portfolio: Portfolio,
        institution: Institution?,
        currency: Currency,
        context: NSManagedObjectContext
    ) -> Transaction {
        let transaction = Transaction(context: context)
        transaction.id = UUID()
        transaction.createdAt = Date()
        transaction.transactionDate = date
        transaction.type = TransactionType.interest.rawValue
        transaction.amount = amount
        transaction.quantity = 1
        transaction.price = amount
        transaction.fees = 0
        transaction.tax = 0
        transaction.currency = currency.rawValue
        transaction.portfolio = portfolio
        transaction.institution = institution
        transaction.tradingInstitution = institution?.name
        transaction.autoFetchPrice = false
        transaction.parentDepositAsset = fixedDeposit
        transaction.asset = fixedDeposit

        if let depositName = fixedDeposit.name ?? fixedDeposit.symbol {
            transaction.notes = "Interest payment for \(depositName)"
        }

        transaction.ensureIdentifiers()
        return transaction
    }

    // MARK: - Early Withdrawal Helpers

    static func createEarlyWithdrawal(
        from fixedDeposit: Asset,
        amount: Double,
        accruedInterest: Double,
        institutionPenalty: Double,
        date: Date,
        portfolio: Portfolio,
        institution: Institution,
        currency: Currency,
        context: NSManagedObjectContext
    ) -> Transaction {
        let transaction = Transaction(context: context)
        transaction.id = UUID()
        transaction.createdAt = Date()
        transaction.transactionDate = date
        transaction.type = TransactionType.depositWithdrawal.rawValue
        transaction.amount = amount
        transaction.quantity = 1
        transaction.price = amount
        transaction.fees = 0
        transaction.tax = 0
        transaction.currency = currency.rawValue
        transaction.portfolio = portfolio
        transaction.institution = institution
        transaction.tradingInstitution = institution.name
        transaction.autoFetchPrice = false
        transaction.parentDepositAsset = fixedDeposit
        transaction.asset = fixedDeposit
        transaction.accruedInterest = accruedInterest
        transaction.institutionPenalty = institutionPenalty

        let netAmount = amount - institutionPenalty
        let penaltyText = institutionPenalty > 0 ? " (penalty: \(Formatters.currency(institutionPenalty, symbol: currency.symbol)))" : ""
        transaction.notes = "Early withdrawal from \(fixedDeposit.name ?? fixedDeposit.symbol ?? "fixed deposit")\(penaltyText). Net amount: \(Formatters.currency(netAmount, symbol: currency.symbol))"

        transaction.ensureIdentifiers()
        return transaction
    }

    static func createMaturityWithdrawal(
        from fixedDeposit: Asset,
        amount: Double,
        date: Date,
        portfolio: Portfolio,
        institution: Institution,
        currency: Currency,
        context: NSManagedObjectContext
    ) -> Transaction {
        let transaction = Transaction(context: context)
        transaction.id = UUID()
        transaction.createdAt = Date()
        transaction.transactionDate = date
        transaction.type = TransactionType.depositWithdrawal.rawValue
        transaction.amount = amount
        transaction.quantity = 1
        transaction.price = amount
        transaction.fees = 0
        transaction.tax = 0
        transaction.currency = currency.rawValue
        transaction.portfolio = portfolio
        transaction.institution = institution
        transaction.tradingInstitution = institution.name
        transaction.autoFetchPrice = false
        transaction.parentDepositAsset = fixedDeposit
        transaction.asset = fixedDeposit
        transaction.accruedInterest = 0
        transaction.institutionPenalty = 0

        let depositName = fixedDeposit.name ?? fixedDeposit.symbol ?? "fixed deposit"
        transaction.notes = "Maturity withdrawal for \(depositName)"

        transaction.ensureIdentifiers()
        return transaction
    }
}
