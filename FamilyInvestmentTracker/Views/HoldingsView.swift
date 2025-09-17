import SwiftUI
import CoreData
import Foundation

struct HoldingsView: View {
    @ObservedObject var portfolio: Portfolio
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest private var holdingsFetch: FetchedResults<Holding>

    init(portfolio: Portfolio) {
        self.portfolio = portfolio
        _holdingsFetch = FetchRequest<Holding>(
            sortDescriptors: [NSSortDescriptor(key: "asset.name", ascending: true)],
            predicate: NSPredicate(format: "portfolio == %@", portfolio),
            animation: .default
        )
    }

    var body: some View {
        VStack {
            let filteredHoldings = holdingsFetch.filter { $0.quantity > 0 || ($0.asset?.assetType == AssetType.insurance.rawValue) }

            if filteredHoldings.isEmpty {
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
                    ForEach(filteredHoldings, id: \.objectID) { holding in
                        if let asset = holding.asset {
                            HoldingRowView(holding: holding, asset: asset)
                        }
                    }
                }
                .listStyle(PlainListStyle())
            }
        }
    }
}

struct HoldingRowView: View {
    @ObservedObject var holding: Holding
    @ObservedObject var asset: Asset
    @Environment(\.managedObjectContext) private var viewContext
    @State private var showingCashValueEditor = false
    @State private var editingCashValue: Double = 0

    private var currentValue: Double {
        // For insurance, use cash value; for others, use market value
        if asset.assetType == "Insurance" {
            return holding.value(forKey: "cashValue") as? Double ?? 0
        }
        return holding.quantity * asset.currentPrice
    }

    private var isInsurance: Bool {
        asset.assetType == "Insurance"
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
                    Text(asset.symbol ?? "N/A")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Text(asset.name ?? "Unknown Asset")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    HStack {
                        Text(Formatters.currency(currentValue))
                            .font(.headline)
                            .fontWeight(.semibold)

                        if isInsurance {
                            Button(action: {
                                editingCashValue = holding.value(forKey: "cashValue") as? Double ?? 0
                                showingCashValueEditor = true
                            }) {
                                Image(systemName: "pencil.circle")
                                    .foregroundColor(.blue)
                                    .font(.caption)
                            }
                        }
                    }

                    if isInsurance {
                        Text("Cash Value")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
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
            }
            
            HStack {
                if isInsurance {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Policy Type")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Insurance Policy")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }

                    Spacer()

                    VStack(alignment: .center, spacing: 2) {
                        Text("Policyholder")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Policy Owner")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Death Benefit")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Insurance")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                } else {
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
                        Text(Formatters.currency(asset.currentPrice))
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
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
        .sheet(isPresented: $showingCashValueEditor) {
            CashValueEditorView(holding: holding, editingCashValue: $editingCashValue)
        }
    }
}

struct CashValueEditorView: View {
    let holding: Holding
    @Binding var editingCashValue: Double
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Update Cash Value")) {
                    HStack {
                        Text("Current Cash Value")
                        Spacer()
                        TextField("0.00", value: $editingCashValue, format: .number)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(width: 120)
                        Text("$")
                            .foregroundColor(.secondary)
                    }
                }

                Section(header: Text("Policy Information")) {
                    HStack {
                        Text("Policy Type")
                        Spacer()
                        Text("Insurance Policy")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Policyholder")
                        Spacer()
                        Text("Policy Owner")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Previous Cash Value")
                        Spacer()
                        Text(Formatters.currency(holding.value(forKey: "cashValue") as? Double ?? 0))
                            .foregroundColor(.secondary)
                    }
                }

                if let error = error {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Update Cash Value")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveCashValue()
                    }
                    .disabled(editingCashValue < 0)
                }
            }
        }
    }

    private func saveCashValue() {
        guard editingCashValue >= 0 else {
            error = "Cash value cannot be negative"
            return
        }

        holding.setValue(editingCashValue, forKey: "cashValue")
        holding.updatedAt = Date()

        if let portfolio = holding.portfolio {
            let holdings = (portfolio.holdings?.allObjects as? [Holding]) ?? []
            let holdingsValue = holdings.reduce(0.0) { sum, holding in
                guard let asset = holding.asset else { return sum }
                if asset.assetType == AssetType.insurance.rawValue {
                    let cashValue = holding.value(forKey: "cashValue") as? Double ?? 0
                    return sum + cashValue
                }
                return sum + (holding.quantity * asset.currentPrice)
            }
            portfolio.totalValue = holdingsValue + portfolio.cashBalanceSafe
            portfolio.updatedAt = Date()
        }

        do {
            try viewContext.save()
            print("💰 Updated cash value for \(holding.asset?.name ?? "Unknown"): \(editingCashValue)")
            dismiss()
        } catch {
            self.error = "Failed to save cash value: \(error.localizedDescription)"
        }
    }
}

#Preview {
    HoldingsView(portfolio: PersistenceController.preview.container.viewContext.registeredObjects.first(where: { $0 is Portfolio }) as! Portfolio)
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
