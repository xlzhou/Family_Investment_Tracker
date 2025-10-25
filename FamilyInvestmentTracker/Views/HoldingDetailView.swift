import SwiftUI
import CoreData
import Foundation

struct HoldingDetailView: View {
    @ObservedObject var holding: Holding
    @ObservedObject var asset: Asset
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var localizationManager: LocalizationManager

    @State private var editingPrice: Double = 0
    @State private var editingCashValue: Double = 0
    @State private var showingPriceEditor = false
    @State private var showingCashValueEditor = false
    @State private var showingPaymentManagement = false
    @State private var showingAddTransaction = false
    @State private var pendingTransactionType: TransactionType = .buy
    @State private var addTransactionPresentationID = UUID()
    @State private var error: String?
    @State private var autoFetchToggle: Bool
    @State private var isUpdatingAutoFetchPreference = false

    private let currencyService = CurrencyService.shared
    private let marketDataService = MarketDataService.shared

    init(holding: Holding, asset: Asset) {
        _holding = ObservedObject(initialValue: holding)
        _asset = ObservedObject(initialValue: asset)
        asset.migrateAutoFetchPreferenceIfNeeded(limitTo: holding.portfolio)
        _autoFetchToggle = State(initialValue: asset.resolvedAutoFetchPreference)
    }

    private var isInsurance: Bool {
        asset.assetType == "Insurance"
    }

    private var isStructuredProduct: Bool {
        asset.assetType == AssetType.structuredProduct.rawValue
    }

    private var holdingInstitution: Institution? {
        holding.value(forKey: "institution") as? Institution
    }

    private var insurance: NSManagedObject? {
        asset.value(forKey: "insurance") as? NSManagedObject
    }

    private var insuranceTransactions: [Transaction] {
        let transactions = asset.transactions?.allObjects as? [Transaction] ?? []
        return transactions.filter {
            $0.portfolio?.objectID == holding.portfolio?.objectID &&
            $0.type == TransactionType.insurance.rawValue
        }.sorted { ($0.transactionDate ?? Date.distantPast) < ($1.transactionDate ?? Date.distantPast) }
    }

    private var insurancePurchaseDate: Date? {
        guard let firstTransaction = insuranceTransactions.first else { return nil }
        return firstTransaction.transactionDate ?? firstTransaction.createdAt
    }

    private var totalPaidPremium: Double {
        guard isInsurance, let portfolio = holding.portfolio else { return 0 }
        let paid = InsurancePaymentService.totalPaidAmount(for: asset, in: portfolio, context: viewContext)
        let portfolioCurrency = Currency(rawValue: portfolio.mainCurrency ?? "USD") ?? .usd
        return CurrencyService.shared.convertAmount(paid, from: portfolioCurrency, to: displayCurrency)
    }

    private var insurancePaymentDeposits: [Transaction] {
        guard let portfolio = holding.portfolio else { return [] }
        return InsurancePaymentService.paymentTransactions(for: asset, in: portfolio, context: viewContext)
    }

    private var hasAutoFetchEnabled: Bool {
        autoFetchToggle
    }

    private var structuredProductTransactions: [Transaction] {
        let transactions = asset.transactions?.allObjects as? [Transaction] ?? []
        return transactions
            .filter { $0.portfolio?.objectID == holding.portfolio?.objectID }
            .sorted { ($0.transactionDate ?? Date.distantPast) > ($1.transactionDate ?? Date.distantPast) }
    }

    private var buySellHistory: [Transaction] {
        guard let portfolio = holding.portfolio else { return [] }
        let transactions = asset.transactions?.allObjects as? [Transaction] ?? []
        return transactions
            .filter { transaction in
                guard transaction.portfolio?.objectID == portfolio.objectID else { return false }
                guard let type = TransactionType(rawValue: transaction.type ?? "") else { return false }
                return type == .buy || type == .sell
            }
            .sorted { lhs, rhs in
                let lhsDate = lhs.transactionDate ?? lhs.createdAt ?? Date.distantPast
                let rhsDate = rhs.transactionDate ?? rhs.createdAt ?? Date.distantPast
                return lhsDate > rhsDate
            }
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
        guard autoFetchToggle else { return }
        await marketDataService.updateMarketPrices(for: [asset], in: viewContext)
    }

    private func updateAutoFetchPreference(_ enabled: Bool) {
        guard let portfolio = holding.portfolio else { return }

        if isUpdatingAutoFetchPreference { return }
        isUpdatingAutoFetchPreference = true
        defer { isUpdatingAutoFetchPreference = false }

        let previousPreference = asset.resolvedAutoFetchPreference
        asset.applyAutoFetchPreference(enabled, limitTo: portfolio)

        do {
            try viewContext.save()
            autoFetchToggle = asset.resolvedAutoFetchPreference
            if enabled {
                Task { await refreshAssetPrice() }
            }
        } catch {
            viewContext.rollback()
            self.error = "Failed to update auto-fetch setting: \(error.localizedDescription)"
            autoFetchToggle = previousPreference
        }
    }

    var body: some View {
        NavigationView {
            Form {
                // Asset Information Section
                Section(header: Text(localizationManager.localizedString(for: "holdingDetail.assetInformation.title"))) {
                    HStack {
                        Text(localizationManager.localizedString(for: "holdingDetail.assetInformation.symbol"))
                        Spacer()
                        Text(asset.symbol ?? "N/A")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text(localizationManager.localizedString(for: "holdingDetail.assetInformation.name"))
                        Spacer()
                        Text(asset.name ?? "Unknown Asset")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text(localizationManager.localizedString(for: "holdingDetail.assetInformation.type"))
                        Spacer()
                        Text(asset.assetType?.capitalized ?? localizationManager.localizedString(for: "holdingDetail.unknown"))
                            .foregroundColor(.secondary)
                    }
                }

                // Holdings Information Section
                if !isInsurance {
                    Section(header: Text(localizationManager.localizedString(for: "holdingDetail.holdingsInformation.title"))) {
                        if isStructuredProduct {
                            HStack {
                                Text(localizationManager.localizedString(for: "holdingDetail.assetInformation.issuer"))
                                Spacer()
                                Text((holdingInstitution?.name ?? localizationManager.localizedString(for: "holdingDetail.holdingsInformation.unassigned")))
                                    .foregroundColor(.secondary)
                            }

                            HStack {
                                Text(localizationManager.localizedString(for: "holdingDetail.holdingsInformation.investmentAmount"))
                                Spacer()
                                Text(Formatters.currency(structuredProductInvestmentAmount, symbol: portfolioMainCurrency.displayName))
                                    .fontWeight(.medium)
                            }

                            HStack {
                                Text(localizationManager.localizedString(for: "holdingDetail.assetInformation.interestRate"))
                                Spacer()
                                Text(Formatters.percent(structuredProductInterestRate, fractionDigits: 2))
                                    .foregroundColor(.secondary)
                            }

                            if let maturityDate = structuredProductMaturityDate {
                                HStack {
                                    Text(localizationManager.localizedString(for: "holdingDetail.assetInformation.maturityDate"))
                                    Spacer()
                                    Text(maturityDate, style: .date)
                                        .foregroundColor(.secondary)
                                }
                            }

                            if !structuredProductLinkedAssets.isEmpty {
                                HStack {
                                    Text(localizationManager.localizedString(for: "holdingDetail.holdingsInformation.linkedAssets"))
                                    Spacer()
                                    Text(structuredProductLinkedAssets)
                                        .foregroundColor(.secondary)
                                }
                            }

                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(localizationManager.localizedString(for: "holdingDetail.holdingsInformation.lastRecordedPrice"))
                                    /*Text("(\(displayCurrency.displayName))")
                                        .font(.caption)
                                        .foregroundColor(.secondary)*/
                                }
                                Spacer()
                                HStack {
                                    Text(Formatters.currency(displayPrice, symbol: displayCurrency.displayName, fractionDigits: 6))
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
                            Text(localizationManager.localizedString(for: "holdingDetail.messages.priceDescription"))
                                .font(.caption)
                                .foregroundColor(.secondary)

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

                            Toggle(localizationManager.localizedString(for: "holdingDetail.holdingsInformation.autoFetchPrice"), isOn: $autoFetchToggle)
                                .toggleStyle(SwitchToggleStyle())
                                .onChange(of: autoFetchToggle) { _, newValue in
                                    guard !isUpdatingAutoFetchPreference else { return }
                                    updateAutoFetchPreference(newValue)
                                }

                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(localizationManager.localizedString(for: "holdingDetail.holdingsInformation.totalValue"))
                                    /*Text("(\(displayCurrency.displayName))")
                                        .font(.caption)
                                        .foregroundColor(.secondary)*/
                                }
                                Spacer()
                                Text(Formatters.currency(displayCurrentValue, symbol: displayCurrency.displayName))
                                    .foregroundColor(.secondary)
                            }

                            if holding.portfolio != nil {
                                HStack(spacing: 16) {
                                    Button(localizationManager.localizedString(for: "holdingDetail.actions.buyMore")) {
                                        presentTrade(.buy)
                                    }
                                    Button(localizationManager.localizedString(for: "holdingDetail.actions.sell")) {
                                        presentTrade(.sell)
                                    }
                                }
                                .padding(.top, 4)
                            }
                        } else {

                            HStack {
                                Text(localizationManager.localizedString(for: "holdingDetail.assetInformation.issuer"))
                                Spacer()
                                Text((holdingInstitution?.name ?? localizationManager.localizedString(for: "holdingDetail.holdingsInformation.unassigned")))
                                    .foregroundColor(.secondary)
                            }
                            
                            HStack {
                                Text(localizationManager.localizedString(for: "holdingDetail.holdingsInformation.quantity"))
                                Spacer()
                                Text(Formatters.decimal(holding.quantity, fractionDigits: 5))
                                    .foregroundColor(.secondary)
                            }

                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(localizationManager.localizedString(for: "holdingDetail.holdingsInformation.lastRecordedPrice"))
                                    /*Text("(\(displayCurrency.displayName))")
                                        .font(.caption)
                                        .foregroundColor(.secondary)*/
                                }
                                Spacer()
                                HStack {
                                    Text(Formatters.currency(displayPrice, symbol: displayCurrency.displayName, fractionDigits: 6))
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
                            Text(localizationManager.localizedString(for: "holdingDetail.messages.priceDescription"))
                                .font(.caption)
                                .foregroundColor(.secondary)

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

                            Toggle(localizationManager.localizedString(for: "holdingDetail.holdingsInformation.autoFetchPrice"), isOn: $autoFetchToggle)
                                .toggleStyle(SwitchToggleStyle())
                                .onChange(of: autoFetchToggle) { _, newValue in
                                    guard !isUpdatingAutoFetchPreference else { return }
                                    updateAutoFetchPreference(newValue)
                                }

                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(localizationManager.localizedString(for: "holdingDetail.holdingsInformation.averageCostBasis"))
                                    /*Text("(\(portfolioMainCurrency.displayName))")
                                        .font(.caption)
                                        .foregroundColor(.secondary)*/
                                }
                                Spacer()
                                Text(Formatters.currency(holding.averageCostBasis, symbol: portfolioMainCurrency.displayName, fractionDigits: 6))
                                    .foregroundColor(.secondary)
                            }

                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(localizationManager.localizedString(for: "holdingDetail.holdingsInformation.totalValue"))
                                    /*Text("(\(displayCurrency.displayName))")
                                        .font(.caption)
                                        .foregroundColor(.secondary)*/
                                }
                                Spacer()
                                Text(Formatters.currency(displayCurrentValue, symbol: displayCurrency.displayName))
                                    .fontWeight(.semibold)
                            }

                            if holding.portfolio != nil {
                                HStack(spacing: 16) {
                                    Button(localizationManager.localizedString(for: "holdingDetail.actions.buyMore")) {
                                        presentTrade(.buy)
                                    }
                                    Button(localizationManager.localizedString(for: "holdingDetail.actions.sell")) {
                                        presentTrade(.sell)
                                    }
                                }
                                .padding(.top, 4)
                            }
                        }
                    }
                }

                // Insurance Sections (for insurance assets)
                if isInsurance {
                    insuranceDetailsSection
                    insuranceFinancialSection
                    insurancePremiumSection
                    insuranceCoverageSection
                    insuranceBeneficiariesSection
                }

                // Performance Section (for non-insurance assets)
                if !isInsurance {
                    Section(header: Text(localizationManager.localizedString(for: "holdingDetail.performance.title"))) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(localizationManager.localizedString(for: "holdingDetail.holdingsInformation.costBasis"))
                                /*Text("(\(portfolioMainCurrency.displayName))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)*/
                            }
                            Spacer()
                            Text(Formatters.currency(costBasis, symbol: portfolioMainCurrency.displayName))
                                .foregroundColor(.secondary)
                        }

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(localizationManager.localizedString(for: "holdingDetail.performance.unrealizedGainLoss"))
                                /*Text("(\(portfolioMainCurrency.displayName))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)*/
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(Formatters.signedCurrency(unrealizedGainLoss, symbol: portfolioMainCurrency.displayName))
                                    .fontWeight(.medium)
                                    .foregroundColor(unrealizedGainLoss >= 0 ? .green : .red)

                                Text("(" + Formatters.signedPercent(gainLossPercentage) + ")")
                                    .font(.caption)
                                    .foregroundColor(unrealizedGainLoss >= 0 ? .green : .red)
                            }
                        }

                        if holding.totalDividends != 0 {
                            let cumulativeIncome = holding.totalDividends
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(localizationManager.localizedString(for: "holdingDetail.performance.cumulativeIncome"))
                                    /*Text("(\(portfolioMainCurrency.displayName))")
                                        .font(.caption)
                                        .foregroundColor(.secondary)*/
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
                                    Text(localizationManager.localizedString(for: "holdingDetail.performance.totalReturnWithIncome"))
                                    /*Text("(\(portfolioMainCurrency.displayName))")
                                        .font(.caption)
                                        .foregroundColor(.secondary)*/
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(Formatters.signedCurrency(incomeAdjustedGain, symbol: portfolioMainCurrency.displayName))
                                        .fontWeight(.medium)
                                        .foregroundColor(incomeAdjustedGain >= 0 ? .green : .red)

                                    Text("(" + Formatters.signedPercent(incomeAdjustedPercent) + ")")
                                        .font(.caption)
                                        .foregroundColor(incomeAdjustedGain >= 0 ? .green : .red)
                                }
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

                // Transaction History Section
                if !isInsurance {
                    Section(header: Text(localizationManager.localizedString(for: "holdingDetail.transactions.title"))) {
                        if buySellHistory.isEmpty {
                            Text("No buy or sell transactions recorded for this asset.")
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(buySellHistory, id: \.objectID) { transaction in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(transactionDisplayName(for: transaction))
                                            .fontWeight(.medium)
                                        Spacer()
                                        Text(transactionDisplayDate(for: transaction), style: .date)
                                            .foregroundColor(.secondary)
                                    }

                                    HStack {
                                        Text(localizationManager.localizedString(for: "holdingDetail.holdingsInformation.quantity"))
                                        Spacer()
                                        Text(Formatters.decimal(transaction.quantity, fractionDigits: 5))
                                            .foregroundColor(.secondary)
                                    }

                                    HStack {
                                        Text(localizationManager.localizedString(for: "holdingDetail.holdingsInformation.price"))
                                        Spacer()
                                        Text(Formatters.currency(transaction.price, symbol: transactionCurrency(for: transaction).displayName, fractionDigits: 6))
                                            .foregroundColor(.secondary)
                                    }

                                    HStack {
                                        Text(localizationManager.localizedString(for: "holdingDetail.performance.total"))
                                        Spacer()
                                        Text(Formatters.currency(transaction.quantity * transaction.price, symbol: transactionCurrency(for: transaction).displayName))
                                            .foregroundColor(.secondary)
                                    }

                                    if let notes = transaction.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
                                        Text(notes)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }

                // Price Update Information
                if let lastUpdate = asset.lastPriceUpdate {
                    Section(header: Text("Price Information")) {
                        HStack {
                            Text(localizationManager.localizedString(for: "holdingDetail.performance.lastUpdate"))
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

                Section {
                    Text(localizationManager.localizedString(for: "holdingDetail.messages.historicalCosts"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .navigationTitle(asset.symbol ?? localizationManager.localizedString(for: "holdingDetail.navigation.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    if isInsurance, holding.portfolio != nil {
                        Button(localizationManager.localizedString(for: "holdingDetail.actions.payments")) {
                            showingPaymentManagement = true
                        }
                    }
                    Button(localizationManager.localizedString(for: "common.done")) {
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
        .sheet(isPresented: $showingAddTransaction) {
            if let portfolio = holding.portfolio {
                AddTransactionView(portfolio: portfolio,
                                   initialTransactionType: pendingTransactionType,
                                   initialAsset: asset,
                                   initialInstitution: holdingInstitution)
                    .id(addTransactionPresentationID)
                    .environment(\.managedObjectContext, viewContext)
                    .interactiveDismissDisabled()
            } else {
                Text(localizationManager.localizedString(for: "holdingDetail.messages.noPortfolio"))
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .padding()
            }
        }
        .sheet(isPresented: $showingPaymentManagement) {
            if let portfolio = holding.portfolio {
                InsurancePaymentManagementView(portfolio: portfolio, insuranceAsset: asset)
                    .environment(\.managedObjectContext, viewContext)
            } else {
                Text(localizationManager.localizedString(for: "holdingDetail.messages.noPortfolio"))
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .padding()
            }
        }
    }

    // MARK: - Insurance Detail Sections

    @ViewBuilder
    private var insuranceDetailsSection: some View {
        Section(header: Text(localizationManager.localizedString(for: "holdingDetail.insurance.details.title"))) {
            HStack {
                Text(localizationManager.localizedString(for: "holdingDetail.insurance.details.policySymbol"))
                Spacer()
                Text(asset.symbol ?? "-")
                    .foregroundColor(.secondary)
            }
            HStack {
                Text("Policy Type")
                Spacer()
                Text(insurance?.value(forKey: "insuranceType") as? String ?? "-")
                    .foregroundColor(.secondary)
            }
            HStack {
                Text("Policy Holder")
                Spacer()
                Text(insurance?.value(forKey: "policyholder") as? String ?? "-")
                    .foregroundColor(.secondary)
            }
            HStack {
                Text("Insured Person")
                Spacer()
                Text(insurance?.value(forKey: "insuredPerson") as? String ?? "-")
                    .foregroundColor(.secondary)
            }
            if let policyNumber = insurance?.value(forKey: "contactNumber") as? String, !policyNumber.isEmpty {
                HStack {
                    Text("Policy Number")
                    Spacer()
                    Text(policyNumber)
                        .foregroundColor(.secondary)
                }
            }
            if let purchaseDate = insurancePurchaseDate {
                HStack {
                    Text("Policy Purchase Date")
                    Spacer()
                    Text(purchaseDate, style: .date)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var insuranceFinancialSection: some View {
        Section(header: Text(localizationManager.localizedString(for: "holdingDetail.insurance.financialDetails.title"))) {

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cash Value")
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

            insuranceValueRow(label: "Basic Insured Amount", amount: insurance?.value(forKey: "basicInsuredAmount") as? Double)
            insuranceValueRow(label: "Additional Payment", amount: insurance?.value(forKey: "additionalPaymentAmount") as? Double)
            insuranceValueRow(label: "Death Benefit", amount: insurance?.value(forKey: "deathBenefit") as? Double)
            HStack {
                Text("Total Paid Premium")
                Spacer()
                Text(Formatters.currency(totalPaidPremium, symbol: displayCurrency.displayName))
                    .foregroundColor(.blue)
                    .fontWeight(.semibold)
            }
        }
    }

    @ViewBuilder
    private var insurancePremiumSection: some View {
        Section(header: Text("Premium Details")) {
            let paymentType = insurance?.value(forKey: "premiumPaymentType") as? String ?? "-"
            let paymentStatus = insurance?.value(forKey: "premiumPaymentStatus") as? String ?? "-"
            HStack {
                Text("Payment Type")
                Spacer()
                Text(paymentType)
                    .foregroundColor(.secondary)
            }
            HStack {
                Text("Payment Status")
                Spacer()
                Text(paymentStatus)
                    .foregroundColor(.secondary)
            }
            insuranceValueRow(label: "Single Premium", amount: insurance?.value(forKey: "singlePremium") as? Double)
            if let discounted = insurance?.value(forKey: "firstDiscountedPremium") as? Double, abs(discounted) > 1e-6 {
                insuranceValueRow(label: "First Discounted Premium", amount: discounted)
            }
            insuranceValueRow(label: "Total Premium", amount: insurance?.value(forKey: "totalPremium") as? Double)
            if let term = insurance?.value(forKey: "premiumPaymentTerm") as? Int32, term > 0 {
                HStack {
                    Text("Payment Term")
                    Spacer()
                    Text("\(term) years")
                        .foregroundColor(.secondary)
                }
            }
            insuranceToggleRow(label: "Participating", value: insurance?.value(forKey: "isParticipating") as? Bool)
            insuranceToggleRow(label: "Supplementary Insurance", value: insurance?.value(forKey: "hasSupplementaryInsurance") as? Bool)
        }
    }

    @ViewBuilder
    private var insuranceCoverageSection: some View {
        Section(header: Text("Coverage & Benefits")) {
            if let expiration = insurance?.value(forKey: "coverageExpirationDate") as? Date {
                insuranceDateRow(label: "Coverage Expiration", date: expiration)
            }
            if let maturityDate = insurance?.value(forKey: "maturityBenefitRedemptionDate") as? Date {
                insuranceDateRow(label: "Maturity Benefit Date", date: maturityDate)
            }
            insuranceValueRow(label: "Estimated Maturity Benefit", amount: insurance?.value(forKey: "estimatedMaturityBenefit") as? Double)
            insuranceToggleRow(label: "Can Withdraw Premiums", value: insurance?.value(forKey: "canWithdrawPremiums") as? Bool)
            if let percentage = insurance?.value(forKey: "maxWithdrawalPercentage") as? Double, percentage > 0 {
                HStack {
                    Text("Max Withdrawal %")
                    Spacer()
                    Text("\(Formatters.decimal(percentage, fractionDigits: 1))%")
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var insuranceBeneficiariesSection: some View {
        if let beneficiaries = insurance?.value(forKey: "beneficiaries") as? Set<NSManagedObject>, !beneficiaries.isEmpty {
            Section(header: Text("Beneficiaries")) {
                ForEach(Array(beneficiaries), id: \.objectID) { beneficiary in
                    HStack {
                        Text(beneficiary.value(forKey: "name") as? String ?? "-" )
                        Spacer()
                        let pct = beneficiary.value(forKey: "percentage") as? Double ?? 0
                        Text("\(Formatters.decimal(pct, fractionDigits: 1))%")
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private func insuranceValueRow(label: String, amount: Double?) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(Formatters.currency(amount ?? 0, symbol: displayCurrency.displayName))
                .foregroundColor(.secondary)
        }
    }

    private func insuranceToggleRow(label: String, value: Bool?) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text((value ?? false) ? "Yes" : "No")
                .foregroundColor(.secondary)
        }
    }

    private func insuranceDateRow(label: String, date: Date) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(date, style: .date)
                .foregroundColor(.secondary)
        }
    }

    private func transactionDisplayDate(for transaction: Transaction) -> Date {
        transaction.transactionDate ?? transaction.createdAt ?? Date()
    }

    private func transactionCurrency(for transaction: Transaction) -> Currency {
        if let code = transaction.currency, let currency = Currency(rawValue: code) {
            return currency
        }
        return portfolioMainCurrency
    }

    private func transactionDisplayName(for transaction: Transaction) -> String {
        if let type = TransactionType(rawValue: transaction.type ?? "") {
            return type.displayName
        }
        return transaction.type ?? "Transaction"
    }

    private func presentTrade(_ type: TransactionType) {
        pendingTransactionType = type
        addTransactionPresentationID = UUID()
        showingAddTransaction = true
    }
}

struct PriceEditorView: View {
    @ObservedObject var asset: Asset
    @Binding var editingPrice: Double
    let displayCurrency: Currency
    let portfolioMainCurrency: Currency
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var localizationManager: LocalizationManager
    @State private var error: String?

    private let currencyService = CurrencyService.shared

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text(localizationManager.localizedString(for: "holdingDetail.priceInformation.priceUpdate"))) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(localizationManager.localizedString(for: "holdingDetail.holdingsInformation.lastRecordedPrice"))
                            /*Text("(\(displayCurrency.displayName))")
                                .font(.caption)
                                .foregroundColor(.secondary)*/
                        }
                        Spacer()
                        Text(displayCurrency.displayName)
                            .foregroundColor(.secondary)
                        TextField("0.00", value: $editingPrice, format: .number)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(width: 120)
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
                        Text(localizationManager.localizedString(for: "holdingDetail.assetInformation.name"))
                        Spacer()
                        Text(asset.name ?? "Unknown Asset")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Previous Price")
                            /*Text("(\(displayCurrency.displayName))")
                                .font(.caption)
                                .foregroundColor(.secondary)*/
                        }
                        Spacer()
                        Text(Formatters.currency(currencyService.convertAmount(asset.currentPrice, from: portfolioMainCurrency, to: displayCurrency), symbol: displayCurrency.displayName, fractionDigits: 6))
                            .foregroundColor(.secondary)
                    }
                }

                Section(footer: Text("Note: This will manually set the price. To enable automatic price fetching, turn on 'Auto-fetch price' when creating or editing transactions or toggle it from the holding detail screen.")) {
                    EmptyView()
                }

                if let error = error {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle(localizationManager.localizedString(for: "holdingDetail.priceEditor.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(localizationManager.localizedString(for: "holdingDetail.priceEditor.cancel")) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(localizationManager.localizedString(for: "holdingDetail.priceEditor.save")) {
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
        HoldingDetailView(holding: holding, asset: asset)
            .environment(\.managedObjectContext, context)
    } else {
        Text("No preview data available")
    }
}
