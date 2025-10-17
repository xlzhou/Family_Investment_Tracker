import Foundation
import CoreData

extension Transaction {
    /// Returns whether cash discipline adjustments were applied when the transaction was saved.
    /// Defaults to `true` so legacy transactions (without the stored flag) continue to behave as before.
    var cashDisciplineWasApplied: Bool {
        get {
            if let stored = value(forKey: "cashDisciplineApplied") as? NSNumber {
                return stored.boolValue
            }
            return true
        }
        set {
            setValue(newValue, forKey: "cashDisciplineApplied")
        }
    }
}
