import Foundation
import ZIPFoundation

/// OOXML-пакет (docx/xlsx), целиком прочитанный в память с сохранением порядка файлов.
struct ZipPackage {
    struct Entry {
        var path: String
        var data: Data
    }

    var entries: [Entry]

    init(data: Data) throws {
        let archive: Archive
        do {
            archive = try Archive(data: data, accessMode: .read)
        } catch {
            throw ShtrafinatorError.invalidArchive
        }
        var result: [Entry] = []
        for entry in archive where entry.type == .file {
            var buffer = Data()
            _ = try archive.extract(entry, skipCRC32: false) { buffer.append($0) }
            result.append(Entry(path: entry.path, data: buffer))
        }
        entries = result
    }

    init(contentsOf url: URL) throws {
        try self.init(data: Data(contentsOf: url))
    }

    subscript(path: String) -> Data? {
        get { entries.first { $0.path == path }?.data }
        set {
            guard let index = entries.firstIndex(where: { $0.path == path }) else { return }
            if let newValue { entries[index].data = newValue } else { entries.remove(at: index) }
        }
    }

    func serialized() throws -> Data {
        let archive = try Archive(data: Data(), accessMode: .create)
        for entry in entries {
            let data = entry.data
            try archive.addEntry(
                with: entry.path,
                type: .file,
                uncompressedSize: Int64(data.count),
                compressionMethod: .deflate,
                provider: { position, size in
                    let start = Int(position)
                    return data.subdata(in: start..<start + size)
                }
            )
        }
        guard let output = archive.data else { throw ShtrafinatorError.invalidArchive }
        return output
    }
}
