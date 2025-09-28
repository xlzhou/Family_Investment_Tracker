import Foundation
import CoreData

extension Holding {
    var institutionSafe: Institution? {
        get { value(forKey: "institution") as? Institution }
        set { setValue(newValue, forKey: "institution") }
    }
}

extension Transaction {
    var institutionSafe: Institution? {
        get { value(forKey: "institution") as? Institution }
        set { setValue(newValue, forKey: "institution") }
    }
}
