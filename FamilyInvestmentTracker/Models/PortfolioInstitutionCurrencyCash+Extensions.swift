import Foundation
import CoreData

extension PortfolioInstitutionCurrencyCash {

    // MARK: - Safe Access Properties

    var idSafe: UUID {
        get { (self.value(forKey: "id") as? UUID) ?? UUID() }
        set { self.setValue(newValue, forKey: "id") }
    }

    var amountSafe: Double {
        get { (self.value(forKey: "amount") as? Double) ?? 0.0 }
        set {
            self.setValue(newValue, forKey: "amount")
            self.setValue(Date(), forKey: "updatedAt")
        }
    }

    var currencySafe: String {
        get { (self.value(forKey: "currency") as? String) ?? "USD" }
        set { self.setValue(newValue, forKey: "currency") }
    }

    // MARK: - Helper Methods

    func addToAmount(_ delta: Double) {
        amountSafe = amountSafe + delta
    }

    // MARK: - Factory Methods

    static func findOrCreate(portfolio: Portfolio, institution: Institution, currency: String, context: NSManagedObjectContext) -> PortfolioInstitutionCurrencyCash {
        // First try to find existing record
        let request: NSFetchRequest<PortfolioInstitutionCurrencyCash> = PortfolioInstitutionCurrencyCash.fetchRequest()
        request.predicate = NSPredicate(format: "portfolio == %@ AND institution == %@ AND currency == %@", portfolio, institution, currency)
        request.fetchLimit = 1

        if let existingCash = try? context.fetch(request).first {
            return existingCash
        }

        // Create new record if not found
        let newCash = PortfolioInstitutionCurrencyCash(context: context)
        newCash.setValue(UUID(), forKey: "id")
        newCash.setValue(portfolio, forKey: "portfolio")
        newCash.setValue(institution, forKey: "institution")
        newCash.setValue(currency, forKey: "currency")
        newCash.setValue(0.0, forKey: "amount")
        newCash.setValue(Date(), forKey: "createdAt")
        newCash.setValue(Date(), forKey: "updatedAt")

        return newCash
    }

    static func getCurrencyBalance(portfolio: Portfolio, institution: Institution, currency: String, context: NSManagedObjectContext) -> Double {
        let request: NSFetchRequest<PortfolioInstitutionCurrencyCash> = PortfolioInstitutionCurrencyCash.fetchRequest()
        request.predicate = NSPredicate(format: "portfolio == %@ AND institution == %@ AND currency == %@", portfolio, institution, currency)
        request.fetchLimit = 1

        guard let existingCash = try? context.fetch(request).first else {
            return 0.0
        }

        return existingCash.amountSafe
    }

    static func updateCurrencyBalance(portfolio: Portfolio, institution: Institution, currency: String, newAmount: Double, context: NSManagedObjectContext) {
        let cashRecord = findOrCreate(portfolio: portfolio, institution: institution, currency: currency, context: context)
        cashRecord.amountSafe = newAmount
    }

    static func addToCurrencyBalance(portfolio: Portfolio, institution: Institution, currency: String, delta: Double, context: NSManagedObjectContext) {
        let cashRecord = findOrCreate(portfolio: portfolio, institution: institution, currency: currency, context: context)
        cashRecord.addToAmount(delta)
    }

    static func getAllCurrencyBalances(portfolio: Portfolio, institution: Institution, context: NSManagedObjectContext) -> [PortfolioInstitutionCurrencyCash] {
        let request: NSFetchRequest<PortfolioInstitutionCurrencyCash> = PortfolioInstitutionCurrencyCash.fetchRequest()
        request.predicate = NSPredicate(format: "portfolio == %@ AND institution == %@", portfolio, institution)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \PortfolioInstitutionCurrencyCash.currency, ascending: true)]

        return (try? context.fetch(request)) ?? []
    }
}

// MARK: - Portfolio Extensions for Multi-Currency Cash Access

extension Portfolio {

    func getCurrencyBalance(for institution: Institution, currency: String) -> Double {
        guard let context = self.managedObjectContext else { return 0.0 }
        return PortfolioInstitutionCurrencyCash.getCurrencyBalance(portfolio: self, institution: institution, currency: currency, context: context)
    }

    func setCurrencyBalance(for institution: Institution, currency: String, amount: Double) {
        guard let context = self.managedObjectContext else { return }
        PortfolioInstitutionCurrencyCash.updateCurrencyBalance(portfolio: self, institution: institution, currency: currency, newAmount: amount, context: context)
    }

    func addToCurrencyBalance(for institution: Institution, currency: String, delta: Double) {
        guard let context = self.managedObjectContext else { return }
        PortfolioInstitutionCurrencyCash.addToCurrencyBalance(portfolio: self, institution: institution, currency: currency, delta: delta, context: context)
    }

    func getAllCurrencyBalances(for institution: Institution) -> [PortfolioInstitutionCurrencyCash] {
        guard let context = self.managedObjectContext else { return [] }
        return PortfolioInstitutionCurrencyCash.getAllCurrencyBalances(portfolio: self, institution: institution, context: context)
    }

    func getTotalCashBalanceInMainCurrency() -> Double {
        guard let context = self.managedObjectContext,
              let mainCurrencyCode = self.mainCurrency,
              let mainCurrency = Currency(rawValue: mainCurrencyCode) else { return 0.0 }

        let request: NSFetchRequest<PortfolioInstitutionCurrencyCash> = PortfolioInstitutionCurrencyCash.fetchRequest()
        request.predicate = NSPredicate(format: "portfolio == %@", self)

        guard let balances = try? context.fetch(request) else { return 0.0 }

        return balances.reduce(0) { total, record in
            guard let currency = Currency(rawValue: record.currencySafe) else { return total }
            let convertedAmount = CurrencyService.shared.convertAmount(
                record.amountSafe,
                from: currency,
                to: mainCurrency
            )
            return total + convertedAmount
        }
    }
}
