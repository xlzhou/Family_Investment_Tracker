import Foundation
import CoreData

extension Transaction {
    /// Generates a stable identifier using the transaction date and a short random suffix.
    static func generateIdentifier(from date: Date = Date()) -> String {
        let timestamp = Transaction.identifierDateFormatter.string(from: date)
        let randomComponent = Transaction.randomSuffix()
        return "TXN-\(timestamp)-\(randomComponent)"
    }

    /// Ensures the transaction has a UUID and human-readable identifier.
    func ensureIdentifiers() {
        if id == nil {
            id = UUID()
        }

        if transactionCode?.isEmpty ?? true {
            let baseDate = transactionDate ?? Date()
            transactionCode = Transaction.generateIdentifier(from: baseDate)
        }
    }

    private static let identifierDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    private static func randomSuffix() -> String {
        let uuid = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        return String(uuid.prefix(6)).uppercased()
    }
}
