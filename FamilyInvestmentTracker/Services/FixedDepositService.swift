import Foundation
import CoreData

final class FixedDepositService {
    static let shared = FixedDepositService()
    private init() {}

    // MARK: - Fixed Deposit Creation

    /// Create a new fixed deposit asset
    func createFixedDeposit(
        name: String,
        symbol: String?,
        institution: Institution?,
        portfolio: Portfolio,
        amount: Double,
        currency: Currency,
        termMonths: Int,
        interestRate: Double,
        allowEarlyWithdrawal: Bool = false,
        context: NSManagedObjectContext
    ) -> Asset {
        let asset = Asset(context: context)
        asset.id = UUID()
        asset.createdAt = Date()
        asset.assetType = AssetType.deposit.rawValue
        asset.depositSubtypeEnum = .fixed
        asset.name = name
        asset.symbol = symbol
        asset.currentPrice = amount
        asset.lastPriceUpdate = Date()
        asset.setValue(interestRate, forKey: "interestRate")
        asset.allowEarlyWithdrawal = allowEarlyWithdrawal

        // Calculate maturity date
        let calendar = Calendar.current
        if let maturityDate = calendar.date(byAdding: .month, value: termMonths, to: Date()) {
            asset.maturityDate = maturityDate
        }

        // Create holding for the fixed deposit
        let holding = Holding(context: context)
        holding.id = UUID()
        holding.quantity = 1
        holding.averageCostBasis = amount
        holding.totalDividends = 0
        holding.realizedGainLoss = 0
        holding.updatedAt = Date()
        holding.asset = asset
        holding.portfolio = portfolio
        holding.institution = institution

        // Ensure identifiers are set
        asset.ensureIdentifier()
        holding.ensureIdentifier()

        return asset
    }

    // MARK: - Fixed Deposit Withdrawal

    /// Process an early withdrawal from a fixed deposit
    func processEarlyWithdrawal(
        from fixedDeposit: Asset,
        amount: Double,
        accruedInterest: Double,
        institutionPenalty: Double,
        portfolio: Portfolio,
        institution: Institution,
        currency: Currency,
        context: NSManagedObjectContext
    ) -> Transaction {
        // Create the withdrawal transaction
        let transaction = Transaction.createEarlyWithdrawal(
            from: fixedDeposit,
            amount: amount,
            accruedInterest: accruedInterest,
            institutionPenalty: institutionPenalty,
            date: Date(),
            portfolio: portfolio,
            institution: institution,
            currency: currency,
            context: context
        )

        // Update the holding
        if let holding = findHolding(for: fixedDeposit, portfolio: portfolio, context: context) {
            let withdrawalPercentage = amount / fixedDeposit.currentPrice
            holding.quantity = max(0, holding.quantity - withdrawalPercentage)
            holding.updatedAt = Date()
        }

        // Add cash to available balance
        let netAmount = amount - institutionPenalty
        CashBalanceService.shared.addToAvailableCashBalance(
            for: portfolio,
            institution: institution,
            currency: currency,
            delta: netAmount
        )

        return transaction
    }

    /// Process a maturity withdrawal from a fixed deposit
    func processMaturityWithdrawal(
        from fixedDeposit: Asset,
        portfolio: Portfolio,
        institution: Institution,
        currency: Currency,
        context: NSManagedObjectContext
    ) -> Transaction {
        guard let holding = findHolding(for: fixedDeposit, portfolio: portfolio, context: context) else {
            fatalError("No holding found for fixed deposit")
        }

        let amount = holding.quantity * fixedDeposit.currentPrice

        // Create the withdrawal transaction
        let transaction = Transaction.createMaturityWithdrawal(
            from: fixedDeposit,
            amount: amount,
            date: Date(),
            portfolio: portfolio,
            institution: institution,
            currency: currency,
            context: context
        )

        // Clear the holding
        holding.quantity = 0
        holding.updatedAt = Date()

        // Add cash to available balance
        CashBalanceService.shared.addToAvailableCashBalance(
            for: portfolio,
            institution: institution,
            currency: currency,
            delta: amount
        )

        return transaction
    }

    // MARK: - Interest Payment

    /// Create an interest payment for a fixed deposit
    func createInterestPayment(
        for fixedDeposit: Asset,
        amount: Double,
        date: Date,
        portfolio: Portfolio,
        institution: Institution?,
        currency: Currency,
        context: NSManagedObjectContext
    ) -> Transaction {
        let transaction = Transaction.createInterestPayment(
            for: fixedDeposit,
            amount: amount,
            date: date,
            portfolio: portfolio,
            institution: institution,
            currency: currency,
            context: context
        )

        // Add interest to cash balance
        if let institution = institution {
            CashBalanceService.shared.addToAvailableCashBalance(
                for: portfolio,
                institution: institution,
                currency: currency,
                delta: amount
            )
        }

        return transaction
    }

    // MARK: - Validation

    /// Check if a fixed deposit can be withdrawn early
    func canWithdrawEarly(from fixedDeposit: Asset) -> Bool {
        return fixedDeposit.canWithdrawEarly()
    }

    /// Check if a fixed deposit is matured
    func isMatured(_ fixedDeposit: Asset) -> Bool {
        return fixedDeposit.isMatured
    }

    /// Check if a fixed deposit is active (not matured)
    func isActive(_ fixedDeposit: Asset) -> Bool {
        return fixedDeposit.isActiveFixedDeposit
    }

    /// Get days until maturity for a fixed deposit
    func daysUntilMaturity(for fixedDeposit: Asset) -> Int? {
        return fixedDeposit.daysUntilMaturity
    }

    // MARK: - Helper Methods

    private func findHolding(for asset: Asset, portfolio: Portfolio, context: NSManagedObjectContext) -> Holding? {
        let request: NSFetchRequest<Holding> = Holding.fetchRequest()
        request.predicate = NSPredicate(format: "asset == %@ AND portfolio == %@", asset, portfolio)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }

    // MARK: - Portfolio Fixed Deposit Management

    /// Get all fixed deposits for a portfolio
    func getFixedDeposits(for portfolio: Portfolio, context: NSManagedObjectContext) -> [Asset] {
        let request: NSFetchRequest<Asset> = Asset.fetchRequest()
        request.predicate = NSPredicate(format: "assetType == %@ AND depositSubtype == %@", AssetType.deposit.rawValue, "fixed")

        guard let assets = try? context.fetch(request) else { return [] }

        // Filter to only include assets that have holdings in this portfolio
        return assets.filter { asset in
            let holdings = (asset.holdings?.allObjects as? [Holding]) ?? []
            return holdings.contains { $0.portfolio == portfolio && $0.quantity > 0 }
        }
    }

    /// Get active fixed deposits (not matured) for a portfolio
    func getActiveFixedDeposits(for portfolio: Portfolio, context: NSManagedObjectContext) -> [Asset] {
        return getFixedDeposits(for: portfolio, context: context).filter { isActive($0) }
    }

    /// Get matured fixed deposits for a portfolio
    func getMaturedFixedDeposits(for portfolio: Portfolio, context: NSManagedObjectContext) -> [Asset] {
        return getFixedDeposits(for: portfolio, context: context).filter { isMatured($0) }
    }

    // MARK: - Asset Identifier Management

    /// Ensure an asset has a valid identifier
    private func ensureIdentifier(for asset: Asset) {
        if asset.id == nil {
            asset.id = UUID()
        }
    }

    /// Ensure a holding has a valid identifier
    private func ensureIdentifier(for holding: Holding) {
        if holding.id == nil {
            holding.id = UUID()
        }
    }
}
