import SwiftUI
import Foundation
import Charts
import CoreData

private enum AssetTypePalette {
    static func color(for typeName: String) -> Color {
        if let assetType = AssetType(rawValue: typeName) {
            switch assetType {
            case .stock: return .blue
            case .etf: return .green
            case .bond: return .orange
            case .mutualFund: return .purple
            case .cryptocurrency: return .yellow
            case .preciousMetal: return .brown
            case .insurance: return .pink
            case .structuredProduct: return .cyan
            case .deposit: return .gray
            case .other: return .teal
            }
        }

        let normalized = typeName.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.lowercased().contains("fixed deposit") {
            return .gray
        }

        let hash = abs(normalized.hashValue)
        let hue = Double(hash % 360) / 360.0
        return Color(hue: hue, saturation: 0.45, brightness: 0.85)
    }
}

struct AnalyticsView: View {
    @ObservedObject var portfolio: Portfolio
    @StateObject private var viewModel = PortfolioViewModel()
    @Environment(\.managedObjectContext) private var viewContext
    @State private var refreshID = UUID()
    @State private var performanceHistory: [PerformanceDataPoint] = []
    @State private var dividendHistory: [DividendDataPoint] = []
    @State private var isLoadingPerformance = false
    @State private var isLoadingDividends = false
    @State private var performanceSnapshot: PortfolioPerformance?
    @State private var realizedPnLYTD: Double = 0
    @State private var isShowingRealizedPnL = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Portfolio Performance Summary
                PerformanceSummaryView(
                    portfolio: portfolio,
                    performance: performanceSnapshot ?? viewModel.calculatePortfolioPerformance(portfolio: portfolio),
                    realizedPnLYTD: realizedPnLYTD,
                    onShowRealizedPnL: { isShowingRealizedPnL = true }
                )

                // Asset Allocation Chart
                AssetAllocationChartView(portfolio: portfolio, viewModel: viewModel)

                // Performance Over Time Chart
                PerformanceChartView(
                    data: performanceHistory,
                    isLoading: isLoadingPerformance,
                    currencySymbol: portfolioCurrency.symbol
                )

                // Dividend History Chart
                DividendHistoryView(
                    data: dividendHistory,
                    isLoading: isLoadingDividends,
                    currencySymbol: portfolioCurrency.symbol
                )
            }
            .padding()
        }
        .id(refreshID)
        .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange, object: viewContext)) { notification in
            let updated = notification.userInfo?[NSUpdatedObjectsKey] as? Set<NSManagedObject> ?? []
            let refreshed = notification.userInfo?[NSRefreshedObjectsKey] as? Set<NSManagedObject> ?? []
            let inserted = notification.userInfo?[NSInsertedObjectsKey] as? Set<NSManagedObject> ?? []
            let relevant = updated.union(refreshed).union(inserted)
            if relevant.contains(where: { $0.objectID == portfolio.objectID || ($0 as? Transaction)?.portfolio == portfolio || ($0 as? Holding)?.portfolio == portfolio }) {
                refreshID = UUID()
            }
        }
        .task {
            viewModel.invalidateAnalyticsCache(for: portfolio)
            await loadAnalyticsData()
        }
        .onChange(of: refreshID) { _, _ in
            viewModel.invalidateAnalyticsCache(for: portfolio)
            Task { await loadAnalyticsData() }
        }
        .sheet(isPresented: $isShowingRealizedPnL) {
            RealizedPnLView(portfolio: portfolio)
                .environment(\.managedObjectContext, viewContext)
        }
    }

    private var portfolioCurrency: Currency {
        Currency(rawValue: portfolio.mainCurrency ?? Currency.usd.rawValue) ?? .usd
    }

    @MainActor
    private func loadAnalyticsData() async {
        isLoadingPerformance = true
        isLoadingDividends = true

        let summary = viewModel.calculatePortfolioPerformance(portfolio: portfolio)
        let performance = viewModel.performanceHistory(for: portfolio)
        let dividends = viewModel.dividendHistory(for: portfolio)
        let calendar = Calendar.current
        let now = Date()
        let startOfYear = calendar.date(from: calendar.dateComponents([.year], from: now)) ?? now
        let realizedYTD = RealizedPnLCalculator.totalRealizedPnL(for: portfolio,
                                                                 startDate: startOfYear,
                                                                 endDate: now,
                                                                 context: viewContext)

        performanceHistory = performance
        dividendHistory = dividends
        performanceSnapshot = summary
        realizedPnLYTD = realizedYTD
        isLoadingPerformance = false
        isLoadingDividends = false
    }
}

struct PerformanceSummaryView: View {
    let portfolio: Portfolio
    let performance: PortfolioPerformance
    let realizedPnLYTD: Double
    let onShowRealizedPnL: () -> Void

    private var portfolioCurrency: Currency {
        Currency(rawValue: portfolio.mainCurrency ?? "USD") ?? .usd
    }
    
    private var currencySymbol: String {
        portfolioCurrency.symbol
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Performance Summary")
                .font(.title2)
                .fontWeight(.semibold)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                PerformanceCardView(
                    title: "Current Value",
                    value: Formatters.currency(performance.currentValue, symbol: currencySymbol),
                    color: .blue
                )
                
                PerformanceCardView(
                    title: "Cost Basis",
                    value: Formatters.currency(performance.costBasis, symbol: currencySymbol),
                    color: .gray
                )
                
                PerformanceCardView(
                    title: "Unrealized P&L",
                    value: Formatters.signedCurrency(performance.unrealizedGainLoss, symbol: currencySymbol),
                    color: performance.unrealizedGainLoss >= 0 ? .green : .red
                )
                
                PerformanceCardView(
                    title: "Total Return",
                    value: Formatters.signedPercent(performance.totalReturnPercentage),
                    color: performance.totalReturnPercentage >= 0 ? .green : .red
                )
                
                PerformanceCardView(
                    title: "Realized P&L (YTD)",
                    value: Formatters.signedCurrency(realizedPnLYTD, symbol: currencySymbol),
                    color: realizedPnLYTD >= 0 ? .green : .red,
                    action: onShowRealizedPnL
                )

                PerformanceCardView(
                    title: "Total Dividends",
                    value: Formatters.currency(performance.totalDividends, symbol: currencySymbol),
                    color: .purple
                )
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(15)
        .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
}

struct PerformanceCardView: View {
    let title: String
    let value: String
    let color: Color
    let action: (() -> Void)?

    init(title: String,
         value: String,
         color: Color,
         action: (() -> Void)? = nil) {
        self.title = title
        self.value = value
        self.color = color
        self.action = action
    }

    var body: some View {
        Group {
            if let action {
                Button(action: action) {
                    cardContent
                }
                .buttonStyle(.plain)
            } else {
                cardContent
            }
        }
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)

            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(10)
    }
}

struct AssetAllocationChartView: View {
    let portfolio: Portfolio
    let viewModel: PortfolioViewModel
    
    private var allocations: [AssetAllocation] {
        viewModel.getAssetAllocation(portfolio: portfolio)
    }

    private var institutionAllocations: [InstitutionAllocation] {
        viewModel.getInstitutionAllocations(portfolio: portfolio)
    }

    private var portfolioCurrency: Currency {
        Currency(rawValue: portfolio.mainCurrency ?? "USD") ?? .usd
    }

    private var currencySymbol: String {
        portfolioCurrency.symbol
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Asset Allocation")
                .font(.headline)            
            if allocations.isEmpty {
                Text("No assets to display")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                HStack(alignment: .top, spacing: 32) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("By Asset Type")
                            .font(.headline)

                        HStack(spacing: 16) {
                            Chart(allocations, id: \.type) { allocation in
                                SectorMark(
                                    angle: .value("Value", allocation.value),
                                    innerRadius: .ratio(0.4),
                                    angularInset: 1
                                )
                                .foregroundStyle(colorForAssetType(allocation.type))
                                .opacity(0.8)
                            }
                            .frame(width: 160, height: 160)

                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(allocations, id: \.type) { allocation in
                                    HStack(spacing: 8) {
                                        Circle()
                                            .fill(colorForAssetType(allocation.type))
                                            .frame(width: 12, height: 12)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(allocation.type)
                                                .font(.subheadline)
                                                .fontWeight(.medium)

                                            Text("\(Formatters.decimal(allocation.percentage, fractionDigits: 1))% • \(Formatters.currency(allocation.value, symbol: currencySymbol, fractionDigits: 0))")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }

                                        Spacer()
                                    }
                                }
                            }
                        }
                    }

                    if !institutionAllocations.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("By Institution")
                                .font(.headline)

                            HStack(spacing: 16) {
                                Chart(institutionAllocations, id: \.name) { allocation in
                                    SectorMark(
                                        angle: .value("Value", allocation.value),
                                        innerRadius: .ratio(0.4),
                                        angularInset: 1
                                    )
                                    .foregroundStyle(colorForInstitution(allocation.name))
                                    .opacity(0.85)
                                }
                                .frame(width: 160, height: 160)

                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(institutionAllocations, id: \.name) { allocation in
                                        HStack(spacing: 8) {
                                            Circle()
                                                .fill(colorForInstitution(allocation.name))
                                                .frame(width: 12, height: 12)

                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(allocation.name)
                                                    .font(.subheadline)
                                                    .fontWeight(.medium)

                                                Text("\(Formatters.decimal(allocation.percentage, fractionDigits: 1))% • \(Formatters.currency(allocation.value, symbol: currencySymbol, fractionDigits: 0))")
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }

                                            Spacer()
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(15)
        .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
    
    private func colorForAssetType(_ type: String) -> Color {
        AssetTypePalette.color(for: type)
    }

    private func colorForInstitution(_ name: String) -> Color {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let hash = abs(trimmed.hashValue)
        let hue = Double(hash % 360) / 360.0
        return Color(hue: hue, saturation: 0.55, brightness: 0.85)
    }
}

struct PerformanceChartView: View {
    let data: [PerformanceDataPoint]
    let isLoading: Bool
    let currencySymbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Portfolio Performance (30 Days)")
                .font(.title2)
                .fontWeight(.semibold)
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 160)
            } else if data.count <= 1 {
                Text("Not enough history to display performance.")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                Chart(data, id: \.date) { dataPoint in
                    LineMark(
                        x: .value("Date", dataPoint.date),
                        y: .value("Value", dataPoint.value)
                    )
                    .foregroundStyle(.blue)
                    .lineStyle(StrokeStyle(lineWidth: 2))

                    AreaMark(
                        x: .value("Date", dataPoint.date),
                        y: .value("Value", dataPoint.value)
                    )
                    .foregroundStyle(.blue.opacity(0.1))
                }
                .frame(height: 200)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.month().day())
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        if let number = value.as(Double.self) {
                            AxisValueLabel(Formatters.currency(number, symbol: currencySymbol, fractionDigits: 0))
                        } else {
                            AxisValueLabel()
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(15)
        .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
}

struct DividendHistoryView: View {
    let data: [DividendDataPoint]
    let isLoading: Bool
    let currencySymbol: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Dividend History (12 Months)")
                .font(.title2)
                .fontWeight(.semibold)
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 160)
            } else if data.isEmpty {
                Text("No dividend or interest income recorded in this period.")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                Chart(data, id: \.month) { dataPoint in
                    BarMark(
                        x: .value("Month", dataPoint.month),
                        y: .value("Income", dataPoint.amount)
                    )
                    .foregroundStyle(.purple)
                    .cornerRadius(4)
                }
                .frame(height: 200)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .month, count: 2)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.month(.abbreviated))
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        if let number = value.as(Double.self) {
                            AxisValueLabel(Formatters.currency(number, symbol: currencySymbol, fractionDigits: 0))
                        } else {
                            AxisValueLabel()
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(15)
        .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
}

struct PerformanceDataPoint {
    let date: Date
    let value: Double
}

struct DividendDataPoint {
    let month: Date
    let amount: Double
}

#Preview {
    AnalyticsView(portfolio: PersistenceController.preview.container.viewContext.registeredObjects.first(where: { $0 is Portfolio }) as! Portfolio)
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
