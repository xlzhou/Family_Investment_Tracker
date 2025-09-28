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
    @State private var selectedAssetType: AssetType? = nil
    @State private var selectedInstitutionID: NSManagedObjectID? = nil
    @State private var sortOption: TransactionSortOption = .dateDescending
    
    private var filteredTransactions: [Transaction] {
        var transactions = allTransactions

        // Apply base filter
        switch selectedFilter {
        case .all:
            break
        case .buy:
            transactions = transactions.filter { $0.type == TransactionType.buy.rawValue }
        case .sell:
            transactions = transactions.filter { $0.type == TransactionType.sell.rawValue }
        case .dividend:
            transactions = transactions.filter { $0.type == TransactionType.dividend.rawValue }
        case .interest:
            transactions = transactions.filter { $0.type == TransactionType.interest.rawValue }
        case .deposit:
            transactions = transactions.filter { t in
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
            transactions = transactions.filter { $0.type == TransactionType.insurance.rawValue }
        }

        // Asset type filter
        if let type = selectedAssetType {
            transactions = transactions.filter { transaction in
                guard let assetTypeRaw = transaction.asset?.assetType else { return false }
                return assetTypeRaw == type.rawValue
            }
        }

        // Institution filter
        if let institutionID = selectedInstitutionID,
           let institution = try? viewContext.existingObject(with: institutionID) as? Institution {
            transactions = transactions.filter { transaction in
                if let txnInstitution = transaction.institution {
                    return txnInstitution.objectID == institution.objectID
                }
                if let asset = transaction.asset {
                    return InstitutionAssetService.shared.isAssetAvailableAt(asset: asset, institution: institution, context: viewContext)
                }
                return false
            }
        }

        return sortTransactions(transactions)
    }

    private var allTransactions: [Transaction] {
        let transactions = (portfolio.transactions?.allObjects as? [Transaction]) ?? []
        ensureTransactionIdentifiersIfNeeded(for: transactions)
        return transactions
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

            if !allTransactions.isEmpty {
                filterBar
                    .padding(.bottom, 8)
            }

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
                print("❌ Error deleting transaction: \(error)")
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

private extension TransactionsView {
    enum TransactionSortOption: String, CaseIterable {
        case dateDescending
        case dateAscending
        case netAmountDescending
        case netAmountAscending

        var displayName: String {
            switch self {
            case .dateDescending: return "Date ▾"
            case .dateAscending: return "Date ▴"
            case .netAmountDescending: return "Net Amount ▾"
            case .netAmountAscending: return "Net Amount ▴"
            }
        }
    }

    var filterBar: some View {
        HStack(spacing: 12) {
            Menu {
                Button("All Asset Types") { selectedAssetType = nil }
                ForEach(availableAssetTypes, id: \.self) { type in
                    Button(type.displayName) { selectedAssetType = type }
                }
            } label: {
                HStack {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                    Text(selectedAssetType?.displayName ?? "All Types")
                }
                .font(.caption)
                .padding(8)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(8)
            }

            Menu {
                Button("All Institutions") { selectedInstitutionID = nil }
                ForEach(availableInstitutions, id: \.objectID) { institution in
                    Button(institution.name ?? "Unknown") { selectedInstitutionID = institution.objectID }
                }
            } label: {
                HStack {
                    Image(systemName: "building.columns")
                    Text(selectedInstitutionLabel)
                }
                .font(.caption)
                .padding(8)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(8)
            }

            Menu {
                ForEach(TransactionSortOption.allCases, id: \.self) { option in
                    Button(option.displayName) { sortOption = option }
                }
            } label: {
                HStack {
                    Image(systemName: "arrow.up.arrow.down")
                    Text(sortOption.displayName)
                }
                .font(.caption)
                .padding(8)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(8)
            }

            if selectedAssetType != nil || selectedInstitutionID != nil || sortOption != .dateDescending {
                Button("Clear") {
                    selectedAssetType = nil
                    selectedInstitutionID = nil
                    sortOption = .dateDescending
                }
                .font(.caption)
            }

            Spacer()
        }
        .padding(.horizontal)
    }

    var availableAssetTypes: [AssetType] {
        let types = allTransactions.compactMap { txn -> AssetType? in
            guard let typeRaw = txn.asset?.assetType else { return nil }
            return AssetType(rawValue: typeRaw)
        }
        return Array(Set(types)).sorted { $0.displayName < $1.displayName }
    }

    var availableInstitutions: [Institution] {
        var seen = Set<NSManagedObjectID>()
        var results: [Institution] = []

        for transaction in allTransactions {
            if let institution = transaction.institution, seen.insert(institution.objectID).inserted {
                results.append(institution)
            }
        }

        return results.sorted { ($0.name ?? "") < ($1.name ?? "") }
    }

    var selectedInstitutionLabel: String {
        guard let institutionID = selectedInstitutionID,
              let institution = try? viewContext.existingObject(with: institutionID) as? Institution else {
            return "All Institutions"
        }
        return institution.name ?? "All Institutions"
    }

    func sortTransactions(_ transactions: [Transaction]) -> [Transaction] {
        switch sortOption {
        case .dateDescending:
            return transactions.sorted { ($0.transactionDate ?? Date.distantPast) > ($1.transactionDate ?? Date.distantPast) }
        case .dateAscending:
            return transactions.sorted { ($0.transactionDate ?? Date.distantPast) < ($1.transactionDate ?? Date.distantPast) }
        case .netAmountDescending:
            return transactions.sorted { netValue(for: $0) > netValue(for: $1) }
        case .netAmountAscending:
            return transactions.sorted { netValue(for: $0) < netValue(for: $1) }
        }
    }

    func netValue(for transaction: Transaction) -> Double {
        guard let type = TransactionType(rawValue: transaction.type ?? "") else {
            return transaction.amount - transaction.fees - transaction.tax
        }

        switch type {
        case .buy:
            return transaction.amount + transaction.fees + transaction.tax
        case .sell:
            return transaction.amount - transaction.fees - transaction.tax
        default:
            return transaction.amount - transaction.fees - transaction.tax
        }
    }
}

struct TransactionRowView: View {
    @ObservedObject var transaction: Transaction
    
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
        guard let type = transactionType else {
            return transaction.amount - transaction.fees - transaction.tax
        }

        switch type {
        case .buy:
            return transaction.amount + transaction.fees + transaction.tax
        case .sell:
            return transaction.amount - transaction.fees - transaction.tax
        default:
            return transaction.amount - transaction.fees - transaction.tax
        }
    }

    private var depositSymbolLabel: String? {
        guard transactionType == .deposit else { return nil }
        let symbol = transaction.asset?.symbol ?? transaction.asset?.name
        let trimmed = symbol?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            return trimmed
        }
        return nil
    }

    private var depositInstitutionLabel: String? {
        guard transactionType == .deposit else { return nil }
        let primary = transaction.tradingInstitution?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let primary, !primary.isEmpty {
            return primary
        }

        let fallback = (transaction.value(forKey: "institution") as? Institution)?.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let fallback, !fallback.isEmpty {
            return fallback
        }
        return nil
    }

    private var insuranceSymbolLabel: String? {
        guard transactionType == .insurance else { return nil }
        let symbol = transaction.asset?.symbol?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let symbol, !symbol.isEmpty {
            return symbol
        }
        return nil
    }

    private var insuranceNameLabel: String? {
        guard transactionType == .insurance else { return nil }
        let name = transaction.asset?.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let name, !name.isEmpty {
            return name
        }
        return nil
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

                if transactionType == .deposit {
                    if depositSymbolLabel != nil || depositInstitutionLabel != nil {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 2) {
                                if let symbolLabel = depositSymbolLabel {
                                    Text(symbolLabel)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                                if let institutionLabel = depositInstitutionLabel {
                                    Text(institutionLabel)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                            }

                            Spacer()

                            Text(Formatters.currency(netValue, symbol: transactionCurrency.symbol))
                                .font(.headline)
                                .fontWeight(.semibold)
                                .foregroundColor(typeColor)
                        }
                    }
                } else if transactionType == .insurance {
                    if insuranceSymbolLabel != nil || insuranceNameLabel != nil {
                        VStack(alignment: .leading, spacing: 2) {
                            if let symbolLabel = insuranceSymbolLabel {
                                Text(symbolLabel)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            if let nameLabel = insuranceNameLabel {
                                Text(nameLabel)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    } else {
                        Text("Insurance")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                } else if let asset = transaction.asset {
                    Text(asset.name ?? asset.symbol ?? "N/A")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                if transactionType != .deposit {
                    HStack {
                        if transaction.quantity > 1 {
                            Text("\(Formatters.decimal(transaction.quantity, fractionDigits: 5)) @ \(Formatters.currency(transaction.price, symbol: transactionCurrency.symbol))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Text(Formatters.currency(netValue, symbol: transactionCurrency.symbol))
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(typeColor)
                    }
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
