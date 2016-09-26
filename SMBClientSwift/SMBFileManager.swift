//
//  SMBFileManager.swift
//  ComicSMB
//
//  Created by Kun Wang on 4/24/16.
//  Copyright © 2016 Kun Wang. All rights reserved.
//

import Foundation
import libdsm

open class SMBFileManager: NSObject {
    fileprivate let SMB_MOD_RO = SMB_MOD_READ | SMB_MOD_READ_EXT | SMB_MOD_READ_ATTR | SMB_MOD_READ_CTL
    fileprivate let SMB_MOD_RW = SMB_MOD_READ | SMB_MOD_WRITE | SMB_MOD_APPEND | SMB_MOD_READ_EXT | SMB_MOD_WRITE_EXT | SMB_MOD_READ_ATTR | SMB_MOD_WRITE_ATTR | SMB_MOD_READ_CTL

    fileprivate struct Path {
        fileprivate var string: String

        init(_ str: String) {
            self.string = str
        }

        func toString() -> String {
            return string
        }

        var isRoot: Bool {
            get { return string == "/" }
        }

        func combine(_ path: String) -> Path {
            guard path != "" else { return self }
            if path[path.startIndex] == "/" {
                return Path(path)
            } else {
                return Path(string + "/" + path)
            }
        }

        func normalize() -> Path? {
            var parts = [String]()
            for s in string.components(separatedBy: "/") {
                switch s {
                case "", ".": break
                case "..":
                     guard !parts.isEmpty else { return nil }
                     parts.removeLast()
                default:
                    parts.append(s)
                }
            }
            return Path("/" + parts.joined(separator: "/"))
        }

        func parse(_ checkShare: Bool = true) -> (String, String, String)? {
            let parts = string.components(separatedBy: "/")
            guard parts.count > 1 else { return nil }
            let ipStr = parts[1]
            let share = parts.count > 2 ? parts[2] : ""
            guard !checkShare || share != "" else { return nil }
            let interPath = parts.count > 3 ? "/" + parts[3..<parts.count].joined(separator: "/") : "/"
            return (ipStr, share, interPath)
        }
    }

    fileprivate class SessionData {
        let session: OpaquePointer
        var shares = [String: smb_tid]()

        init(session: OpaquePointer) {
            self.session = session
        }
    }

    open static let sharedInstance = SMBFileManager()

    fileprivate var _currentDirectoryPath = Path("/")
    fileprivate var sessions = [String: SessionData]()

    fileprivate override init() {}

    internal func addSession(_ name: String, ipStr: String, session: OpaquePointer) {
        let s = SessionData(session: session)
        sessions[name] = s
        sessions[ipStr] = s
    }

    internal func removeSession(_ name: String, ipStr: String) {
        sessions.removeValue(forKey: name)
        sessions.removeValue(forKey: ipStr)
    }

    fileprivate func connectShare(_ sessionData: SessionData, share: String) -> smb_tid? {
        var tid: smb_tid = 0
        if smb_tree_connect(sessionData.session, share, &tid) == 0 {
            sessionData.shares[share] = tid
            return tid
        }
        return nil
    }

    fileprivate func disconnectShare(_ sessionData: SessionData, share: String) {
        if let tid = sessionData.shares[share] {
            smb_tree_disconnect(sessionData.session, tid)
            sessionData.shares.removeValue(forKey: share)
        }
    }

    fileprivate func toNormalizedFullPath(_ path: String) -> Path? {
        return _currentDirectoryPath.combine(path).normalize()
    }

    fileprivate func toSMBPath(_ path: String) -> String {
        if path == "/" {
            return ""
        }
        return path.replacingOccurrences(of: "/", with: "\\")
    }

    fileprivate func getOrConnectShare(_ ipStr: String, share: String) -> (OpaquePointer, smb_tid)? {
        guard let sessionData = self.sessions[ipStr] else { return nil }
        if let tid = sessionData.shares[share] {
            return (sessionData.session, tid)
        } else {
            guard let tid = connectShare(sessionData, share: share) else { return nil }
            return (sessionData.session, tid)
        }
    }

    open var currentDirectoryPath: String {
        get {
            return _currentDirectoryPath.toString()
        }
    }

    open func changeCurrentDirectoryPath(_ path: String) -> Bool {
        guard let apath = toNormalizedFullPath(path) else { return false }
        if apath.isRoot {
            _currentDirectoryPath = apath
            return true
        }
        guard let (ipStr, share, _) = apath.parse(false) else { return false }
        if share == "" {
            guard self.sessions[ipStr] != nil else { return false }
            _currentDirectoryPath = apath
            return true
        } else {
            guard directoryExistsAtPath(apath.toString()) else { return false }
            _currentDirectoryPath = apath
            return true
        }
    }

    open func contentsOfDirectoryAtPath(_ path: String) -> [String] {
        guard let (ipStr, share, ipath) = toNormalizedFullPath(path)?.parse(false)
              else { return [String]() }
        if share == "" {
            guard let s = self.sessions[ipStr]?.session else { return [String]() }
            var list: smb_share_list? = nil
            guard smb_share_get_list(s, &list, nil) == 0 else { return [String]() }
            defer { smb_share_list_destroy(list) }
            let count = smb_share_list_count(list)
            return (0..<count).map { String(cString: smb_share_list_at(list, $0)) }
        } else {
            guard let (s, tid) = getOrConnectShare(ipStr, share: share) else { return [String]() }
            let pattern = ipath == "/" ? "\\*" : toSMBPath(ipath) + "\\*"
            let list = smb_find(s, tid, pattern)
            guard list != nil else { return [String]() }
            defer { smb_stat_list_destroy(list) }
            let count = smb_stat_list_count(list)
            return (0..<count).map({ String(cString: smb_stat_name(smb_stat_list_at(list, $0))) }).filter({ $0 != "." && $0 != ".." })
        }
    }

    open func createDirectoryAtPath(_ path: String) -> Bool {
        guard let (ipStr, share, ipath) = toNormalizedFullPath(path)?.parse() else { return false }
        guard let (s, tid) = getOrConnectShare(ipStr, share: share) else { return false }
        guard smb_directory_create(s, tid, toSMBPath(ipath)) == 0 else { return false }
        return true
    }

    open func removeItemAtPath(_ path: String) {
        guard let (ipStr, share, ipath) = toNormalizedFullPath(path)?.parse() else { return }
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

    open func moveItemAtPath(_ path: String, toPath: String) -> Bool {
        guard let (ipStr, share, ipath) = toNormalizedFullPath(path)?.parse() else { return false }
        guard let (toIpStr, toShare, toIPath) = toNormalizedFullPath(toPath)?.parse() else { return false }
        guard ipStr == toIpStr && share == toShare && ipath != "/" && toIPath != "/" else { return false }
        guard let (s, tid) = getOrConnectShare(ipStr, share: share) else { return false }
        guard smb_file_mv(s, tid, toSMBPath(ipath), toSMBPath(toIPath)) == 0 else { return false }
        return true
    }

    open func fileExistsAtPath(_ path: String) -> Bool {
        guard let (ipStr, share, ipath) = toNormalizedFullPath(path)?.parse() else { return false }
        guard let (s, tid) = getOrConnectShare(ipStr, share: share) else { return false }
        if ipath == "/" {
            return true
        }
        let st = smb_fstat(s, tid, toSMBPath(ipath))
        guard st != nil else { return false }
        defer { smb_stat_destroy(st) }
        return true
    }

    open func directoryExistsAtPath(_ path: String) -> Bool {
        guard let (ipStr, share, ipath) = toNormalizedFullPath(path)?.parse() else { return false }
        guard let (s, tid) = getOrConnectShare(ipStr, share: share) else { return false }
        if ipath == "/" {
            return true
        }
        let st = smb_fstat(s, tid, toSMBPath(ipath))
        guard st != nil else { return false }
        defer { smb_stat_destroy(st) }
        return smb_stat_get(st, SMB_STAT_ISDIR) == 1
    }

    fileprivate func openFile(_ path: String, mod: UInt32) -> SMBFileHandle? {
        guard let (ipStr, share, ipath) = toNormalizedFullPath(path)?.parse() else { return nil }
        guard let (s, tid) = getOrConnectShare(ipStr, share: share) else { return nil }
        var fd: smb_fd = 0
        guard smb_fopen(s, tid, ipath, mod, &fd) == 0 else { return nil }
        return SMBFileHandle(session: s, fd: fd)
    }

    open func openFile(forReadingAtPath path: String) -> SMBFileHandle? {
        return openFile(path, mod: UInt32(SMB_MOD_RO))
    }

    open func openFile(forWritingAtPath path: String) -> SMBFileHandle? {
        return openFile(path, mod: UInt32(SMB_MOD_RW))
    }

    open func openFile(forUpdatingAtPath path: String) -> SMBFileHandle? {
        return openFile(path, mod: UInt32(SMB_MOD_RW))
    }
}
