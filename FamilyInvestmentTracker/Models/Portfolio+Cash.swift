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
}
