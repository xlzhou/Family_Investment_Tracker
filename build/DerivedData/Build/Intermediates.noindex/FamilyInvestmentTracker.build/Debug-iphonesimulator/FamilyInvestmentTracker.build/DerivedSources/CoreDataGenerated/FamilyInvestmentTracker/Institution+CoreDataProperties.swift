//
//  Institution+CoreDataProperties.swift
//  
//
//  Created by 周晓凌 on 2025/9/24.
//
//  This file was automatically generated and should not be edited.
//

public import Foundation
public import CoreData


public typealias InstitutionCoreDataPropertiesSet = NSSet

extension Institution {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Institution> {
        return NSFetchRequest<Institution>(entityName: "Institution")
    }

    @NSManaged public var createdAt: Date?
    @NSManaged public var id: UUID?
    @NSManaged public var name: String?
    @NSManaged public var assetAvailabilities: NSSet?
    @NSManaged public var portfolioCurrencyCashBalances: NSSet?
    @NSManaged public var transactions: NSSet?

}

// MARK: Generated accessors for assetAvailabilities
extension Institution {

    @objc(addAssetAvailabilitiesObject:)
    @NSManaged public func addToAssetAvailabilities(_ value: InstitutionAssetAvailability)

    @objc(removeAssetAvailabilitiesObject:)
    @NSManaged public func removeFromAssetAvailabilities(_ value: InstitutionAssetAvailability)

    @objc(addAssetAvailabilities:)
    @NSManaged public func addToAssetAvailabilities(_ values: NSSet)

    @objc(removeAssetAvailabilities:)
    @NSManaged public func removeFromAssetAvailabilities(_ values: NSSet)

}

// MARK: Generated accessors for portfolioCurrencyCashBalances
extension Institution {

    @objc(addPortfolioCurrencyCashBalancesObject:)
    @NSManaged public func addToPortfolioCurrencyCashBalances(_ value: PortfolioInstitutionCurrencyCash)

    @objc(removePortfolioCurrencyCashBalancesObject:)
    @NSManaged public func removeFromPortfolioCurrencyCashBalances(_ value: PortfolioInstitutionCurrencyCash)

    @objc(addPortfolioCurrencyCashBalances:)
    @NSManaged public func addToPortfolioCurrencyCashBalances(_ values: NSSet)

    @objc(removePortfolioCurrencyCashBalances:)
    @NSManaged public func removeFromPortfolioCurrencyCashBalances(_ values: NSSet)

}

// MARK: Generated accessors for transactions
extension Institution {

    @objc(addTransactionsObject:)
    @NSManaged public func addToTransactions(_ value: Transaction)

    @objc(removeTransactionsObject:)
    @NSManaged public func removeFromTransactions(_ value: Transaction)

    @objc(addTransactions:)
    @NSManaged public func addToTransactions(_ values: NSSet)

    @objc(removeTransactions:)
    @NSManaged public func removeFromTransactions(_ values: NSSet)

}

extension Institution : Identifiable {

}
