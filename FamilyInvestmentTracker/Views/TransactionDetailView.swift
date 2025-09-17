import SwiftUI
import Foundation
import CoreData

struct TransactionDetailView: View {
    @ObservedObject var transaction: Transaction
    @Environment(\.dismiss) private var dismiss
    
    private var currency: Currency {
        Currency(rawValue: transaction.currency ?? "USD") ?? .usd
    }

    private var netValue: Double {
        return transaction.amount - transaction.fees - transaction.tax
    }

    private var isInsurance: Bool {
        transaction.type == TransactionType.insurance.rawValue
    }

    private var insurance: NSManagedObject? {
        transaction.asset?.value(forKey: "insurance") as? NSManagedObject
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Overview")) {
                    HStack {
                        Text("Transaction ID")
                        Spacer()
                        Text(transaction.transactionCode ?? "-")
                            .font(.system(.callout, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
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
                    if let maturity = transaction.maturityDate {
                        HStack {
                            Text("Maturity Date")
                            Spacer()
                            Text(maturity, style: .date)
                                .foregroundColor(.secondary)
                        }
                    }
                    HStack {
                        Text("Gross Amount")
                        Spacer()
                        Text(Formatters.currency(transaction.amount, symbol: currency.symbol))
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Net Amount")
                        Spacer()
                        Text(Formatters.currency(netValue, symbol: currency.symbol))
                            .foregroundColor(.primary)
                            .fontWeight(.semibold)
                    }
                    if let paymentInstitution = transaction.value(forKey: "paymentInstitutionName") as? String, !paymentInstitution.isEmpty {
                        HStack {
                            Text("Payment Institution")
                            Spacer()
                            Text(paymentInstitution)
                                .foregroundColor(.secondary)
                        }
                    }
                    if isInsurance {
                        HStack {
                            Text("Payment Deducted")
                            Spacer()
                            let deducted = (transaction.value(forKey: "paymentDeducted") as? Bool) ?? false
                            Text(deducted ? "Yes" : "No")
                                .foregroundColor(.secondary)
                        }
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

                if isInsurance {
                    insuranceDetailsSection
                    insuranceFinancialSection
                    insurancePremiumSection
                    insuranceCoverageSection
                    insuranceBeneficiariesSection
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

    @ViewBuilder
    private var insuranceDetailsSection: some View {
        Section(header: Text("Insurance Details")) {
            HStack {
                Text("Policy Symbol")
                Spacer()
                Text(transaction.asset?.symbol ?? "-")
                    .foregroundColor(.secondary)
            }
            HStack {
                Text("Policy Type")
                Spacer()
                Text(insurance?.value(forKey: "insuranceType") as? String ?? "-")
                    .foregroundColor(.secondary)
            }
            HStack {
                Text("Policyholder")
                Spacer()
                Text(insurance?.value(forKey: "policyholder") as? String ?? "-")
                    .foregroundColor(.secondary)
            }
            HStack {
                Text("Insured Person")
                Spacer()
                Text(insurance?.value(forKey: "insuredPerson") as? String ?? "-")
                    .foregroundColor(.secondary)
            }
            if let phone = insurance?.value(forKey: "contactNumber") as? String, !phone.isEmpty {
                HStack {
                    Text("Contact Number")
                    Spacer()
                    Text(phone)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var insuranceFinancialSection: some View {
        Section(header: Text("Financial Details")) {
            valueRow(label: "Basic Insured Amount", amount: insurance?.value(forKey: "basicInsuredAmount") as? Double)
            valueRow(label: "Additional Payment", amount: insurance?.value(forKey: "additionalPaymentAmount") as? Double)
            valueRow(label: "Death Benefit", amount: insurance?.value(forKey: "deathBenefit") as? Double)
        }
    }

    @ViewBuilder
    private var insurancePremiumSection: some View {
        Section(header: Text("Premium Details")) {
            let paymentType = insurance?.value(forKey: "premiumPaymentType") as? String ?? "-"
            let paymentStatus = insurance?.value(forKey: "premiumPaymentStatus") as? String ?? "-"
            HStack {
                Text("Payment Type")
                Spacer()
                Text(paymentType)
                    .foregroundColor(.secondary)
            }
            HStack {
                Text("Payment Status")
                Spacer()
                Text(paymentStatus)
                    .foregroundColor(.secondary)
            }
            valueRow(label: "Single Premium", amount: insurance?.value(forKey: "singlePremium") as? Double)
            valueRow(label: "Total Premium", amount: insurance?.value(forKey: "totalPremium") as? Double)
            if let term = insurance?.value(forKey: "premiumPaymentTerm") as? Int32, term > 0 {
                HStack {
                    Text("Payment Term")
                    Spacer()
                    Text("\(term) years")
                        .foregroundColor(.secondary)
                }
            }
            toggleRow(label: "Participating", value: insurance?.value(forKey: "isParticipating") as? Bool)
            toggleRow(label: "Supplementary Insurance", value: insurance?.value(forKey: "hasSupplementaryInsurance") as? Bool)
        }
    }

    @ViewBuilder
    private var insuranceCoverageSection: some View {
        Section(header: Text("Coverage & Benefits")) {
            if let expiration = insurance?.value(forKey: "coverageExpirationDate") as? Date {
                dateRow(label: "Coverage Expiration", date: expiration)
            }
            if let maturityDate = insurance?.value(forKey: "maturityBenefitRedemptionDate") as? Date {
                dateRow(label: "Maturity Benefit Date", date: maturityDate)
            }
            valueRow(label: "Estimated Maturity Benefit", amount: insurance?.value(forKey: "estimatedMaturityBenefit") as? Double)
            toggleRow(label: "Can Withdraw Premiums", value: insurance?.value(forKey: "canWithdrawPremiums") as? Bool)
            if let percentage = insurance?.value(forKey: "maxWithdrawalPercentage") as? Double, percentage > 0 {
                HStack {
                    Text("Max Withdrawal %")
                    Spacer()
                    Text("\(Formatters.decimal(percentage, fractionDigits: 1))%")
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var insuranceBeneficiariesSection: some View {
        if let beneficiaries = insurance?.value(forKey: "beneficiaries") as? Set<NSManagedObject>, !beneficiaries.isEmpty {
            Section(header: Text("Beneficiaries")) {
                ForEach(Array(beneficiaries), id: \.objectID) { beneficiary in
                    HStack {
                        Text(beneficiary.value(forKey: "name") as? String ?? "-" )
                        Spacer()
                        let pct = beneficiary.value(forKey: "percentage") as? Double ?? 0
                        Text("\(Formatters.decimal(pct, fractionDigits: 1))%")
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private func valueRow(label: String, amount: Double?) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(Formatters.currency(amount ?? 0, symbol: currency.symbol))
                .foregroundColor(.secondary)
        }
    }

    private func toggleRow(label: String, value: Bool?) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text((value ?? false) ? "Yes" : "No")
                .foregroundColor(.secondary)
        }
    }

    private func dateRow(label: String, date: Date) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(date, style: .date)
                .foregroundColor(.secondary)
        }
    }
}
