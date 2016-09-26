//
//  SMBClient.swift
//  ComicSMB
//
//  Created by Kun Wang on 4/23/16.
//  Copyright © 2016 Kun Wang. All rights reserved.
//

import Foundation
import libdsm

private func ipToStr(_ ip: UInt32) -> String {
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

open class SMBClient: NSObject {

    fileprivate struct Server {
        let name: String
        let ip: UInt32
        let session: OpaquePointer
        let user: String
        let pass: String
    }

    open static let sharedInstance = SMBClient()

    fileprivate var nameService: OpaquePointer = netbios_ns_new()

    fileprivate let defaultDiscoveryTimeout: TimeInterval = 4.0

    fileprivate var _discovering = false
    fileprivate var onNetBIOSEntryAdded: ((SMBServerEntry) -> Void)? = nil
    fileprivate var onNetBIOSEntryRemoved: ((SMBServerEntry) -> Void)? = nil

    fileprivate var connectedServers = [String: Server]()

    open var discovering: Bool {
        get { return _discovering }
    }

    fileprivate override init() {}

    deinit {
        netbios_ns_destroy(nameService)
    }

    open func resolveIPWithName(_ name: String) -> UInt32? {
        var ip: UInt32 = 0
        guard netbios_ns_resolve(nameService, name, Int8(NETBIOS_FILESERVER), &ip) == 0 else { return nil }
        return ip
    }

    open func lookupNameByIP(_ ip: UInt32) -> String? {
        let name = netbios_ns_inverse(nameService, ip)
        guard name != nil else { return nil }
        return String(cString: name!)
    }

    open func startDiscoveryWithTimeout(_ timeout: TimeInterval = 0, added: @escaping (SMBServerEntry) -> Void, removed: @escaping (SMBServerEntry) -> Void) -> Bool {
        if self.discovering {
            self.stopDiscovery()
        }

        var callbacks = netbios_ns_discover_callbacks()
        callbacks.p_opaque = Unmanaged.passUnretained(self).toOpaque()
        callbacks.pf_on_entry_added = { (ptr: UnsafeMutableRawPointer?, centry: OpaquePointer?) in
            let ser = Unmanaged<SMBClient>.fromOpaque(ptr!).takeUnretainedValue()
            let name = String(cString: netbios_ns_entry_name(centry!))
            let ip = netbios_ns_entry_ip(centry!)
            DispatchQueue.main.async {
                ser.onNetBIOSEntryAdded!(SMBServerEntry(name: name, ip: ip))
            }
        }
        callbacks.pf_on_entry_removed = { (ptr: UnsafeMutableRawPointer?, centry: OpaquePointer?) in
            let ser = Unmanaged<SMBClient>.fromOpaque(ptr!).takeUnretainedValue()
            let name = String(cString: netbios_ns_entry_name(centry!))
            let ip = netbios_ns_entry_ip(centry!)
            DispatchQueue.main.async {
                ser.onNetBIOSEntryRemoved!(SMBServerEntry(name: name, ip: ip))
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

    open func stopDiscovery() {
        self._discovering = false
        self.onNetBIOSEntryAdded = nil
        self.onNetBIOSEntryRemoved = nil
        netbios_ns_discover_stop(self.nameService)
        netbios_ns_destroy(self.nameService)
        self.nameService = netbios_ns_new()
    }

    open func isConnected(_ name: String) -> Bool {
        return connectedServers[name] != nil
    }

    open func isConnected(_ name: String, withUser username: String) -> Bool {
        guard let srv = connectedServers[name] else { return false }
        return srv.user == username
    }

    open func connect(_ name: String, ip: UInt32, username: String = "", password: String = "") -> Bool {
        if connectedServers[name] != nil {
            return false
        }

        let s = smb_session_new()
        guard smb_session_connect(s, name, ip, Int32(SMB_TRANSPORT_TCP)) == 0 else {
            smb_session_destroy(s)
            return false
        }
        smb_session_set_creds(s, name, username.isEmpty ? " " : username, password.isEmpty ? " " : password)
        guard smb_session_login(s) == 0 else {
            smb_session_destroy(s)
            return false
        }
        guard username.isEmpty || smb_session_is_guest(s) != 1 else { // here has a bug in libdsm, it report -1 but logined
            smb_session_destroy(s)
            return false
        }
        connectedServers[name] = Server(name: name, ip: ip, session: s!, user: username, pass: password)
        SMBFileManager.sharedInstance.addSession(name, ipStr: ipToStr(ip), session: s!)
        return true
    }

    open func disconnect(_ name: String) {
        if let srv = connectedServers[name] {
            SMBFileManager.sharedInstance.removeSession(srv.name, ipStr: ipToStr(srv.ip))
            smb_session_destroy(srv.session)
            connectedServers.removeValue(forKey: name)
        }
    }
}
