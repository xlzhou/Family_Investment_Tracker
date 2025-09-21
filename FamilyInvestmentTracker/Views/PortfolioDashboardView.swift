import SwiftUI
import Foundation
import CoreData
import Charts

struct PortfolioDashboardView: View {
    @ObservedObject var portfolio: Portfolio
    @Environment(\.managedObjectContext) private var viewContext
    
    @State private var showingAddTransaction = false
    @State private var showingPortfolioSettings = false
    @State private var showingCloudShare = false
    @State private var showingShareSetup = false
    @State private var isPreparingShare = false
    @State private var shareSetupError: String?
    @State private var selectedTab = 0
    @State private var showingCashBreakdown = false
    @StateObject private var viewModel = PortfolioViewModel()
    @StateObject private var ownershipService = PortfolioOwnershipService.shared
    
    var body: some View {
        VStack(spacing: 16) {
            // Header with portfolio value
            PortfolioHeaderView(portfolio: portfolio)
            
            // Quick Stats
            QuickStatsView(portfolio: portfolio, showingCashBreakdown: $showingCashBreakdown)
                .padding(.top, -8)
            
            // Tab Selection
            Picker("View", selection: $selectedTab) {
                Text("Holdings").tag(0)
                Text("Transactions").tag(1)
                Text("Analytics").tag(2)
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.horizontal)
            .padding(.top, -8)
            
            // Tab Content
            Group {
                switch selectedTab {
                case 0:
                    HoldingsView(portfolio: portfolio)
                case 1:
                    TransactionsView(portfolio: portfolio)
                case 2:
                    AnalyticsView(portfolio: portfolio)
                default:
                    HoldingsView(portfolio: portfolio)
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
                    if ownershipService.canSharePortfolio(portfolio) {
                        Button(action: {
                            handleShareButtonTap()
                        }) {
                            Image(systemName: "person.2")
                        }
                    }

                    Button(action: {
                        showingAddTransaction = true
                    }) {
                        Image(systemName: "plus")
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
                context: viewContext
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
        .sheet(isPresented: $showingCashBreakdown) {
            CashBreakdownViewInline(portfolio: portfolio)
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
}

private struct ShareSetupSheet: View {
    let portfolioName: String
    let isPreparingShare: Bool
    let errorMessage: String?
    let onCancel: () -> Void
    let onStartSharing: () -> Void

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.blue)

                Text("Share \(portfolioName)")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Invite family members to collaborate on this portfolio. You'll be able to choose who has access in the next step.")
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
                        Text("Start Sharing")
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
            .navigationTitle("Share Portfolio")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onCancel)
                        .disabled(isPreparingShare)
                }
            }
        }
    }
}

struct PortfolioHeaderView: View {
    @ObservedObject var portfolio: Portfolio
    @StateObject private var currencyService = CurrencyService.shared
    
    private var mainCurrency: Currency {
        Currency(rawValue: portfolio.mainCurrency ?? "USD") ?? .usd
    }

    private var totalCashFromInstitutions: Double {
        // Get all institutions that have transactions in this portfolio
        let transactions = (portfolio.transactions?.allObjects as? [Transaction]) ?? []
        let institutionSet = Set(transactions.compactMap { $0.institution })

        return institutionSet.reduce(0) { $0 + $1.cashBalanceSafe }
    }

    private var totalValueInMainCurrency: Double {
        // Calculate total value by converting all holdings to main currency
        let holdingsTotal = portfolio.holdings?.compactMap { $0 as? Holding }.reduce(0.0) { result, holding in
            guard let asset = holding.asset else { return result }
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
            Text("Total Value")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Text(currencyService.formatAmount(totalValueInMainCurrency, in: mainCurrency))
                .font(.largeTitle)
                .fontWeight(.bold)
            
            HStack(spacing: 20) {
                VStack {
                    Text("Holdings")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(portfolio.holdings?.count ?? 0)")
                        .font(.title3)
                        .fontWeight(.semibold)
                }
                
                VStack {
                    Text("Transactions")
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
        .padding(.horizontal)
    }
}

struct QuickStatsView: View {
    @ObservedObject var portfolio: Portfolio
    @Binding var showingCashBreakdown: Bool
    @StateObject private var currencyService = CurrencyService.shared
    
    private var mainCurrency: Currency {
        Currency(rawValue: portfolio.mainCurrency ?? "USD") ?? .usd
    }
    
    private var totalGainLoss: Double {
        portfolio.holdings?.compactMap { $0 as? Holding }.reduce(0) { result, holding in
            guard let asset = holding.asset else { return result }
            let currentValue = holding.quantity * asset.currentPrice
            let costBasis = holding.quantity * holding.averageCostBasis
            return result + (currentValue - costBasis)
        } ?? 0
    }
    
    private var totalDividends: Double {
        portfolio.holdings?.compactMap { $0 as? Holding }.reduce(0) { $0 + $1.totalDividends } ?? 0
    }

    private var totalCashFromInstitutions: Double {
        // Get all institutions that have transactions in this portfolio
        let transactions = (portfolio.transactions?.allObjects as? [Transaction]) ?? []
        let institutionSet = Set(transactions.compactMap { $0.institution })

        return institutionSet.reduce(0) { $0 + $1.cashBalanceSafe }
    }
    
    var body: some View {
        HStack(spacing: 15) {
            StatCardView(
                title: "Unrealized P&L",
                value: currencyService.formatAmount(totalGainLoss, in: mainCurrency),
                color: totalGainLoss >= 0 ? .green : .red
            )
            
            StatCardView(
                title: "Total Dividends",
                value: currencyService.formatAmount(totalDividends, in: mainCurrency),
                color: .blue
            )

            Button(action: {
                showingCashBreakdown = true
            }) {
                StatCardView(
                    title: "Cash",
                    value: currencyService.formatAmount(totalCashFromInstitutions, in: mainCurrency),
                    color: .gray
                )
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal)
    }
}

struct StatCardView: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(10)
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

struct CashBreakdownViewInline: View {
    @ObservedObject var portfolio: Portfolio
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @StateObject private var currencyService = CurrencyService.shared

    private var mainCurrency: Currency {
        Currency(rawValue: portfolio.mainCurrency ?? "USD") ?? .usd
    }

    private var institutionsWithCash: [Institution] {
        // Get all institutions that have transactions in this portfolio
        let transactions = (portfolio.transactions?.allObjects as? [Transaction]) ?? []
        let institutionSet = Set(transactions.compactMap { $0.institution })

        // Filter to only show institutions with non-zero cash balance
        return institutionSet.filter { $0.cashBalanceSafe != 0 }
            .sorted { ($0.name ?? "") < ($1.name ?? "") }
    }

    private var totalCash: Double {
        institutionsWithCash.reduce(0) { $0 + $1.cashBalanceSafe }
    }

    var body: some View {
        NavigationView {
            VStack {
                if institutionsWithCash.isEmpty {
                    // Empty state
                    VStack(spacing: 16) {
                        Image(systemName: "banknote")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)

                        Text("No Cash Holdings")
                            .font(.title2)
                            .fontWeight(.medium)

                        Text("Cash balances will appear here when you make deposit transactions.")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // Cash breakdown list
                    List {
                        Section(header: Text("Cash by Institution")) {
                            ForEach(institutionsWithCash, id: \.objectID) { institution in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(institution.name ?? "Unknown Institution")
                                            .font(.headline)

                                        Text("Last updated recently")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }

                                    Spacer()

                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text(currencyService.formatAmount(institution.cashBalanceSafe, in: mainCurrency))
                                            .font(.headline)
                                            .foregroundColor(institution.cashBalanceSafe >= 0 ? .primary : .red)

                                        Text(mainCurrency.displayName)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }

                        Section(footer: Text("Total cash is calculated by summing all institution cash balances.")) {
                            HStack {
                                Text("Total Cash")
                                    .font(.headline)
                                    .fontWeight(.semibold)

                                Spacer()

                                Text(currencyService.formatAmount(totalCash, in: mainCurrency))
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(totalCash >= 0 ? .primary : .red)
                            }
                            .padding(.vertical, 8)
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                        }
                    }
                }
            }
            .navigationTitle("Cash Holdings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    NavigationView {
        PortfolioDashboardView(portfolio: PersistenceController.preview.container.viewContext.registeredObjects.first(where: { $0 is Portfolio }) as! Portfolio)
    }
    .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
