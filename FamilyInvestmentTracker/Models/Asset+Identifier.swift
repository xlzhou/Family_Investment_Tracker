import Foundation
import CoreData

extension Asset {
    /// Ensures the asset has a UUID identifier.
    func ensureIdentifier() {
        if id == nil {
            id = UUID()
        }
    }
}