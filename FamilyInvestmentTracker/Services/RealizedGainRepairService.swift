import CoreData
import Foundation

struct RealizedGainRepairSummary {
    struct HoldingSummary {
        let portfolioName: String
        let assetName: String
        let institutionName: String?
        let previousValue: Double
        let recalculatedValue: Double
        let delta: Double
    }

    let holdings: [HoldingSummary]

    var updatedHoldingsCount: Int {
        holdings.count
    }

    var totalDelta: Double {
        holdings.reduce(0) { $0 + $1.delta }
    }
}

final class RealizedGainRepairService {
    static let shared = RealizedGainRepairService()

    private init() {}

    func repairAllPortfolios(in context: NSManagedObjectContext) async throws -> RealizedGainRepairSummary {
        try await context.perform {
            let portfolioRequest: NSFetchRequest<Portfolio> = Portfolio.fetchRequest()
            portfolioRequest.returnsObjectsAsFaults = false
            let portfolios = try context.fetch(portfolioRequest)

            var holdingSummaries: [RealizedGainRepairSummary.HoldingSummary] = []

            for portfolio in portfolios {
                let portfolioName = portfolio.name ?? "Unnamed Portfolio"
                let holdings = (portfolio.holdings?.allObjects as? [Holding]) ?? []
                let transactions = (portfolio.transactions?.allObjects as? [Transaction]) ?? []
                let sellTransactions = transactions.filter { txn in
                    guard let type = TransactionType(rawValue: txn.type ?? "") else { return false }
                    return type == .sell
                }

                for holding in holdings {
                    guard let asset = holding.asset else { continue }
                    let previousValue = holding.realizedGainLoss

                    let holdingInstitution = holding.value(forKey: "institution") as? Institution
                    let recalculated = sellTransactions.filter { txn in
                        guard txn.asset?.objectID == asset.objectID else { return false }
                        if let holdingInstitution {
                            return txn.institution?.objectID == holdingInstitution.objectID
                        } else {
                            return txn.institution == nil
                        }
                    }.reduce(0.0) { $0 + $1.realizedGainAmount }

                    guard abs(previousValue - recalculated) > 0.0001 else { continue }

                    holding.realizedGainLoss = recalculated
                    holding.updatedAt = Date()

                    let institutionName = holdingInstitution?.name
                    let summary = RealizedGainRepairSummary.HoldingSummary(
                        portfolioName: portfolioName,
                        assetName: asset.symbol ?? asset.name ?? "Unknown Asset",
                        institutionName: institutionName,
                        previousValue: previousValue,
                        recalculatedValue: recalculated,
                        delta: recalculated - previousValue
                    )
                    holdingSummaries.append(summary)
                }
            }

            if context.hasChanges {
                try context.save()
            }

            return RealizedGainRepairSummary(holdings: holdingSummaries)
        }
    }
}
