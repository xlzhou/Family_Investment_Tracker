import SwiftUI
import CoreData
import Foundation

struct HoldingsView: View {
    @ObservedObject var portfolio: Portfolio
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest private var holdingsFetch: FetchedResults<Holding>
    @State private var selectedAssetTypes: Set<AssetType> = []
    @State private var selectedInstitutionID: NSManagedObjectID? = nil

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
            if !allHoldings.isEmpty {
                filterBar
                    .padding(.horizontal)

                // Show summary when filters are applied
                if !selectedAssetTypes.isEmpty || selectedInstitutionID != nil {
                    filterSummary
                        .padding(.horizontal)
                        .padding(.top, 8)
                }
            }

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

private extension HoldingsView {
    var allHoldings: [Holding] {
        holdingsFetch.filter { $0.quantity > 0 || ($0.asset?.assetType == AssetType.insurance.rawValue) }
    }

    var filteredHoldings: [Holding] {
        allHoldings.filter { holding in
            guard let asset = holding.asset else { return false }

            let matchesType: Bool
            if selectedAssetTypes.isEmpty {
                matchesType = true
            } else {
                matchesType = selectedAssetTypes.contains { $0.rawValue == asset.assetType }
            }

            let matchesInstitution: Bool
            if let institutionID = selectedInstitutionID,
               let institution = try? viewContext.existingObject(with: institutionID) as? Institution {
                // Check if any transactions for this holding came from the selected institution
                let transactions = (asset.transactions?.allObjects as? [Transaction]) ?? []
                let portfolioTransactions = transactions.filter { $0.portfolio?.objectID == portfolio.objectID }
                matchesInstitution = portfolioTransactions.contains { $0.institution?.objectID == institution.objectID }
            } else {
                matchesInstitution = true
            }

            return matchesType && matchesInstitution
        }
    }

    var availableAssetTypes: [AssetType] {
        let types = allHoldings.compactMap { holding -> AssetType? in
            guard let typeRaw = holding.asset?.assetType else { return nil }
            return AssetType(rawValue: typeRaw)
        }
        return Array(Set(types)).sorted { $0.displayName < $1.displayName }
    }

    var availableInstitutions: [Institution] {
        var seen = Set<NSManagedObjectID>()
        var results: [Institution] = []

        for holding in allHoldings {
            guard let asset = holding.asset else { continue }
            // Get institutions from actual transactions that created this holding
            let transactions = (asset.transactions?.allObjects as? [Transaction]) ?? []
            let portfolioTransactions = transactions.filter { $0.portfolio?.objectID == portfolio.objectID }

            for transaction in portfolioTransactions {
                if let institution = transaction.institution, seen.insert(institution.objectID).inserted {
                    results.append(institution)
                }
            }
        }

        return results.sorted { ($0.name ?? "") < ($1.name ?? "") }
    }

    var filterBar: some View {
        HStack(spacing: 12) {
            Menu {
                Button(action: {
                    selectedAssetTypes.removeAll()
                }) {
                    HStack {
                        Text("All Asset Types")
                        Spacer()
                        if selectedAssetTypes.isEmpty {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                        }
                    }
                }

                Divider()

                ForEach(availableAssetTypes, id: \.self) { type in
                    Button(action: {
                        if selectedAssetTypes.contains(type) {
                            selectedAssetTypes.remove(type)
                        } else {
                            selectedAssetTypes.insert(type)
                        }
                    }) {
                        HStack {
                            Text(type.displayName)
                            Spacer()
                            if selectedAssetTypes.contains(type) {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
            } label: {
                HStack {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                    Text(assetTypeFilterLabel)
                }
                .font(.caption)
                .padding(8)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(8)
            }

            Menu {
                Button("All Institutions") { selectedInstitutionID = nil }
                ForEach(availableInstitutions, id: \.objectID) { institution in
                    Button(institution.name ?? "Unknown") { selectedInstitutionID = institution.objectID }
                }
            } label: {
                HStack {
                    Image(systemName: "building.columns")
                    Text(selectedInstitutionLabel)
                }
                .font(.caption)
                .padding(8)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(8)
            }

            if !selectedAssetTypes.isEmpty || selectedInstitutionID != nil {
                Button("Clear") {
                    selectedAssetTypes.removeAll()
                    selectedInstitutionID = nil
                }
                .font(.caption)
            }

            Spacer()
        }
    }

    var selectedInstitutionLabel: String {
        guard let institutionID = selectedInstitutionID,
              let institution = try? viewContext.existingObject(with: institutionID) as? Institution else {
            return "All Institutions"
        }
        return institution.name ?? "All Institutions"
    }

    var assetTypeFilterLabel: String {
        if selectedAssetTypes.isEmpty {
            return "All Types"
        } else if selectedAssetTypes.count == 1 {
            return selectedAssetTypes.first?.displayName ?? "All Types"
        } else {
            return "\(selectedAssetTypes.count) Types"
        }
    }

    private var portfolioCurrency: Currency {
        guard let currencyCode = portfolio.mainCurrency else { return .usd }
        return Currency(rawValue: currencyCode) ?? .usd
    }

    private var filteredSummary: (totalValue: Double, totalUnrealizedPnL: Double, totalDividends: Double) {
        var totalValue: Double = 0
        var totalUnrealizedPnL: Double = 0
        var totalDividends: Double = 0

        for holding in filteredHoldings {
            guard let asset = holding.asset else { continue }

            // Calculate current value (for total value display)
            let currentValue: Double
            if asset.assetType == AssetType.insurance.rawValue {
                currentValue = holding.value(forKey: "cashValue") as? Double ?? 0
            } else {
                currentValue = holding.quantity * asset.currentPrice
            }

            // Calculate unrealized P&L (including insurance with proper calculation)
            let unrealizedPnL: Double
            if asset.assetType == AssetType.insurance.rawValue {
                // For insurance: P&L = Cash Value - Actual Paid Premium
                let cashValue = holding.value(forKey: "cashValue") as? Double ?? 0

                let paidPremium = InsurancePaymentService.totalPaidAmount(for: asset, in: portfolio, context: viewContext)
                unrealizedPnL = cashValue - paidPremium
            } else {
                // For securities: P&L = Current Value - Cost Basis
                let costBasis = holding.quantity * holding.averageCostBasis
                let securityValue = holding.quantity * asset.currentPrice
                unrealizedPnL = securityValue - costBasis
            }

            totalUnrealizedPnL += unrealizedPnL
            totalValue += currentValue
            totalDividends += holding.totalDividends
        }

        return (totalValue, totalUnrealizedPnL, totalDividends)
    }

    var filterSummary: some View {
        let summary = filteredSummary

        return VStack(spacing: 8) {
            HStack {
                Text("Filtered Results Summary")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
                Text("\(filteredHoldings.count) holdings")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                VStack(alignment: .center, spacing: 4) {
                    Text("Total Value")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(Formatters.currency(summary.totalValue, symbol: portfolioCurrency.displayName))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                }

                VStack(alignment: .center, spacing: 4) {
                    Text("Unrealized P&L")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(Formatters.signedCurrency(summary.totalUnrealizedPnL, symbol: portfolioCurrency.symbol))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(summary.totalUnrealizedPnL >= 0 ? .green : .red)
                }

                VStack(alignment: .center, spacing: 4) {
                    Text("Total Dividends")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(Formatters.currency(summary.totalDividends, symbol: portfolioCurrency.displayName))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                }
            }
        }
        .padding(12)
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(12)
    }
}

struct HoldingRowView: View {
    @ObservedObject var holding: Holding
    @ObservedObject var asset: Asset
    @Environment(\.managedObjectContext) private var viewContext
    @State private var showingHoldingDetail = false
    @State private var showingCashValueEditor = false
    @State private var editingCashValue: Double = 0

    private var portfolioCurrency: Currency {
        guard let portfolio = holding.portfolio,
              let code = portfolio.mainCurrency,
              let resolved = Currency(rawValue: code) else {
            return .usd
        }
        return resolved
    }

    private var currencySymbol: String { portfolioCurrency.symbol }

    private var currentValue: Double {
        // For insurance, use cash value; for others, use market value
        if asset.assetType == "Insurance" {
            return holding.value(forKey: "cashValue") as? Double ?? 0
        }
        return holding.quantity * asset.currentPrice
    }

    private var insuranceObject: NSManagedObject? {
        asset.value(forKey: "insurance") as? NSManagedObject
    }

    private var basicInsuredAmountValue: Double {
        insuranceObject?.value(forKey: "basicInsuredAmount") as? Double ?? 0
    }

    private var policyHolderName: String {
        insuranceObject?.value(forKey: "policyholder") as? String ?? "-"
    }

    private var totalPaidPremiumValue: Double {
        guard let portfolio = holding.portfolio else { return 0 }
        return InsurancePaymentService.totalPaidAmount(for: asset, in: portfolio, context: viewContext)
    }

    private var isInsurance: Bool {
        asset.assetType == "Insurance"
    }
    
    private var isStructuredProduct: Bool {
        asset.assetType == AssetType.structuredProduct.rawValue
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
    
    private var hasAutoFetchEnabled: Bool {
        asset.resolvedAutoFetchPreference
    }

    private var structuredProductTransactions: [Transaction] {
        let transactions = asset.transactions?.allObjects as? [Transaction] ?? []
        return transactions
            .filter { $0.portfolio?.objectID == holding.portfolio?.objectID }
            .sorted { ($0.transactionDate ?? Date.distantPast) > ($1.transactionDate ?? Date.distantPast) }
    }

    private var structuredProductInterestRateValue: Double {
        asset.value(forKey: "interestRate") as? Double ?? 0
    }

    private var structuredProductLinkedAssetsText: String {
        (asset.value(forKey: "linkedAssets") as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var structuredProductMaturityDate: Date? {
        structuredProductTransactions.first?.maturityDate
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(asset.name ?? "Unknown Asset")
                        .font(.headline)
                        .fontWeight(.semibold)

                    Text(asset.symbol ?? "N/A")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    HStack {
                        Text(Formatters.currency(currentValue, symbol: portfolioCurrency.displayName))
                            .font(.headline)
                            .fontWeight(.semibold)

                        if isInsurance {
                            Button(action: {
                                editingCashValue = holding.value(forKey: "cashValue") as? Double ?? 0
                                showingCashValueEditor = true
                            }) {
                                Image(systemName: "pencil")
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
                            Text("Unrealized P/L")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(Formatters.signedCurrency(unrealizedGainLoss, symbol: currencySymbol))
                                .font(.subheadline)
                                .foregroundColor(unrealizedGainLoss >= 0 ? .green : .red)

                            Text("(" + Formatters.signedPercent(gainLossPercentage, fractionDigits: 2) + ")")
                                .font(.caption)
                                .foregroundColor(unrealizedGainLoss >= 0 ? .green : .red)
                        }
                    }
                }
            }
            
            HStack {
                if isInsurance {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Basic Insured Amount")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text(Formatters.currency(basicInsuredAmountValue, symbol: portfolioCurrency.displayName))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .center, spacing: 2) {
                        Text("Policy Holder")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text(policyHolderName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Paid Premium")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text(Formatters.currency(totalPaidPremiumValue, symbol: portfolioCurrency.displayName))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else if isStructuredProduct {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 2) {
                            Text("Quantity")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(Formatters.decimal(holding.quantity, fractionDigits: 5))
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        if isStructuredProduct, !structuredProductLinkedAssetsText.isEmpty {
                            Text("Linked Assets: \(structuredProductLinkedAssetsText)")
                                .font(.caption)
                                .foregroundColor(.secondary)
            }
                    }

                    Spacer()

                    VStack(alignment: .center, spacing: 2) {
                        Text("Interest Rate")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(Formatters.percent(structuredProductInterestRateValue, fractionDigits: 2))
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        HStack(spacing: 4) {
                            Text("Current Price")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(Formatters.currency(asset.currentPrice, symbol: portfolioCurrency.displayName, fractionDigits: 3))
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Image(systemName: "pencil")
                                .foregroundColor(.blue)
                                .font(.caption2)
                        }
                        if holding.totalDividends >= 0 {
                            HStack {
                                Text("Total Dividends/Interest:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                Text(Formatters.currency(holding.totalDividends, symbol: portfolioCurrency.displayName))
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Quantity")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(Formatters.decimal(holding.quantity, fractionDigits: 5))
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }

                    Spacer()

                    VStack(alignment: .center, spacing: 2) {
                        Text("Avg Cost")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(Formatters.currency(holding.averageCostBasis, symbol: portfolioCurrency.displayName, fractionDigits: 3))
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        
                        HStack {
                            Text("Current Price")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(Formatters.currency(asset.currentPrice, symbol: portfolioCurrency.displayName, fractionDigits: 3))
                                .font(.subheadline)
                                .fontWeight(.medium)

                            if hasAutoFetchEnabled {
                                let marketOffline = MarketDataService.shared.isOfflineMode
                                let currencyOffline = CurrencyService.shared.isOfflineMode
                                let isOffline = marketOffline || currencyOffline
                                Image(systemName: "globe")
                                    .foregroundColor(isOffline ? .red : .blue)
                                    .font(.caption2)
                                    .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NetworkStatusChanged"))) { _ in
                                        print("🔍 HoldingsView: Received network status change notification")
                                        // Force SwiftUI to re-evaluate the color
                                    }
                            } else {
                                Image(systemName: "pencil")
                                    .foregroundColor(.blue)
                                    .font(.caption2)
                            }
                        }
                        if holding.totalDividends >= 0 {
                            HStack(){    
                                Text("Total Dividends/Interest:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    
                                Text(Formatters.currency(holding.totalDividends, symbol: portfolioCurrency.displayName))
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
            }

            /*if isStructuredProduct, !structuredProductLinkedAssetsText.isEmpty {
                Text("Linked Assets: \(structuredProductLinkedAssetsText)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }*/
            
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            showingHoldingDetail = true
        }
        .sheet(isPresented: $showingHoldingDetail) {
            HoldingDetailView(holding: holding, asset: asset)
        }
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

    private var originalTransactionCurrency: Currency {
        guard let asset = holding.asset else {
            return portfolioMainCurrency
        }

        // Get the original transaction currency for insurance assets
        let transactions = asset.transactions?.allObjects as? [Transaction] ?? []
        let insuranceTransactions = transactions.filter {
            $0.portfolio?.objectID == holding.portfolio?.objectID &&
            $0.type == TransactionType.insurance.rawValue
        }

        // Get the first (oldest) insurance transaction's currency
        if let firstTransaction = insuranceTransactions.sorted(by: {
            ($0.transactionDate ?? Date.distantPast) < ($1.transactionDate ?? Date.distantPast)
        }).first,
           let currencyCode = firstTransaction.currency,
           let currency = Currency(rawValue: currencyCode) {
            return currency
        }

        // Fallback to portfolio main currency if no insurance transaction found
        return portfolioMainCurrency
    }

    private var portfolioMainCurrency: Currency {
        guard let portfolio = holding.portfolio,
              let code = portfolio.mainCurrency,
              let currency = Currency(rawValue: code) else {
            return Currency.usd
        }
        return currency
    }

    private var currencySymbol: String {
        return originalTransactionCurrency.symbol
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Update Cash Value")) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Current Cash Value")
                            Text("(\(originalTransactionCurrency.displayName))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        TextField("0.00", value: $editingCashValue, format: .number)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(width: 120)
                        Text(currencySymbol)
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
                        Text(Formatters.currency(holding.value(forKey: "cashValue") as? Double ?? 0, symbol: originalTransactionCurrency.displayName))
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
            portfolio.totalValue = holdingsValue + portfolio.resolvedCashBalance()
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
