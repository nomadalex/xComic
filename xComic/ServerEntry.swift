//
//  ServerEntry.swift
//  xComic
//
//  Created by Kun Wang on 4/28/16.
//  Copyright © 2016 Kun Wang. All rights reserved.
//

import Foundation

class ServerEntry: NSObject, NSCoding {
    let name: String
    let ip: UInt32
    let username: String
    let password: String

    fileprivate static let nameKey = "name"
    fileprivate static let ipKey = "ip"
    fileprivate static let usernameKey = "username"
    fileprivate static let passwordKey = "password"

    init(name: String, ip: UInt32, username: String, password: String) {
        self.name = name
        self.ip = ip
        self.username = username
        self.password = password
    }

    required init?(coder aDecoder: NSCoder) {
        self.name = aDecoder.decodeObject(forKey: ServerEntry.nameKey) as! String
        self.ip = UInt32(aDecoder.decodeInt32(forKey: ServerEntry.ipKey))
        self.username = aDecoder.decodeObject(forKey: ServerEntry.usernameKey) as! String
        self.password = aDecoder.decodeObject(forKey: ServerEntry.passwordKey) as! String
    }

    func encode(with aCoder: NSCoder) {
        aCoder.encode(self.name, forKey: ServerEntry.nameKey)
        aCoder.encode(Int32(self.ip), forKey: ServerEntry.ipKey)
        aCoder.encode(self.username, forKey: ServerEntry.usernameKey)
        aCoder.encode(self.password, forKey: ServerEntry.passwordKey)
    }
}
