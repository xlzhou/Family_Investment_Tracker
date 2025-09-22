//
//  Asset+CoreDataProperties.swift
//  
//
//  Created by 周晓凌 on 2025/9/22.
//
//  This file was automatically generated and should not be edited.
//

public import Foundation
public import CoreData


public typealias AssetCoreDataPropertiesSet = NSSet

extension Asset {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Asset> {
        return NSFetchRequest<Asset>(entityName: "Asset")
    }

    @NSManaged public var assetType: String?
    @NSManaged public var createdAt: Date?
    @NSManaged public var currentPrice: Double
    @NSManaged public var id: UUID?
    @NSManaged public var interestRate: Double
    @NSManaged public var lastPriceUpdate: Date?
    @NSManaged public var name: String?
    @NSManaged public var linkedAssets: String?
    @NSManaged public var symbol: String?
    @NSManaged public var holdings: NSSet?
    @NSManaged public var transactions: NSSet?
    @NSManaged public var insurance: Insurance?
    @NSManaged public var institutionAvailabilities: NSSet?

}

// MARK: Generated accessors for holdings
extension Asset {

    @objc(addHoldingsObject:)
    @NSManaged public func addToHoldings(_ value: Holding)

    @objc(removeHoldingsObject:)
    @NSManaged public func removeFromHoldings(_ value: Holding)

    @objc(addHoldings:)
    @NSManaged public func addToHoldings(_ values: NSSet)

    @objc(removeHoldings:)
    @NSManaged public func removeFromHoldings(_ values: NSSet)

}

// MARK: Generated accessors for transactions
extension Asset {

    @objc(addTransactionsObject:)
    @NSManaged public func addToTransactions(_ value: Transaction)

    @objc(removeTransactionsObject:)
    @NSManaged public func removeFromTransactions(_ value: Transaction)

    @objc(addTransactions:)
    @NSManaged public func addToTransactions(_ values: NSSet)

    @objc(removeTransactions:)
    @NSManaged public func removeFromTransactions(_ values: NSSet)

}

// MARK: Generated accessors for institutionAvailabilities
extension Asset {

    @objc(addInstitutionAvailabilitiesObject:)
    @NSManaged public func addToInstitutionAvailabilities(_ value: InstitutionAssetAvailability)

    @objc(removeInstitutionAvailabilitiesObject:)
    @NSManaged public func removeFromInstitutionAvailabilities(_ value: InstitutionAssetAvailability)

    @objc(addInstitutionAvailabilities:)
    @NSManaged public func addToInstitutionAvailabilities(_ values: NSSet)

    @objc(removeInstitutionAvailabilities:)
    @NSManaged public func removeFromInstitutionAvailabilities(_ values: NSSet)

}

extension Asset : Identifiable {

}
