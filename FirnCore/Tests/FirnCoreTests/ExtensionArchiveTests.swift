#if os(macOS)
import Foundation
import Testing
import zlib
@testable import FirnCore

struct ExtensionArchiveTests {
    private struct Entry {
        let name: String
        let content: Data
        var method = 0
        var descriptor = false
        var declaredSize: Int? = nil
        var crc: Int? = nil
        var localName: String? = nil
        var localMethod: Int? = nil
        var localFlags: Int? = nil
        var truncateCompressed = false
        var descriptorSignature = true
    }

    private func append(_ number: Int, _ width: Int, to data: inout Data) {
        for shift in 0..<width { data.append(UInt8(truncatingIfNeeded: number >> (shift * 8))) }
    }

    private func deflate(_ input: Data) -> Data {
        var stream = z_stream()
        precondition(deflateInit2_(&stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, -MAX_WBITS, 8, Z_DEFAULT_STRATEGY,
                                   ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK)
        defer { deflateEnd(&stream) }
        var output = [UInt8](repeating: 0, count: max(128, input.count + 128))
        let result = input.withUnsafeBytes { source in
            output.withUnsafeMutableBytes { target -> Int32 in
                stream.next_in = UnsafeMutablePointer(mutating: source.baseAddress?.assumingMemoryBound(to: Bytef.self))
                stream.avail_in = uInt(source.count)
                stream.next_out = target.baseAddress?.assumingMemoryBound(to: Bytef.self)
                stream.avail_out = uInt(target.count)
                return zlib.deflate(&stream, Z_FINISH)
            }
        }
        precondition(result == Z_STREAM_END)
        return Data(output.prefix(Int(stream.total_out)))
    }

    private func archive(_ entries: [Entry]) -> Data {
        var data = Data()
        var central = Data()
        for entry in entries {
            let offset = data.count
            let name = Data(entry.name.utf8)
            let localName = Data((entry.localName ?? entry.name).utf8)
            var compressed = entry.method == 8 ? deflate(entry.content) : entry.content
            if entry.truncateCompressed { compressed.removeLast() }
            let crc = entry.crc ?? entry.content.withUnsafeBytes { Int(crc32(0, $0.baseAddress?.assumingMemoryBound(to: Bytef.self), uInt($0.count))) }
            let size = entry.declaredSize ?? entry.content.count
            let flags = entry.descriptor ? 8 : 0
            append(0x04034b50, 4, to: &data); append(20, 2, to: &data)
            append(entry.localFlags ?? flags, 2, to: &data); append(entry.localMethod ?? entry.method, 2, to: &data)
            append(0, 4, to: &data); append(entry.descriptor ? 0 : crc, 4, to: &data)
            append(entry.descriptor ? 0 : compressed.count, 4, to: &data)
            append(entry.descriptor ? 0 : size, 4, to: &data)
            append(localName.count, 2, to: &data); append(0, 2, to: &data)
            data.append(localName); data.append(compressed)
            if entry.descriptor {
                if entry.descriptorSignature { append(0x08074b50, 4, to: &data) }
                append(crc, 4, to: &data)
                append(compressed.count, 4, to: &data); append(size, 4, to: &data)
            }
            append(0x02014b50, 4, to: &central); append(0x0314, 2, to: &central); append(20, 2, to: &central)
            append(flags, 2, to: &central); append(entry.method, 2, to: &central); append(0, 4, to: &central)
            append(crc, 4, to: &central); append(compressed.count, 4, to: &central); append(size, 4, to: &central)
            append(name.count, 2, to: &central); append(0, 2, to: &central); append(0, 2, to: &central)
            append(0, 2, to: &central); append(0, 2, to: &central); append(0, 4, to: &central)
            append(offset, 4, to: &central); central.append(name)
        }
        let directoryOffset = data.count
        data.append(central)
        append(0x06054b50, 4, to: &data); append(0, 2, to: &data); append(0, 2, to: &data)
        append(entries.count, 2, to: &data); append(entries.count, 2, to: &data)
        append(central.count, 4, to: &data); append(directoryOffset, 4, to: &data); append(0, 2, to: &data)
        return data
    }

    private func check(_ entries: [Entry], valid: Bool) throws {
        guard #available(macOS 15.4, *) else { return }
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".zip")
        defer { try? FileManager.default.removeItem(at: url) }
        try archive(entries).write(to: url)
        if valid { try ExtensionArchive.validate(url) }
        else { #expect(throws: WebExtensionLibraryError.invalidArchive) { try ExtensionArchive.validate(url) } }
    }

    @Test func validStoredAndDeflateWithDescriptor() throws {
        try check([Entry(name: "manifest.json", content: Data("{}".utf8), method: 8, descriptor: true),
                   Entry(name: "icons/icon.png", content: Data(repeating: 42, count: 1000), method: 8, descriptor: true, descriptorSignature: false)], valid: true)
    }

    @Test func rejectsInvalidPayloadAndHeaders() throws {
        let manifest = Entry(name: "manifest.json", content: Data("{}".utf8))
        try check([manifest, Entry(name: "../escape", content: Data())], valid: false)
        try check([manifest, Entry(name: "A", content: Data()), Entry(name: "a", content: Data())], valid: false)
        try check([manifest, Entry(name: "a", content: Data()), Entry(name: "a/b", content: Data())], valid: false)
        try check([Entry(name: "manifest.json", content: Data("{}".utf8), localName: "evilpath.json")], valid: false)
        try check([Entry(name: "manifest.json", content: Data("{}".utf8), localMethod: 8)], valid: false)
        try check([Entry(name: "manifest.json", content: Data("{}".utf8), localFlags: 8)], valid: false)
        try check([Entry(name: "manifest.json", content: Data("{}".utf8), method: 8, declaredSize: 1)], valid: false)
        try check([Entry(name: "manifest.json", content: Data("{}".utf8), crc: 1)], valid: false)
        try check([Entry(name: "manifest.json", content: Data(repeating: 0, count: 100_000), method: 8, descriptor: true, declaredSize: 1)], valid: false)
        try check([Entry(name: "manifest.json", content: Data("{}".utf8), method: 8, truncateCompressed: true)], valid: false)
    }

    @Test func existingOnePasswordFixtureWhenProvided() throws {
        guard #available(macOS 15.4, *) else { return }
        guard let path = ProcessInfo.processInfo.environment["FIRN_ARCHIVE_FIXTURE"] else { return }
        try ExtensionArchive.validate(URL(fileURLWithPath: path))
    }
}
#endif
