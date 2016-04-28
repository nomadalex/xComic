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

    private static let nameKey = "name"
    private static let ipKey = "ip"
    private static let usernameKey = "username"
    private static let passwordKey = "password"

    init(name: String, ip: UInt32, username: String, password: String) {
        self.name = name
        self.ip = ip
        self.username = username
        self.password = password
    }

    required init?(coder aDecoder: NSCoder) {
        self.name = aDecoder.decodeObjectForKey(ServerEntry.nameKey) as! String
        self.ip = UInt32(aDecoder.decodeInt32ForKey(ServerEntry.ipKey))
        self.username = aDecoder.decodeObjectForKey(ServerEntry.usernameKey) as! String
        self.password = aDecoder.decodeObjectForKey(ServerEntry.passwordKey) as! String
    }

    func encodeWithCoder(aCoder: NSCoder) {
        aCoder.encodeObject(self.name, forKey: ServerEntry.nameKey)
        aCoder.encodeInt32(Int32(self.ip), forKey: ServerEntry.ipKey)
        aCoder.encodeObject(self.username, forKey: ServerEntry.usernameKey)
        aCoder.encodeObject(self.password, forKey: ServerEntry.passwordKey)
    }
}