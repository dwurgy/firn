#if os(macOS)
import Foundation
import zlib

@available(macOS 15.4, *)
enum ExtensionArchive {
    static let maximumBytes = 100 * 1024 * 1024
    static let maximumExpandedBytes = 400 * 1024 * 1024
    private static let maximumEntries = 2_000

    static func validate(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size >= 22, size <= maximumBytes else { throw WebExtensionLibraryError.invalidArchive }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count >= 22, data.count <= maximumBytes else { throw WebExtensionLibraryError.invalidArchive }
        func number(_ offset: Int, _ width: Int) -> Int? {
            guard offset >= 0, width > 0, offset <= data.count - width else { return nil }
            var value = 0
            for index in 0..<width { value |= Int(data[offset + index]) << (index * 8) }
            return value
        }
        let searchStart = max(0, data.count - 65_557)
        guard let end = stride(from: data.count - 22, through: searchStart, by: -1).first(where: {
            number($0, 4) == 0x06054b50 && $0 + 22 + (number($0 + 20, 2) ?? -1) == data.count
        }), number(end + 4, 2) == 0, number(end + 6, 2) == 0,
              let count = number(end + 10, 2), count > 0, count <= maximumEntries,
              number(end + 8, 2) == count,
              let directorySize = number(end + 12, 4), let directoryOffset = number(end + 16, 4),
              directoryOffset <= end, directorySize == end - directoryOffset else { throw WebExtensionLibraryError.invalidArchive }

        var cursor = directoryOffset
        var expanded = 0
        var paths = Set<String>()
        var files = Set<String>()
        var ranges: [Range<Int>] = []
        var hasManifest = false
        for _ in 0..<count {
            guard cursor <= end - 46, number(cursor, 4) == 0x02014b50,
                  let flags = number(cursor + 8, 2), flags & ~0x80e == 0,
                  let method = number(cursor + 10, 2), method == 0 || method == 8,
                  let crc = number(cursor + 16, 4),
                  let compressed = number(cursor + 20, 4), let uncompressed = number(cursor + 24, 4),
                  let nameLength = number(cursor + 28, 2), let extraLength = number(cursor + 30, 2),
                  let commentLength = number(cursor + 32, 2), let attributes = number(cursor + 38, 4),
                  let localOffset = number(cursor + 42, 4), nameLength > 0,
                  nameLength + extraLength + commentLength <= end - cursor - 46,
                  localOffset <= directoryOffset - 30, number(localOffset, 4) == 0x04034b50,
                  number(localOffset + 6, 2) == flags, number(localOffset + 8, 2) == method,
                  let localCRC = number(localOffset + 14, 4),
                  let localCompressed = number(localOffset + 18, 4),
                  let localUncompressed = number(localOffset + 22, 4),
                  let localNameLength = number(localOffset + 26, 2),
                  let localExtraLength = number(localOffset + 28, 2),
                  localNameLength == nameLength,
                  localNameLength + localExtraLength <= directoryOffset - localOffset - 30,
                  data[(cursor + 46)..<(cursor + 46 + nameLength)] == data[(localOffset + 30)..<(localOffset + 30 + nameLength)],
                  let name = String(data: data[(cursor + 46)..<(cursor + 46 + nameLength)], encoding: .utf8),
                  !name.hasPrefix("/"), !name.contains("\\"), !name.contains("\0"),
                  uncompressed <= maximumExpandedBytes - expanded,
                  (compressed > 0 || uncompressed == 0),
                  (flags & 8 != 0 ? (localCRC == 0 || localCRC == crc) : localCRC == crc),
                  (flags & 8 != 0 ? (localCompressed == 0 || localCompressed == compressed) : localCompressed == compressed),
                  (flags & 8 != 0 ? (localUncompressed == 0 || localUncompressed == uncompressed) : localUncompressed == uncompressed),
                  method != 0 || compressed == uncompressed else { throw WebExtensionLibraryError.invalidArchive }

            let components = name.split(separator: "/", omittingEmptySubsequences: false)
            let isDirectory = name.hasSuffix("/")
            let meaningful = isDirectory ? components.dropLast() : components[...]
            guard !meaningful.isEmpty, meaningful.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
                  !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
                  !name.hasPrefix("//") else { throw WebExtensionLibraryError.invalidArchive }
            let key = meaningful.joined(separator: "/").precomposedStringWithCanonicalMapping.lowercased()
            guard paths.insert(key).inserted else { throw WebExtensionLibraryError.invalidArchive }
            if !isDirectory { files.insert(key) }
            if name == "manifest.json" && !isDirectory { hasManifest = true }
            let unixMode = (attributes >> 16) & 0xF000
            guard unixMode == 0 || unixMode == (isDirectory ? 0x4000 : 0x8000) else { throw WebExtensionLibraryError.invalidArchive }

            let payloadStart = localOffset + 30 + localNameLength + localExtraLength
            guard compressed <= directoryOffset - payloadStart else { throw WebExtensionLibraryError.invalidArchive }
            let payloadEnd = payloadStart + compressed
            let actualCRC = try checksum(data, start: payloadStart, length: compressed, method: method, declaredSize: uncompressed)
            guard actualCRC == crc else { throw WebExtensionLibraryError.invalidArchive }
            var recordEnd = payloadEnd
            if flags & 8 != 0 {
                let descriptorStarts = number(recordEnd, 4) == 0x08074b50 ? [recordEnd + 4, recordEnd] : [recordEnd]
                guard let descriptor = descriptorStarts.first(where: { offset in
                    offset <= directoryOffset - 12 && number(offset, 4) == crc &&
                    number(offset + 4, 4) == compressed && number(offset + 8, 4) == uncompressed
                }) else { throw WebExtensionLibraryError.invalidArchive }
                recordEnd = descriptor + 12
            }
            ranges.append(localOffset..<recordEnd)
            expanded += uncompressed
            cursor += 46 + nameLength + extraLength + commentLength
        }
        guard cursor == end, hasManifest else { throw WebExtensionLibraryError.invalidArchive }
        ranges.sort { $0.lowerBound < $1.lowerBound }
        guard ranges.first?.lowerBound == 0,
              ranges.last?.upperBound == directoryOffset,
              zip(ranges, ranges.dropFirst()).allSatisfy({ $0.upperBound == $1.lowerBound }) else {
            throw WebExtensionLibraryError.invalidArchive
        }
        for file in files {
            var prefix = file
            while let slash = prefix.lastIndex(of: "/") {
                prefix = String(prefix[..<slash])
                guard !files.contains(prefix) else { throw WebExtensionLibraryError.invalidArchive }
            }
        }
    }

    private static func checksum(_ data: Data, start: Int, length: Int, method: Int, declaredSize: Int) throws -> Int {
        try data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: Bytef.self) else { throw WebExtensionLibraryError.invalidArchive }
            if method == 0 {
                return Int(crc32(0, base.advanced(by: start), uInt(length)))
            }
            var stream = z_stream()
            guard inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
                throw WebExtensionLibraryError.invalidArchive
            }
            defer { inflateEnd(&stream) }
            stream.next_in = UnsafeMutablePointer(mutating: base.advanced(by: start))
            stream.avail_in = uInt(length)
            var output = [UInt8](repeating: 0, count: 64 * 1024)
            var produced = 0
            var checksum: uLong = 0
            while true {
                let result = output.withUnsafeMutableBytes { buffer -> Int32 in
                    stream.next_out = buffer.baseAddress?.assumingMemoryBound(to: Bytef.self)
                    stream.avail_out = uInt(buffer.count)
                    return inflate(&stream, Z_NO_FLUSH)
                }
                let count = output.count - Int(stream.avail_out)
                guard count <= declaredSize - produced else { throw WebExtensionLibraryError.invalidArchive }
                checksum = output.withUnsafeBytes { buffer in
                    crc32(checksum, buffer.baseAddress?.assumingMemoryBound(to: Bytef.self), uInt(count))
                }
                produced += count
                if result == Z_STREAM_END { break }
                guard result == Z_OK, stream.avail_in > 0 || count > 0 else { throw WebExtensionLibraryError.invalidArchive }
            }
            guard produced == declaredSize, stream.avail_in == 0 else { throw WebExtensionLibraryError.invalidArchive }
            return Int(checksum)
        }
    }
}
#endif
