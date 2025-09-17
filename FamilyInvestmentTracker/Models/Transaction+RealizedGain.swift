import Foundation
import CoreData

extension Transaction {
    /// Helper wrapper for the Core Data `realizedGain` attribute.
    var realizedGainAmount: Double {
        get { (self.value(forKey: "realizedGain") as? Double) ?? 0 }
        set { self.setValue(newValue, forKey: "realizedGain") }
    }
}
