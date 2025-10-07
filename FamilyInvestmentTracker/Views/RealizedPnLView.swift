import SwiftUI
import CoreData

struct RealizedPnLView: View {
    let portfolio: Portfolio
    @Environment(\.managedObjectContext) private var viewContext
    private let currencyService = CurrencyService.shared

    @State private var startDate: Date
    @State private var endDate: Date

    @FetchRequest private var allTransactions: FetchedResults<Transaction>

    init(portfolio: Portfolio) {
        self.portfolio = portfolio
        let calendar = Calendar.current
        let now = Date()
        let startOfYear = calendar.date(from: calendar.dateComponents([.year], from: now)) ?? now
        _startDate = State(initialValue: startOfYear)
        _endDate = State(initialValue: now)
        _allTransactions = FetchRequest<Transaction>(
            sortDescriptors: [NSSortDescriptor(key: "transactionDate", ascending: false)],
            predicate: NSPredicate(format: "portfolio == %@", portfolio),
            animation: .default
        )
    }

    private var portfolioCurrency: Currency {
        Currency(rawValue: portfolio.mainCurrency ?? "USD") ?? .usd
    }


    private var filteredRealizedTransactions: [Transaction] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: startDate)
        let endStart = calendar.startOfDay(for: endDate)
        guard let end = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: endStart) else {
            return []
        }

        return allTransactions.filter { transaction in
            guard let date = transaction.transactionDate else { return false }
            guard date >= start && date <= end else { return false }

            let type = TransactionType(rawValue: transaction.type ?? "")
            return type == .sell || type == .dividend || type == .interest
        }
    }

    private var breakdown: RealizedPnLCalculator.Breakdown {
        RealizedPnLCalculator.breakdown(for: portfolio,
                                        startDate: startDate,
                                        endDate: endDate,
                                        context: viewContext)
    }

    private var totalRealized: Double {
        breakdown.total
    }

    // Asset type grouping
    private var groupedByAssetType: [String: [AssetGroupItem]] {
        var groups: [String: [AssetGroupItem]] = [:]

        // Initialize all groups
        groups["Stocks"] = []
        groups["ETFs"] = []
        groups["Bonds"] = []
        groups["Mutual Funds"] = []
        groups["Cryptocurrency"] = []
        groups["Precious Metals"] = []
        groups["Insurance"] = []
        groups["Structured Products"] = []
        groups["Other"] = []
        groups["Deposits"] = []
        groups["Dividends & Interest"] = []

        // Get unique assets with realized transactions
        for assetData in breakdown.soldAssets {
            let groupName = getGroupName(for: assetData.asset)
            let item = AssetGroupItem(
                asset: assetData.asset,
                symbol: assetData.asset.symbol ?? "Unknown",
                name: assetData.asset.name ?? "Unknown Asset",
                realizedPnL: assetData.realizedPnL,
                incomeAmount: assetData.incomeAmount,
                incomeIncludedPnL: assetData.incomeIncludedPnL
            )
            groups[groupName, default: []].append(item)
        }

        // Add deposit interest
        for depositItem in breakdown.depositInterest {
            groups["Deposits", default: []].append(
                AssetGroupItem(
                    asset: nil,
                    symbol: depositItem.symbol,
                    name: "Interest Income",
                    realizedPnL: depositItem.amount,
                    incomeAmount: 0,
                    incomeIncludedPnL: depositItem.amount
                )
            )
        }

        // Add pure dividends & interest (not tied to specific holdings)
        for incomeItem in breakdown.activeIncome {
            groups["Dividends & Interest", default: []].append(
                AssetGroupItem(
                    asset: incomeItem.asset,
                    symbol: incomeItem.symbol,
                    name: incomeItem.name,
                    realizedPnL: 0,
                    incomeAmount: incomeItem.amount,
                    incomeIncludedPnL: incomeItem.amount
                )
            )
        }

        // Sort items within each group
        for key in groups.keys {
            groups[key] = groups[key]?.sorted { $0.symbol < $1.symbol }
        }

        return groups
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Date Range")) {
                    DatePicker("From", selection: $startDate, in: ...Date(), displayedComponents: .date)
                    DatePicker("To", selection: $endDate, in: startDate...Date(), displayedComponents: .date)
                }

                Section(header: Text("Summary")) {
                    HStack {
                        Text("Total Realized P&L")
                        Spacer()
                        Text(Formatters.signedCurrency(totalRealized, symbol: portfolioCurrency.symbol))
                            .fontWeight(.semibold)
                            .foregroundColor(totalRealized >= 0 ? .green : .red)
                    }

                    if totalRealized == 0 {
                        Text("No realized gains or deposit interest in this period.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Includes: sold assets P&L + all dividends/interest + deposit interest")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // Asset Type Groups (only show groups with items)
                ForEach(["Stocks", "ETFs", "Bonds", "Mutual Funds", "Cryptocurrency", "Precious Metals", "Insurance", "Structured Products", "Other", "Deposits", "Dividends & Interest"], id: \.self) { groupName in
                    if let items = groupedByAssetType[groupName], !items.isEmpty {
                        Section(header: HStack {
                            Text(groupName == "Dividends & Interest" ? "Dividends & Interest*" : groupName)
                            Spacer()
                            let groupTotal = items.reduce(0) { $0 + $1.incomeIncludedPnL }
                            Text(Formatters.signedCurrency(groupTotal, symbol: portfolioCurrency.symbol))
                                .font(.caption)
                                .foregroundColor(groupTotal >= 0 ? .green : .red)
                        }) {
                            ForEach(items, id: \.symbol) { item in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.symbol)
                                                .font(.headline)
                                            if item.symbol != item.name && !item.name.isEmpty {
                                                Text(item.name)
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                        Spacer()
                                        VStack(alignment: .trailing, spacing: 2) {
                                            if groupName == "Stocks" || groupName == "ETFs" || groupName == "Bonds" || groupName == "Mutual Funds" || groupName == "Cryptocurrency" || groupName == "Precious Metals" || groupName == "Insurance" || groupName == "Structured Products" || groupName == "Other" {
                                                // For securities: show P&L, Income, Total
                                                Text("P&L: \(Formatters.signedCurrency(item.realizedPnL, symbol: portfolioCurrency.symbol))")
                                                    .font(.caption)
                                                    .foregroundColor(item.realizedPnL >= 0 ? .green : .red)
                                                if item.incomeAmount != 0 {
                                                    Text("Income: \(Formatters.signedCurrency(item.incomeAmount, symbol: portfolioCurrency.symbol))")
                                                        .font(.caption)
                                                        .foregroundColor(item.incomeAmount >= 0 ? .green : .red)
                                                }
                                                Text("Total: \(Formatters.signedCurrency(item.incomeIncludedPnL, symbol: portfolioCurrency.symbol))")
                                                    .font(.subheadline)
                                                    .fontWeight(.semibold)
                                                    .foregroundColor(item.incomeIncludedPnL >= 0 ? .green : .red)
                                            } else {
                                                // For deposits and dividends & interest: show single amount
                                                Text("\(Formatters.signedCurrency(item.incomeIncludedPnL, symbol: portfolioCurrency.symbol))")
                                                    .font(.subheadline)
                                                    .fontWeight(.semibold)
                                                    .foregroundColor(item.incomeIncludedPnL >= 0 ? .green : .red)
                                            }
                                        }
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                }
                // Explanatory note for asterisk
                if let dividendsItems = groupedByAssetType["Dividends & Interest"], !dividendsItems.isEmpty {
                    Section {
                        Text("* Income from active holdings, included in total above")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .italic()
                    }
                }
                if !filteredRealizedTransactions.isEmpty {
                    Section(header: Text("Transactions")) {
                        ForEach(filteredRealizedTransactions, id: \.objectID) { transaction in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(displaySymbol(for: transaction))
                                        .font(.headline)
                                    Spacer()
                                    if let date = transaction.transactionDate {
                                        Text(date, style: .date)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }

                                let realized = realizedAmount(for: transaction)
                                Text(Formatters.signedCurrency(realized, symbol: portfolioCurrency.symbol))
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(realized >= 0 ? .green : .red)

                                if let notes = transaction.notes, !notes.isEmpty {
                                    Text(notes)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                
            }
            .navigationTitle("Realized P&L")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onChange(of: startDate) { _, newValue in
            if newValue > endDate {
                endDate = newValue
            }
        }
        .onChange(of: endDate) { _, newValue in
            if newValue < startDate {
                startDate = newValue
            }
        }
    }

    private func realizedAmount(for transaction: Transaction) -> Double {
        switch TransactionType(rawValue: transaction.type ?? "") {
        case .sell:
            return transaction.realizedGainAmount
        case .dividend, .interest:
            let net = transaction.amount - transaction.fees - transaction.tax
            return convertToPortfolioCurrency(net, currencyCode: transaction.currency)
        default:
            return 0
        }
    }

    private func displaySymbol(for transaction: Transaction) -> String {
        switch TransactionType(rawValue: transaction.type ?? "") {
        case .sell:
            return transaction.asset?.symbol ?? "Unknown"
        case .dividend:
            return "Dividend"
        case .interest:
            return "Interest"
        default:
            return transaction.asset?.symbol ?? transaction.type ?? "Unknown"
        }
    }

    private func convertToPortfolioCurrency(_ amount: Double, currencyCode: String?) -> Double {
        let transactionCurrency = Currency(rawValue: currencyCode ?? portfolioCurrency.rawValue) ?? portfolioCurrency
        return currencyService.convertAmount(amount, from: transactionCurrency, to: portfolioCurrency)
    }


    private func getGroupName(for asset: Asset) -> String {
        guard let assetType = AssetType(rawValue: asset.assetType ?? "") else {
            return "Dividends & Interest"
        }

        switch assetType {
        case .stock:
            return "Stocks"
        case .etf:
            return "ETFs"
        case .bond:
            return "Bonds"
        case .mutualFund:
            return "Mutual Funds"
        case .cryptocurrency:
            return "Cryptocurrency"
        case .preciousMetal:
            return "Precious Metals"
        case .insurance:
            return "Insurance"
        case .structuredProduct:
            return "Structured Products"
        case .other:
            return "Other"
        case .deposit:
            return "Deposits"
        }
    }

}

// MARK: - Supporting Data Structures

struct AssetGroupItem {
    let asset: Asset?
    let symbol: String
    let name: String
    let realizedPnL: Double
    let incomeAmount: Double
    let incomeIncludedPnL: Double
}
