//
//  Transaction+CoreDataProperties.swift
//  
//
//  Created by 周晓凌 on 2025/10/7.
//
//  This file was automatically generated and should not be edited.
//

public import Foundation
public import CoreData


public typealias TransactionCoreDataPropertiesSet = NSSet

extension Transaction {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Transaction> {
        return NSFetchRequest<Transaction>(entityName: "Transaction")
    }

    @NSManaged public var amount: Double
    @NSManaged public var autoFetchPrice: Bool
    @NSManaged public var createdAt: Date?
    @NSManaged public var currency: String?
    @NSManaged public var fees: Double
    @NSManaged public var id: UUID?
    @NSManaged public var interestRate: Double
    @NSManaged public var maturityDate: Date?
    @NSManaged public var notes: String?
    @NSManaged public var paymentDeducted: Bool
    @NSManaged public var paymentDeductedAmount: Double
    @NSManaged public var paymentInstitutionName: String?
    @NSManaged public var price: Double
    @NSManaged public var quantity: Double
    @NSManaged public var realizedGain: Double
    @NSManaged public var tax: Double
    @NSManaged public var tradingInstitution: String?
    @NSManaged public var transactionCode: String?
    @NSManaged public var transactionDate: Date?
    @NSManaged public var type: String?
    @NSManaged public var linkedInsuranceAssetID: UUID?
    @NSManaged public var linkedTransactionID: UUID?
    @NSManaged public var parentDepositAssetID: UUID?
    @NSManaged public var accruedInterest: Double
    @NSManaged public var institutionPenalty: Double
    @NSManaged public var asset: Asset?
    @NSManaged public var institution: Institution?
    @NSManaged public var portfolio: Portfolio?

}

extension Transaction : Identifiable {

}
