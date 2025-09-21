import Foundation
import CoreData

extension Portfolio {
    // Safe access to cashBalance using KVC, in case codegen hasn't updated yet
    var cashBalanceSafe: Double {
        get { (self.value(forKey: "cashBalance") as? Double) ?? 0.0 }
        set { self.setValue(newValue, forKey: "cashBalance") }
    }
    
    func addToCash(_ delta: Double) {
        cashBalanceSafe = cashBalanceSafe + delta
    }

    var enforcesCashDisciplineEnabled: Bool {
        get { (self.value(forKey: "enforcesCashDiscipline") as? Bool) ?? true }
        set { self.setValue(newValue, forKey: "enforcesCashDiscipline") }
    }

    func resolvedCashBalance(tolerance: Double = 0.01) -> Double {
        // NEW: Use PortfolioInstitutionCash system
        let newSystemCash = getTotalCashBalanceFromNewSystem()

        // LEGACY: For backward compatibility during migration
        let portfolioCash = cashBalanceSafe
        let transactions = (transactions?.allObjects as? [Transaction]) ?? []
        let institutions = Set(transactions.compactMap { $0.institution })
        let oldSystemCash = institutions.reduce(0) { partial, institution in
            partial + institution.cashBalanceSafe
        }

        // Prefer new system if it has data, otherwise fall back to old system
        if newSystemCash != 0 {
            return newSystemCash
        }

        // Legacy logic for backward compatibility
        if abs(portfolioCash - oldSystemCash) <= tolerance {
            return portfolioCash
        }

        if oldSystemCash != 0 {
            return oldSystemCash
        }

        return portfolioCash
    }

    private func getTotalCashBalanceFromNewSystem() -> Double {
        guard let context = self.managedObjectContext else { return 0.0 }

        let request: NSFetchRequest<NSManagedObject> = NSFetchRequest(entityName: "PortfolioInstitutionCash")
        request.predicate = NSPredicate(format: "portfolio == %@", self)

        guard let cashRecords = try? context.fetch(request) else { return 0.0 }

        return cashRecords.reduce(0.0) { total, record in
            let balance = (record.value(forKey: "cashBalance") as? Double) ?? 0.0
            return total + balance
        }
    }
}
