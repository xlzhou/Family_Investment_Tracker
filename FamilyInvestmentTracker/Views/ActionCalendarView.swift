import SwiftUI
import CoreData

struct ActionCalendarView: View {
    @ObservedObject var portfolio: Portfolio
    @Environment(\.managedObjectContext) private var viewContext
    @State private var selectedDate = ActionCalendarView.startOfToday()
    @State private var currentMonth = ActionCalendarView.startOfCurrentMonth()
    @State private var actionDays: [Date: [ActionDayItem]] = [:]
    @State private var hasAlignedToNearestEvent = false

    enum ActionDayType: Hashable {
        case fixedDepositMaturity
        case bondMaturity
        case structuredProductMaturity
        case insuranceMaturity
        case premiumPayment
        case other

        var color: Color {
            switch self {
            case .fixedDepositMaturity: return .orange
            case .bondMaturity: return .purple
            case .structuredProductMaturity: return .teal
            case .insuranceMaturity: return .pink
            case .premiumPayment: return .blue
            case .other: return .green
            }
        }

        var icon: String {
            switch self {
            case .fixedDepositMaturity: return "calendar.badge.clock"
            case .bondMaturity: return "banknote"
            case .structuredProductMaturity: return "chart.pie"
            case .insuranceMaturity: return "shield.lefthalf.filled"
            case .premiumPayment: return "dollarsign.circle"
            case .other: return "exclamationmark.circle"
            }
        }

        var debugLabel: String {
            switch self {
            case .fixedDepositMaturity: return "FixedDepositMaturity"
            case .bondMaturity: return "BondMaturity"
            case .structuredProductMaturity: return "StructuredProductMaturity"
            case .insuranceMaturity: return "InsuranceMaturity"
            case .premiumPayment: return "PremiumPayment"
            case .other: return "Other"
            }
        }
    }

    struct ActionDayItem: Identifiable {
        let id = UUID()
        let date: Date
        let type: ActionDayType
        let title: String
        let assetName: String
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        return calendar
    }

    private static func startOfToday() -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        return calendar.startOfDay(for: Date())
    }

    private static func startOfCurrentMonth() -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let now = calendar.startOfDay(for: Date())
        let components = calendar.dateComponents([.year, .month], from: now)
        return calendar.date(from: components) ?? now
    }

    private func normalizedDate(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    // Month navigation
                    HStack {
                        Button(action: previousMonth) {
                            Image(systemName: "chevron.left")
                                .font(.headline)
                        }

                        Spacer()

                        Text(monthYearString(from: currentMonth))
                            .font(.title2)
                            .fontWeight(.semibold)

                        Spacer()

                        Button(action: nextMonth) {
                            Image(systemName: "chevron.right")
                                .font(.headline)
                        }
                    }
                    .padding(.horizontal)

                    // Weekday headers
                    HStack {
                        ForEach(calendar.shortWeekdaySymbols, id: \.self) { day in
                            Text(day)
                                .font(.caption)
                                .fontWeight(.medium)
                                .frame(maxWidth: .infinity)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal)

                    // Calendar grid
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
                        ForEach(daysInMonth(), id: \.self) { date in
                            CalendarDayView(
                                date: date,
                                isCurrentMonth: isCurrentMonth(date),
                                isToday: calendar.isDateInToday(date),
                                isSelected: calendar.isDate(date, inSameDayAs: selectedDate),
                                actionItems: actionDays[normalizedDate(date)] ?? [],
                                onTap: { selectedDate = normalizedDate(date) }
                            )
                        }
                    }
                    .padding(.horizontal)

                    // Action items for selected date
                    if let selectedDateActions = actionDays[normalizedDate(selectedDate)], !selectedDateActions.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Actions for \(formattedDate(selectedDate))")
                                .font(.headline)
                                .padding(.horizontal)

                            VStack(spacing: 8) {
                                ForEach(selectedDateActions) { action in
                                    ActionItemRow(action: action)
                                }
                            }
                            .padding(.horizontal)
                        }
                    } else {
                        Text("No actions scheduled for \(formattedDate(selectedDate))")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .padding()
                    }

                    if !actionsForCurrentMonth.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("This Month")
                                .font(.headline)
                                .padding(.horizontal)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(actionsForCurrentMonth) { action in
                                        CompactActionChip(action: action)
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                    }

                    if !upcomingActions.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Upcoming Actions")
                                .font(.headline)
                                .padding(.horizontal)

                            VStack(spacing: 8) {
                                ForEach(upcomingActions) { action in
                                    ActionItemRow(action: action)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }

                    Spacer(minLength: 0)
                }
                .padding(.bottom, 24)
            }
            .navigationTitle("Action Calendar")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            selectedDate = normalizedDate(selectedDate)
            hasAlignedToNearestEvent = false
            loadActionDays()
        }
        .onChange(of: currentMonth) { _, _ in
            loadActionDays()
        }
    }

    private func loadActionDays() {
        var updatedActionDays: [Date: [ActionDayItem]] = [:]
        var seenAssets = Set<NSManagedObjectID>()
        let horizonDate = calendar.date(byAdding: .year, value: 10, to: normalizedDate(Date())) ?? normalizedDate(Date())

        func appendAction(date: Date?, type: ActionDayType, title: String, asset: Asset) {
            guard let date = date else { return }
            let normalized = normalizedDate(date)
            let assetName = asset.name ?? asset.symbol ?? "Asset"

            guard normalized <= horizonDate else { return }

            if updatedActionDays[normalized]?.contains(where: { $0.type == type && $0.title == title && $0.assetName == assetName }) == true {
                return
            }

            let item = ActionDayItem(
                date: normalized,
                type: type,
                title: title,
                assetName: assetName
            )
            updatedActionDays[normalized, default: []].append(item)
        }

        func collectAsset(_ asset: Asset?) {
            guard let asset = asset else { return }
            let objectID = asset.objectID
            guard !seenAssets.contains(objectID) else { return }
            seenAssets.insert(objectID)

            if let maturityDate = asset.maturityDate {
                let assetType = AssetType(rawValue: asset.assetType ?? "")
                switch assetType {
                case .some(.deposit) where asset.isFixedDeposit:
                    appendAction(date: maturityDate, type: .fixedDepositMaturity, title: "Fixed Deposit Maturity", asset: asset)
                case .some(.bond):
                    appendAction(date: maturityDate, type: .bondMaturity, title: "Bond Maturity", asset: asset)
                case .some(.structuredProduct):
                    appendAction(date: maturityDate, type: .structuredProductMaturity, title: "Structured Product Maturity", asset: asset)
                case .some(.insurance):
                    appendAction(date: maturityDate, type: .insuranceMaturity, title: "Insurance Maturity", asset: asset)
                default:
                    appendAction(date: maturityDate, type: .other, title: "Maturity Date", asset: asset)
                }
            }

            if let insurance = asset.insurance {
                if let nextPaymentDate = calculateNextPremiumPaymentDate(for: insurance, asset: asset, portfolio: portfolio) {
                    appendAction(date: nextPaymentDate, type: .premiumPayment, title: "Premium Payment Due", asset: asset)
                }

                if let redemptionDate = insurance.value(forKey: "maturityBenefitRedemptionDate") as? Date {
                    appendAction(date: redemptionDate, type: .insuranceMaturity, title: "Insurance Benefit Redemption", asset: asset)
                }
            }
        }

        if let holdings = portfolio.holdings?.allObjects as? [Holding] {
            holdings.forEach { collectAsset($0.asset) }
        }

        let fixedDeposits = FixedDepositService.shared.getFixedDeposits(for: portfolio, context: viewContext)
        fixedDeposits.forEach { collectAsset($0) }

        let transactionRequest: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        transactionRequest.predicate = NSPredicate(format: "portfolio == %@", portfolio)
        transactionRequest.includesPendingChanges = true
        transactionRequest.returnsObjectsAsFaults = false

        if let transactions = try? viewContext.fetch(transactionRequest) {
            transactions.forEach { collectAsset($0.asset) }
        }

        actionDays = updatedActionDays

#if DEBUG
        debugPrintActionDays(updatedActionDays)
#endif

        alignToNearestActionDayIfNeeded()
    }

    private func alignToNearestActionDayIfNeeded() {
        guard !hasAlignedToNearestEvent else { return }
        hasAlignedToNearestEvent = true

        let sortedDates = actionDays.keys.sorted()
        guard !sortedDates.isEmpty else { return }

        let today = normalizedDate(Date())
        let target = sortedDates.first { $0 >= today } ?? sortedDates.last!

        if !calendar.isDate(target, equalTo: currentMonth, toGranularity: .month) {
            let components = calendar.dateComponents([.year, .month], from: target)
            if let monthDate = calendar.date(from: components) {
                currentMonth = monthDate
            }
        }

        selectedDate = target

#if DEBUG
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        print("🔎 ActionCalendar: aligned to nearest action month \(formatter.string(from: target))")
#endif
    }

#if DEBUG
    private func debugPrintActionDays(_ days: [Date: [ActionDayItem]]) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone

        let sortedKeys = days.keys.sorted()
        print("🔎 ActionCalendar: marking \(sortedKeys.count) day(s) for \(monthYearString(from: currentMonth))")
        for key in sortedKeys {
            let items = days[key] ?? []
            let joined = items.map { "\($0.type.debugLabel)=\($0.assetName)" }.joined(separator: ", ")
            print("   • \(formatter.string(from: key)): \(joined.isEmpty ? "<no items>" : joined)")
        }
    }
#endif

    private func calculateNextPremiumPaymentDate(for insurance: Insurance, asset: Asset, portfolio: Portfolio) -> Date? {
        guard let premiumPaymentStatus = insurance.premiumPaymentStatus,
              premiumPaymentStatus != "Paid" else { return nil }

        let paymentHistory = InsurancePaymentService.paymentTransactions(for: asset, in: portfolio, context: viewContext)

        // If there are previous payments, calculate next payment date from last payment
        if let lastPayment = paymentHistory.last?.transactionDate {
            return calendar.date(byAdding: .year, value: 1, to: lastPayment)
        }

        // If no payments yet, calculate from original transaction date
        if let originalTransaction = (asset.transactions?.allObjects as? [Transaction])?
            .first(where: { $0.portfolio?.objectID == portfolio.objectID && $0.type == TransactionType.insurance.rawValue }) {
            let startDate = originalTransaction.transactionDate ?? Date()
            return calendar.date(byAdding: .year, value: 1, to: startDate)
        }

        return nil
    }

    private func daysInMonth() -> [Date] {
        let monthRange = calendar.range(of: .day, in: .month, for: currentMonth) ?? 1..<32
        let firstDayOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: currentMonth)) ?? currentMonth
        let firstWeekday = calendar.component(.weekday, from: firstDayOfMonth)

        var days: [Date] = []

        // Add padding days from previous month
        for i in 1..<firstWeekday {
            if let date = calendar.date(byAdding: .day, value: -i, to: firstDayOfMonth) {
                days.insert(date, at: 0)
            }
        }

        // Add days of current month
        for day in 1...monthRange.count {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: firstDayOfMonth) {
                days.append(date)
            }
        }

        // Add padding days from next month
        let totalCells = 42 // 6 weeks * 7 days
        while days.count < totalCells {
            if let lastDate = days.last,
               let nextDate = calendar.date(byAdding: .day, value: 1, to: lastDate) {
                days.append(nextDate)
            }
        }

        return days
    }

    private func isCurrentMonth(_ date: Date) -> Bool {
        return calendar.isDate(date, equalTo: currentMonth, toGranularity: .month)
    }

    private func monthYearString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        return formatter.string(from: date)
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        return formatter.string(from: date)
    }

    private var actionsForCurrentMonth: [ActionDayItem] {
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: currentMonth)) ?? currentMonth
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart

        return actionDays
            .flatMap { $0.value }
            .filter { $0.date >= monthStart && $0.date < nextMonth }
            .sorted { $0.date < $1.date }
    }

    private var upcomingActions: [ActionDayItem] {
        let today = normalizedDate(Date())

        let sorted = actionDays
            .flatMap { $0.value }
            .filter { $0.date >= today }
            .sorted { lhs, rhs in
                if lhs.date == rhs.date {
                    return lhs.assetName < rhs.assetName
                }
                return lhs.date < rhs.date
            }

        return Array(sorted.prefix(20))
    }

    private func previousMonth() {
        currentMonth = calendar.date(byAdding: .month, value: -1, to: currentMonth) ?? currentMonth
    }

    private func nextMonth() {
        currentMonth = calendar.date(byAdding: .month, value: 1, to: currentMonth) ?? currentMonth
    }
}

struct CalendarDayView: View {
    let date: Date
    let isCurrentMonth: Bool
    let isToday: Bool
    let isSelected: Bool
    let actionItems: [ActionCalendarView.ActionDayItem]
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 2) {
                Text("\(Calendar.current.component(.day, from: date))")
                    .font(.caption)
                    .fontWeight(isToday ? .bold : .regular)
                    .foregroundColor(textColor)
                    .frame(width: 32, height: 32)
                    .background(background)
                    .cornerRadius(16)

                // Action indicators
                if !actionItems.isEmpty {
                    HStack(spacing: 4) {
                        Capsule()
                            .fill(indicatorColor)
                            .frame(width: 20, height: 10)
                            .overlay(
                                Text("\(actionItems.count)")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.white)
                            )
                    }
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
#if DEBUG
        .onAppear {
            guard !actionItems.isEmpty else { return }
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            print("🔎 CalendarDayView: \(formatter.string(from: date)) has \(actionItems.map { $0.type.debugLabel }.joined(separator: ", "))")
        }
#endif
    }

    private var textColor: Color {
        if !isCurrentMonth {
            return .secondary
        } else if isToday {
            return .white
        } else {
            return .primary
        }
    }

    private var background: some View {
        Group {
            if isToday {
                Color.blue
            } else if isSelected {
                Color.blue.opacity(0.2)
            } else {
                Color.clear
            }
        }
    }

    private var indicatorColor: Color {
        if actionItems.count == 1 {
            return actionItems.first?.type.color ?? .blue
        }
        // Multiple actions – use a neutral accent
        return .purple
    }
}

struct CompactActionChip: View {
    let action: ActionCalendarView.ActionDayItem

    private var formatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(action.type.color)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(formatter.string(from: action.date))
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(action.assetName)
                    .font(.caption)
                    .foregroundColor(.primary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

struct ActionItemRow: View {
    let action: ActionCalendarView.ActionDayItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: action.type.icon)
                .foregroundColor(action.type.color)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text(action.title)
                    .font(.headline)
                Text(action.assetName)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(8)
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

#Preview {
    ActionCalendarView(portfolio: PersistenceController.preview.container.viewContext.registeredObjects.first(where: { $0 is Portfolio }) as! Portfolio)
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
