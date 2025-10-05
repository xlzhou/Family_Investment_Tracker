import Foundation
import CoreData

extension Institution {
    func getAllCurrencyBalances(for portfolio: Portfolio) -> [PortfolioInstitutionCurrencyCash] {
        guard let context = managedObjectContext else { return [] }

        let request: NSFetchRequest<PortfolioInstitutionCurrencyCash> = PortfolioInstitutionCurrencyCash.fetchRequest()
        request.predicate = NSPredicate(format: "portfolio == %@ AND institution == %@", portfolio, self)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \PortfolioInstitutionCurrencyCash.currency, ascending: true)]

        return (try? context.fetch(request)) ?? []
    }

    func getCashBalance(for portfolio: Portfolio) -> Double {
        guard let mainCurrencyCode = portfolio.mainCurrency,
              let mainCurrency = Currency(rawValue: mainCurrencyCode) else { return 0.0 }

        return getAllCurrencyBalances(for: portfolio).reduce(0) { total, record in
            guard let currency = Currency(rawValue: record.currencySafe) else { return total }
            let amount = record.amountSafe
            let convertedAmount = CurrencyService.shared.convertAmount(amount, from: currency, to: mainCurrency)
            return total + convertedAmount
        }
    }

    // MARK: - Enhanced Cash Balance Methods

    /// Total cash balance including both available cash and fixed deposits
    func getTotalCashBalance(for portfolio: Portfolio) -> Double {
        return CashBalanceService.shared.getTotalCashBalance(for: portfolio, institution: self)
    }

    /// Available cash balance (demand deposits + savings accounts)
    func getAvailableCashBalance(for portfolio: Portfolio) -> Double {
        return CashBalanceService.shared.getAvailableCashBalance(for: portfolio, institution: self)
    }

    /// Fixed deposit balance (locked funds)
    func getFixedDepositBalance(for portfolio: Portfolio) -> Double {
        return CashBalanceService.shared.getFixedDepositBalance(for: portfolio, institution: self)
    }

    /// Check if there's sufficient available cash for a transaction
    func hasSufficientAvailableCash(for portfolio: Portfolio, amount: Double, currency: Currency) -> Bool {
        let availableBalance = getAvailableCashBalance(for: portfolio)
        return availableBalance >= amount
    }

    /// Check if there's sufficient total cash (including fixed deposits) for a transaction
    func hasSufficientTotalCash(for portfolio: Portfolio, amount: Double, currency: Currency) -> Bool {
        let totalBalance = getTotalCashBalance(for: portfolio)
        return totalBalance >= amount
    }

    func setCashBalance(for portfolio: Portfolio, currency: Currency, amount: Double) {
        guard let context = managedObjectContext else { return }

        let record = findOrCreateCurrencyCashRecord(portfolio: portfolio, currency: currency.rawValue, context: context)
        record.amountSafe = amount

        do {
            try context.save()
        } catch {
            print("❌ Error saving currency cash balance: \(error)")
        }
    }

    func addToCashBalance(for portfolio: Portfolio, currency: Currency, delta: Double) {
        guard let context = managedObjectContext else { return }

        let record = findOrCreateCurrencyCashRecord(portfolio: portfolio, currency: currency.rawValue, context: context)
        record.addToAmount(delta)

        do {
            try context.save()
        } catch {
            print("❌ Error saving currency cash balance: \(error)")
        }
    }

    private func findOrCreateCurrencyCashRecord(portfolio: Portfolio, currency: String, context: NSManagedObjectContext) -> PortfolioInstitutionCurrencyCash {
        let request: NSFetchRequest<PortfolioInstitutionCurrencyCash> = PortfolioInstitutionCurrencyCash.fetchRequest()
        request.predicate = NSPredicate(format: "portfolio == %@ AND institution == %@ AND currency == %@", portfolio, self, currency)
        request.fetchLimit = 1

        if let existing = try? context.fetch(request).first {
            return existing
        }

        let record = PortfolioInstitutionCurrencyCash(context: context)
        record.id = UUID()
        record.portfolio = portfolio
        record.institution = self
        record.currency = currency
        record.amount = 0
        record.createdAt = Date()
        record.updatedAt = Date()
        return record
    }
}
