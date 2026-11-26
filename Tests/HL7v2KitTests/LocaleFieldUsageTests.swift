// LocaleFieldUsageTests.swift
// HL7Locale.fieldUsage: the usage a localisation's own attribute table prints for a field,
// and the usage a conformance statement gives it in a message (R1, #34). Pages are those of
// HL7AUSD-STD-OO-ADRM-2021.1.

import Foundation
import Testing
import HL7v2Kit

@Suite("Locale field usage")
struct LocaleFieldUsageTests {
    static let au = HL7Locale.auLocalisation

    @Test("Each code the ADRM prints is read from its attribute table, with the page")
    func codesFromTheAttributeTable() {
        let cases: [(String, Int, FieldUsage, Int)] = [
            ("BHS", 1, .required, 27),               // p 27: BHS-1 R
            ("BHS", 3, .optional, 27),               // p 27: BHS-3 O
            ("MSH", 15, .required, 37),              // p 37: R, "field optionality has been changed to required"
            ("PID", 2, .backwardCompatible, 58),     // p 58: PID-2 B
            ("PID", 3, .required, 58),               // p 58: PID-3 R
            ("OBR", 1, .conditional, 207),           // p 207: OBR-1 C
            ("OBR", 5, .notUsed, 207),               // p 207: OBR-5 X (v2.4 prints B)
            ("RF1", 1, .required, 326),              // p 326: RF1-1 R (v2.4 prints O)
        ]
        for (segment, field, usage, page) in cases {
            let read = Self.au.fieldUsage(segment: segment, field: field)
            #expect(read?.usage == usage, "\(segment)-\(field)")
            #expect(read?.source == .attributeTable, "\(segment)-\(field)")
            #expect(read?.citation == "HL7AUSD-STD-OO-ADRM-2021.1, \(segment) attribute table, p \(page)", "\(segment)-\(field)")
        }
    }

    @Test("The printed letters are the raw values")
    func rawValues() {
        #expect(FieldUsage.allCases.map(\.rawValue) == ["R", "RE", "O", "C", "CE", "X", "B"])
    }

    @Test("No field of the ADRM is RE or CE")
    func noRequiredOrEmpty() {
        var seen: Set<FieldUsage> = []
        for segment in ["BHS", "BTS", "DSC", "ERR", "FHS", "FTS", "MSA", "MSH", "PID", "PV1", "PV2", "AL1", "QRD", "QRF",
                        "OBR", "OBX", "ORC", "RF1", "PRD", "IAM", "RXO", "RXR", "RXC"] {
            for field in 1...60 {
                if let usage = Self.au.fieldUsage(segment: segment, field: field)?.usage { seen.insert(usage) }
            }
        }
        #expect(seen == [.required, .optional, .conditional, .backwardCompatible, .notUsed])
    }

    @Test("nil where the ADRM prints no usage, and everywhere under the base standard")
    func noUsage() {
        #expect(Self.au.fieldUsage(segment: "PV2", field: 39) == nil)   // p 96: printed with no OPT
        #expect(Self.au.fieldUsage(segment: "MSH", field: 22) == nil)   // p 38: Reserved
        #expect(Self.au.fieldUsage(segment: "MSH", field: 28) == nil)   // past the table
        #expect(Self.au.fieldUsage(segment: "NTE", field: 1) == nil)    // the ADRM prints no NTE table
        #expect(Self.au.fieldUsage(segment: "PID", field: 0) == nil)
        #expect(HL7Locale.international.fieldUsage(segment: "PID", field: 3) == nil)
        #expect(HL7Locale.international.fieldUsage(segment: "MSH", field: 15) == nil)
    }

    static func fixture(_ name: String) throws -> Message {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(name).hl7")
        return try Parser(locale: .auLocalisation).parse(Data(contentsOf: url))
    }

    @Test("In a message, a conformance statement that applies to it gives the usage")
    func statementInAMessage() throws {
        let order = try Self.fixture("au_orm_o01")
        let result = try Self.fixture("au_oru_r01_pathology")
        let msh6 = try Path("MSH-6")
        #expect(Self.au.fieldUsage(segment: "MSH", field: 6)?.usage == .optional)          // p 37: MSH-6 O
        let inOrder = Self.au.fieldUsage(at: msh6, in: order)
        #expect(inOrder?.usage == .required)
        #expect(inOrder?.source == .conformanceStatement)
        #expect(inOrder?.citation.contains("HL7au:") == true)
        let inResult = Self.au.fieldUsage(at: msh6, in: result)                            // the statement names ORM alone
        #expect(inResult?.usage == .optional)
        #expect(inResult?.source == .attributeTable)
        // A field no statement touches reads from the table, and a path with no field or no
        // such segment reads nothing.
        #expect(Self.au.fieldUsage(at: try Path("PID-3"), in: order)?.source == .attributeTable)
        #expect(Self.au.fieldUsage(at: try Path("PID"), in: order) == nil)
        #expect(Self.au.fieldUsage(at: try Path("ZZZ-1"), in: order) == nil)
        #expect(HL7Locale.international.fieldUsage(at: msh6, in: order) == nil)
    }

    @Test("The read agrees with the validator: a field it reports as profile-required reads as required")
    func agreesWithTheValidator() throws {
        let fields = ["MSH-6", "MSH-15", "MSH-16", "MSH-17", "MSH-19", "PID-1", "OBR-24", "PRD-7"]
        var reported = 0
        for name in ["au_orm_o01", "au_oru_r01_pathology", "au_oru_r01_radiology", "au_ref_i12", "au_rri_i12", "au_orr_o02"] {
            var message = try Self.fixture(name)
            for field in fields { try? message.clear(at: Path(field)) }
            let issues = Validator(locale: .auLocalisation).validate(message).issues
                .filter { $0.message.contains("field is profile-required") }
            for issue in issues {
                let location = issue.location
                let path = try Path("\(location.segmentID)[\(location.segmentIndex)]-\(try #require(location.fieldIndex))")
                let read = Self.au.fieldUsage(at: path, in: message)
                #expect(read?.usage == .required, "\(name) \(path)")
                #expect(read?.source == .conformanceStatement, "\(name) \(path)")
                reported += 1
            }
            // And the other way: a listed field the read calls required by statement, now empty, is reported.
            for field in fields {
                let path = try Path(field)
                guard Self.au.fieldUsage(at: path, in: message)?.source == .conformanceStatement else { continue }
                #expect(issues.contains { $0.location.segmentID == path.segmentID && $0.location.fieldIndex == path.field },
                        "\(name) \(field) reads required and is not reported")
            }
        }
        #expect(reported >= 8)
    }
}
