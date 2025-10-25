import SwiftUI
import Foundation
import CoreData
import Charts

struct PortfolioDashboardView: View {
    @ObservedObject var portfolio: Portfolio
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var localizationManager: LocalizationManager
    
    @State private var showingAddTransaction = false
    @State private var showingPortfolioSettings = false
    @State private var showingCloudShare = false
    @State private var showingShareSetup = false
    @State private var isPreparingShare = false
    @State private var shareSetupError: String?
    @State private var selectedTab = 0
    @State private var showingCashOverview = false
    @State private var cashOverviewInitialTab: CashOverviewView.Tab = .demandCash
    @State private var showingRealizedPnL = false
    @State private var showingActionCalendar = false
    @StateObject private var viewModel = PortfolioViewModel()
    @StateObject private var ownershipService = PortfolioOwnershipService.shared
    @State private var isRefreshing = false
    
    var body: some View {
        VStack(spacing: 16) {
            // Header and Quick Stats side by side
            HStack(alignment: .top, spacing: 16) {
                // Header with portfolio value (left side)
                PortfolioHeaderView(portfolio: portfolio)
                    .frame(maxWidth: .infinity)

                // Quick Stats (right side in 2x2 grid)
                QuickStatsGridView(portfolio: portfolio) { tab in
                    presentCashOverview(initialTab: tab)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal)

            // Tab Selection
            Picker("View", selection: $selectedTab) {
                Text(localizationManager.localizedString(for: "portfolioDashboard.tabs.holdings")).tag(0)
                Text(localizationManager.localizedString(for: "portfolioDashboard.tabs.transactions")).tag(1)
                Text(localizationManager.localizedString(for: "portfolioDashboard.tabs.analytics")).tag(2)
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.horizontal)
            .padding(.top, -8)

            // Tab Content
            Group {
                switch selectedTab {
                case 0:
                    RefreshableHoldingsView(portfolio: portfolio, onRefresh: performCompleteRefresh)
                case 1:
                    RefreshableTransactionsView(portfolio: portfolio, onRefresh: performCompleteRefresh)
                case 2:
                    RefreshableAnalyticsView(portfolio: portfolio, onRefresh: performCompleteRefresh)
                default:
                    RefreshableHoldingsView(portfolio: portfolio, onRefresh: performCompleteRefresh)
                }
            }
        }
        .navigationTitle(portfolio.name ?? "Portfolio")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: {
                    showingPortfolioSettings = true
                }) {
                    Image(systemName: "gear")
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 16) {

                    Button(action: {
                        showingAddTransaction = true
                    }) {
                        Image(systemName: "plus")
                    }

                    Button {
                        presentCashOverview(initialTab: .fixedDeposits)
                    } label: {
                        Image(systemName: "building.columns")
                    }

                    Button {
                        showingRealizedPnL = true
                    } label: {
                        Image(systemName: "chart.bar.doc.horizontal")
                    }

                    Button(action: {
                        showingActionCalendar = true
                    }) {
                        Image(systemName: "calendar")
                    }

                    if ownershipService.canSharePortfolio(portfolio) {
                        Button(action: {
                            handleShareButtonTap()
                        }) {
                            Image(systemName: "person.2")
                        }
                    }

                }
            }
        }
        .sheet(isPresented: $showingAddTransaction) {
            AddTransactionView(portfolio: portfolio)
                .interactiveDismissDisabled()
        }
        .sheet(isPresented: $showingPortfolioSettings) {
            PortfolioSettingsView(portfolio: portfolio)
        }
        .sheet(isPresented: $showingShareSetup) {
            ShareSetupSheet(
                portfolioName: portfolio.name ?? "Portfolio",
                isPreparingShare: isPreparingShare,
                errorMessage: shareSetupError,
                onCancel: { showingShareSetup = false },
                onStartSharing: { startSharingFlow() }
            )
        }
        .sheet(isPresented: $showingCloudShare) {
            CloudShareView(
                portfolioID: portfolio.objectID,
                container: PersistenceController.shared.container,
                context: viewContext,
                localizationManager: localizationManager
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .cloudShareStatusChanged)) { notification in
            guard let object = notification.object as? NSManagedObjectID,
                  object == portfolio.objectID else { return }
            if let status = notification.userInfo?["status"] as? CloudShareStatus {
                switch status {
                case .shared:
                    showingShareSetup = false
                case .notShared:
                    showingCloudShare = false
                }
            }
        }
        .task {
            viewModel.updatePortfolioPrices(portfolio: portfolio, context: viewContext)
        }
        .onChange(of: selectedTab) { _, newValue in
            if newValue == 0 || newValue == 2 {
                viewModel.updatePortfolioPrices(portfolio: portfolio, context: viewContext)
            }
        }
        .sheet(isPresented: $showingCashOverview) {
            CashOverviewView(portfolio: portfolio, initialTab: cashOverviewInitialTab)
                .environment(\.managedObjectContext, viewContext)
        }
        .sheet(isPresented: $showingRealizedPnL) {
            RealizedPnLView(portfolio: portfolio)
                .environment(\.managedObjectContext, viewContext)
        }
        .sheet(isPresented: $showingActionCalendar) {
            ActionCalendarView(portfolio: portfolio)
                .environment(\.managedObjectContext, viewContext)
        }
    }

    private func handleShareButtonTap() {
        let container = PersistenceController.shared.container
        let status = CloudShareManager.shared.currentStatus(for: portfolio.objectID,
                                                            in: viewContext,
                                                            container: container)
        switch status {
        case .shared:
            showingCloudShare = true
        case .notShared:
            shareSetupError = nil
            showingShareSetup = true
        }
    }

    private func presentCashOverview(initialTab: CashOverviewView.Tab) {
        cashOverviewInitialTab = initialTab
        showingCashOverview = true
    }

    private func startSharingFlow() {
        guard !isPreparingShare else { return }

        isPreparingShare = true
        shareSetupError = nil

        Task {
            do {
                try await CloudShareManager.shared.createShare(for: portfolio.objectID,
                                                                in: viewContext,
                                                                container: PersistenceController.shared.container)

                await MainActor.run {
                    isPreparingShare = false
                    showingShareSetup = false
                    showingCloudShare = true
                }
            } catch {
                await MainActor.run {
                    isPreparingShare = false
                    shareSetupError = error.localizedDescription
                }
            }
        }
    }

    private func performCompleteRefresh() async {
        print("🔄 Starting complete portfolio refresh...")

        await MainActor.run {
            isRefreshing = true
        }

        // Step 2.1: Refresh currency exchange rates
        await refreshCurrencyRates()

        // Step 2.2: Auto-fetch prices and recalculate holdings values
        await refreshAssetPricesAndHoldingsValues()

        // Step 2.3: Recalculate P&L, dividends, and cash balances
        await recalculatePnLDividendsAndCash()

        // Step 2.4: Recalculate total portfolio value
        await recalculateTotalPortfolioValue()

        print("✅ Portfolio refresh completed successfully")

        await MainActor.run {
            isRefreshing = false
        }
    }

    private func refreshCurrencyRates() async {
        print("💱 Refreshing currency exchange rates...")
        // Force refresh currency rates
        await CurrencyService.shared.refreshExchangeRates()
    }

    private func refreshAssetPricesAndHoldingsValues() async {
        print("📈 Refreshing asset prices and holdings values...")
        await MainActor.run {
            viewModel.updatePortfolioPrices(portfolio: portfolio, context: viewContext)
        }
    }

    private func recalculatePnLDividendsAndCash() async {
        print("🧮 Recalculating P&L, dividends, and cash...")
        // This will be handled by the price update process, but we can trigger additional recalculation if needed
        await MainActor.run {
            // Force UI refresh of calculated values
            portfolio.objectWillChange.send()
        }
    }

    private func recalculateTotalPortfolioValue() async {
        print("💰 Recalculating total portfolio value...")
        await MainActor.run {
            // Calculate total value from all holdings and cash
            let holdings = (portfolio.holdings?.allObjects as? [Holding]) ?? []
            let totalHoldingsValue = holdings.reduce(0.0) { sum, holding in
                guard let asset = holding.asset else { return sum }
                // Exclude deposit assets from holdings value calculation
                // Deposit assets are already accounted for in cash balance
                guard asset.assetType != AssetType.deposit.rawValue else { return sum }

                if asset.assetType == AssetType.insurance.rawValue {
                    let cashValue = holding.value(forKey: "cashValue") as? Double ?? 0
                    return sum + cashValue
                }
                return sum + (holding.quantity * asset.currentPrice)
            }

            // Calculate total cash balance using new per-currency system
            let transactions = (portfolio.transactions?.allObjects as? [Transaction]) ?? []
            let institutionSet = Set(transactions.compactMap { $0.institution })
            let totalCashBalance = institutionSet.reduce(0) { $0 + $1.getCashBalance(for: portfolio) }

            portfolio.totalValue = totalHoldingsValue + totalCashBalance

            do {
                try viewContext.save()
                print("💾 Total portfolio value updated: \(portfolio.totalValue)")
            } catch {
                print("❌ Error saving total portfolio value: \(error)")
            }
        }
    }
}

// MARK: - Refreshable Wrapper Views

struct RefreshableHoldingsView: View {
    @ObservedObject var portfolio: Portfolio
    let onRefresh: () async -> Void

    var body: some View {
        HoldingsView(portfolio: portfolio)
            .padding(.top, -20)
            .refreshable {
                await onRefresh()
            }
    }
}

struct RefreshableTransactionsView: View {
    @ObservedObject var portfolio: Portfolio
    let onRefresh: () async -> Void

    var body: some View {
        TransactionsView(portfolio: portfolio)
            .padding(.top, -20)
            .refreshable {
                await onRefresh()
            }
    }
}

struct RefreshableAnalyticsView: View {
    @ObservedObject var portfolio: Portfolio
    let onRefresh: () async -> Void

    var body: some View {
        AnalyticsView(portfolio: portfolio)
            .padding(.top, -20)
            .refreshable {
                await onRefresh()
            }
    }
}

private struct ShareSetupSheet: View {
    let portfolioName: String
    let isPreparingShare: Bool
    let errorMessage: String?
    let onCancel: () -> Void
    let onStartSharing: () -> Void
    @EnvironmentObject private var localizationManager: LocalizationManager

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.blue)

                Text(String(format: localizationManager.localizedString(for: "portfolioDashboard.shareDialog.message"), portfolioName))
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(localizationManager.localizedString(for: "portfolioDashboard.shareDialog.intro"))
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)

                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Button(action: onStartSharing) {
                    if isPreparingShare {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .tint(.white)
                    } else {
                        Text(localizationManager.localizedString(for: "portfolioDashboard.shareDialog.title"))
                            .font(.headline)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(isPreparingShare ? Color.gray : Color.blue)
                .foregroundColor(.white)
                .cornerRadius(12)
                .disabled(isPreparingShare)

                Spacer()
            }
            .padding()
            .navigationTitle(localizationManager.localizedString(for: "portfolioDashboard.shareDialog.title"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(localizationManager.localizedString(for: "common.cancel"), action: onCancel)
                        .disabled(isPreparingShare)
                }
            }
        }
    }
}

struct PortfolioHeaderView: View {
    @ObservedObject var portfolio: Portfolio
    @StateObject private var currencyService = CurrencyService.shared
    @EnvironmentObject private var localizationManager: LocalizationManager
    
    private var mainCurrency: Currency {
        Currency(rawValue: portfolio.mainCurrency ?? "USD") ?? .usd
    }

    private var totalCashFromInstitutions: Double {
        return portfolio.totalCashBalance
    }

    private var totalValueInMainCurrency: Double {
        // Calculate total value by converting all holdings to main currency
        let holdingsTotal = portfolio.holdings?.compactMap { $0 as? Holding }.reduce(0.0) { result, holding in
            guard let asset = holding.asset else { return result }
            // Exclude deposit assets from holdings value calculation
            // Deposit assets are already accounted for in cash balance
            guard asset.assetType != AssetType.deposit.rawValue else { return result }

            if asset.assetType == AssetType.insurance.rawValue {
                let cashValue = holding.value(forKey: "cashValue") as? Double ?? 0
                return result + cashValue
            }
            let holdingValue = holding.quantity * asset.currentPrice

            // For now, assume all assets are in the main currency
            // In a real app, you'd need to track the currency for each asset
            return result + holdingValue
        } ?? 0.0

        return holdingsTotal + totalCashFromInstitutions
    }
    
    var body: some View {
        VStack(spacing: 8) {
            Text(localizationManager.localizedString(for: "portfolioDashboard.header.totalValue"))
                .font(.headline)
                .foregroundColor(.secondary)

            Text(currencyService.formatAmountWithFullCurrency(totalValueInMainCurrency, in: mainCurrency))
                .font(.title)
                .fontWeight(.bold)

            HStack(spacing: 20) {
                VStack {
                    Text(localizationManager.localizedString(for: "portfolioDashboard.header.holdings"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(portfolio.holdings?.count ?? 0)")
                        .font(.title3)
                        .fontWeight(.semibold)
                }

                VStack {
                    Text(localizationManager.localizedString(for: "portfolioDashboard.header.transactions"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(portfolio.transactions?.count ?? 0)")
                        .font(.title3)
                        .fontWeight(.semibold)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(15)
        .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
}

struct QuickStatsGridView: View {
    @ObservedObject var portfolio: Portfolio
    let onCashTapped: (CashOverviewView.Tab) -> Void
    @StateObject private var currencyService = CurrencyService.shared
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var localizationManager: LocalizationManager

    private var mainCurrency: Currency {
        Currency(rawValue: portfolio.mainCurrency ?? "USD") ?? .usd
    }

    private var totalGainLoss: Double {
        let holdings = portfolio.holdings?.compactMap { $0 as? Holding } ?? []

        let result = holdings.reduce(0) { result, holding in
            guard let asset = holding.asset else { return result }

            let gainLoss: Double

            if asset.assetType == AssetType.insurance.rawValue {
                // For insurance: P&L = Cash Value - Actual Paid Premium
                let cashValue = holding.value(forKey: "cashValue") as? Double ?? 0

                let paidPremium = InsurancePaymentService.totalPaidAmount(for: asset, in: portfolio, context: viewContext)
                gainLoss = cashValue - paidPremium
            } else {
                // For securities: P&L = Current Value - Cost Basis
                let currentValue = holding.quantity * asset.currentPrice
                let costBasis = holding.quantity * holding.averageCostBasis
                gainLoss = currentValue - costBasis
            }

            return result + gainLoss
        }

        return result
    }

    private var totalSecuritiesGainLoss: Double {
        let holdings = portfolio.holdings?.compactMap { $0 as? Holding } ?? []

        let result = holdings.reduce(0) { result, holding in
            guard let asset = holding.asset else { return result }

            // Only calculate P&L for non-insurance assets (securities)
            guard asset.assetType != AssetType.insurance.rawValue else { return result }

            let currentValue = holding.quantity * asset.currentPrice
            let costBasis = holding.quantity * holding.averageCostBasis
            let gainLoss = currentValue - costBasis

            return result + gainLoss
        }

        return result
    }

    private var totalDividends: Double {
        portfolio.holdings?.compactMap { $0 as? Holding }.reduce(0) { $0 + $1.totalDividends } ?? 0
    }

    private var totalHoldingsValue: Double {
        // Reuse the same calculation logic from recalculateTotalPortfolioValue
        let holdings = (portfolio.holdings?.allObjects as? [Holding]) ?? []
        return holdings.reduce(0.0) { sum, holding in
            guard let asset = holding.asset else { return sum }
            // Exclude deposit assets from holdings value calculation
            // Deposit assets are already accounted for in cash balance
            guard asset.assetType != AssetType.deposit.rawValue else { return sum }

            if asset.assetType == AssetType.insurance.rawValue {
                let cashValue = holding.value(forKey: "cashValue") as? Double ?? 0
                return sum + cashValue
            }
            return sum + (holding.quantity * asset.currentPrice)
        }
    }

    private var totalSecuritiesHoldingsValue: Double {
        let holdings = (portfolio.holdings?.allObjects as? [Holding]) ?? []
        return holdings.reduce(0.0) { sum, holding in
            guard let asset = holding.asset else { return sum }
            // Exclude insurance and deposit assets from securities calculation
            guard asset.assetType != AssetType.insurance.rawValue else { return sum }
            guard asset.assetType != AssetType.deposit.rawValue else { return sum }
            return sum + (holding.quantity * asset.currentPrice)
        }
    }

    private var totalCashFromInstitutions: Double {
        return portfolio.totalCashBalance
    }

    private var availableCashBalance: Double {
        return portfolio.availableCashBalance
    }

    private var fixedDepositBalance: Double {
        return portfolio.fixedDepositBalance
    }

    var body: some View {
        VStack(spacing: 4) {
            // Top row
            HStack(spacing: 8) {
                StatCardView(
                    title: localizationManager.localizedString(for: "portfolioDashboard.statCard.totalHoldingsValue"),
                    value: currencyService.formatAmount(totalHoldingsValue, in: mainCurrency),
                    color: totalHoldingsValue >= 0 ? .green : .red,
                    subtitle: "Securities: \(currencyService.formatAmount(totalSecuritiesHoldingsValue, in: mainCurrency))"
                )

                Button(action: {
                    onCashTapped(.demandCash)
                }) {
                    StatCardView(
                        title: localizationManager.localizedString(for: "portfolioDashboard.statCard.totalCash"),
                        value: currencyService.formatAmount(totalCashFromInstitutions, in: mainCurrency),
                        color: totalCashFromInstitutions >= 0 ? .blue : .red,
                        subtitle: "Available: \(currencyService.formatAmount(availableCashBalance, in: mainCurrency))\nFixed Deposits: \(currencyService.formatAmount(fixedDepositBalance, in: mainCurrency))"
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }

            // Bottom row
            HStack(spacing: 8) {
                StatCardView(
                    title: localizationManager.localizedString(for: "portfolioDashboard.statCard.unrealizedPnL"),
                    value: currencyService.formatAmount(totalGainLoss, in: mainCurrency),
                    color: totalGainLoss >= 0 ? .green : .red,
                    subtitle: "Securities: \(currencyService.formatAmount(totalSecuritiesGainLoss, in: mainCurrency))"
                )

                StatCardView(
                    title: localizationManager.localizedString(for: "portfolioDashboard.statCard.totalDividendsInterest"),
                    value: currencyService.formatAmount(totalDividends, in: mainCurrency),
                    color: totalDividends >= 0 ? .green : .red,
                    subtitle: nil
                )
            }
        }
    }
}

struct QuickStatsView: View {
    @ObservedObject var portfolio: Portfolio
    let onCashTapped: (CashOverviewView.Tab) -> Void
    @StateObject private var currencyService = CurrencyService.shared
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var localizationManager: LocalizationManager

    private var mainCurrency: Currency {
        Currency(rawValue: portfolio.mainCurrency ?? "USD") ?? .usd
    }

    private var totalGainLoss: Double {
        let holdings = portfolio.holdings?.compactMap { $0 as? Holding } ?? []

        let result = holdings.reduce(0) { result, holding in
            guard let asset = holding.asset else { return result }

            let gainLoss: Double

            if asset.assetType == AssetType.insurance.rawValue {
                // For insurance: P&L = Cash Value - Actual Paid Premium
                let cashValue = holding.value(forKey: "cashValue") as? Double ?? 0

                let paidPremium = InsurancePaymentService.totalPaidAmount(for: asset, in: portfolio, context: viewContext)
                gainLoss = cashValue - paidPremium
            } else {
                // For securities: P&L = Current Value - Cost Basis
                let currentValue = holding.quantity * asset.currentPrice
                let costBasis = holding.quantity * holding.averageCostBasis
                gainLoss = currentValue - costBasis
            }

            return result + gainLoss
        }

        return result
    }

    private var totalSecuritiesGainLoss: Double {
        let holdings = portfolio.holdings?.compactMap { $0 as? Holding } ?? []

        let result = holdings.reduce(0) { result, holding in
            guard let asset = holding.asset else { return result }

            // Only calculate P&L for non-insurance assets (securities)
            guard asset.assetType != AssetType.insurance.rawValue else { return result }

            let currentValue = holding.quantity * asset.currentPrice
            let costBasis = holding.quantity * holding.averageCostBasis
            let gainLoss = currentValue - costBasis

            return result + gainLoss
        }

        return result
    }

    private var totalDividends: Double {
        portfolio.holdings?.compactMap { $0 as? Holding }.reduce(0) { $0 + $1.totalDividends } ?? 0
    }

    private var totalHoldingsValue: Double {
        // Reuse the same calculation logic from recalculateTotalPortfolioValue
        let holdings = (portfolio.holdings?.allObjects as? [Holding]) ?? []
        return holdings.reduce(0.0) { sum, holding in
            guard let asset = holding.asset else { return sum }
            // Exclude deposit assets from holdings value calculation
            // Deposit assets are already accounted for in cash balance
            guard asset.assetType != AssetType.deposit.rawValue else { return sum }

            if asset.assetType == AssetType.insurance.rawValue {
                let cashValue = holding.value(forKey: "cashValue") as? Double ?? 0
                return sum + cashValue
            }
            return sum + (holding.quantity * asset.currentPrice)
        }
    }

    private var totalSecuritiesHoldingsValue: Double {
        let holdings = (portfolio.holdings?.allObjects as? [Holding]) ?? []
        return holdings.reduce(0.0) { sum, holding in
            guard let asset = holding.asset else { return sum }
            // Exclude insurance and deposit assets from securities calculation
            guard asset.assetType != AssetType.insurance.rawValue else { return sum }
            guard asset.assetType != AssetType.deposit.rawValue else { return sum }
            return sum + (holding.quantity * asset.currentPrice)
        }
    }

    private var totalCashFromInstitutions: Double {
        return portfolio.totalCashBalance
    }

    private var availableCashBalance: Double {
        return portfolio.availableCashBalance
    }

    private var fixedDepositBalance: Double {
        return portfolio.fixedDepositBalance
    }

    var body: some View {
        HStack(spacing: 15) {
            StatCardView(
                title: localizationManager.localizedString(for: "portfolioDashboard.statCard.totalHoldingsValue"),
                value: currencyService.formatAmount(totalHoldingsValue, in: mainCurrency),
                color: totalHoldingsValue >= 0 ? .green : .red,
                subtitle: "Securities: \(currencyService.formatAmount(totalSecuritiesHoldingsValue, in: mainCurrency))"
            )

            Button(action: {
                onCashTapped(.demandCash)
            }) {
                StatCardView(
                    title: localizationManager.localizedString(for: "portfolioDashboard.statCard.totalCash"),
                    value: currencyService.formatAmount(totalCashFromInstitutions, in: mainCurrency),
                    color: totalCashFromInstitutions >= 0 ? .blue : .red,
                    subtitle: "Available: \(currencyService.formatAmount(availableCashBalance, in: mainCurrency))\nFixed Deposits: \(currencyService.formatAmount(fixedDepositBalance, in: mainCurrency))"
                )
            }
            .buttonStyle(PlainButtonStyle())

            StatCardView(
                title: localizationManager.localizedString(for: "portfolioDashboard.statCard.unrealizedPnL"),
                value: currencyService.formatAmount(totalGainLoss, in: mainCurrency),
                color: totalGainLoss >= 0 ? .green : .red,
                subtitle: "Securities: \(currencyService.formatAmount(totalSecuritiesGainLoss, in: mainCurrency))"
            )

            StatCardView(
                title: localizationManager.localizedString(for: "portfolioDashboard.statCard.totalDividendsInterest"),
                value: currencyService.formatAmount(totalDividends, in: mainCurrency),
                color: totalDividends >= 0 ? .green : .red,
                subtitle: nil
            )
        }
        .padding(.horizontal)
        .padding(.top, -8)
    }
}

struct StatCardView: View {
    let title: String
    let value: String
    let color: Color
    let subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)

            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(color)

            if let subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 65, maxHeight: 65, alignment: .topLeading)
        .padding(8)
        .background(Color(.systemBackground))
        .cornerRadius(8)
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

#Preview {
    NavigationView {
        PortfolioDashboardView(portfolio: PersistenceController.preview.container.viewContext.registeredObjects.first(where: { $0 is Portfolio }) as! Portfolio)
    }
    .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
