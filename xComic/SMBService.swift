//
//  SMBService.swift
//  ComicSMB
//
//  Created by Kun Wang on 4/23/16.
//  Copyright © 2016 Kun Wang. All rights reserved.
//

import Foundation

private func ipToStr(ip: UInt32) -> String {
    let byte1 = UInt8(ip & 0xff)
    let byte2 = UInt8((ip>>8) & 0xff)
    let byte3 = UInt8((ip>>16) & 0xff)
    let byte4 = UInt8((ip>>24) & 0xff)

    return "\(byte1).\(byte2).\(byte3).\(byte4)"
}

public struct SMBServerEntry {
    public var name = ""
    public var ip: UInt32 = 0

    public func ipStr() -> String {
        return ipToStr(ip)
    }
}

public class SMBService: NSObject {

    private struct Server {
        let name: String
        let ip: UInt32
        let session: COpaquePointer
        let user: String?
        let pass: String?
    }

    public static let sharedInstance = SMBService()

    private var nameService: COpaquePointer = netbios_ns_new()

    private let defaultDiscoveryTimeout: NSTimeInterval = 4.0

    private var _discovering = false
    private var onNetBIOSEntryAdded: ((SMBServerEntry) -> Void)? = nil
    private var onNetBIOSEntryRemoved: ((SMBServerEntry) -> Void)? = nil

    private var connectedServers = [String: Server]()

    public var discovering: Bool {
        get { return _discovering }
    }

    private override init() {}

    deinit {
        netbios_ns_destroy(nameService)
    }

    public func resolveIPWithName(name: String) -> UInt32? {
        var ip: UInt32 = 0
        guard netbios_ns_resolve(nameService, name, Int8(NETBIOS_FILESERVER), &ip) == 0 else { return nil }
        return ip
    }

    public func lookupNameByIP(ip: UInt32) -> String? {
        let name = netbios_ns_inverse(nameService, ip)
        guard name != nil else { return nil }
        return String.fromCString(name)
    }

    public func startDiscoveryWithTimeout(timeout: NSTimeInterval = 0, added: (SMBServerEntry) -> Void, removed: (SMBServerEntry) -> Void) -> Bool {
        if self.discovering {
            self.stopDiscovery()
        }

        var callbacks = netbios_ns_discover_callbacks()
        callbacks.p_opaque = UnsafeMutablePointer<Void>(Unmanaged.passUnretained(self).toOpaque())
        callbacks.pf_on_entry_added = { (ptr: UnsafeMutablePointer<Void>, centry: COpaquePointer) in
            let ser = Unmanaged<SMBService>.fromOpaque(COpaquePointer(ptr)).takeUnretainedValue()
            let name = String.fromCString(netbios_ns_entry_name(centry))
            let ip = netbios_ns_entry_ip(centry)
            dispatch_async(dispatch_get_main_queue()) {
                ser.onNetBIOSEntryAdded!(SMBServerEntry(name: name!, ip: ip))
            }
        }
        callbacks.pf_on_entry_removed = { (ptr: UnsafeMutablePointer<Void>, centry: COpaquePointer) in
            let ser = Unmanaged<SMBService>.fromOpaque(COpaquePointer(ptr)).takeUnretainedValue()
            let name = String.fromCString(netbios_ns_entry_name(centry))
            let ip = netbios_ns_entry_ip(centry)
            dispatch_async(dispatch_get_main_queue()) {
                ser.onNetBIOSEntryRemoved!(SMBServerEntry(name: name!, ip: ip))
            }
        }

        self._discovering = true
        self.onNetBIOSEntryAdded = added
        self.onNetBIOSEntryRemoved = removed

        let timeo = timeout <= DBL_EPSILON ? self.defaultDiscoveryTimeout : timeout

        let ret = netbios_ns_discover_start(self.nameService, UInt32(timeo), &callbacks)

        if ret == 0 {
            return true
        } else {
            self._discovering = false
            self.onNetBIOSEntryAdded = nil
            self.onNetBIOSEntryRemoved = nil
            return false
        }
    }

    public func stopDiscovery() {
        self._discovering = false
        self.onNetBIOSEntryAdded = nil
        self.onNetBIOSEntryRemoved = nil
        netbios_ns_discover_stop(self.nameService)
        netbios_ns_destroy(self.nameService)
        self.nameService = netbios_ns_new()
    }

    public func isConnected(name: String) -> Bool {
        return connectedServers[name] != nil
    }

    public func connect(name: String, ip: UInt32, username: String = "", password: String = "") -> Bool {
        if connectedServers[name] != nil {
            return false
        }

        let s = smb_session_new()
        guard smb_session_connect(s, name, ip, Int32(SMB_TRANSPORT_TCP)) == 0 else {
            smb_session_destroy(s)
            return false
        }
        smb_session_set_creds(s, name, username == "" ? " " : username, password == "" ? " " : password)
        guard smb_session_login(s) == 0 else {
            smb_session_destroy(s)
            return false
        }
        connectedServers[name] = Server(name: name, ip: ip, session: s, user: username, pass: password)
        SMBFileManager.sharedInstance.addSession(name, ipStr: ipToStr(ip), session: s)
        return true
    }

    public func disconnect(name: String) {
        if let srv = connectedServers[name] {
            SMBFileManager.sharedInstance.removeSession(srv.name, ipStr: ipToStr(srv.ip))
            smb_session_destroy(srv.session)
            connectedServers.removeValueForKey(name)
        }
    }
}
