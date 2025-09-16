import SwiftUI
import CoreData
import Foundation

struct TransactionsView: View {
    @ObservedObject var portfolio: Portfolio
    @Environment(\.managedObjectContext) private var viewContext
    
    @State private var selectedFilter = TransactionFilter.all
    @State private var selectedTransaction: Transaction?
    
    private var filteredTransactions: [Transaction] {
        let transactions = (portfolio.transactions?.allObjects as? [Transaction]) ?? []
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
    }
    
    private func deleteTransactions(offsets: IndexSet) {
        withAnimation {
            offsets.map { filteredTransactions[$0] }.forEach(viewContext.delete)
            
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
                
                HStack {
                    if transaction.quantity > 1 {
                        Text("\(Formatters.decimal(transaction.quantity)) @ \(Formatters.currency(transaction.price))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Text(Formatters.currency(transaction.amount))
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
