import CoreData
import Foundation

struct CashDisciplineService {
    private static let notePrefix = "[CashDiscipline] Linked Transaction "
    private static let detailSeparator = " • "
    private static let noteDivider = " | "
    private static let noteDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    static func companionNoteIdentifier(for transaction: Transaction) -> String? {
        guard let transactionID = transaction.id else { return nil }
        return companionNoteIdentifier(for: transactionID)
    }

    static func companionNoteIdentifier(for transactionID: UUID) -> String {
        "\(notePrefix)\(transactionID.uuidString)"
    }

    static func extractLinkedTransactionID(from note: String) -> UUID? {
        guard note.hasPrefix(notePrefix) else { return nil }
        let remainder = note.dropFirst(notePrefix.count)
        let identifierPortion: Substring
        if let dividerRange = remainder.range(of: noteDivider) {
            identifierPortion = remainder[..<dividerRange.lowerBound]
        } else if let separatorRange = remainder.range(of: " ") {
            identifierPortion = remainder[..<separatorRange.lowerBound]
        } else {
            identifierPortion = remainder
        }
        let trimmed = identifierPortion.trimmingCharacters(in: .whitespacesAndNewlines)
        return UUID(uuidString: trimmed)
    }

    static func companionNote(for transaction: Transaction, companionAmount: Double, currency: Currency) -> String? {
        guard let identifier = companionNoteIdentifier(for: transaction) else { return nil }

        var components: [String] = []

        if let typeRaw = transaction.type,
           let type = TransactionType(rawValue: typeRaw) {
            components.append(type.displayName)
        }

        if let symbol = transaction.asset?.symbol?.trimmingCharacters(in: .whitespacesAndNewlines), !symbol.isEmpty {
            components.append(symbol)
        } else if let name = transaction.asset?.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            components.append(name)
        } else if let institutionName = transaction.tradingInstitution?.trimmingCharacters(in: .whitespacesAndNewlines), !institutionName.isEmpty {
            components.append(institutionName)
        }

        let quantity = transaction.quantity
        if abs(quantity) > 1e-6 {
            let quantityText = String(format: NSLocalizedString("cashDiscipline.qty",
                                                                comment: "Quantity entry for cash discipline companion note"),
                                      Formatters.decimal(quantity))
            components.append(quantityText)
        }

        let price = transaction.price
        if abs(price) > 1e-6 {
            let priceText = String(format: NSLocalizedString("cashDiscipline.price",
                                                             comment: "Price entry for cash discipline companion note"),
                                   Formatters.currency(price, symbol: currency.symbol))
            components.append(priceText)
        }

        let fees = transaction.fees
        if abs(fees) > 1e-6 {
            let feesText = String(format: NSLocalizedString("cashDiscipline.fees",
                                                            comment: "Fees entry for cash discipline companion note"),
                                  Formatters.currency(fees, symbol: currency.symbol))
            components.append(feesText)
        }

        let tax = transaction.tax
        if abs(tax) > 1e-6 {
            let taxText = String(format: NSLocalizedString("cashDiscipline.tax",
                                                           comment: "Tax entry for cash discipline companion note"),
                                 Formatters.currency(tax, symbol: currency.symbol))
            components.append(taxText)
        }

        let settlementDisplay = abs(companionAmount)
        let settlementText = String(format: NSLocalizedString("cashDiscipline.settlement",
                                                               comment: "Settlement entry for cash discipline companion note"),
                                     Formatters.currency(settlementDisplay, symbol: currency.symbol))
        components.append(settlementText)

        if let date = transaction.transactionDate {
            let dateText = String(format: NSLocalizedString("cashDiscipline.date",
                                                            comment: "Date entry for cash discipline companion note"),
                                  noteDateFormatter.string(from: date))
            components.append(dateText)
        }

        guard !components.isEmpty else {
            return identifier
        }

        return identifier + noteDivider + components.joined(separator: detailSeparator)
    }

    static func findCompanionDeposit(for transaction: Transaction, in context: NSManagedObjectContext) -> Transaction? {
        guard let portfolio = transaction.portfolio,
              let transactionID = transaction.id else {
            return nil
        }

        let request: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        request.predicate = NSPredicate(
            format: "portfolio == %@ AND type IN {%@, %@} AND linkedTransactionID == %@",
            portfolio,
            TransactionType.deposit.rawValue,
            TransactionType.depositWithdrawal.rawValue,
            transactionID as CVarArg
        )
        request.fetchLimit = 1

        return try? context.fetch(request).first
    }
}
