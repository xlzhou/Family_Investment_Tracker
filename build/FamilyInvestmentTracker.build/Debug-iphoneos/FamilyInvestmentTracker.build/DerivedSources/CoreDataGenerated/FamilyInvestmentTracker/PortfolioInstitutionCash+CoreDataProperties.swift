//
//  PortfolioInstitutionCash+CoreDataProperties.swift
//  
//
//  Created by 周晓凌 on 2025/9/22.
//
//  This file was automatically generated and should not be edited.
//

public import Foundation
public import CoreData


public typealias PortfolioInstitutionCashCoreDataPropertiesSet = NSSet

extension PortfolioInstitutionCash {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<PortfolioInstitutionCash> {
        return NSFetchRequest<PortfolioInstitutionCash>(entityName: "PortfolioInstitutionCash")
    }

    @NSManaged public var id: UUID?
    @NSManaged public var cashBalance: Double
    @NSManaged public var createdAt: Date?
    @NSManaged public var updatedAt: Date?
    @NSManaged public var portfolio: Portfolio?
    @NSManaged public var institution: Institution?

}

extension PortfolioInstitutionCash : Identifiable {

}
