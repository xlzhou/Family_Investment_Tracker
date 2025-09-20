import Foundation
import CoreData

class InstitutionAssetService {
    static let shared = InstitutionAssetService()

    private init() {}

    /// Get all assets available at a specific institution
    func getAssetsAvailableAt(institution: Institution, context: NSManagedObjectContext) -> [Asset] {
        let request: NSFetchRequest<InstitutionAssetAvailability> = NSFetchRequest(entityName: "InstitutionAssetAvailability")
        request.predicate = NSPredicate(format: "institution == %@", institution)
        request.sortDescriptors = [NSSortDescriptor(key: "lastTransactionDate", ascending: false)]

        do {
            let availabilities = try context.fetch(request)
            return availabilities.compactMap { $0.value(forKey: "asset") as? Asset }
        } catch {
            print("❌ Error fetching assets for institution \(institution.name ?? "Unknown"): \(error)")
            return []
        }
    }

    /// Get all institutions where a specific asset is available
    func getInstitutionsOffering(asset: Asset, context: NSManagedObjectContext) -> [Institution] {
        let request: NSFetchRequest<InstitutionAssetAvailability> = NSFetchRequest(entityName: "InstitutionAssetAvailability")
        request.predicate = NSPredicate(format: "asset == %@", asset)
        request.sortDescriptors = [NSSortDescriptor(key: "lastTransactionDate", ascending: false)]

        do {
            let availabilities = try context.fetch(request)
            return availabilities.compactMap { $0.value(forKey: "institution") as? Institution }
        } catch {
            print("❌ Error fetching institutions for asset \(asset.symbol ?? "Unknown"): \(error)")
            return []
        }
    }

    /// Check if an asset is available at a specific institution
    func isAssetAvailableAt(asset: Asset, institution: Institution, context: NSManagedObjectContext) -> Bool {
        let request: NSFetchRequest<InstitutionAssetAvailability> = NSFetchRequest(entityName: "InstitutionAssetAvailability")
        request.predicate = NSPredicate(format: "institution == %@ AND asset == %@", institution, asset)
        request.fetchLimit = 1

        do {
            let count = try context.count(for: request)
            return count > 0
        } catch {
            print("❌ Error checking asset availability: \(error)")
            return false
        }
    }

    /// Get the last transaction date for an asset at an institution
    func getLastTransactionDate(asset: Asset, institution: Institution, context: NSManagedObjectContext) -> Date? {
        let request: NSFetchRequest<InstitutionAssetAvailability> = NSFetchRequest(entityName: "InstitutionAssetAvailability")
        request.predicate = NSPredicate(format: "institution == %@ AND asset == %@", institution, asset)
        request.fetchLimit = 1

        do {
            if let availability = try context.fetch(request).first {
                return availability.value(forKey: "lastTransactionDate") as? Date
            }
        } catch {
            print("❌ Error fetching last transaction date: \(error)")
        }
        return nil
    }
}