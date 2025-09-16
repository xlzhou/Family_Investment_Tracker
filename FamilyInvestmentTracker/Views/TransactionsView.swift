import SwiftUI
import CoreData
import Foundation

struct TransactionsView: View {
    @ObservedObject var portfolio: Portfolio
    @Environment(\.managedObjectContext) private var viewContext
    private let currencyService = CurrencyService.shared
    
    @State private var selectedFilter = TransactionFilter.all
    @State private var selectedTransaction: Transaction?
    @State private var showingDeleteConfirmation = false
    @State private var transactionToDelete: Transaction?
    
    private var portfolioCurrency: Currency {
        Currency(rawValue: portfolio.mainCurrency ?? "USD") ?? .usd
    }
    
    private var filteredTransactions: [Transaction] {
        let transactions = (portfolio.transactions?.allObjects as? [Transaction]) ?? []
        ensureTransactionIdentifiersIfNeeded(for: transactions)
        print("📊 Found \(transactions.count) total transactions for portfolio \(portfolio.name ?? "Unknown")")
        let sorted = transactions.sorted { ($0.transactionDate ?? Date.distantPast) > ($1.transactionDate ?? Date.distantPast) }
        
        switch selectedFilter {
        case .all:
            return sorted
        case .buy:
            return sorted.filter { $0.type == TransactionType.buy.rawValue }
        case .sell:
            return sorted.filter { $0.type == TransactionType.sell.rawValue }
        case .dividend:
            return sorted.filter { $0.type == TransactionType.dividend.rawValue }
        case .interest:
            return sorted.filter { $0.type == TransactionType.interest.rawValue }
        case .deposit:
            return sorted.filter { t in
                let tType = TransactionType(rawValue: t.type ?? "")
                let fees = t.fees
                let tax = t.tax
                switch tType {
                case .some(.deposit):
                    return true
                case .some(.sell):
                    return (t.quantity * t.price - fees - tax) > 0
                case .some(.dividend), .some(.interest):
                    return (t.amount - fees - tax) > 0
                default:
                    return false
                }
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Filter Picker
            Picker("Filter", selection: $selectedFilter) {
                ForEach(TransactionFilter.allCases, id: \.self) { filter in
                    Text(filter.displayName).tag(filter)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding()
            
            // Transactions List
            if filteredTransactions.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 50))
                        .foregroundColor(.secondary)
                    
                    Text("No Transactions")
                        .font(.title3)
                        .fontWeight(.medium)
                    
                    Text("Add your first transaction using the + button")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                List {
                    ForEach(filteredTransactions, id: \.objectID) { transaction in
                        TransactionRowView(transaction: transaction)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedTransaction = transaction
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button("Delete", role: .destructive) {
                                    transactionToDelete = transaction
                                    showingDeleteConfirmation = true
                                }
                                .tint(.red)
                            }
                    }
                    .onDelete(perform: deleteTransactions)
                }
                .listStyle(PlainListStyle())
            }
        }
        .sheet(isPresented: Binding(get: { selectedTransaction != nil }, set: { if !$0 { selectedTransaction = nil } })) {
            if let txn = selectedTransaction {
                TransactionDetailView(transaction: txn)
            }
        }
        .alert("Delete Transaction", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                transactionToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let transaction = transactionToDelete {
                    deleteTransaction(transaction)
                }
                transactionToDelete = nil
            }
        } message: {
            if let transaction = transactionToDelete {
                Text("Are you sure you want to delete this \(transaction.type?.lowercased() ?? "transaction")? This action cannot be undone.")
            }
        }
    }
    
    private func deleteTransaction(_ transaction: Transaction) {
        withAnimation {
            // Reverse the transaction's impact on portfolio before deleting
            reverseTransactionImpact(transaction)

            viewContext.delete(transaction)

            do {
                try viewContext.save()
            } catch {
                print("Error deleting transaction: \(error)")
            }
        }
    }

    private func ensureTransactionIdentifiersIfNeeded(for transactions: [Transaction]) {
        var updated = false

        for transaction in transactions {
            let previousCode = transaction.transactionCode
            let previousId = transaction.id
            transaction.ensureIdentifiers()

            if transaction.transactionCode != previousCode || transaction.id != previousId {
                updated = true
            }
        }

        if updated && viewContext.hasChanges {
            do {
                try viewContext.save()
            } catch {
                print("Error ensuring transaction identifiers: \(error)")
            }
        }
    }

    private func deleteTransactions(offsets: IndexSet) {
        withAnimation {
            let transactionsToDelete = offsets.map { filteredTransactions[$0] }

            // Reverse each transaction's impact on portfolio before deleting
            transactionsToDelete.forEach { transaction in
                reverseTransactionImpact(transaction)
            }

            transactionsToDelete.forEach(viewContext.delete)

            do {
                try viewContext.save()
            } catch {
                print("Error deleting transactions: \(error)")
            }
        }
    }

    private func reverseTransactionImpact(_ transaction: Transaction) {
        guard let transactionType = TransactionType(rawValue: transaction.type ?? "") else { return }

        let isAmountOnly = transactionType == .dividend || transactionType == .interest || transactionType == .deposit || transactionType == .withdrawal
        let transactionCurrency = Currency(rawValue: transaction.currency ?? portfolioCurrency.rawValue) ?? portfolioCurrency
        let cashDisciplineEnabled = portfolio.enforcesCashDisciplineEnabled
        let institution = transaction.institution

        if isAmountOnly {
            // Reverse cash movements
            let originalNetCash = transaction.amount - transaction.fees - transaction.tax
            let netCash = currencyService.convertAmount(originalNetCash, from: transactionCurrency, to: portfolioCurrency)
            switch transactionType {
            case .deposit:
                portfolio.addToCash(-netCash) // Reverse the deposit
                if cashDisciplineEnabled, let institution = institution {
                    institution.cashBalanceSafe -= netCash
                }
            case .withdrawal:
                portfolio.addToCash(netCash) // Reverse the withdrawal
                if cashDisciplineEnabled, let institution = institution {
                    institution.cashBalanceSafe += netCash
                }
            case .dividend, .interest:
                portfolio.addToCash(-netCash) // Reverse the dividend/interest
                // Also reverse dividend tracking on holding if there's an associated asset
                if let asset = transaction.asset,
                   let holding = findHolding(for: asset) {
                    let dividendValue = currencyService.convertAmount(transaction.amount, from: transactionCurrency, to: portfolioCurrency)
                    holding.totalDividends = max(0, holding.totalDividends - dividendValue)
                    holding.updatedAt = Date()
                }
            default:
                break
            }
        } else {
            // Reverse asset transactions (buy/sell)
            if let asset = transaction.asset {
                reverseHoldingImpact(for: asset, transaction: transaction, transactionType: transactionType)

                // Reverse cash movement for sells
                if transactionType == .sell {
                    let originalProceeds = (transaction.quantity * transaction.price) - transaction.fees - transaction.tax
                    let netProceeds = currencyService.convertAmount(originalProceeds, from: transactionCurrency, to: portfolioCurrency)
                    if netProceeds != 0 {
                        portfolio.addToCash(-netProceeds) // Reverse the cash from sale
                        if cashDisciplineEnabled, let institution = institution {
                            institution.cashBalanceSafe -= netProceeds
                        }
                    }
                } else if transactionType == .buy {
                    let originalCost = (transaction.quantity * transaction.price) + transaction.fees + transaction.tax
                    let cost = currencyService.convertAmount(originalCost, from: transactionCurrency, to: portfolioCurrency)
                    if cashDisciplineEnabled {
                        portfolio.addToCash(cost)
                        if let institution = institution {
                            institution.cashBalanceSafe += cost
                        }
                    }
                }
            }
        }

        // Recompute portfolio totals
        recomputePortfolioTotals()
    }

    private func findHolding(for asset: Asset) -> Holding? {
        let request: NSFetchRequest<Holding> = Holding.fetchRequest()
        request.predicate = NSPredicate(format: "asset == %@ AND portfolio == %@", asset, portfolio)
        return try? viewContext.fetch(request).first
    }

    private func reverseHoldingImpact(for asset: Asset, transaction: Transaction, transactionType: TransactionType) {
        guard let holding = findHolding(for: asset) else { return }
        let transactionCurrency = Currency(rawValue: transaction.currency ?? portfolioCurrency.rawValue) ?? portfolioCurrency
        let priceInPortfolio = currencyService.convertAmount(transaction.price, from: transactionCurrency, to: portfolioCurrency)

        switch transactionType {
        case .buy:
            // Reverse buy: subtract quantity and recalculate cost basis
            let transactionCost = transaction.quantity * priceInPortfolio
            let currentTotalCost = holding.quantity * holding.averageCostBasis
            let newQuantity = holding.quantity - transaction.quantity

            if newQuantity > 0 {
                let newTotalCost = currentTotalCost - transactionCost
                holding.averageCostBasis = newTotalCost / newQuantity
                holding.quantity = newQuantity
            } else {
                // If quantity goes to zero or below, reset the holding
                holding.quantity = 0
                holding.averageCostBasis = 0
            }

        case .sell:
            // Reverse sell: add quantity back and reverse realized gains
            holding.quantity += transaction.quantity
            let realizedGain = transaction.quantity * (priceInPortfolio - holding.averageCostBasis)
            holding.realizedGainLoss -= realizedGain

        default:
            break
        }

        holding.updatedAt = Date()
    }

    private func recomputePortfolioTotals() {
        let holdings = (portfolio.holdings?.allObjects as? [Holding]) ?? []
        let totalHoldings = holdings.reduce(0.0) { partial, holding in
            guard let asset = holding.asset else { return partial }
            return partial + (holding.quantity * asset.currentPrice)
        }

        // Use the safe cash balance accessor
        let cashBalance = portfolio.cashBalanceSafe
        portfolio.totalValue = totalHoldings + cashBalance
        portfolio.updatedAt = Date()
    }
}

struct TransactionRowView: View {
    let transaction: Transaction
    
    private var transactionType: TransactionType? {
        TransactionType(rawValue: transaction.type ?? "")
    }
    
    private var transactionCurrency: Currency {
        Currency(rawValue: transaction.currency ?? "USD") ?? .usd
    }
    
    private var typeColor: Color {
        switch transactionType {
        case .buy:
            return .green
        case .sell:
            return .red
        case .dividend, .interest:
            return .blue
        default:
            return .gray
        }
    }
    
    private var typeIcon: String {
        switch transactionType {
        case .buy:
            return "plus.circle.fill"
        case .sell:
            return "minus.circle.fill"
        case .dividend, .interest:
            return "dollarsign.circle.fill"
        default:
            return "circle.fill"
        }
    }

    private var netValue: Double {
        return transaction.amount - transaction.fees - transaction.tax
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Type Icon
            Image(systemName: typeIcon)
                .font(.title2)
                .foregroundColor(typeColor)
                .frame(width: 30)
            
            // Transaction Details
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(transaction.type?.capitalized ?? "Unknown")
                        .font(.headline)
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    Text(transaction.transactionDate ?? Date(), style: .date)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if let asset = transaction.asset {
                    Text(asset.symbol ?? "N/A")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                if let code = transaction.transactionCode {
                    Text(code)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    if transaction.quantity > 1 {
                        Text("\(Formatters.decimal(transaction.quantity)) @ \(Formatters.currency(transaction.price, symbol: transactionCurrency.symbol))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Text(Formatters.currency(netValue, symbol: transactionCurrency.symbol))
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(typeColor)
                }
                
                if let notes = transaction.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

enum TransactionFilter: CaseIterable {
    case all, buy, sell, dividend, interest, deposit
    
    var displayName: String {
        switch self {
        case .all: return "All"
        case .buy: return "Buy"
        case .sell: return "Sell"
        case .dividend: return "Dividend"
        case .interest: return "Interest"
        case .deposit: return "Deposit"
        }
    }
}

#Preview {
    TransactionsView(portfolio: PersistenceController.preview.container.viewContext.registeredObjects.first(where: { $0 is Portfolio }) as! Portfolio)
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
