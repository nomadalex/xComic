//
//  ComicRecord.swift
//  xComic
//
//  Created by Kun Wang on 4/27/16.
//  Copyright © 2016 Kun Wang. All rights reserved.
//

import Foundation
import CoreData

@objc(ComicRecord)
class ComicRecord: NSManagedObject {
    var images: [String]? {
        get {
            return images_ as? [String]
        }
        set {
            images_ = newValue as NSObject?
        }
    }

    var server: ServerEntry? {
        get {
            return server_ as? ServerEntry
        }
        set {
            server_ = newValue
        }
    }

    convenience init(context: NSManagedObjectContext, server: ServerEntry, title: String, thumbnail: String, path: String, images: [String]) {
        let entity = NSEntityDescription.entity(forEntityName: "ComicRecord", in: context)!
        self.init(entity: entity, insertInto: context)
        self.server = server
        self.title = title
        self.thumbnail = thumbnail
        self.path = path
        self.images = images
        self.cur = 0
    }
}
