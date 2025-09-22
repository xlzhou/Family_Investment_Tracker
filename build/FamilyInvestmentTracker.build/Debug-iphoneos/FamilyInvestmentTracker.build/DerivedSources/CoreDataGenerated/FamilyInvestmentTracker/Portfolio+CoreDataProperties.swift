//
//  Portfolio+CoreDataProperties.swift
//  
//
//  Created by 周晓凌 on 2025/9/22.
//
//  This file was automatically generated and should not be edited.
//

public import Foundation
public import CoreData


public typealias PortfolioCoreDataPropertiesSet = NSSet

extension Portfolio {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Portfolio> {
        return NSFetchRequest<Portfolio>(entityName: "Portfolio")
    }

    @NSManaged public var createdAt: Date?
    @NSManaged public var id: UUID?
    @NSManaged public var mainCurrency: String?
    @NSManaged public var name: String?
    @NSManaged public var ownerID: String?
    @NSManaged public var cashBalance: Double
    @NSManaged public var enforcesCashDiscipline: Bool
    @NSManaged public var totalValue: Double
    @NSManaged public var updatedAt: Date?
    @NSManaged public var holdings: NSSet?
    @NSManaged public var transactions: NSSet?
    @NSManaged public var institutionCashBalances: NSSet?

}

// MARK: Generated accessors for holdings
extension Portfolio {

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
extension Portfolio {

    @objc(addTransactionsObject:)
    @NSManaged public func addToTransactions(_ value: Transaction)

    @objc(removeTransactionsObject:)
    @NSManaged public func removeFromTransactions(_ value: Transaction)

    @objc(addTransactions:)
    @NSManaged public func addToTransactions(_ values: NSSet)

    @objc(removeTransactions:)
    @NSManaged public func removeFromTransactions(_ values: NSSet)

}

// MARK: Generated accessors for institutionCashBalances
extension Portfolio {

    @objc(addInstitutionCashBalancesObject:)
    @NSManaged public func addToInstitutionCashBalances(_ value: PortfolioInstitutionCash)

    @objc(removeInstitutionCashBalancesObject:)
    @NSManaged public func removeFromInstitutionCashBalances(_ value: PortfolioInstitutionCash)

    @objc(addInstitutionCashBalances:)
    @NSManaged public func addToInstitutionCashBalances(_ values: NSSet)

    @objc(removeInstitutionCashBalances:)
    @NSManaged public func removeFromInstitutionCashBalances(_ values: NSSet)

}

extension Portfolio : Identifiable {

}
