//
//  PortfolioInstitutionCurrencyCash+CoreDataProperties.swift
//  
//
//  Created by 周晓凌 on 2025/9/24.
//
//  This file was automatically generated and should not be edited.
//

public import Foundation
public import CoreData


public typealias PortfolioInstitutionCurrencyCashCoreDataPropertiesSet = NSSet

extension PortfolioInstitutionCurrencyCash {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<PortfolioInstitutionCurrencyCash> {
        return NSFetchRequest<PortfolioInstitutionCurrencyCash>(entityName: "PortfolioInstitutionCurrencyCash")
    }

    @NSManaged public var amount: Double
    @NSManaged public var createdAt: Date?
    @NSManaged public var currency: String?
    @NSManaged public var id: UUID?
    @NSManaged public var updatedAt: Date?
    @NSManaged public var institution: Institution?
    @NSManaged public var portfolio: Portfolio?

}

extension PortfolioInstitutionCurrencyCash : Identifiable {

}
