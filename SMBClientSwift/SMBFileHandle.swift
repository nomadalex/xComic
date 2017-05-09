//
//  SMBFileHandle.swift
//  ComicSMB
//
//  Created by Kun Wang on 4/24/16.
//  Copyright © 2016 Kun Wang. All rights reserved.
//

import Foundation
import libdsm

public class SMBFileHandle: NSObject {
    fileprivate var session: OpaquePointer? = nil
    fileprivate var fd: smb_fd = 0

    internal init(session: OpaquePointer, fd: smb_fd) {
        self.session = session
        self.fd = fd
    }

    deinit {
        closeFile()
    }

    public var offsetInFile: UInt64 {
        get {
            return UInt64(smb_fseek(session, fd, 0, Int32(SMB_SEEK_CUR)))
        }
    }

    public var lengthOfFile: UInt64 {
        get {
            return smb_stat_get(smb_stat_fd(session, fd), SMB_STAT_SIZE)
        }
    }

    public func readDataToEndOfFile() -> Data {
        let offset = offsetInFile
        let length = lengthOfFile
        let (delta, _) = UInt64.subtractWithOverflow(length, offset)
        return readDataOfLength(Int(delta))
    }

    public func readDataOfLength(_ length: Int) -> Data {
        var data = Data(count: length)
        return data.withUnsafeMutableBytes { (bytes: UnsafeMutablePointer<UInt8>) -> Data in
            var ptr = bytes
            var rest = data.count
            while (rest > 0) {
                let readed = smb_fread(session, fd, ptr, rest)
                if readed < 0 {
                    return Data()
                }
                ptr = ptr.advanced(by: readed)
                rest = rest - readed
            }
            return data
        }
    }

    public func writeData(_ data: Data) -> Bool {
        return data.withUnsafeBytes { (bytes: UnsafePointer<UInt8>) -> Bool in
            var ptr = UnsafeMutablePointer<UInt8>.init(mutating: bytes);
            var rest = data.count
            while (rest > 0) {
                let writed = smb_fwrite(session, fd, ptr, rest)
                if writed < 0 {
                    return false
                }
                ptr = ptr.advanced(by: writed)
                rest = rest - writed
            }
            return true
        }
    }

    public func seekToEndOfFile() -> UInt64 {
        let length = lengthOfFile
        smb_fseek(session, fd, off_t(lengthOfFile), Int32(SMB_SEEK_SET))
        return length
    }

    public func seekToFileOffset(_ offset: UInt64) {
        smb_fseek(session, fd, off_t(offset), Int32(SMB_SEEK_SET))
    }

    public func closeFile() {
        if fd != 0 {
            smb_fclose(session, fd)
            fd = 0
        }
    }
}
