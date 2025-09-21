import SwiftUI
import CoreData

struct CashBreakdownView: View {
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
        return institutionSet.filter { $0.getCashBalance(for: portfolio) != 0 }
            .sorted { ($0.name ?? "") < ($1.name ?? "") }
    }

    private var totalCash: Double {
        institutionsWithCash.reduce(0) { $0 + $1.getCashBalance(for: portfolio) }
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

                                        Text("Updated \(institution.value(forKey: "updatedAt") as? Date ?? Date(), style: .relative) ago")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }

                                    Spacer()

                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text(currencyService.formatAmount(institution.getCashBalance(for: portfolio), in: mainCurrency))
                                            .font(.headline)
                                            .foregroundColor(institution.getCashBalance(for: portfolio) >= 0 ? .primary : .red)

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
    let context = PersistenceController.preview.container.viewContext
    if let portfolio = context.registeredObjects.first(where: { $0 is Portfolio }) as? Portfolio {
        return CashBreakdownView(portfolio: portfolio)
            .environment(\.managedObjectContext, context)
    } else {
        return Text("No preview data available")
    }
}