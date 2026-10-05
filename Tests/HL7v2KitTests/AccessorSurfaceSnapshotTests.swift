// AccessorSurfaceSnapshotTests.swift
// P9 final review: pins the whole unreleased typed-accessor surface. The v3.13.0
// released-surface tests are superset checks (a released accessor must survive);
// this one is an equality check, so any rename, retype, drop, addition or
// re-index of an accessor fails until the snapshot is deliberately regenerated.

import Testing
import Foundation

/// The public accessor surface at HEAD against its committed snapshot.
///
/// `Tests/Fixtures/APISurface/segment-accessors-unreleased.txt` holds one
/// `File|name|type|field index` line per `public var` in the generated segment
/// structs (`Sources/HL7v2Kit/Segment/Generated/<SEG>.swift`), and
/// `composite-accessors-unreleased.txt` one `File|name|type|component index` line per
/// `public var` in `Sources/HL7v2Kit/Composite/` (hand-written views and their
/// generated `+Components` extensions). The index is the first position the getter
/// reads; a deprecated alias takes its target's index, and a tail accessor reading
/// `fields[n...]` records `n...`.
///
/// Regenerate both files after a deliberate surface change with
/// `API_SURFACE_SNAPSHOT_WRITE=1 xcrun swift test --filter AccessorSurfaceSnapshotTests`,
/// then review the diff. At tag time the snapshots are promoted to the release
/// snapshots (`segment-accessors-v<X.Y.Z>.txt`, `composite-accessors-v<X.Y.Z>.txt`)
/// that the released-surface tests read, and fresh `-unreleased` files begin the next cycle.
@Suite("Unreleased accessor surface matches its snapshot (P9)")
struct AccessorSurfaceSnapshotTests {

    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // HL7v2KitTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // repository root

    static let fixtures = root.appendingPathComponent("Tests/Fixtures/APISurface")

    /// `File|name|type|index` for every `public var` in the given source files, in file order.
    static func surface(_ files: [URL]) -> [String] {
        var lines: [String] = []
        for url in files {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let file = url.deletingPathExtension().lastPathComponent
            let source = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            var found: [(name: String, type: String, body: [String])] = []
            for (i, line) in source.enumerated() where line.hasPrefix("public var ") {
                guard let colon = line.range(of: ": "), let brace = line.range(of: " {") else { continue }
                let name = String(line[line.index(line.startIndex, offsetBy: 11)..<colon.lowerBound])
                let type = String(line[colon.upperBound..<brace.lowerBound])
                let body = Array(source[(i + 1)...].prefix { $0 != "}" })
                found.append((name, type, body))
            }
            let indices = Dictionary(found.map { ($0.name, index(of: $0.body)) }, uniquingKeysWith: { a, _ in a })
            for entry in found {
                var at = indices[entry.name] ?? "-"
                // A deprecated alias reads its target accessor.
                if at == "-", entry.body.count == 1, let target = indices[entry.body[0]] { at = target }
                lines.append("\(file)|\(entry.name)|\(entry.type)|\(at)")
            }
        }
        return lines
    }

    /// The first position a getter body reads: `field(7)`, `repetitions(7)`,
    /// `componentValue(7)`, `component(7, as:)` or `fields[7...]`.
    static func index(of body: [String]) -> String {
        for line in body {
            if let m = line.range(of: #"fields\[[0-9]+\.\.\.\]"#, options: .regularExpression) {
                return line[m].filter { $0.isNumber } + "..."
            }
            if let m = line.range(of: #"\([0-9]+[,)]"#, options: .regularExpression) {
                return String(line[m].filter { $0.isNumber })
            }
        }
        return "-"
    }

    static func sources(_ directory: String, matching pattern: String) -> [URL] {
        let dir = root.appendingPathComponent(directory)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return names.filter { $0.range(of: pattern, options: .regularExpression) != nil }
            .sorted().map { dir.appendingPathComponent($0) }
    }

    static var segmentSurface: [String] {
        surface(sources("Sources/HL7v2Kit/Segment/Generated", matching: #"^[A-Z0-9]{3}\.swift$"#))
    }

    static var compositeSurface: [String] {
        surface(sources("Sources/HL7v2Kit/Composite", matching: #"\.swift$"#)
            + sources("Sources/HL7v2Kit/Composite/Generated", matching: #"\.swift$"#))
    }

    /// Compares `actual` with the snapshot `name`, or rewrites the snapshot when
    /// `API_SURFACE_SNAPSHOT_WRITE` is set.
    static func check(_ actual: [String], against name: String) throws {
        let url = fixtures.appendingPathComponent(name)
        if ProcessInfo.processInfo.environment["API_SURFACE_SNAPSHOT_WRITE"] != nil {
            try (actual.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
            return
        }
        let expected = try String(contentsOf: url, encoding: .utf8)
            .components(separatedBy: "\n").filter { !$0.isEmpty }
        let added = Set(actual).subtracting(expected).sorted()
        let removed = Set(expected).subtracting(actual).sorted()
        #expect(added.isEmpty, "\(name): not in the snapshot: \(added.prefix(20))")
        #expect(removed.isEmpty, "\(name): in the snapshot but not declared: \(removed.prefix(20))")
        #expect(actual == expected, "\(name): order or duplicates differ; regenerate deliberately")
    }

    @Test("Every segment-struct accessor matches the snapshot exactly (name, type, field index)")
    func segmentAccessorsMatchSnapshot() throws {
        let actual = Self.segmentSurface
        #expect(!actual.contains { $0.hasSuffix("|-") }, "an accessor with no field index")
        try Self.check(actual, against: "segment-accessors-unreleased.txt")
    }

    @Test("Every composite accessor matches the snapshot exactly (name, type, component index)")
    func compositeAccessorsMatchSnapshot() throws {
        let actual = Self.compositeSurface
        try Self.check(actual, against: "composite-accessors-unreleased.txt")
    }
}
