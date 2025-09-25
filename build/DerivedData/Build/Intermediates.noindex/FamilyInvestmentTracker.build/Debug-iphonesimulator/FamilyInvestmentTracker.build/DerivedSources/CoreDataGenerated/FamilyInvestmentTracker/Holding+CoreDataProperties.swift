//
//  Holding+CoreDataProperties.swift
//  
//
//  Created by 周晓凌 on 2025/9/24.
//
//  This file was automatically generated and should not be edited.
//

public import Foundation
public import CoreData


public typealias HoldingCoreDataPropertiesSet = NSSet

extension Holding {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Holding> {
        return NSFetchRequest<Holding>(entityName: "Holding")
    }

    @NSManaged public var averageCostBasis: Double
    @NSManaged public var cashValue: Double
    @NSManaged public var id: UUID?
    @NSManaged public var quantity: Double
    @NSManaged public var realizedGainLoss: Double
    @NSManaged public var totalDividends: Double
    @NSManaged public var updatedAt: Date?
    @NSManaged public var asset: Asset?
    @NSManaged public var portfolio: Portfolio?

}

extension Holding : Identifiable {

}
