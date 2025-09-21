import CoreData
import CloudKit
import Foundation

struct PersistenceController {
    static let shared = PersistenceController()

    static var preview: PersistenceController = {
        let result = PersistenceController(inMemory: true)
        let viewContext = result.container.viewContext
        
        // Create sample data for previews
        let jerryPortfolio = Portfolio(context: viewContext)
        jerryPortfolio.id = UUID()
        jerryPortfolio.name = "Jerry"
        jerryPortfolio.createdAt = Date()
        
        let carolPortfolio = Portfolio(context: viewContext)
        carolPortfolio.id = UUID()
        carolPortfolio.name = "Carol"
        carolPortfolio.createdAt = Date()
        
        let familyPortfolio = Portfolio(context: viewContext)
        familyPortfolio.id = UUID()
        familyPortfolio.name = "Family"
        familyPortfolio.createdAt = Date()
        
        do {
            try viewContext.save()
        } catch {
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
        return result
    }()

    let container: NSPersistentCloudKitContainer

    init(inMemory: Bool = false) {
        container = NSPersistentCloudKitContainer(name: "FamilyInvestmentTracker")
        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        }
        
        // Configure CloudKit and migrations
        container.persistentStoreDescriptions.forEach { storeDescription in
            storeDescription.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            storeDescription.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
            storeDescription.setOption(true as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
            storeDescription.setOption(true as NSNumber, forKey: NSInferMappingModelAutomaticallyOption)

            // Configure CloudKit container
            storeDescription.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
                containerIdentifier: "iCloud.com.kongkong.FamilyInvestmentTracker"
            )
        }
        
        container.loadPersistentStores(completionHandler: { [container] (storeDescription, error) in
            if let error = error as NSError? {
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }

            // Run cash balance migration after Core Data is loaded
            if !inMemory {
                DispatchQueue.main.async {
                    PersistenceController.runCashBalanceMigration(container: container)
                }
            }
        })
        container.viewContext.automaticallyMergesChangesFromParent = true
    }
}

extension PersistenceController {
    func save() {
        let context = container.viewContext

        if context.hasChanges {
            do {
                try context.save()
            } catch {
                let nsError = error as NSError
                fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
            }
        }
    }

    // MARK: - CloudKit Sharing

    func canEdit(object: NSManagedObject) -> Bool {
        return container.canUpdateRecord(forManagedObjectWith: object.objectID)
    }

    func canDelete(object: NSManagedObject) -> Bool {
        return container.canDeleteRecord(forManagedObjectWith: object.objectID)
    }

    // MARK: - Migration

    private static func runCashBalanceMigration(container: NSPersistentCloudKitContainer) {
        let userDefaults = UserDefaults.standard
        let migrationKey = "CashBalanceMigrationCompleted"

        // Check if migration has already been completed
        if userDefaults.bool(forKey: migrationKey) {
            print("💰 Cash balance migration already completed, skipping...")
            return
        }

        print("🔄 Starting cash balance migration...")

        do {
            try container.viewContext.performAndWait {
                try performCashBalanceMigration(in: container.viewContext)
                try container.viewContext.save()

                // Mark migration as completed
                userDefaults.set(true, forKey: migrationKey)
                print("✅ Cash balance migration completed successfully")
            }
        } catch {
            print("❌ Cash balance migration failed: \(error)")
        }
    }

    private static func performCashBalanceMigration(in context: NSManagedObjectContext) throws {
        // Get all portfolios and institutions
        let portfolioFetch: NSFetchRequest<Portfolio> = Portfolio.fetchRequest()
        let institutionFetch: NSFetchRequest<Institution> = Institution.fetchRequest()

        let portfolios = try context.fetch(portfolioFetch)
        let institutions = try context.fetch(institutionFetch)

        print("📊 Found \(portfolios.count) portfolios and \(institutions.count) institutions")

        var migrationCount = 0

        // For each portfolio, find institutions with transactions and migrate cash balances
        for portfolio in portfolios {
            let transactions = (portfolio.transactions?.allObjects as? [Transaction]) ?? []
            let portfolioInstitutions = Set(transactions.compactMap { $0.institution })

            print("📁 Portfolio '\(portfolio.name ?? "Unknown")' has transactions with \(portfolioInstitutions.count) institutions")

            for institution in portfolioInstitutions {
                // Check if this portfolio-institution pair already has a PortfolioInstitutionCash record
                let existingCashFetch: NSFetchRequest<NSManagedObject> = NSFetchRequest(entityName: "PortfolioInstitutionCash")
                existingCashFetch.predicate = NSPredicate(format: "portfolio == %@ AND institution == %@", portfolio, institution)
                existingCashFetch.fetchLimit = 1

                if let _ = try? context.fetch(existingCashFetch).first {
                    print("⏭️  PortfolioInstitutionCash already exists for \(portfolio.name ?? "Unknown") - \(institution.name ?? "Unknown")")
                    continue
                }

                // Create new PortfolioInstitutionCash record
                let cashRecord = NSEntityDescription.insertNewObject(forEntityName: "PortfolioInstitutionCash", into: context)
                cashRecord.setValue(UUID(), forKey: "id")
                cashRecord.setValue(portfolio, forKey: "portfolio")
                cashRecord.setValue(institution, forKey: "institution")

                // Migrate the cash balance from institution to portfolio-institution pair
                let institutionCashBalance = (institution.value(forKey: "cashBalance") as? Double) ?? 0.0
                cashRecord.setValue(institutionCashBalance, forKey: "cashBalance")
                cashRecord.setValue(Date(), forKey: "createdAt")
                cashRecord.setValue(Date(), forKey: "updatedAt")

                migrationCount += 1
                print("💰 Migrated \(institutionCashBalance) cash for \(portfolio.name ?? "Unknown") - \(institution.name ?? "Unknown")")
            }
        }

        print("🎯 Migration completed: Created \(migrationCount) PortfolioInstitutionCash records")
    }
}