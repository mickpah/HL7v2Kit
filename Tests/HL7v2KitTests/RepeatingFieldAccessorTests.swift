// RepeatingFieldAccessorTests.swift
// P9-4 (V251-C11): every repeating field (`*` or a bound) has a `…All`
// accessor that returns every repetition in wire order, agreeing with `~n`
// path access and with `TypedSegment.repetitions(_:)`.

import Testing
import Foundation
@testable import HL7v2Kit

@Suite("Repeating-field All accessors (P9-4)")
struct RepeatingFieldAccessorTests {

    private let wire = TestWires.adt("PID|1||111^^^HOSP^MR~222^^^GOV^MC~333^^^LAB^PI||Smith^John~Smyth^Jon")

    @Test("PID-3 patientIdentifierListAll returns every CX repetition in wire order")
    func cxAll() throws {
        let (message, pid) = try hydratedMessage(PID.self, from: wire)
        let all = pid.patientIdentifierListAll
        #expect(all.map(\.id) == ["111", "222", "333"])
        #expect(all[1].identifierTypeCode == message["PID-3~2.5"])
        #expect(all[2].assigningAuthorityNamespace == message["PID-3~3.4"])
        #expect(pid.patientIdentifierList?.id == all.first?.id)
    }

    @Test("PID-5 patientNameAll returns every XPN repetition")
    func xpnAll() throws {
        let (message, pid) = try hydratedMessage(PID.self, from: wire)
        #expect(pid.patientNameAll.map(\.familyName) == ["Smith", "Smyth"])
        #expect(pid.patientNameAll[1].givenName == message["PID-5~2.2"])
    }

    @Test("A scalar repeating field returns [String?] matching ~n path access")
    func scalarAll() throws {
        let (message, obx) = try hydratedMessage(OBX.self, from: TestWires.oru("OBX|1|NM|8867-4^Heart rate^LN||72|/min|60-100|H~A"))
        #expect(obx.abnormalFlagsAll == ["H", "A"])
        let second = obx.abnormalFlagsAll[1]
        #expect(second == message["OBX-8~2"])
    }

    @Test("An absent repeating field returns an empty array")
    func absentAll() throws {
        let pid = try hydrated(PID.self, from: TestWires.adt("PID|1"))
        #expect(pid.patientIdentifierListAll.isEmpty)
        #expect(pid.patientNameAll.isEmpty)
    }

    @Test("Empty repetitions, a present-but-empty field and HL7 null pass through repetitions(_:) unchanged")
    func emptyAndNull() throws {
        let gaps = try hydrated(PID.self, from: TestWires.adt("PID|1||A~~B"))
        #expect(gaps.patientIdentifierListAll.count == gaps.repetitions(3).count)
        #expect(gaps.patientIdentifierListAll.map(\.id) == ["A", "", "B"])

        let empty = try hydrated(PID.self, from: TestWires.adt("PID|1||||Smith^John"))
        #expect(empty.patientIdentifierListAll.map(\.id) == [""])
        #expect(empty.patientIdentifierList?.id == "")

        let null = try hydrated(PID.self, from: TestWires.adt("PID|1||\"\""))
        #expect(null.patientIdentifierListAll.map(\.id) == ["\"\""])

        let scalar = try hydrated(OBX.self, from: TestWires.oru("OBX|1|NM|8867-4^Heart rate^LN||72|/min|60-100|H~~\"\""))
        #expect(scalar.abnormalFlagsAll == ["H", "", "\"\""])
        let lone = try hydrated(OBX.self, from: TestWires.oru("OBX|1|NM|8867-4^Heart rate^LN||72|/min|60-100|"))
        #expect(lone.abnormalFlagsAll.count == lone.repetitions(8).count)
        #expect(lone.abnormalFlagsAll == [""])
    }

    @Test("A scalar All element is nil when that repetition is not a single scalar")
    func scalarAllNonScalarRepetition() throws {
        let obx = try hydrated(OBX.self, from: TestWires.oru("OBX|1|NM|8867-4^Heart rate^LN||72|/min|60-100|H^X~A"))
        #expect(obx.abnormalFlagsAll == [nil, "A"])
        #expect(obx.abnormalFlags == nil)
    }

    @Test("A bounded repeating field (OBR-17, max 2) gets an All accessor")
    func boundedAll() throws {
        let obr = try hydrated(OBR.self, from: TestWires.oru("OBR|1|||CBC" + String(repeating: "|", count: 13) + "^PRN^PH^^^^5551234~^WPN^PH^^^^5555678"))
        #expect(obr.orderCallbackPhoneNumberAll.map(\.telecommunicationUseCode) == ["PRN", "WPN"])
        #expect(obr.orderCallbackPhoneNumberAll.first?.localNumber == obr.orderCallbackPhoneNumber?.localNumber)
    }

    @Test("Representative All signatures are pinned")
    func signatures() {
        let cx: KeyPath<PID, [CX]> = \.patientIdentifierListAll
        let xpn: KeyPath<PID, [XPN]> = \.patientNameAll
        let scalar: KeyPath<OBX, [String?]> = \.abnormalFlagsAll
        let xcn: KeyPath<PRT, [XCN]> = \.participationPersonAll
        let first: KeyPath<PID, CX?> = \.patientIdentifierList
        let pinned: [AnyKeyPath] = [cx, xpn, scalar, xcn, first]
        #expect(pinned.count == 5)
    }

    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private struct Schema: Decodable {
        struct Field: Decodable { let index: Int; let swiftName: String; let repeatability: String }
        let segmentID: String
        let fields: [Field]
    }

    /// The schema each struct is generated from: canonical v2.5.1, else the earliest definer.
    private static func emittingSchemas() throws -> [Schema] {
        let fm = FileManager.default
        let schemasRoot = root.appendingPathComponent("Resources/schemas")
        var order = try fm.contentsOfDirectory(atPath: schemasRoot.path).filter { $0.hasPrefix("v") }.sorted()
        order.removeAll { $0 == "v2.5.1" }
        order.insert("v2.5.1", at: 0)
        var byID: [String: Schema] = [:]
        for dir in order {
            let url = schemasRoot.appendingPathComponent(dir)
            for file in try fm.contentsOfDirectory(atPath: url.path).sorted() where file.hasSuffix(".json") {
                let schema = try JSONDecoder().decode(Schema.self, from: Data(contentsOf: url.appendingPathComponent(file)))
                if byID[schema.segmentID] == nil { byID[schema.segmentID] = schema }
            }
        }
        return byID.values.sorted { $0.segmentID < $1.segmentID }
    }

    @Test("Exactly the repeating fields of each generating schema have an All accessor, and its singular DocC says so")
    func coverage() throws {
        let generated = Self.root.appendingPathComponent("Sources/HL7v2Kit/Segment/Generated")
        var total = 0
        for schema in try Self.emittingSchemas() {
            let text = try String(contentsOf: generated.appendingPathComponent("\(schema.segmentID).swift"), encoding: .utf8)
            let declared = Set(text.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { $0.hasPrefix("public var ") }
                .compactMap { $0.dropFirst("public var ".count).split(separator: ":").first.map(String.init) }
                .filter { $0.hasSuffix("All") })
            let expected = Set(schema.fields.filter { $0.repeatability != "1" }.map { $0.swiftName + "All" })
            #expect(declared == expected, "\(schema.segmentID): All accessors \(declared.sorted()) != \(expected.sorted())")
            for field in schema.fields where field.repeatability != "1" {
                #expect(text.contains("\(schema.segmentID)-\(field.index): every repetition of"),
                        "\(schema.segmentID)-\(field.index): no All DocC")
            }
            total += expected.count
        }
        #expect(total == 536)
        let pid = try String(contentsOf: generated.appendingPathComponent("PID.swift"), encoding: .utf8)
        #expect(pid.contains("Repeating field: this accessor reads the first repetition; `patientIdentifierListAll` returns every repetition."))
    }
}
