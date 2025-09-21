import Foundation
import CoreData

extension Institution {
    // DEPRECATED: Use getCashBalance(for:) instead
    // This is kept for backward compatibility during migration
    var cashBalanceSafe: Double {
        get { (self.value(forKey: "cashBalance") as? Double) ?? 0.0 }
        set { self.setValue(newValue, forKey: "cashBalance") }
    }

    // NEW: Portfolio-aware cash balance methods
    func getCashBalance(for portfolio: Portfolio) -> Double {
        guard let context = self.managedObjectContext else { return 0.0 }

        // Fetch PortfolioInstitutionCash record directly
        let request: NSFetchRequest<NSManagedObject> = NSFetchRequest(entityName: "PortfolioInstitutionCash")
        request.predicate = NSPredicate(format: "portfolio == %@ AND institution == %@", portfolio, self)
        request.fetchLimit = 1

        guard let cashRecord = try? context.fetch(request).first,
              let balance = cashRecord.value(forKey: "cashBalance") as? Double else {
            return 0.0
        }

        return balance
    }

    func setCashBalance(for portfolio: Portfolio, amount: Double) {
        guard let context = self.managedObjectContext else { return }

        // Find or create PortfolioInstitutionCash record
        let request: NSFetchRequest<NSManagedObject> = NSFetchRequest(entityName: "PortfolioInstitutionCash")
        request.predicate = NSPredicate(format: "portfolio == %@ AND institution == %@", portfolio, self)
        request.fetchLimit = 1

        let cashRecord: NSManagedObject
        if let existingRecord = try? context.fetch(request).first {
            cashRecord = existingRecord
        } else {
            cashRecord = NSEntityDescription.insertNewObject(forEntityName: "PortfolioInstitutionCash", into: context)
            cashRecord.setValue(UUID(), forKey: "id")
            cashRecord.setValue(portfolio, forKey: "portfolio")
            cashRecord.setValue(self, forKey: "institution")
            cashRecord.setValue(Date(), forKey: "createdAt")
        }

        cashRecord.setValue(amount, forKey: "cashBalance")
        cashRecord.setValue(Date(), forKey: "updatedAt")
    }

    func addToCashBalance(for portfolio: Portfolio, delta: Double) {
        let currentBalance = getCashBalance(for: portfolio)
        setCashBalance(for: portfolio, amount: currentBalance + delta)
    }
}
