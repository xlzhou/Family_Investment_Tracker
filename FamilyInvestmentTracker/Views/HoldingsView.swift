import SwiftUI
import CoreData
import Foundation

struct HoldingsView: View {
    @ObservedObject var portfolio: Portfolio
    @Environment(\.managedObjectContext) private var viewContext
    
    private var holdings: [Holding] {
        let allHoldings = (portfolio.holdings?.allObjects as? [Holding]) ?? []
        let filteredHoldings = allHoldings.filter { $0.quantity > 0 }
        print("📈 Holdings Debug: Total=\(allHoldings.count), Filtered=\(filteredHoldings.count)")
        for holding in allHoldings {
            print("   - \(holding.asset?.symbol ?? "Unknown"): qty=\(holding.quantity), cost=\(holding.averageCostBasis)")
        }
        return filteredHoldings
    }
    
    var body: some View {
        VStack {
            if holdings.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "chart.pie")
                        .font(.system(size: 50))
                        .foregroundColor(.secondary)
                    
                    Text("No Holdings")
                        .font(.title3)
                        .fontWeight(.medium)
                    
                    Text("Start by adding your first transaction")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                List {
                    ForEach(holdings, id: \.objectID) { holding in
                        HoldingRowView(holding: holding)
                    }
                }
                .listStyle(PlainListStyle())
            }
        }
    }
}

struct HoldingRowView: View {
    let holding: Holding
    
    private var currentValue: Double {
        guard let asset = holding.asset else { return 0 }
        return holding.quantity * asset.currentPrice
    }
    
    private var costBasis: Double {
        return holding.quantity * holding.averageCostBasis
    }
    
    private var unrealizedGainLoss: Double {
        return currentValue - costBasis
    }
    
    private var gainLossPercentage: Double {
        guard costBasis > 0 else { return 0 }
        return (unrealizedGainLoss / costBasis) * 100
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(holding.asset?.symbol ?? "N/A")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Text(holding.asset?.name ?? "Unknown Asset")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text(Formatters.currency(currentValue))
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    HStack(spacing: 4) {
                        Text(Formatters.signedCurrency(unrealizedGainLoss))
                            .font(.subheadline)
                            .foregroundColor(unrealizedGainLoss >= 0 ? .green : .red)
                        
                        Text("(" + Formatters.signedPercent(gainLossPercentage) + ")")
                            .font(.caption)
                            .foregroundColor(unrealizedGainLoss >= 0 ? .green : .red)
                    }
                }
            }
            
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Shares")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(Formatters.decimal(holding.quantity))
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                
                Spacer()
                
                VStack(alignment: .center, spacing: 2) {
                    Text("Avg Cost")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(Formatters.currency(holding.averageCostBasis))
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Current Price")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(Formatters.currency(holding.asset?.currentPrice ?? 0))
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
            }
            
            if holding.totalDividends > 0 {
                HStack {
                    Text("Total Dividends:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text(Formatters.currency(holding.totalDividends))
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.blue)
                }
            }
        }
        .padding(.vertical, 8)
    }
}

#Preview {
    HoldingsView(portfolio: PersistenceController.preview.container.viewContext.registeredObjects.first(where: { $0 is Portfolio }) as! Portfolio)
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
