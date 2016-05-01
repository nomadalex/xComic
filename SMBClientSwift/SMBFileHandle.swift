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
    private var session: COpaquePointer = nil
    private var fd: smb_fd = 0

    internal init(session: COpaquePointer, fd: smb_fd) {
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

    public func readDataToEndOfFile() -> NSData {
        let offset = offsetInFile
        let length = lengthOfFile
        let (delta, _) = UInt64.subtractWithOverflow(length, offset)
        return readDataOfLength(Int(delta))
    }

    public func readDataOfLength(length: Int) -> NSData {
        if let data = NSMutableData(length: length) {
            var ptr = UnsafeMutablePointer<Int8>(data.mutableBytes)
            var rest = data.length
            while (rest > 0) {
                let readed = smb_fread(session, fd, ptr, rest)
                if readed < 0 {
                    return NSData()
                }
                ptr = ptr.advancedBy(readed)
                rest = rest - readed
            }
            return data
        }
        return NSData()
    }

    public func writeData(data: NSData) -> Bool {
        var ptr = unsafeBitCast(data.bytes, UnsafeMutablePointer<Int8>.self)
        var rest = data.length
        while (rest > 0) {
            let writed = smb_fwrite(session, fd, ptr, rest)
            if writed < 0 {
                return false
            }
            ptr = ptr.advancedBy(writed)
            rest = rest - writed
        }
        return true
    }

    public func seekToEndOfFile() -> UInt64 {
        let length = lengthOfFile
        smb_fseek(session, fd, off_t(lengthOfFile), Int32(SMB_SEEK_SET))
        return length
    }

    public func seekToFileOffset(offset: UInt64) {
        smb_fseek(session, fd, off_t(offset), Int32(SMB_SEEK_SET))
    }

    public func closeFile() {
        if fd != 0 {
            smb_fclose(session, fd)
            fd = 0
        }
    }
}
