import Foundation
import Compression

/// Minimal ZIP reader (stored and deflate entries). Used to open .docx files on the device.
struct ZipReader {
    private struct Entry {
        let method: Int
        let compressedSize: Int
        let uncompressedSize: Int
        let headerOffset: Int
    }

    private let data: Data
    private let entries: [String: Entry]

    var entryNames: [String] { entries.keys.sorted() }

    init?(url: URL) {
        guard let loaded = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        self.init(data: loaded)
    }

    init?(data input: Data) {
        let base = input.startIndex == 0 ? input : Data(input)
        guard base.count >= 22 else { return nil }

        // The end-of-central-directory record sits at the very end (followed by an optional comment).
        var eocd = -1
        var cursor = base.count - 22
        let lowest = max(0, base.count - 22 - 65535)
        while cursor >= lowest {
            if ZipReader.u32(base, cursor) == 0x0605_4B50 {
                eocd = cursor
                break
            }
            cursor -= 1
        }
        guard eocd >= 0 else { return nil }

        let count = ZipReader.u16(base, eocd + 10)
        var offset = ZipReader.u32(base, eocd + 16)
        var found: [String: Entry] = [:]
        for _ in 0..<count {
            guard offset >= 0, offset + 46 <= base.count,
                  ZipReader.u32(base, offset) == 0x0201_4B50 else { return nil }
            let method = ZipReader.u16(base, offset + 10)
            let compressed = ZipReader.u32(base, offset + 20)
            let uncompressed = ZipReader.u32(base, offset + 24)
            let nameLength = ZipReader.u16(base, offset + 28)
            let extraLength = ZipReader.u16(base, offset + 30)
            let commentLength = ZipReader.u16(base, offset + 32)
            let headerOffset = ZipReader.u32(base, offset + 42)
            guard offset + 46 + nameLength <= base.count else { return nil }
            let nameData = base.subdata(in: (offset + 46)..<(offset + 46 + nameLength))
            let name = String(decoding: nameData, as: UTF8.self)
            found[name] = Entry(method: method, compressedSize: compressed,
                                uncompressedSize: uncompressed, headerOffset: headerOffset)
            offset += 46 + nameLength + extraLength + commentLength
        }
        self.data = base
        self.entries = found
    }

    func contains(_ name: String) -> Bool { entries[name] != nil }

    /// The decompressed bytes of one entry, or nil when it is missing or unreadable.
    func read(_ name: String) -> Data? {
        guard let entry = entries[name] else { return nil }
        let header = entry.headerOffset
        guard header >= 0, header + 30 <= data.count,
              ZipReader.u32(data, header) == 0x0403_4B50 else { return nil }
        let start = header + 30 + ZipReader.u16(data, header + 26) + ZipReader.u16(data, header + 28)
        let end = start + entry.compressedSize
        guard start <= end, end <= data.count else { return nil }
        let payload = data.subdata(in: start..<end)
        switch entry.method {
        case 0: return payload
        case 8: return ZipReader.inflate(payload, expectedSize: entry.uncompressedSize)
        default: return nil
        }
    }

    // MARK: Helpers

    private static func u16(_ d: Data, _ o: Int) -> Int {
        let low = Int(d[o])
        let high = Int(d[o + 1]) << 8
        return low | high
    }

    private static func u32(_ d: Data, _ o: Int) -> Int {
        let b0 = Int(d[o])
        let b1 = Int(d[o + 1]) << 8
        let b2 = Int(d[o + 2]) << 16
        let b3 = Int(d[o + 3]) << 24
        return b0 | b1 | b2 | b3
    }

    /// ZIP stores raw deflate streams, which is what COMPRESSION_ZLIB decodes.
    private static func inflate(_ input: Data, expectedSize: Int) -> Data? {
        if expectedSize == 0 { return Data() }
        guard expectedSize > 0, expectedSize <= 128 * 1024 * 1024 else { return nil }
        var output = Data(count: expectedSize)
        let inputCount = input.count
        let written = output.withUnsafeMutableBytes { (out: UnsafeMutableRawBufferPointer) -> Int in
            return input.withUnsafeBytes { (src: UnsafeRawBufferPointer) -> Int in
                guard let outBase = out.bindMemory(to: UInt8.self).baseAddress,
                      let srcBase = src.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(outBase, expectedSize, srcBase, inputCount, nil, COMPRESSION_ZLIB)
            }
        }
        return written == expectedSize ? output : nil
    }
}
