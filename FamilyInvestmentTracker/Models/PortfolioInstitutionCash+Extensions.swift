import Foundation
import CoreData

extension PortfolioInstitutionCash {

    // MARK: - Safe Access Properties

    var cashBalanceSafe: Double {
        get { (self.value(forKey: "cashBalance") as? Double) ?? 0.0 }
        set {
            self.setValue(newValue, forKey: "cashBalance")
            self.setValue(Date(), forKey: "updatedAt")
        }
    }

    var idSafe: UUID {
        get { (self.value(forKey: "id") as? UUID) ?? UUID() }
        set { self.setValue(newValue, forKey: "id") }
    }

    // MARK: - Helper Methods

    func addToCash(_ delta: Double) {
        cashBalanceSafe = cashBalanceSafe + delta
    }

    // MARK: - Factory Methods

    static func findOrCreate(portfolio: Portfolio, institution: Institution, context: NSManagedObjectContext) -> PortfolioInstitutionCash {
        // First try to find existing record
        let request: NSFetchRequest<PortfolioInstitutionCash> = PortfolioInstitutionCash.fetchRequest()
        request.predicate = NSPredicate(format: "portfolio == %@ AND institution == %@", portfolio, institution)
        request.fetchLimit = 1

        if let existingCash = try? context.fetch(request).first {
            return existingCash
        }

        // Create new record if not found
        let newCash = PortfolioInstitutionCash(context: context)
        newCash.setValue(UUID(), forKey: "id")
        newCash.setValue(portfolio, forKey: "portfolio")
        newCash.setValue(institution, forKey: "institution")
        newCash.setValue(0.0, forKey: "cashBalance")
        newCash.setValue(Date(), forKey: "createdAt")
        newCash.setValue(Date(), forKey: "updatedAt")

        return newCash
    }

    static func getCashBalance(portfolio: Portfolio, institution: Institution, context: NSManagedObjectContext) -> Double {
        let request: NSFetchRequest<PortfolioInstitutionCash> = PortfolioInstitutionCash.fetchRequest()
        request.predicate = NSPredicate(format: "portfolio == %@ AND institution == %@", portfolio, institution)
        request.fetchLimit = 1

        guard let existingCash = try? context.fetch(request).first else {
            return 0.0
        }

        return existingCash.cashBalanceSafe
    }

    static func updateCashBalance(portfolio: Portfolio, institution: Institution, newBalance: Double, context: NSManagedObjectContext) {
        let cashRecord = findOrCreate(portfolio: portfolio, institution: institution, context: context)
        cashRecord.cashBalanceSafe = newBalance
    }

    static func addToCashBalance(portfolio: Portfolio, institution: Institution, delta: Double, context: NSManagedObjectContext) {
        let cashRecord = findOrCreate(portfolio: portfolio, institution: institution, context: context)
        cashRecord.addToCash(delta)
    }
}

// MARK: - Portfolio Extensions for Cash Access

extension Portfolio {

    func getCashBalance(for institution: Institution) -> Double {
        guard let context = self.managedObjectContext else { return 0.0 }
        return PortfolioInstitutionCash.getCashBalance(portfolio: self, institution: institution, context: context)
    }

    func setCashBalance(for institution: Institution, amount: Double) {
        guard let context = self.managedObjectContext else { return }
        PortfolioInstitutionCash.updateCashBalance(portfolio: self, institution: institution, newBalance: amount, context: context)
    }

    func addToCashBalance(for institution: Institution, delta: Double) {
        guard let context = self.managedObjectContext else { return }
        PortfolioInstitutionCash.addToCashBalance(portfolio: self, institution: institution, delta: delta, context: context)
    }

    func getTotalCashBalance() -> Double {
        let cashBalances = (institutionCashBalances?.allObjects as? [PortfolioInstitutionCash]) ?? []
        return cashBalances.reduce(0) { $0 + $1.cashBalanceSafe }
    }
}

// MARK: - Institution Extensions for Cash Access

extension Institution {

    func getCashBalance(for portfolio: Portfolio) -> Double {
        guard let context = self.managedObjectContext else { return 0.0 }
        return PortfolioInstitutionCash.getCashBalance(portfolio: portfolio, institution: self, context: context)
    }

    func setCashBalance(for portfolio: Portfolio, amount: Double) {
        guard let context = self.managedObjectContext else { return }
        PortfolioInstitutionCash.updateCashBalance(portfolio: portfolio, institution: self, newBalance: amount, context: context)
    }

    func addToCashBalance(for portfolio: Portfolio, delta: Double) {
        guard let context = self.managedObjectContext else { return }
        PortfolioInstitutionCash.addToCashBalance(portfolio: portfolio, institution: self, delta: delta, context: context)
    }

    func getTotalCashBalance() -> Double {
        let cashBalances = (portfolioCashBalances?.allObjects as? [PortfolioInstitutionCash]) ?? []
        return cashBalances.reduce(0) { $0 + $1.cashBalanceSafe }
    }
}