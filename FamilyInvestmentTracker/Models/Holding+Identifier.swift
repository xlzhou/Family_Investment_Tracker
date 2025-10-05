import Foundation
import CoreData

extension Holding {
    /// Ensures the holding has a UUID identifier.
    func ensureIdentifier() {
        if id == nil {
            id = UUID()
        }
    }
}