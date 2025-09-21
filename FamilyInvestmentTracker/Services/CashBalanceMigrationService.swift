import Foundation
import CoreData

class CashBalanceMigrationService {
    static let shared = CashBalanceMigrationService()
    private init() {}

    /// Migrates existing institution cash balances to the new PortfolioInstitutionCash system
    func migrateExistingCashBalances(context: NSManagedObjectContext) {
        let userDefaults = UserDefaults.standard
        let migrationKey = "CashBalanceMigrationCompleted"

        // Check if migration has already been completed
        if userDefaults.bool(forKey: migrationKey) {
            print("💰 Cash balance migration already completed, skipping...")
            return
        }

        print("🔄 Starting cash balance migration...")

        do {
            try context.performAndWait {
                try performMigration(in: context)
                try context.save()

                // Mark migration as completed
                userDefaults.set(true, forKey: migrationKey)
                print("✅ Cash balance migration completed successfully")
            }
        } catch {
            print("❌ Cash balance migration failed: \(error)")
        }
    }

    private func performMigration(in context: NSManagedObjectContext) throws {
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
                let existingCashFetch: NSFetchRequest<PortfolioInstitutionCash> = PortfolioInstitutionCash.fetchRequest()
                existingCashFetch.predicate = NSPredicate(format: "portfolio == %@ AND institution == %@", portfolio, institution)
                existingCashFetch.fetchLimit = 1

                if let existingCash = try? context.fetch(existingCashFetch).first {
                    print("⏭️  PortfolioInstitutionCash already exists for \(portfolio.name ?? "Unknown") - \(institution.name ?? "Unknown")")
                    continue
                }

                // Create new PortfolioInstitutionCash record
                let cashRecord = PortfolioInstitutionCash(context: context)
                cashRecord.setValue(UUID(), forKey: "id")
                cashRecord.setValue(portfolio, forKey: "portfolio")
                cashRecord.setValue(institution, forKey: "institution")

                // Migrate the cash balance from institution to portfolio-institution pair
                let institutionCashBalance = institution.cashBalanceSafe
                cashRecord.setValue(institutionCashBalance, forKey: "cashBalance")
                cashRecord.setValue(Date(), forKey: "createdAt")
                cashRecord.setValue(Date(), forKey: "updatedAt")

                migrationCount += 1
                print("💰 Migrated \(institutionCashBalance) cash for \(portfolio.name ?? "Unknown") - \(institution.name ?? "Unknown")")
            }
        }

        // Handle institutions that might have cash but no transactions (edge case)
        for institution in institutions {
            if institution.cashBalanceSafe != 0 {
                // If institution has cash but we haven't created any PortfolioInstitutionCash records for it,
                // we need to assign it to some portfolio. We'll use the first portfolio that has transactions with this institution.
                let institutionTransactions = (institution.transactions?.allObjects as? [Transaction]) ?? []
                let portfoliosWithTransactions = Set(institutionTransactions.compactMap { $0.portfolio })

                if portfoliosWithTransactions.isEmpty {
                    // Institution has cash but no transactions - this is an edge case
                    // We'll assign the cash to the first available portfolio
                    if let firstPortfolio = portfolios.first {
                        let existingCashFetch: NSFetchRequest<PortfolioInstitutionCash> = PortfolioInstitutionCash.fetchRequest()
                        existingCashFetch.predicate = NSPredicate(format: "portfolio == %@ AND institution == %@", firstPortfolio, institution)
                        existingCashFetch.fetchLimit = 1

                        if (try? context.fetch(existingCashFetch).first) == nil {
                            let cashRecord = PortfolioInstitutionCash(context: context)
                            cashRecord.setValue(UUID(), forKey: "id")
                            cashRecord.setValue(firstPortfolio, forKey: "portfolio")
                            cashRecord.setValue(institution, forKey: "institution")
                            cashRecord.setValue(institution.cashBalanceSafe, forKey: "cashBalance")
                            cashRecord.setValue(Date(), forKey: "createdAt")
                            cashRecord.setValue(Date(), forKey: "updatedAt")

                            migrationCount += 1
                            print("🔧 Assigned orphaned cash \(institution.cashBalanceSafe) from \(institution.name ?? "Unknown") to \(firstPortfolio.name ?? "Unknown")")
                        }
                    }
                }
            }
        }

        print("🎯 Migration completed: Created \(migrationCount) PortfolioInstitutionCash records")
    }

    /// Forces a re-migration (useful for testing)
    func forceMigration(context: NSManagedObjectContext) {
        let userDefaults = UserDefaults.standard
        userDefaults.set(false, forKey: "CashBalanceMigrationCompleted")
        migrateExistingCashBalances(context: context)
    }

    /// Checks if migration has been completed
    var isMigrationCompleted: Bool {
        return UserDefaults.standard.bool(forKey: "CashBalanceMigrationCompleted")
    }
}