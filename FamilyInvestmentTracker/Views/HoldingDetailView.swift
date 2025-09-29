import SwiftUI
import CoreData
import Foundation

struct HoldingDetailView: View {
    @ObservedObject var holding: Holding
    @ObservedObject var asset: Asset
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @State private var editingPrice: Double = 0
    @State private var editingCashValue: Double = 0
    @State private var showingPriceEditor = false
    @State private var showingCashValueEditor = false
    @State private var error: String?

    private let currencyService = CurrencyService.shared
    private let marketDataService = MarketDataService.shared

    private var isInsurance: Bool {
        asset.assetType == "Insurance"
    }

    private var isStructuredProduct: Bool {
        asset.assetType == AssetType.structuredProduct.rawValue
    }

    private var hasAutoFetchEnabled: Bool {
        let transactions = asset.transactions?.allObjects as? [Transaction] ?? []
        return transactions.contains { $0.autoFetchPrice }
    }

    private var structuredProductTransactions: [Transaction] {
        let transactions = asset.transactions?.allObjects as? [Transaction] ?? []
        return transactions
            .filter { $0.portfolio?.objectID == holding.portfolio?.objectID }
            .sorted { ($0.transactionDate ?? Date.distantPast) > ($1.transactionDate ?? Date.distantPast) }
    }

    private var structuredProductInterestRate: Double {
        asset.value(forKey: "interestRate") as? Double ?? 0
    }

    private var structuredProductLinkedAssets: String {
        (asset.value(forKey: "linkedAssets") as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var structuredProductMaturityDate: Date? {
        structuredProductTransactions.first?.maturityDate
    }

    private var structuredProductInvestmentAmount: Double {
        if let amount = structuredProductTransactions.first?.amount, amount > 0 {
            return amount
        }
        if costBasis > 0 {
            return costBasis
        }
        return currentValue
    }

    private var currentValue: Double {
        if isInsurance {
            return holding.value(forKey: "cashValue") as? Double ?? 0
        }
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

    private var portfolioMainCurrency: Currency {
        guard let portfolio = holding.portfolio,
              let currencyCode = portfolio.mainCurrency else {
            return .usd
        }
        return Currency(rawValue: currencyCode) ?? .usd
    }

    private var displayCurrency: Currency {
        // For insurance assets, always use the original transaction currency
        if isInsurance {
            return insuranceCashValueCurrency
        }

        // Get all buy transactions for this asset
        let transactions = asset.transactions?.allObjects as? [Transaction] ?? []
        let buyTransactions = transactions.filter { $0.type == TransactionType.buy.rawValue }

        if buyTransactions.isEmpty {
            return portfolioMainCurrency
        }

        // Get unique currencies from buy transactions
        let currencies = Set(buyTransactions.compactMap { transaction in
            Currency(rawValue: transaction.currency ?? "")
        })

        // If all transactions use the same currency, use that
        if currencies.count == 1, let currency = currencies.first {
            return currency
        }

        // If multiple currencies, use portfolio main currency
        return portfolioMainCurrency
    }

    private var insuranceCashValueCurrency: Currency {
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

    private var displayPrice: Double {
        // Convert current price from portfolio currency to display currency
        return currencyService.convertAmount(asset.currentPrice, from: portfolioMainCurrency, to: displayCurrency)
    }

    private var displayCurrentValue: Double {
        if isInsurance {
            return holding.value(forKey: "cashValue") as? Double ?? 0
        }
        return holding.quantity * displayPrice
    }

    private func refreshAssetPrice() async {
        // Only refresh if this asset has auto-fetch enabled
        let transactions = asset.transactions?.allObjects as? [Transaction] ?? []
        let hasAutoFetch = transactions.contains { $0.autoFetchPrice }

        guard hasAutoFetch else {
            return
        }
        await marketDataService.updateMarketPrices(for: [asset], in: viewContext)
    }

    var body: some View {
        NavigationView {
            Form {
                // Asset Information Section
                Section(header: Text("Asset Information")) {
                    HStack {
                        Text("Symbol")
                        Spacer()
                        Text(asset.symbol ?? "N/A")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Name")
                        Spacer()
                        Text(asset.name ?? "Unknown Asset")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Type")
                        Spacer()
                        Text(asset.assetType?.capitalized ?? "Unknown")
                            .foregroundColor(.secondary)
                    }
                }

                // Holdings Information Section
                Section(header: Text("Holdings Information")) {
                    if isInsurance {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Cash Value")
                                Text("(\(displayCurrency.displayName))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Text(Formatters.currency(holding.value(forKey: "cashValue") as? Double ?? 0, symbol: displayCurrency.displayName))
                                .fontWeight(.medium)
                            Button(action: {
                                editingCashValue = holding.value(forKey: "cashValue") as? Double ?? 0
                                showingCashValueEditor = true
                            }) {
                                Image(systemName: "pencil")
                                    .foregroundColor(.blue)
                            }
                        }
                    } else if isStructuredProduct {
                        HStack {
                            Text("Investment Amount")
                            Spacer()
                            Text(Formatters.currency(structuredProductInvestmentAmount, symbol: portfolioMainCurrency.displayName))
                                .fontWeight(.medium)
                        }

                        HStack {
                            Text("Institution")
                            Spacer()
                            Text(((holding.value(forKey: "institution") as? Institution)?.name ?? "Unassigned"))
                                .foregroundColor(.secondary)
                        }

                        HStack {
                            Text("Interest Rate")
                            Spacer()
                            Text(Formatters.percent(structuredProductInterestRate, fractionDigits: 2))
                                .foregroundColor(.secondary)
                        }

                        if let maturityDate = structuredProductMaturityDate {
                            HStack {
                                Text("Maturity Date")
                                Spacer()
                                Text(maturityDate, style: .date)
                                    .foregroundColor(.secondary)
                            }
                        }

                        if !structuredProductLinkedAssets.isEmpty {
                            HStack {
                                Text("Linked Assets")
                                Spacer()
                                Text(structuredProductLinkedAssets)
                                    .foregroundColor(.secondary)
                            }
                        }

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Current Price")
                                Text("(\(displayCurrency.displayName))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            HStack {
                                Text(Formatters.currency(displayPrice, symbol: displayCurrency.displayName))
                                    .fontWeight(.medium)

                                if hasAutoFetchEnabled {
                                    let marketOffline = MarketDataService.shared.isOfflineMode
                                    let currencyOffline = CurrencyService.shared.isOfflineMode
                                    let isOffline = marketOffline || currencyOffline
                                    Image(systemName: "globe")
                                        .foregroundColor(isOffline ? .red : .blue)
                                        .font(.caption)
                                        .onAppear {
                                            // Trigger actual price updates for this asset
                                            Task {
                                                await refreshAssetPrice()
                                            }
                                        }
                                } else {
                                    Button(action: {
                                        editingPrice = displayPrice
                                        showingPriceEditor = true
                                    }) {
                                        Image(systemName: "pencil")
                                            .foregroundColor(.blue)
                                    }
                                }
                            }
                        }

                        if hasAutoFetchEnabled {
                            HStack {
                                Text("Price Source")
                                Spacer()
                                let marketOffline = MarketDataService.shared.isOfflineMode
                                let currencyOffline = CurrencyService.shared.isOfflineMode
                                let isOffline = marketOffline || currencyOffline
                                Text(isOffline ?
                                     "Network returned incomplete data. Using cached data from \(isOffline ? (MarketDataService.shared.getPricesAge() ?? CurrencyService.shared.getRateAge() ?? "earlier") : "now")" :
                                     "Auto-fetched from Yahoo Finance")
                                    .font(.caption)
                                    .foregroundColor(isOffline ? .red : .blue)
                            }
                        }

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Total Value")
                                Text("(\(displayCurrency.displayName))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Text(Formatters.currency(displayCurrentValue, symbol: displayCurrency.displayName))
                                .foregroundColor(.secondary)
                        }
                    } else {
                        HStack {
                            Text("Quantity")
                            Spacer()
                            Text(Formatters.decimal(holding.quantity, fractionDigits: 5))
                                .foregroundColor(.secondary)
                        }

                        HStack {
                            Text("Institution")
                            Spacer()
                            Text(((holding.value(forKey: "institution") as? Institution)?.name ?? "Unassigned"))
                                .foregroundColor(.secondary)
                        }

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Current Price")
                                Text("(\(displayCurrency.displayName))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            HStack {
                                Text(Formatters.currency(displayPrice, symbol: displayCurrency.displayName))
                                    .fontWeight(.medium)

                                if hasAutoFetchEnabled {
                                    let marketOffline = MarketDataService.shared.isOfflineMode
                                    let currencyOffline = CurrencyService.shared.isOfflineMode
                                    let isOffline = marketOffline || currencyOffline
                                    Image(systemName: "globe")
                                        .foregroundColor(isOffline ? .red : .blue)
                                        .font(.caption)
                                        .onAppear {
                                            // Trigger actual price updates for this asset
                                            Task {
                                                await refreshAssetPrice()
                                            }
                                        }
                                } else {
                                    Button(action: {
                                        editingPrice = displayPrice
                                        showingPriceEditor = true
                                    }) {
                                        Image(systemName: "pencil")
                                            .foregroundColor(.blue)
                                    }
                                }
                            }
                        }

                        if hasAutoFetchEnabled {
                            HStack {
                                Text("Price Source")
                                Spacer()
                                let marketOffline = MarketDataService.shared.isOfflineMode
                                let currencyOffline = CurrencyService.shared.isOfflineMode
                                let isOffline = marketOffline || currencyOffline
                                Text(isOffline ?
                                     "Network returned incomplete data. Using cached data from \(isOffline ? (MarketDataService.shared.getPricesAge() ?? CurrencyService.shared.getRateAge() ?? "earlier") : "now")" :
                                     "Auto-fetched from Yahoo Finance")
                                    .font(.caption)
                                    .foregroundColor(isOffline ? .red : .blue)
                            }
                        }

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Average Cost Basis")
                                Text("(\(portfolioMainCurrency.displayName))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Text(Formatters.currency(holding.averageCostBasis, symbol: portfolioMainCurrency.displayName))
                                .foregroundColor(.secondary)
                        }

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Total Value")
                                Text("(\(displayCurrency.displayName))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Text(Formatters.currency(displayCurrentValue, symbol: displayCurrency.displayName))
                                .fontWeight(.semibold)
                        }
                    }
                }

                // Performance Section (for non-insurance assets)
                if !isInsurance {
                    Section(header: Text("Performance")) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Cost Basis")
                                Text("(\(portfolioMainCurrency.displayName))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Text(Formatters.currency(costBasis, symbol: portfolioMainCurrency.displayName))
                                .foregroundColor(.secondary)
                        }

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Unrealized Gain/Loss")
                                Text("(\(portfolioMainCurrency.displayName))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(Formatters.signedCurrency(unrealizedGainLoss, symbol: portfolioMainCurrency.symbol))
                                    .fontWeight(.medium)
                                    .foregroundColor(unrealizedGainLoss >= 0 ? .green : .red)

                                Text("(" + Formatters.signedPercent(gainLossPercentage) + ")")
                                    .font(.caption)
                                    .foregroundColor(unrealizedGainLoss >= 0 ? .green : .red)
                            }
                        }

                        let cumulativeIncome = holding.totalDividends
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Cumulative Income (Dividends/Interest)")
                                Text("(\(portfolioMainCurrency.displayName))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Text(Formatters.currency(cumulativeIncome, symbol: portfolioMainCurrency.displayName))
                                .fontWeight(.medium)
                                .foregroundColor(.blue)
                        }

                        let incomeAdjustedGain = unrealizedGainLoss + cumulativeIncome
                        let incomeAdjustedPercent = costBasis > 0 ? (incomeAdjustedGain / costBasis) * 100 : 0
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Total Return (with Income)")
                                Text("(\(portfolioMainCurrency.displayName))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(Formatters.signedCurrency(incomeAdjustedGain, symbol: portfolioMainCurrency.symbol))
                                    .fontWeight(.medium)
                                    .foregroundColor(incomeAdjustedGain >= 0 ? .green : .red)

                                Text("(" + Formatters.signedPercent(incomeAdjustedPercent) + ")")
                                    .font(.caption)
                                    .foregroundColor(incomeAdjustedGain >= 0 ? .green : .red)
                            }
                        }

                        if holding.realizedGainLoss != 0 {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Realized Gain/Loss")
                                    Text("(\(portfolioMainCurrency.displayName))")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Text(Formatters.signedCurrency(holding.realizedGainLoss, symbol: portfolioMainCurrency.symbol))
                                    .fontWeight(.medium)
                                    .foregroundColor(holding.realizedGainLoss >= 0 ? .green : .red)
                            }
                        }
                    }
                }

                // Price Update Information
                if let lastUpdate = asset.lastPriceUpdate {
                    Section(header: Text("Price Information")) {
                        HStack {
                            Text("Last Updated")
                            Spacer()
                            Text(lastUpdate, style: .relative)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                if let error = error {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle(asset.symbol ?? "Asset Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $showingPriceEditor) {
            PriceEditorView(asset: asset, editingPrice: $editingPrice, displayCurrency: displayCurrency, portfolioMainCurrency: portfolioMainCurrency)
                .interactiveDismissDisabled()
        }
        .sheet(isPresented: $showingCashValueEditor) {
            CashValueEditorView(holding: holding, editingCashValue: $editingCashValue)
        }
    }
}

struct PriceEditorView: View {
    @ObservedObject var asset: Asset
    @Binding var editingPrice: Double
    let displayCurrency: Currency
    let portfolioMainCurrency: Currency
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?

    private let currencyService = CurrencyService.shared

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Update Current Price")) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Current Price")
                            Text("(\(displayCurrency.displayName))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        TextField("0.00", value: $editingPrice, format: .number)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(width: 120)
                        Text(displayCurrency.symbol)
                            .foregroundColor(.secondary)
                    }
                }

                Section(header: Text("Asset Information")) {
                    HStack {
                        Text("Symbol")
                        Spacer()
                        Text(asset.symbol ?? "N/A")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Name")
                        Spacer()
                        Text(asset.name ?? "Unknown Asset")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Previous Price")
                            Text("(\(displayCurrency.displayName))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Text(Formatters.currency(currencyService.convertAmount(asset.currentPrice, from: portfolioMainCurrency, to: displayCurrency), symbol: displayCurrency.displayName))
                            .foregroundColor(.secondary)
                    }
                }

                Section(footer: Text("Note: This will manually set the price. To enable automatic price fetching, turn on 'Auto-fetch price' when creating or editing transactions for this asset.")) {
                    EmptyView()
                }

                if let error = error {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Update Price")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        savePrice()
                    }
                    .disabled(editingPrice <= 0)
                }
            }
        }
    }

    private func savePrice() {
        guard editingPrice > 0 else {
            error = "Price must be greater than zero"
            return
        }

        // Convert price from display currency to portfolio main currency for storage
        let priceInPortfolioCurrency = currencyService.convertAmount(editingPrice, from: displayCurrency, to: portfolioMainCurrency)

        asset.currentPrice = priceInPortfolioCurrency
        asset.lastPriceUpdate = Date()

        do {
            try viewContext.save()
            print("💰 Updated price for \(asset.symbol ?? "Unknown"): \(editingPrice) \(displayCurrency.code) -> \(priceInPortfolioCurrency) \(portfolioMainCurrency.code)")

            if let holdings = asset.holdings?.allObjects as? [Holding] {
                let impactedPortfolios = Set(holdings.compactMap { $0.portfolio })
                for portfolio in impactedPortfolios {
                    let relatedHoldings = (portfolio.holdings?.allObjects as? [Holding]) ?? []
                    let totalHoldingsValue = relatedHoldings.reduce(0.0) { total, holding in
                        guard let holdingAsset = holding.asset else { return total }
                        if holdingAsset.assetType == AssetType.insurance.rawValue {
                            let cashValue = holding.value(forKey: "cashValue") as? Double ?? 0
                            return total + cashValue
                        }
                        return total + (holding.quantity * holdingAsset.currentPrice)
                    }

                    let totalValue = totalHoldingsValue + portfolio.resolvedCashBalance()
                    portfolio.totalValue = totalValue
                    portfolio.updatedAt = Date()
                    portfolio.objectWillChange.send()
                }
            }

            dismiss()
        } catch {
            self.error = "Failed to save price: \(error.localizedDescription)"
        }
    }

}

#Preview {
    let context = PersistenceController.preview.container.viewContext
    if let holding = context.registeredObjects.first(where: { $0 is Holding }) as? Holding,
       let asset = holding.asset {
        return HoldingDetailView(holding: holding, asset: asset)
            .environment(\.managedObjectContext, context)
    } else {
        return Text("No preview data available")
    }
}
