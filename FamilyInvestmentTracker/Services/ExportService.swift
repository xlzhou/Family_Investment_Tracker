import Foundation
import CoreData
import PDFKit
import UIKit

class ExportService: ObservableObject {
    static let shared = ExportService()
    
    private init() {}
    
    func exportPortfolioData(portfolios: [Portfolio], format: ExportFormat) -> URL? {
        switch format {
        case .csv:
            return exportToCSV(portfolios: portfolios)
        case .pdf:
            return exportToPDF(portfolios: portfolios)
        }
    }
    
    // MARK: - CSV Export
    private func exportToCSV(portfolios: [Portfolio]) -> URL? {
        var csvContent = "Portfolio,Transaction ID,Symbol,Asset Name,Asset Type,Transaction Type,Quantity,Price,Amount,Fees,Date,Notes\n"
        
        for portfolio in portfolios {
            let transactions = (portfolio.transactions?.allObjects as? [Transaction]) ?? []
            ensureTransactionIdentifiers(in: transactions, context: portfolio.managedObjectContext)
            let sortedTransactions = transactions.sorted { 
                ($0.transactionDate ?? Date.distantPast) > ($1.transactionDate ?? Date.distantPast)
            }
            
            for transaction in sortedTransactions {
                let portfolioName = portfolio.name ?? "Unknown"
                let identifier = transaction.transactionCode ?? ""
                let symbol = transaction.asset?.symbol ?? ""
                let assetName = transaction.asset?.name ?? ""
                let assetType = transaction.asset?.assetType ?? ""
                let transactionType = transaction.type ?? ""
                let quantity = transaction.quantity
                let price = transaction.price
                let amount = transaction.amount
                let fees = transaction.fees
                let date = formatDate(transaction.transactionDate ?? Date())
                let notes = transaction.notes ?? ""
                
                let row = "\(csvEscape(portfolioName)),\(csvEscape(identifier)),\(csvEscape(symbol)),\(csvEscape(assetName)),\(csvEscape(assetType)),\(csvEscape(transactionType)),\(quantity),\(price),\(amount),\(fees),\(date),\(csvEscape(notes))\n"
                csvContent += row
            }
        }
        
        return saveToTemporaryFile(content: csvContent, fileName: "family_investment_data.csv")
    }
    
    private func csvEscape(_ string: String) -> String {
        if string.contains(",") || string.contains("\"") || string.contains("\n") {
            return "\"\(string.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return string
    }
    
    // MARK: - PDF Export
    private func exportToPDF(portfolios: [Portfolio]) -> URL? {
        let pdfRenderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792)) // Letter size
        
        let pdfData = pdfRenderer.pdfData { context in
            var yPosition: CGFloat = 50
            let margin: CGFloat = 50
            let pageWidth: CGFloat = 612 - (margin * 2)
            
            for (portfolioIndex, portfolio) in portfolios.enumerated() {
                if portfolioIndex > 0 {
                    context.beginPage()
                    yPosition = 50
                }
                
                // Portfolio Title
                yPosition = drawText(
                    text: portfolio.name ?? "Unknown Portfolio",
                    at: CGPoint(x: margin, y: yPosition),
                    width: pageWidth,
                    font: .boldSystemFont(ofSize: 24),
                    context: context.cgContext
                )
                yPosition += 20
                
                // Portfolio Summary
                let performance = calculatePortfolioPerformance(portfolio: portfolio)
                let summaryText = """
                Total Value (Holdings): \(Formatters.currency(performance.currentValue))
                Cost Basis: \(Formatters.currency(performance.costBasis))
                Unrealized P&L: \(Formatters.currency(performance.unrealizedGainLoss))
                Total Dividends: \(Formatters.currency(performance.totalDividends))
                Cash Balance: \(Formatters.currency(portfolio.resolvedCashBalance()))
                """
                
                yPosition = drawText(
                    text: summaryText,
                    at: CGPoint(x: margin, y: yPosition),
                    width: pageWidth,
                    font: .systemFont(ofSize: 12),
                    context: context.cgContext
                )
                yPosition += 30
                
                // Holdings Table
                yPosition = drawHoldingsTable(
                    portfolio: portfolio,
                    startY: yPosition,
                    margin: margin,
                    pageWidth: pageWidth,
                    context: context
                )
                
                // Transactions Table
                yPosition += 30
                yPosition = drawTransactionsTable(
                    portfolio: portfolio,
                    startY: yPosition,
                    margin: margin,
                    pageWidth: pageWidth,
                    context: context
                )
            }
        }
        
        return saveToTemporaryFile(data: pdfData, fileName: "family_investment_report.pdf")
    }
    
    private func drawText(text: String, at point: CGPoint, width: CGFloat, font: UIFont, context: CGContext) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.black
        ]
        
        let attributedString = NSAttributedString(string: text, attributes: attributes)
        let textRect = CGRect(x: point.x, y: point.y, width: width, height: CGFloat.greatestFiniteMagnitude)
        let boundingRect = attributedString.boundingRect(with: textRect.size, options: [.usesLineFragmentOrigin], context: nil)
        
        attributedString.draw(in: textRect)
        
        return point.y + boundingRect.height
    }
    
    private func drawHoldingsTable(portfolio: Portfolio, startY: CGFloat, margin: CGFloat, pageWidth: CGFloat, context: UIGraphicsPDFRendererContext) -> CGFloat {
        var yPosition = startY
        
        // Table Header
        yPosition = drawText(
            text: "Holdings",
            at: CGPoint(x: margin, y: yPosition),
            width: pageWidth,
            font: .boldSystemFont(ofSize: 16),
            context: context.cgContext
        )
        yPosition += 10
        
        let holdings = (portfolio.holdings?.allObjects as? [Holding])?.filter { $0.quantity > 0 } ?? []
        
        if holdings.isEmpty {
            yPosition = drawText(
                text: "No holdings",
                at: CGPoint(x: margin, y: yPosition),
                width: pageWidth,
                font: .systemFont(ofSize: 12),
                context: context.cgContext
            )
        } else {
            for holding in holdings {
                let holdingText = "\(holding.asset?.symbol ?? "N/A"): \(Formatters.decimal(holding.quantity)) shares @ \(Formatters.currency(holding.asset?.currentPrice ?? 0))"
                yPosition = drawText(
                    text: holdingText,
                    at: CGPoint(x: margin, y: yPosition),
                    width: pageWidth,
                    font: .systemFont(ofSize: 10),
                    context: context.cgContext
                )
                yPosition += 5
            }
        }
        
        return yPosition
    }
    
    private func drawTransactionsTable(portfolio: Portfolio, startY: CGFloat, margin: CGFloat, pageWidth: CGFloat, context: UIGraphicsPDFRendererContext) -> CGFloat {
        var yPosition = startY
        
        // Table Header
        yPosition = drawText(
            text: "Recent Transactions",
            at: CGPoint(x: margin, y: yPosition),
            width: pageWidth,
            font: .boldSystemFont(ofSize: 16),
            context: context.cgContext
        )
        yPosition += 10
        
        let transactions = (portfolio.transactions?.allObjects as? [Transaction]) ?? []
        ensureTransactionIdentifiers(in: transactions, context: portfolio.managedObjectContext)
        let sortedTransactions = transactions.sorted { 
            ($0.transactionDate ?? Date.distantPast) > ($1.transactionDate ?? Date.distantPast)
        }.prefix(10) // Last 10 transactions

        if sortedTransactions.isEmpty {
            yPosition = drawText(
                text: "No transactions",
                at: CGPoint(x: margin, y: yPosition),
                width: pageWidth,
                font: .systemFont(ofSize: 12),
                context: context.cgContext
            )
        } else {
            for transaction in sortedTransactions {
                let transactionText = "\(transaction.transactionCode ?? "N/A") | \(formatDate(transaction.transactionDate ?? Date())): \(transaction.type ?? "Unknown") \(transaction.asset?.symbol ?? "N/A") - \(Formatters.currency(transaction.amount))"
                yPosition = drawText(
                    text: transactionText,
                    at: CGPoint(x: margin, y: yPosition),
                    width: pageWidth,
                    font: .systemFont(ofSize: 10),
                    context: context.cgContext
                )
                yPosition += 5
            }
        }
        
        return yPosition
    }
    
    // MARK: - Helper Methods
    private func calculatePortfolioPerformance(portfolio: Portfolio) -> PortfolioPerformance {
        let holdings = portfolio.holdings?.allObjects as? [Holding] ?? []
        let context = portfolio.managedObjectContext ?? PersistenceController.shared.container.viewContext
        let includeInsurance = DashboardSettingsService.shared.includeInsuranceInPerformance

        var holdingsCurrentValue: Double = 0
        var totalCostBasis: Double = 0
        var unrealizedGainLoss: Double = 0
        var totalDividends: Double = 0
        var totalRealizedGains: Double = 0

        for holding in holdings {
            guard let asset = holding.asset else { continue }

            if asset.assetType == AssetType.deposit.rawValue {
                totalDividends += holding.totalDividends
                continue
            }

            if asset.assetType == AssetType.insurance.rawValue {
                let cashValue = (holding.value(forKey: "cashValue") as? Double) ?? 0
                holdingsCurrentValue += cashValue
                if includeInsurance {
                    let paidPremium = InsurancePaymentService.totalPaidAmount(for: asset, in: portfolio, context: context)
                    totalCostBasis += paidPremium
                    unrealizedGainLoss += cashValue - paidPremium
                }
                totalDividends += holding.totalDividends
                continue
            }

            let currentValue = holding.quantity * asset.currentPrice
            let costBasis = holding.quantity * holding.averageCostBasis
            holdingsCurrentValue += currentValue
            totalCostBasis += costBasis
            unrealizedGainLoss += currentValue - costBasis
            totalDividends += holding.totalDividends
            totalRealizedGains += holding.realizedGainLoss
        }

        let totalReturn = unrealizedGainLoss + totalRealizedGains + totalDividends
        let totalReturnPercentage = totalCostBasis > 0 ? (totalReturn / totalCostBasis) * 100 : 0

        return PortfolioPerformance(
            currentValue: holdingsCurrentValue + portfolio.totalCashBalance,
            costBasis: totalCostBasis,
            unrealizedGainLoss: unrealizedGainLoss,
            realizedGainLoss: totalRealizedGains,
            totalDividends: totalDividends,
            totalReturn: totalReturn,
            totalReturnPercentage: totalReturnPercentage
        )
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return formatter.string(from: date)
    }

    private func ensureTransactionIdentifiers(in transactions: [Transaction], context: NSManagedObjectContext?) {
        var updated = false

        for transaction in transactions {
            let previousCode = transaction.transactionCode
            let previousId = transaction.id
            transaction.ensureIdentifiers()

            if transaction.transactionCode != previousCode || transaction.id != previousId {
                updated = true
            }
        }

        if updated, let context = context, context.hasChanges {
            do {
                try context.save()
            } catch {
                print("Error ensuring transaction identifiers during export: \(error)")
            }
        }
    }
    
    private func saveToTemporaryFile(content: String, fileName: String) -> URL? {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(fileName)
        
        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            print("Error saving file: \(error)")
            return nil
        }
    }
    
    private func saveToTemporaryFile(data: Data, fileName: String) -> URL? {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(fileName)
        
        do {
            try data.write(to: fileURL)
            return fileURL
        } catch {
            print("Error saving file: \(error)")
            return nil
        }
    }
}
