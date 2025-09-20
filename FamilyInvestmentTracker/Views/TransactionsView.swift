import SwiftUI
import CoreData
import Foundation

struct TransactionsView: View {
    @ObservedObject var portfolio: Portfolio
    @Environment(\.managedObjectContext) private var viewContext
    @State private var selectedFilter = TransactionFilter.all
    @State private var selectedTransaction: Transaction?
    @State private var showingDeleteConfirmation = false
    @State private var transactionToDelete: Transaction?
    @State private var showingRealizedPnL = false
    
    private var filteredTransactions: [Transaction] {
        let transactions = (portfolio.transactions?.allObjects as? [Transaction]) ?? []
        ensureTransactionIdentifiersIfNeeded(for: transactions)
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
        case .insurance:
            return sorted.filter { $0.type == TransactionType.insurance.rawValue }
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
                TransactionDetailView(transaction: txn, portfolio: portfolio)
            }
        }
        .sheet(isPresented: $showingRealizedPnL) {
            RealizedPnLView(portfolio: portfolio)
                .environment(\.managedObjectContext, viewContext)
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
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingRealizedPnL = true
                } label: {
                    Label("Realized P&L", systemImage: "chart.bar.doc.horizontal")
                }
            }
        }
    }
    
    private func deleteTransaction(_ transaction: Transaction) {
        withAnimation {
            TransactionImpactService.reverse(transaction, in: portfolio, context: viewContext)
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

            transactionsToDelete.forEach { transaction in
                TransactionImpactService.reverse(transaction, in: portfolio, context: viewContext)
            }

            transactionsToDelete.forEach(viewContext.delete)

            do {
                try viewContext.save()
            } catch {
                print("Error deleting transactions: \(error)")
            }
        }
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
                    Text(asset.name ?? asset.symbol ?? "N/A")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
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
    case all, buy, sell, dividend, interest, deposit, insurance
    
    var displayName: String {
        switch self {
        case .all: return "All"
        case .buy: return "Buy"
        case .sell: return "Sell"
        case .dividend: return "Dividend"
        case .interest: return "Interest"
        case .deposit: return "Deposit"
        case .insurance: return "Insurance"
        }
    }
}

#Preview {
    TransactionsView(portfolio: PersistenceController.preview.container.viewContext.registeredObjects.first(where: { $0 is Portfolio }) as! Portfolio)
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
