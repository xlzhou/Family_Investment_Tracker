import Foundation
import CoreData

final class CashBalanceService {
    static let shared = CashBalanceService()
    private init() {}

    private let currencyService = CurrencyService.shared

    // MARK: - Cash Balance Calculations

    /// Calculate total cash balance (available + fixed deposits) for a portfolio
    func getTotalCashBalance(for portfolio: Portfolio) -> Double {
        guard let context = portfolio.managedObjectContext else { return 0.0 }

        let currencyBalances = getTotalCurrencyBalances(for: portfolio, context: context)
        return convertToPortfolioCurrency(currencyBalances, portfolio: portfolio)
    }

    /// Calculate available cash balance (demand deposits + savings accounts) for a portfolio
    func getAvailableCashBalance(for portfolio: Portfolio) -> Double {
        guard let context = portfolio.managedObjectContext else { return 0.0 }

        let availableBalances = getAvailableCurrencyBalances(for: portfolio, context: context)
        return convertToPortfolioCurrency(availableBalances, portfolio: portfolio)
    }

    /// Calculate locked fixed deposit balance for a portfolio
    func getFixedDepositBalance(for portfolio: Portfolio) -> Double {
        guard let context = portfolio.managedObjectContext else { return 0.0 }

        let fixedDepositBalances = getFixedDepositCurrencyBalances(for: portfolio, context: context)
        return convertToPortfolioCurrency(fixedDepositBalances, portfolio: portfolio)
    }

    // MARK: - Institution-Specific Cash Balances

    /// Get total cash balance for a specific institution
    func getTotalCashBalance(for portfolio: Portfolio, institution: Institution) -> Double {
        guard let context = portfolio.managedObjectContext else { return 0.0 }

        let currencyBalances = getTotalCurrencyBalances(for: portfolio, institution: institution, context: context)
        return convertToPortfolioCurrency(currencyBalances, portfolio: portfolio)
    }

    /// Get available cash balance for a specific institution
    func getAvailableCashBalance(for portfolio: Portfolio, institution: Institution) -> Double {
        guard let context = portfolio.managedObjectContext else { return 0.0 }

        let availableBalances = getAvailableCurrencyBalances(for: portfolio, institution: institution, context: context)
        return convertToPortfolioCurrency(availableBalances, portfolio: portfolio)
    }

    /// Get fixed deposit balance for a specific institution
    func getFixedDepositBalance(for portfolio: Portfolio, institution: Institution) -> Double {
        guard let context = portfolio.managedObjectContext else { return 0.0 }

        let fixedDepositBalances = getFixedDepositCurrencyBalances(for: portfolio, institution: institution, context: context)
        return convertToPortfolioCurrency(fixedDepositBalances, portfolio: portfolio)
    }

    // MARK: - Currency-Specific Cash Balances

    /// Get total cash balance in a specific currency for a portfolio
    func getTotalCashBalance(for portfolio: Portfolio, currency: Currency) -> Double {
        guard let context = portfolio.managedObjectContext else { return 0.0 }

        let currencyBalances = getTotalCurrencyBalances(for: portfolio, context: context)
        return currencyBalances[currency.rawValue] ?? 0.0
    }

    /// Get available cash balance in a specific currency for a portfolio
    func getAvailableCashBalance(for portfolio: Portfolio, currency: Currency) -> Double {
        guard let context = portfolio.managedObjectContext else { return 0.0 }

        let availableBalances = getAvailableCurrencyBalances(for: portfolio, context: context)
        return availableBalances[currency.rawValue] ?? 0.0
    }

    /// Get fixed deposit balance in a specific currency for a portfolio
    func getFixedDepositBalance(for portfolio: Portfolio, currency: Currency) -> Double {
        guard let context = portfolio.managedObjectContext else { return 0.0 }

        let fixedDepositBalances = getFixedDepositCurrencyBalances(for: portfolio, context: context)
        return fixedDepositBalances[currency.rawValue] ?? 0.0
    }

    // MARK: - Private Helper Methods

    private func getTotalCurrencyBalances(for portfolio: Portfolio, context: NSManagedObjectContext) -> [String: Double] {
        var balances = getAvailableCurrencyBalances(for: portfolio, context: context)
        let fixedBalances = getFixedDepositCurrencyBalances(for: portfolio, context: context)

        for (currency, amount) in fixedBalances {
            balances[currency, default: 0.0] += amount
        }

        return balances
    }

    private func getTotalCurrencyBalances(for portfolio: Portfolio, institution: Institution, context: NSManagedObjectContext) -> [String: Double] {
        var balances = getAvailableCurrencyBalances(for: portfolio, institution: institution, context: context)
        let fixedBalances = getFixedDepositCurrencyBalances(for: portfolio, institution: institution, context: context)

        for (currency, amount) in fixedBalances {
            balances[currency, default: 0.0] += amount
        }

        return balances
    }

    private func getAvailableCurrencyBalances(for portfolio: Portfolio, context: NSManagedObjectContext) -> [String: Double] {
        let request: NSFetchRequest<PortfolioInstitutionCurrencyCash> = PortfolioInstitutionCurrencyCash.fetchRequest()
        request.predicate = NSPredicate(format: "portfolio == %@", portfolio)

        guard let balances = try? context.fetch(request) else { return [:] }

        return balances.reduce(into: [:]) { result, record in
            let currency = record.currencySafe
            let amount = record.amountSafe
            result[currency] = (result[currency] ?? 0.0) + amount
        }
    }

    private func getAvailableCurrencyBalances(for portfolio: Portfolio, institution: Institution, context: NSManagedObjectContext) -> [String: Double] {
        let request: NSFetchRequest<PortfolioInstitutionCurrencyCash> = PortfolioInstitutionCurrencyCash.fetchRequest()
        request.predicate = NSPredicate(format: "portfolio == %@ AND institution == %@", portfolio, institution)

        guard let balances = try? context.fetch(request) else { return [:] }

        return balances.reduce(into: [:]) { result, record in
            let currency = record.currencySafe
            let amount = record.amountSafe
            result[currency] = (result[currency] ?? 0.0) + amount
        }
    }

    private func getFixedDepositCurrencyBalances(for portfolio: Portfolio, context: NSManagedObjectContext) -> [String: Double] {
        let request: NSFetchRequest<Asset> = Asset.fetchRequest()
        request.predicate = NSPredicate(format: "assetType == %@ AND depositSubtype == %@", AssetType.deposit.rawValue, "fixed")

        guard let fixedDeposits = try? context.fetch(request) else { return [:] }

        return fixedDeposits.reduce(into: [:]) { result, asset in
            let holdings = (asset.holdings?.allObjects as? [Holding]) ?? []
            let portfolioHoldings = holdings.filter { $0.portfolio == portfolio }
            let currencyCode = resolvedCurrencyCode(for: asset, portfolio: portfolio)

            for holding in portfolioHoldings {
                let amount = holding.quantity * asset.currentPrice
                result[currencyCode, default: 0.0] += amount
            }
        }
    }

    private func getFixedDepositCurrencyBalances(for portfolio: Portfolio, institution: Institution, context: NSManagedObjectContext) -> [String: Double] {
        let request: NSFetchRequest<Asset> = Asset.fetchRequest()
        request.predicate = NSPredicate(format: "assetType == %@ AND depositSubtype == %@", AssetType.deposit.rawValue, "fixed")

        guard let fixedDeposits = try? context.fetch(request) else { return [:] }

        return fixedDeposits.reduce(into: [:]) { result, asset in
            let holdings = (asset.holdings?.allObjects as? [Holding]) ?? []
            let portfolioHoldings = holdings.filter { $0.portfolio == portfolio && $0.institution == institution }
            let currencyCode = resolvedCurrencyCode(for: asset, portfolio: portfolio)

            for holding in portfolioHoldings {
                let amount = holding.quantity * asset.currentPrice
                result[currencyCode, default: 0.0] += amount
            }
        }
    }

    private func resolvedCurrencyCode(for asset: Asset, portfolio: Portfolio) -> String {
        let transactions = (asset.transactions?.allObjects as? [Transaction]) ?? []
        if let match = transactions.first(where: { $0.portfolio?.objectID == portfolio.objectID && ($0.currency?.isEmpty == false) }) {
            return match.currency ?? (portfolio.mainCurrency ?? Currency.usd.rawValue)
        }
        if let portfolioCurrency = portfolio.mainCurrency {
            return portfolioCurrency
        }
        return Currency.usd.rawValue
    }

    private func convertToPortfolioCurrency(_ currencyBalances: [String: Double], portfolio: Portfolio) -> Double {
        guard let mainCurrencyCode = portfolio.mainCurrency,
              let mainCurrency = Currency(rawValue: mainCurrencyCode) else { return 0.0 }

        return currencyBalances.reduce(0) { total, entry in
            let (currencyCode, amount) = entry
            guard let currency = Currency(rawValue: currencyCode) else { return total }
            let convertedAmount = currencyService.convertAmount(amount, from: currency, to: mainCurrency)
            return total + convertedAmount
        }
    }

    // MARK: - Validation Methods

    /// Check if there's sufficient available cash for a transaction
    func hasSufficientAvailableCash(for portfolio: Portfolio, amount: Double, currency: Currency) -> Bool {
        let availableBalance = getAvailableCashBalance(for: portfolio, currency: currency)
        return availableBalance >= amount
    }

    /// Check if there's sufficient total cash (including fixed deposits) for a transaction
    func hasSufficientTotalCash(for portfolio: Portfolio, amount: Double, currency: Currency) -> Bool {
        let totalBalance = getTotalCashBalance(for: portfolio, currency: currency)
        return totalBalance >= amount
    }

    // MARK: - Cash Balance Updates

    /// Update available cash balance for a specific institution and currency
    func updateAvailableCashBalance(for portfolio: Portfolio, institution: Institution, currency: Currency, amount: Double) {
        guard let context = portfolio.managedObjectContext else { return }

        let record = PortfolioInstitutionCurrencyCash.findOrCreate(
            portfolio: portfolio,
            institution: institution,
            currency: currency.rawValue,
            context: context
        )
        record.amountSafe = amount

        do {
            try context.save()
        } catch {
            print("❌ Error updating available cash balance: \(error)")
        }
    }

    /// Add to available cash balance for a specific institution and currency
    func addToAvailableCashBalance(for portfolio: Portfolio, institution: Institution, currency: Currency, delta: Double) {
        guard let context = portfolio.managedObjectContext else { return }

        let record = PortfolioInstitutionCurrencyCash.findOrCreate(
            portfolio: portfolio,
            institution: institution,
            currency: currency.rawValue,
            context: context
        )
        record.addToAmount(delta)

        do {
            try context.save()
        } catch {
            print("❌ Error adding to available cash balance: \(error)")
        }
    }
}
