import Foundation

private let fatMagic: UInt32 = 0xcafebabe
private let fatCigam: UInt32 = 0xbebafeca
private let fatMagic64: UInt32 = 0xcafebabf
private let fatCigam64: UInt32 = 0xbfbafeca
private let mhMagic64: UInt32 = 0xfeedfacf
private let lcSegment64: UInt32 = 0x19
private let lcLoadDylib: UInt32 = 0xc
private let lcLoadWeakDylib: UInt32 = 0x18 | 0x80000000
private let lcReexportDylib: UInt32 = 0x1f | 0x80000000
private let lcLoadUpwardDylib: UInt32 = 0x23 | 0x80000000

enum MachOInjectorError: LocalizedError {
    case unsupportedBinary
    case insufficientHeaderPadding(String)
    case malformedBinary(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedBinary:
            return "Unsupported Mach-O format. Only 64-bit Mach-O is supported."
        case .insufficientHeaderPadding(let path):
            return "Not enough Mach-O header padding to inject \(path)."
        case .malformedBinary(let message):
            return "Malformed Mach-O binary: \(message)"
        }
    }
}

final class MachOInjector {
    func injectDylib(at fileURL: URL, loadPath: String) throws {
        var data = try Data(contentsOf: fileURL)
        let bigMagic = try data.readUInt32(at: 0, endian: .big)
        let littleMagic = try data.readUInt32(at: 0, endian: .little)

        switch bigMagic {
        case fatMagic, fatCigam, fatMagic64, fatCigam64:
            try patchFatBinary(data: &data, loadPath: loadPath, magic: bigMagic)
        default:
            guard littleMagic == mhMagic64 else {
                throw MachOInjectorError.unsupportedBinary
            }
            try patchThinSlice(data: &data, sliceOffset: 0, sliceSize: data.count, loadPath: loadPath)
        }

        try data.write(to: fileURL)
    }

    private func patchFatBinary(data: inout Data, loadPath: String, magic: UInt32) throws {
        let is64 = magic == fatMagic64 || magic == fatCigam64
        let nfatArch = Int(try data.readUInt32(at: 4, endian: .big))
        let archSize = is64 ? 32 : 20

        for index in 0..<nfatArch {
            let archOffset = 8 + (index * archSize)
            let sliceOffset: Int
            let sliceSize: Int

            if is64 {
                sliceOffset = Int(try data.readUInt64(at: archOffset + 8, endian: .big))
                sliceSize = Int(try data.readUInt64(at: archOffset + 16, endian: .big))
            } else {
                sliceOffset = Int(try data.readUInt32(at: archOffset + 8, endian: .big))
                sliceSize = Int(try data.readUInt32(at: archOffset + 12, endian: .big))
            }

            try patchThinSlice(data: &data, sliceOffset: sliceOffset, sliceSize: sliceSize, loadPath: loadPath)
        }
    }

    private func patchThinSlice(data: inout Data, sliceOffset: Int, sliceSize: Int, loadPath: String) throws {
        guard try data.readUInt32(at: sliceOffset, endian: .little) == mhMagic64 else {
            throw MachOInjectorError.unsupportedBinary
        }

        let ncmdsOffset = sliceOffset + 16
        let sizeofcmdsOffset = sliceOffset + 20
        let ncmds = Int(try data.readUInt32(at: ncmdsOffset, endian: .little))
        let sizeofcmds = Int(try data.readUInt32(at: sizeofcmdsOffset, endian: .little))
        let loadCommandsStart = sliceOffset + 32
        let loadCommandsEnd = loadCommandsStart + sizeofcmds
        let sliceEnd = sliceOffset + sliceSize

        guard loadCommandsEnd <= sliceEnd else {
            throw MachOInjectorError.malformedBinary("load commands exceed slice bounds")
        }

        var cursor = loadCommandsStart
        var firstContentOffset = Int.max

        for _ in 0..<ncmds {
            guard cursor + 8 <= sliceEnd else {
                throw MachOInjectorError.malformedBinary("load command header out of bounds")
            }

            let cmd = try data.readUInt32(at: cursor, endian: .little)
            let cmdsize = Int(try data.readUInt32(at: cursor + 4, endian: .little))
            guard cmdsize >= 8, cursor + cmdsize <= sliceEnd else {
                throw MachOInjectorError.malformedBinary("invalid load command size")
            }

            if isDylibCommand(cmd) {
                let nameOffset = Int(try data.readUInt32(at: cursor + 8, endian: .little))
                let existingPath = try data.readCString(at: cursor + nameOffset, upperBound: cursor + cmdsize)
                if existingPath == loadPath {
                    return
                }
            }

            if cmd == lcSegment64 {
                let nsects = Int(try data.readUInt32(at: cursor + 64, endian: .little))
                let sectionTableOffset = cursor + 72

                if nsects > 0 {
                    for sectionIndex in 0..<nsects {
                        let sectionOffset = sectionTableOffset + (sectionIndex * 80)
                        guard sectionOffset + 80 <= cursor + cmdsize else {
                            throw MachOInjectorError.malformedBinary("section table truncated")
                        }

                        let rawSize = Int(try data.readUInt64(at: sectionOffset + 40, endian: .little))
                        let rawOffset = Int(try data.readUInt32(at: sectionOffset + 48, endian: .little))
                        if rawOffset > 0, rawSize > 0 {
                            firstContentOffset = min(firstContentOffset, sliceOffset + rawOffset)
                        }
                    }
                } else {
                    let fileOffset = Int(try data.readUInt64(at: cursor + 40, endian: .little))
                    let fileSize = Int(try data.readUInt64(at: cursor + 48, endian: .little))
                    if fileOffset > 0, fileSize > 0 {
                        firstContentOffset = min(firstContentOffset, sliceOffset + fileOffset)
                    }
                }
            }

            cursor += cmdsize
        }

        if firstContentOffset == .max {
            firstContentOffset = sliceEnd
        }

        let commandData = makeDylibCommand(loadPath: loadPath)
        let availableSpace = firstContentOffset - loadCommandsEnd
        guard availableSpace >= commandData.count else {
            throw MachOInjectorError.insufficientHeaderPadding(loadPath)
        }

        data.replaceSubrange(loadCommandsEnd..<(loadCommandsEnd + commandData.count), with: commandData)
        try data.writeUInt32(UInt32(ncmds + 1), at: ncmdsOffset, endian: .little)
        try data.writeUInt32(UInt32(sizeofcmds + commandData.count), at: sizeofcmdsOffset, endian: .little)
    }

    private func isDylibCommand(_ cmd: UInt32) -> Bool {
        cmd == lcLoadDylib || cmd == lcLoadWeakDylib || cmd == lcReexportDylib || cmd == lcLoadUpwardDylib
    }

    private func makeDylibCommand(loadPath: String) -> Data {
        let pathData = Data(loadPath.utf8) + Data([0])
        let commandSize = aligned(24 + pathData.count, to: 8)
        var data = Data(count: commandSize)
        data.writeUInt32Unchecked(lcLoadDylib, at: 0, endian: .little)
        data.writeUInt32Unchecked(UInt32(commandSize), at: 4, endian: .little)
        data.writeUInt32Unchecked(24, at: 8, endian: .little)
        data.replaceSubrange(24..<(24 + pathData.count), with: pathData)
        return data
    }

    private func aligned(_ value: Int, to boundary: Int) -> Int {
        ((value + boundary - 1) / boundary) * boundary
    }
}

private enum Endian {
    case little
    case big
}

private extension Data {
    func readUInt32(at offset: Int, endian: Endian) throws -> UInt32 {
        guard offset + 4 <= count else {
            throw MachOInjectorError.malformedBinary("readUInt32 out of bounds")
        }
        let value = self[offset..<(offset + 4)].withUnsafeBytes { rawBuffer in
            rawBuffer.load(as: UInt32.self)
        }
        switch endian {
        case .little:
            return UInt32(littleEndian: value)
        case .big:
            return UInt32(bigEndian: value)
        }
    }

    func readUInt64(at offset: Int, endian: Endian) throws -> UInt64 {
        guard offset + 8 <= count else {
            throw MachOInjectorError.malformedBinary("readUInt64 out of bounds")
        }
        let value = self[offset..<(offset + 8)].withUnsafeBytes { rawBuffer in
            rawBuffer.load(as: UInt64.self)
        }
        switch endian {
        case .little:
            return UInt64(littleEndian: value)
        case .big:
            return UInt64(bigEndian: value)
        }
    }

    mutating func writeUInt32(_ value: UInt32, at offset: Int, endian: Endian) throws {
        guard offset + 4 <= count else {
            throw MachOInjectorError.malformedBinary("writeUInt32 out of bounds")
        }
        writeUInt32Unchecked(value, at: offset, endian: endian)
    }

    mutating func writeUInt32Unchecked(_ value: UInt32, at offset: Int, endian: Endian) {
        var encoded: UInt32
        switch endian {
        case .little:
            encoded = value.littleEndian
        case .big:
            encoded = value.bigEndian
        }
        Swift.withUnsafeBytes(of: &encoded) { buffer in
            replaceSubrange(offset..<(offset + 4), with: buffer)
        }
    }

    func readCString(at offset: Int, upperBound: Int) throws -> String {
        guard offset < min(upperBound, count) else {
            throw MachOInjectorError.malformedBinary("string offset out of bounds")
        }
        var end = offset
        let bound = min(upperBound, count)
        while end < bound, self[end] != 0 {
            end += 1
        }
        return String(decoding: self[offset..<end], as: UTF8.self)
    }
}
