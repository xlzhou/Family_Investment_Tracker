import SwiftUI
import CoreData
import Foundation

struct ExportDataView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var localizationManager: LocalizationManager
    @Binding var selectedFormat: ExportFormat
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Portfolio.name, ascending: true)],
        animation: .default)
    private var portfolios: FetchedResults<Portfolio>
    
    @State private var selectedPortfolios = Set<Portfolio>()
    @State private var isExporting = false
    @State private var exportedFileURL: URL?
    @State private var showingShareSheet = false
    @State private var exportError: String?
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Form {
                    // Export Format Section
                    Section(header: Text(localizationManager.localizedString(for: "exportData.format.sectionHeader"))) {
                        Picker(localizationManager.localizedString(for: "exportData.format.pickerLabel"), selection: $selectedFormat) {
                            ForEach(ExportFormat.allCases, id: \.self) { format in
                                Text(format.displayName).tag(format)
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                    }
                    
                    // Portfolio Selection Section
                    Section(header: Text(localizationManager.localizedString(for: "exportData.portfolios.sectionHeader")), footer: Text(localizationManager.localizedString(for: "exportData.portfolios.sectionFooter"))) {
                        ForEach(portfolios, id: \.id) { portfolio in
                            HStack {
                                Button(action: {
                                    togglePortfolioSelection(portfolio)
                                }) {
                                    HStack {
                                        Image(systemName: selectedPortfolios.contains(portfolio) ? "checkmark.circle.fill" : "circle")
                                            .foregroundColor(selectedPortfolios.contains(portfolio) ? .blue : .gray)
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(portfolio.name ?? localizationManager.localizedString(for: "exportData.portfolios.unknownPortfolio"))
                                                .font(.headline)
                                                .foregroundColor(.primary)

                                            Text("\(Formatters.currency(portfolio.totalValue)) • \(portfolio.transactions?.count ?? 0) \(localizationManager.localizedString(for: "exportData.portfolios.transactions"))")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        
                                        Spacer()
                                    }
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        
                        HStack {
                            Button(action: selectAllPortfolios) {
                                Text(localizationManager.localizedString(for: "exportData.portfolios.selectAll"))
                                    .font(.subheadline)
                                    .foregroundColor(.blue)
                            }

                            Spacer()

                            Button(action: deselectAllPortfolios) {
                                Text(localizationManager.localizedString(for: "exportData.portfolios.deselectAll"))
                                    .font(.subheadline)
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                    
                    // Export Information Section
                    Section(header: Text(localizationManager.localizedString(for: "exportData.information.sectionHeader"))) {
                        HStack {
                            Text(localizationManager.localizedString(for: "exportData.information.selectedPortfolios"))
                            Spacer()
                            Text("\(selectedPortfolios.count)")
                                .foregroundColor(.secondary)
                        }

                        HStack {
                            Text(localizationManager.localizedString(for: "exportData.information.totalTransactions"))
                            Spacer()
                            Text("\(totalTransactions)")
                                .foregroundColor(.secondary)
                        }

                        HStack {
                            Text(localizationManager.localizedString(for: "exportData.information.fileFormat"))
                            Spacer()
                            Text(selectedFormat.displayName)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // Export Button
                VStack(spacing: 16) {
                    if let error = exportError {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    
                    Button(action: exportData) {
                        HStack {
                            if isExporting {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                Text(localizationManager.localizedString(for: "exportData.button.exporting"))
                            } else {
                                Image(systemName: "square.and.arrow.up")
                                Text(localizationManager.localizedString(for: "exportData.button.exportData"))
                            }
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(selectedPortfolios.isEmpty ? Color.gray : Color.blue)
                        .cornerRadius(12)
                    }
                    .disabled(selectedPortfolios.isEmpty || isExporting)
                    .padding(.horizontal)
                }
                .padding(.bottom)
            }
            .navigationTitle(localizationManager.localizedString(for: "exportData.navigation.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(localizationManager.localizedString(for: "exportData.navigation.cancel")) {
                        dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            if let fileURL = exportedFileURL {
                ShareSheet(activityItems: [fileURL])
            }
        }
        .onAppear {
            // Select all portfolios by default
            selectedPortfolios = Set(portfolios)
        }
    }
    
    private var totalTransactions: Int {
        selectedPortfolios.reduce(0) { total, portfolio in
            total + (portfolio.transactions?.count ?? 0)
        }
    }
    
    private func togglePortfolioSelection(_ portfolio: Portfolio) {
        if selectedPortfolios.contains(portfolio) {
            selectedPortfolios.remove(portfolio)
        } else {
            selectedPortfolios.insert(portfolio)
        }
    }
    
    private func selectAllPortfolios() {
        selectedPortfolios = Set(portfolios)
    }
    
    private func deselectAllPortfolios() {
        selectedPortfolios.removeAll()
    }
    
    private func exportData() {
        guard !selectedPortfolios.isEmpty else { return }
        
        isExporting = true
        exportError = nil
        
        DispatchQueue.global(qos: .userInitiated).async {
            let portfolioArray = Array(selectedPortfolios)
            let fileURL = ExportService.shared.exportPortfolioData(
                portfolios: portfolioArray,
                format: selectedFormat
            )
            
            DispatchQueue.main.async {
                isExporting = false
                
                if let fileURL = fileURL {
                    exportedFileURL = fileURL
                    showingShareSheet = true
                } else {
                    exportError = localizationManager.localizedString(for: "exportData.error.exportFailed")
                }
            }
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    ExportDataView(selectedFormat: .constant(.csv))
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
