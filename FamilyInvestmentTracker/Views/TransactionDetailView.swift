import SwiftUI
import Foundation
import CoreData

struct TransactionDetailView: View {
    @ObservedObject var transaction: Transaction
    @Environment(\.dismiss) private var dismiss
    
    private var currency: Currency {
        Currency(rawValue: transaction.currency ?? "USD") ?? .usd
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Overview")) {
                    HStack {
                        Text("Type")
                        Spacer()
                        Text(transaction.type ?? "-")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Date")
                        Spacer()
                        Text(transaction.transactionDate ?? Date(), style: .date)
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Amount")
                        Spacer()
                        Text(Formatters.currency(transaction.amount, symbol: currency.symbol))
                            .foregroundColor(.primary)
                            .fontWeight(.semibold)
                    }
                }
                
                Section(header: Text(transaction.type == TransactionType.dividend.rawValue ? "Dividend Source" : "Asset")) {
                    HStack {
                        Text("Symbol")
                        Spacer()
                        Text(transaction.asset?.symbol ?? "-")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Name")
                        Spacer()
                        Text(transaction.asset?.name ?? "-")
                            .foregroundColor(.secondary)
                    }
                    if transaction.type != TransactionType.dividend.rawValue {
                        HStack {
                            Text("Quantity")
                            Spacer()
                            Text(Formatters.decimal(transaction.quantity))
                                .foregroundColor(.secondary)
                        }
                        HStack {
                            Text("Price")
                            Spacer()
                            Text(Formatters.currency(transaction.price, symbol: currency.symbol))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Section(header: Text("Costs")) {
                    HStack {
                        Text("Fees")
                        Spacer()
                        Text(Formatters.currency(transaction.fees, symbol: currency.symbol))
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Tax")
                        Spacer()
                        Text(Formatters.currency(transaction.tax, symbol: currency.symbol))
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Institution")
                        Spacer()
                        Text(transaction.tradingInstitution ?? "-")
                            .foregroundColor(.secondary)
                    }
                }
                
                if let notes = transaction.notes, !notes.isEmpty {
                    Section(header: Text("Notes")) {
                        Text(notes)
                    }
                }
            }
            .navigationTitle("Transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}
