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
            return type == .sell || type == .dividend || type == .interest || type == .deposit || type == .depositWithdrawal
        }
    }

    private var totalRealized: Double {
        // Option 1: (sold assets' income-included P&L) + deposit interest
        // Excludes "Dividends & Interest" section to avoid double counting

        var total: Double = 0

        // Add sold assets' income-included P&L
        let soldAssets = getAssetsWithRealizedTransactions()
        total += soldAssets.reduce(0) { $0 + $1.incomeIncludedPnL }

        // Add deposit interest
        let depositInterest = getDepositInterest()
        total += depositInterest.reduce(0) { $0 + $1.realizedPnL }

        return total
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
        let assetsWithRealized = getAssetsWithRealizedTransactions()

        for assetData in assetsWithRealized {
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
        let depositInterest = getDepositInterest()
        for depositItem in depositInterest {
            groups["Deposits", default: []].append(depositItem)
        }

        // Add pure dividends & interest (not tied to specific holdings)
        let pureIncome = getPureDividendsAndInterest()
        for incomeItem in pureIncome {
            groups["Dividends & Interest", default: []].append(incomeItem)
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
                        Text("Includes: sold assets P&L + dividends/interest from sold assets + deposit interest")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // Asset Type Groups (only show groups with items)
                ForEach(["Stocks", "ETFs", "Bonds", "Mutual Funds", "Cryptocurrency", "Precious Metals", "Insurance", "Structured Products", "Other", "Deposits", "Dividends & Interest"], id: \.self) { groupName in
                    if let items = groupedByAssetType[groupName], !items.isEmpty {
                        Section(header: HStack {
                            Text(groupName)
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
        case .deposit, .depositWithdrawal:
            // Only count positive deposit amounts as interest income
            if transaction.amount > 0 {
                let net = transaction.amount - transaction.fees - transaction.tax
                return convertToPortfolioCurrency(net, currencyCode: transaction.currency)
            }
            return 0
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

    private func getAssetsWithRealizedTransactions() -> [AssetRealizedData] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: startDate)
        let endStart = calendar.startOfDay(for: endDate)
        guard let end = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: endStart) else {
            return []
        }

        var assetDataMap: [Asset: AssetRealizedData] = [:]

        // Only get SELL transactions and dividend/interest for sold assets within date range
        let sellTransactions = allTransactions.filter { transaction in
            guard let date = transaction.transactionDate else { return false }
            guard date >= start && date <= end else { return false }
            return TransactionType(rawValue: transaction.type ?? "") == .sell
        }

        // For each sell transaction, collect the realized P&L
        for transaction in sellTransactions {
            guard let asset = transaction.asset else { continue }

            if assetDataMap[asset] == nil {
                assetDataMap[asset] = AssetRealizedData(asset: asset, realizedPnL: 0, incomeAmount: 0, incomeIncludedPnL: 0)
            }

            let realizedGain = transaction.realizedGainAmount
            assetDataMap[asset]?.realizedPnL += realizedGain
            assetDataMap[asset]?.incomeIncludedPnL += realizedGain
        }

        // Now add dividends/interest ONLY for assets that were sold in this period
        let soldAssets = Set(assetDataMap.keys)
        let incomeTransactions = allTransactions.filter { transaction in
            guard let date = transaction.transactionDate else { return false }
            guard date >= start && date <= end else { return false }
            guard let asset = transaction.asset else { return false }
            guard soldAssets.contains(asset) else { return false } // Only for sold assets

            let type = TransactionType(rawValue: transaction.type ?? "")
            return type == .dividend || type == .interest
        }

        for transaction in incomeTransactions {
            guard let asset = transaction.asset else { continue }
            let net = transaction.amount - transaction.fees - transaction.tax
            let convertedAmount = convertToPortfolioCurrency(net, currencyCode: transaction.currency)
            assetDataMap[asset]?.incomeAmount += convertedAmount
            assetDataMap[asset]?.incomeIncludedPnL += convertedAmount
        }

        return Array(assetDataMap.values).filter { $0.realizedPnL != 0 || $0.incomeIncludedPnL != 0 }
    }

    private func getDepositInterest() -> [AssetGroupItem] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: startDate)
        let endStart = calendar.startOfDay(for: endDate)
        guard let end = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: endStart) else {
            return []
        }

        var depositGroups: [String: Double] = [:]

        // Get INTEREST transactions only (not principal deposits)
        let interestTransactions = allTransactions.filter { transaction in
            guard let date = transaction.transactionDate else { return false }
            guard date >= start && date <= end else { return false }

            let type = TransactionType(rawValue: transaction.type ?? "")
            return type == .interest
        }

        for transaction in interestTransactions {
            let institutionName = transaction.institution?.name ?? "Unknown Institution"

            // Determine if this is from a fixed deposit or demand deposit
            let isFromFixedDeposit = transaction.asset?.assetType == AssetType.deposit.rawValue &&
                                   transaction.asset?.isFixedDeposit == true
            let depositType = isFromFixedDeposit ? "Fixed Deposits" : "Demand Deposits"
            let key = "\(institutionName) - \(depositType)"

            let net = transaction.amount - transaction.fees - transaction.tax
            let convertedAmount = convertToPortfolioCurrency(net, currencyCode: transaction.currency)
            depositGroups[key, default: 0] += convertedAmount
        }

        return depositGroups.map { key, amount in
            AssetGroupItem(
                asset: nil,
                symbol: key,
                name: "Interest Income",
                realizedPnL: amount,
                incomeAmount: 0, // For deposits, the amount IS the income
                incomeIncludedPnL: amount
            )
        }.sorted { $0.symbol < $1.symbol }
    }

    private func getPureDividendsAndInterest() -> [AssetGroupItem] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: startDate)
        let endStart = calendar.startOfDay(for: endDate)
        guard let end = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: endStart) else {
            return []
        }

        var incomeGroups: [Asset: Double] = [:]

        // Get dividend/interest transactions for assets with no sells in period
        let incomeTransactions = allTransactions.filter { transaction in
            guard let date = transaction.transactionDate else { return false }
            guard date >= start && date <= end else { return false }

            let type = TransactionType(rawValue: transaction.type ?? "")
            return type == .dividend || type == .interest
        }

        for transaction in incomeTransactions {
            guard let asset = transaction.asset else { continue }

            // Check if this asset has any sell transactions in the period
            let hasSells = allTransactions.contains { sellTransaction in
                guard let sellDate = sellTransaction.transactionDate else { return false }
                guard sellDate >= start && sellDate <= end else { return false }
                guard sellTransaction.asset == asset else { return false }
                return TransactionType(rawValue: sellTransaction.type ?? "") == .sell
            }

            // Only include in pure income if no sells occurred (these are still active holdings)
            if !hasSells {
                let net = transaction.amount - transaction.fees - transaction.tax
                let convertedAmount = convertToPortfolioCurrency(net, currencyCode: transaction.currency)
                incomeGroups[asset, default: 0] += convertedAmount
            }
        }

        return incomeGroups.map { asset, amount in
            AssetGroupItem(
                asset: asset,
                symbol: asset.symbol ?? "Unknown",
                name: asset.name ?? "Unknown Asset",
                realizedPnL: 0, // No sells, so no realized P&L
                incomeAmount: amount,
                incomeIncludedPnL: amount
            )
        }.sorted { $0.symbol < $1.symbol }
    }
}

// MARK: - Supporting Data Structures

struct AssetRealizedData {
    let asset: Asset
    var realizedPnL: Double
    var incomeAmount: Double
    var incomeIncludedPnL: Double
}

struct AssetGroupItem {
    let asset: Asset?
    let symbol: String
    let name: String
    let realizedPnL: Double
    let incomeAmount: Double
    let incomeIncludedPnL: Double
}
