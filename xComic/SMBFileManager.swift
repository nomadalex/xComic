//
//  SMBFileManager.swift
//  ComicSMB
//
//  Created by Kun Wang on 4/24/16.
//  Copyright © 2016 Kun Wang. All rights reserved.
//

import Foundation

public class SMBFileManager: NSObject {
    private let SMB_MOD_RO = SMB_MOD_READ | SMB_MOD_READ_EXT | SMB_MOD_READ_ATTR | SMB_MOD_READ_CTL
    private let SMB_MOD_RW = SMB_MOD_READ | SMB_MOD_WRITE | SMB_MOD_APPEND | SMB_MOD_READ_EXT | SMB_MOD_WRITE_EXT | SMB_MOD_READ_ATTR | SMB_MOD_WRITE_ATTR | SMB_MOD_READ_CTL

    private class SessionData {
        let session: COpaquePointer
        var shares = [String: smb_tid]()

        init(session: COpaquePointer) {
            self.session = session
        }
    }

    private var _currentDirectoryPath = "/"
    private var sessions = [String: SessionData]()

    internal override init() {}

    internal func addSession(ipStr: String, session: COpaquePointer) {
        sessions[ipStr] = SessionData(session: session)
    }

    internal func removeSession(ipStr: String) {
        sessions.removeValueForKey(ipStr)
    }

    internal func getSession(ipStr: String) -> COpaquePointer {
        if let sessionData = sessions[ipStr] {
            return sessionData.session
        }
        return nil
    }

    private func connectShare(sessionData: SessionData, share: String) -> smb_tid? {
        var tid: smb_tid = 0
        if smb_tree_connect(sessionData.session, share, &tid) == 0 {
            sessionData.shares[share] = tid
            return tid
        }
        return nil
    }

    private func disconnectShare(sessionData: SessionData, share: String) {
        if let tid = sessionData.shares[share] {
            smb_tree_disconnect(sessionData.session, tid)
            sessionData.shares.removeValueForKey(share)
        }
    }

    private func toAbsoultePath(path: String) -> String {
        var p: String
        if path != "/" && path[path.endIndex.predecessor()] == "/" {
            p = path.substringToIndex(path.endIndex.predecessor())
        } else {
            p = path
        }
        if p[p.startIndex] == "/" {
            return p;
        }
        if path == "" {
            return _currentDirectoryPath
        }
        return _currentDirectoryPath + "/" + p
    }

    private func parsePath(path: String, checkShare: Bool = true) -> (String, String, String)? {
        var parts = path.componentsSeparatedByString("/")
        if parts.last == "" {
            parts.removeLast()
        }

        let ipStr = parts.count > 1 ? parts[1] : ""
        let share = parts.count > 2 ? parts[2] : ""

        if ipStr == "" || (checkShare && share == "") {
            return nil
        }

        let interPath = parts.count > 3 ?
                        "/" + parts[3..<parts.count].joinWithSeparator("/") :
                        "/"
        return (ipStr, share, interPath)
    }

    private func toSMBPath(path: String) -> String {
        if path == "/" {
            return ""
        }
        return path.stringByReplacingOccurrencesOfString("/", withString: "\\")
    }

    private func getOrConnectShare(ipStr: String, share: String) -> (COpaquePointer, smb_tid)? {
        guard let sessionData = self.sessions[ipStr] else { return nil }
        if let tid = sessionData.shares[share] {
            return (sessionData.session, tid)
        } else {
            guard let tid = connectShare(sessionData, share: share) else { return nil }
            return (sessionData.session, tid)
        }
    }

    public var currentDirectoryPath: String {
        get {
            return _currentDirectoryPath
        }
    }

    public func changeCurrentDirectoryPath(path: String) -> Bool {
        let apath = toAbsoultePath(path)
        if apath == "/" {
            _currentDirectoryPath = apath
            return true
        }
        guard let (ipStr, share, _) = parsePath(apath, checkShare: false) else { return false }
        if share == "" {
            guard self.sessions[ipStr] != nil else { return false }
            _currentDirectoryPath = apath
            return true
        } else {
            guard directoryExistsAtPath(apath) else { return false }
            _currentDirectoryPath = apath
            return true
        }
    }

    public func contentsOfDirectoryAtPath(path: String) -> [String] {
        guard let (ipStr, share, ipath) = parsePath(toAbsoultePath(path), checkShare: false) else { return [String]() }
        if share == "" {
            guard let s = self.sessions[ipStr]?.session else { return [String]() }
            var list: smb_share_list = nil
            guard smb_share_get_list(s, &list, nil) == 0 else { return [String]() }
            defer { smb_share_list_destroy(list) }
            let count = smb_share_list_count(list)
            return (0..<count).map { String.fromCString(smb_share_list_at(list, $0))! }
        } else {
            guard let (s, tid) = getOrConnectShare(ipStr, share: share) else { return [String]() }
            let pattern = ipath == "/" ? "\\*" : toSMBPath(ipath) + "\\*"
            let list = smb_find(s, tid, pattern)
            guard list != nil else { return [String]() }
            defer { smb_stat_list_destroy(list) }
            let count = smb_stat_list_count(list)
            return (0..<count).map { String.fromCString(smb_stat_name(smb_stat_list_at(list, $0)))! }
        }
    }

    public func createDirectoryAtPath(path: String, withIntermediateDirectories createIntermediates: Bool = false) -> Bool {
        guard let (ipStr, share, ipath) = parsePath(toAbsoultePath(path)) else { return false }
        guard let (s, tid) = getOrConnectShare(ipStr, share: share) else { return false }
        guard smb_directory_create(s, tid, toSMBPath(ipath)) == 0 else { return false }
        return true
    }

    public func removeItemAtPath(path: String) {
        guard let (ipStr, share, ipath) = parsePath(toAbsoultePath(path)) else { return }
        guard let (s, tid) = getOrConnectShare(ipStr, share: share) else { return }
        let smbPath = toSMBPath(ipath)
        let st = smb_fstat(s, tid, smbPath)
        guard st != nil else { return }
        defer { smb_stat_destroy(st) }
        if smb_stat_get(st, SMB_STAT_ISDIR) == 1 {
            smb_directory_rm(s, tid, smbPath)
        } else {
            smb_file_rm(s, tid, smbPath)
        }
    }

    public func moveItemAtPath(path: String, toPath: String) -> Bool {
        guard let (ipStr, share, ipath) = parsePath(toAbsoultePath(path)) else { return false }
        guard let (toIpStr, toShare, toIPath) = parsePath(toAbsoultePath(toPath)) else { return false }
        guard ipStr == toIpStr && share == toShare && ipath != "/" && toIPath != "/" else { return false }
        guard let (s, tid) = getOrConnectShare(ipStr, share: share) else { return false }
        guard smb_file_mv(s, tid, toSMBPath(ipath), toSMBPath(toIPath)) == 0 else { return false }
        return true
    }

    public func fileExistsAtPath(path: String) -> Bool {
        guard let (ipStr, share, ipath) = parsePath(toAbsoultePath(path)) else { return false }
        guard let (s, tid) = getOrConnectShare(ipStr, share: share) else { return false }
        if ipath == "/" {
            return true
        }
        let st = smb_fstat(s, tid, toSMBPath(ipath))
        guard st != nil else { return false }
        defer { smb_stat_destroy(st) }
        return true
    }

    public func directoryExistsAtPath(path: String) -> Bool {
        guard let (ipStr, share, ipath) = parsePath(toAbsoultePath(path)) else { return false }
        guard let (s, tid) = getOrConnectShare(ipStr, share: share) else { return false }
        if ipath == "/" {
            return true
        }
        let st = smb_fstat(s, tid, toSMBPath(ipath))
        guard st != nil else { return false }
        defer { smb_stat_destroy(st) }
        return smb_stat_get(st, SMB_STAT_ISDIR) == 1
    }

    private func openFile(path: String, mod: UInt32) -> SMBFileHandle? {
        guard let (ipStr, share, ipath) = parsePath(toAbsoultePath(path)) else { return nil }
        guard let (s, tid) = getOrConnectShare(ipStr, share: share) else { return nil }
        var fd: smb_fd = 0
        guard smb_fopen(s, tid, ipath, mod, &fd) == 0 else { return nil }
        return SMBFileHandle(session: s, fd: fd)
    }

    public func openFile(forReadingAtPath path: String) -> SMBFileHandle? {
        return openFile(path, mod: UInt32(SMB_MOD_RO))
    }

    public func openFile(forWritingAtPath path: String) -> SMBFileHandle? {
        return openFile(path, mod: UInt32(SMB_MOD_RW))
    }

    public func openFile(forUpdatingAtPath path: String) -> SMBFileHandle? {
        return openFile(path, mod: UInt32(SMB_MOD_RW))
    }
}
