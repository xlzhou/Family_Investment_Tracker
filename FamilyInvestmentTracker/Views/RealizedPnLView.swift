import SwiftUI
import CoreData

struct RealizedPnLView: View {
    let portfolio: Portfolio
    @Environment(\.managedObjectContext) private var viewContext
    private let currencyService = CurrencyService.shared

    @State private var startDate: Date
    @State private var endDate: Date

    @FetchRequest private var realizedTransactions: FetchedResults<Transaction>

    init(portfolio: Portfolio) {
        self.portfolio = portfolio
        let calendar = Calendar.current
        let now = Date()
        let startOfYear = calendar.date(from: calendar.dateComponents([.year], from: now)) ?? now
        _startDate = State(initialValue: startOfYear)
        _endDate = State(initialValue: now)
        _realizedTransactions = FetchRequest<Transaction>(
            sortDescriptors: [NSSortDescriptor(key: "transactionDate", ascending: false)],
            predicate: NSPredicate(format: "portfolio == %@ AND type IN %@", portfolio, [TransactionType.sell.rawValue, TransactionType.dividend.rawValue, TransactionType.interest.rawValue]),
            animation: .default
        )
    }

    private var portfolioCurrency: Currency {
        Currency(rawValue: portfolio.mainCurrency ?? "USD") ?? .usd
    }

    private var filteredTransactions: [Transaction] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: startDate)
        let endStart = calendar.startOfDay(for: endDate)
        guard let end = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: endStart) else {
            return []
        }

        return realizedTransactions.filter { transaction in
            guard let date = transaction.transactionDate else { return false }
            return date >= start && date <= end
        }
    }

    private var totalRealized: Double {
        filteredTransactions.reduce(0) { partial, transaction in
            partial + realizedAmount(for: transaction)
        }
    }

    private var realizedBySymbol: [(symbol: String, amount: Double)] {
        let grouped = Dictionary(grouping: filteredTransactions) { transaction in
            displaySymbol(for: transaction)
        }

        return grouped.map { key, value in
            let total = value.reduce(0) { partial, transaction in
                partial + realizedAmount(for: transaction)
            }
            return (symbol: key, amount: total)
        }
        .sorted { $0.symbol < $1.symbol }
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

                    if filteredTransactions.isEmpty {
                        Text("No realized gains, dividends, or interest in this period.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if !realizedBySymbol.isEmpty {
                    Section(header: Text("By Symbol")) {
                        ForEach(realizedBySymbol, id: \.symbol) { entry in
                            HStack {
                                Text(entry.symbol)
                                Spacer()
                                Text(Formatters.signedCurrency(entry.amount, symbol: portfolioCurrency.symbol))
                                    .foregroundColor(entry.amount >= 0 ? .green : .red)
                            }
                        }
                    }
                }

                if !filteredTransactions.isEmpty {
                    Section(header: Text("Transactions")) {
                        ForEach(filteredTransactions, id: \.objectID) { transaction in
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
}
