// SegmentReleasedSurfaceTests.swift
// P9-4 (ADR-014): adding the `…All` accessors must not change a released
// segment accessor. `Tests/Fixtures/APISurface/segment-structs-v3.13.0.txt`
// holds every `public` declaration in v3.13.0's
// Sources/HL7v2Kit/Segment/Generated/ files (`git show v3.13.0:<path>`),
// normalised to its signature as `File|signature`. Each must still be declared,
// with the same name and type, in the same generated file.

import Testing
import Foundation

@Suite("Released segment-struct surface is unchanged (P9-4)")
struct SegmentReleasedSurfaceTests {

    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // HL7v2KitTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // repository root

    /// The normalised public signatures declared at HEAD in `Generated/<file>.swift`.
    static func signatures(_ file: String) -> Set<String> {
        let url = root.appendingPathComponent("Sources/HL7v2Kit/Segment/Generated/\(file).swift")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return Set(text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("public ") }
            .map { line in
                var s = line
                if let brace = s.range(of: " {") { s = String(s[..<brace.lowerBound]) }
                if let assign = s.range(of: " = ") { s = String(s[..<assign.lowerBound]) }
                return s.trimmingCharacters(in: .whitespaces)
            })
    }

    @Test("Every v3.13.0 public segment-struct declaration is still declared with the same name and type")
    func releasedSurfaceIsUnchanged() throws {
        let snapshot = Self.root.appendingPathComponent("Tests/Fixtures/APISurface/segment-structs-v3.13.0.txt")
        let entries = try String(contentsOf: snapshot, encoding: .utf8)
            .components(separatedBy: "\n").filter { !$0.isEmpty }
        #expect(entries.count == 3312)
        var cache: [String: Set<String>] = [:]
        for entry in entries {
            let parts = entry.split(separator: "|", maxSplits: 1).map(String.init)
            let declared = cache[parts[0]] ?? Self.signatures(parts[0])
            cache[parts[0]] = declared
            #expect(declared.contains(parts[1]), "\(parts[0]): `\(parts[1])` changed or removed")
        }
    }

    @Test("No segment struct declares an accessor name twice")
    func accessorNamesAreUnique() throws {
        let dir = Self.root.appendingPathComponent("Sources/HL7v2Kit/Segment/Generated")
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasSuffix(".swift") && $0.count == 9 }
        #expect(files.count > 180)
        for file in files.sorted() {
            let text = try String(contentsOf: dir.appendingPathComponent(file), encoding: .utf8)
            let names = text.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { $0.hasPrefix("public var ") }
                .compactMap { $0.dropFirst("public var ".count).split(separator: ":").first.map(String.init) }
            let duplicates = Dictionary(grouping: names, by: { $0 }).filter { $0.value.count > 1 }.keys.sorted()
            #expect(duplicates.isEmpty, "\(file) declares \(duplicates) more than once")
        }
    }
}
