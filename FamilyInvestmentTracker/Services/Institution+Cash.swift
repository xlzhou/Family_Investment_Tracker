import Foundation
import CoreData

extension Institution {
    var cashBalanceSafe: Double {
        get { (self.value(forKey: "cashBalance") as? Double) ?? 0.0 }
        set { self.setValue(newValue, forKey: "cashBalance") }
    }
}
