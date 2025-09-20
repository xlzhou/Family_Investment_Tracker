import SwiftUI
import Foundation
import Charts
import CoreData

struct AnalyticsView: View {
    @ObservedObject var portfolio: Portfolio
    @StateObject private var viewModel = PortfolioViewModel()
    @Environment(\.managedObjectContext) private var viewContext
    @State private var refreshID = UUID()
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Portfolio Performance Summary
                PerformanceSummaryView(portfolio: portfolio, viewModel: viewModel)
                
                // Asset Allocation Chart
                AssetAllocationChartView(portfolio: portfolio, viewModel: viewModel)
                
                // Performance Over Time Chart
                PerformanceChartView(portfolio: portfolio)
                
                // Dividend History Chart
                DividendHistoryView(portfolio: portfolio)
            }
            .padding()
        }
        .id(refreshID)
        .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange, object: viewContext)) { notification in
            let updated = notification.userInfo?[NSUpdatedObjectsKey] as? Set<NSManagedObject> ?? []
            let refreshed = notification.userInfo?[NSRefreshedObjectsKey] as? Set<NSManagedObject> ?? []
            let inserted = notification.userInfo?[NSInsertedObjectsKey] as? Set<NSManagedObject> ?? []
            let relevant = updated.union(refreshed).union(inserted)
            if relevant.contains(where: { $0.objectID == portfolio.objectID }) {
                refreshID = UUID()
            }
        }
    }
}

struct PerformanceSummaryView: View {
    let portfolio: Portfolio
    let viewModel: PortfolioViewModel
    
    private var performance: PortfolioPerformance {
        viewModel.calculatePortfolioPerformance(portfolio: portfolio)
    }

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
                    title: "Realized P&L",
                    value: Formatters.signedCurrency(performance.realizedGainLoss, symbol: currencySymbol),
                    color: performance.realizedGainLoss >= 0 ? .green : .red
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
    
    var body: some View {
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
        switch type {
        case "Stock":
            return .blue
        case "ETF":
            return .green
        case "Bond":
            return .orange
        case "Mutual Fund":
            return .purple
        case "Cryptocurrency":
            return .yellow
        case "Deposit":
            return .gray
        case "Cash":
            return .teal
        case "Structured Product":
            return .brown
        default:
            return .pink
        }
    }

    private func colorForInstitution(_ name: String) -> Color {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let hash = abs(trimmed.hashValue)
        let hue = Double(hash % 360) / 360.0
        return Color(hue: hue, saturation: 0.55, brightness: 0.85)
    }
}

struct PerformanceChartView: View {
    let portfolio: Portfolio
    
    private var performanceData: [PerformanceDataPoint] {
        // Generate sample performance data
        // In a real app, this would come from historical data
        let calendar = Calendar.current
        let endDate = Date()
        
        return (0...30).compactMap { dayOffset in
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: endDate) else { return nil }
            
            // Simulate performance data
            let baseValue = portfolio.totalValue
            let variation = Double.random(in: -0.1...0.1)
            let value = baseValue * (1 + variation)
            
            return PerformanceDataPoint(date: date, value: value)
        }.reversed()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Portfolio Performance (30 Days)")
                .font(.title2)
                .fontWeight(.semibold)
            
            Chart(performanceData, id: \.date) { dataPoint in
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
                AxisMarks { _ in
                    AxisGridLine()
                    AxisValueLabel()
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
    let portfolio: Portfolio
    
    private var dividendData: [DividendDataPoint] {
        let calendar = Calendar.current
        let currentDate = Date()
        
        // Generate sample dividend data for the last 12 months
        return (0...11).compactMap { monthOffset in
            guard let date = calendar.date(byAdding: .month, value: -monthOffset, to: currentDate) else { return nil }
            
            // Simulate dividend payments
            let dividendAmount = Double.random(in: 0...200)
            
            return DividendDataPoint(month: date, amount: dividendAmount)
        }.reversed()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Dividend History (12 Months)")
                .font(.title2)
                .fontWeight(.semibold)
            
            Chart(dividendData, id: \.month) { dataPoint in
                BarMark(
                    x: .value("Month", dataPoint.month),
                    y: .value("Dividends", dataPoint.amount)
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
                AxisMarks { _ in
                    AxisGridLine()
                    AxisValueLabel()
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
