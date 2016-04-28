//
//  ComicRecord+CoreDataProperties.swift
//  xComic
//
//  Created by Kun Wang on 4/28/16.
//  Copyright © 2016 Kun Wang. All rights reserved.
//
//  Choose "Create NSManagedObject Subclass…" from the Core Data editor menu
//  to delete and recreate this implementation file for your updated model.
//

import Foundation
import CoreData

extension ComicRecord {

    @NSManaged var cur: NSNumber?
    @NSManaged var path: String?
    @NSManaged var images_: NSObject?
    @NSManaged var thumbnail: String?
    @NSManaged var title: String?

}
