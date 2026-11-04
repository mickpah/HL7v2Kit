// FieldTableOpennessTests.swift
// Per-field table openness (P2-15, ADR-016): a field whose own prose cites a closed HL7
// table "for suggested values" (or calls it User-defined, or says it can be extended) is
// marked `tableOpen` in its schema entry, and the field-level closed-table check skips it.

import Foundation
import Testing
@testable import HL7v2Kit

@Suite("Per-field table openness")
struct FieldTableOpennessTests {

    /// A marked field the scalar check would otherwise enforce (an `ID` field bound to a
    /// closed HL7 table), and the wire version that carries it.
    struct Marked: Sendable, CustomTestStringConvertible {
        let version: String
        let segment: String
        let index: Int
        let table: String
        var testDescription: String { "v\(version) \(segment)-\(index) (\(table))" }
    }

    static let enforced: [Marked] = [
        // v2.4 CH03 sec 3.4.2.31 PID-31: "Refer to HL7 Table 0136 - Yes/no indicator for suggested values."
        Marked(version: "2.4", segment: "PID", index: 31, table: "0136"),
        // v2.6 / v2.8.2 CH06 sec 6.5.2.24 DG1-24 and CH16 RFI-3, IVC-13, PSG-4, PSL-47: "... for suggested values."
        Marked(version: "2.6", segment: "DG1", index: 24, table: "0136"),
        Marked(version: "2.6", segment: "RFI", index: 3, table: "0136"),
        Marked(version: "2.6", segment: "IVC", index: 13, table: "0136"),
        Marked(version: "2.6", segment: "PSG", index: 4, table: "0136"),
        Marked(version: "2.6", segment: "PSL", index: 47, table: "0136"),
        Marked(version: "2.8.2", segment: "DG1", index: 24, table: "0136"),
        Marked(version: "2.8.2", segment: "RFI", index: 3, table: "0136"),
        Marked(version: "2.8.2", segment: "IVC", index: 13, table: "0136"),
        Marked(version: "2.8.2", segment: "PSG", index: 4, table: "0136"),
        Marked(version: "2.8.2", segment: "PSL", index: 47, table: "0136"),
        // RXD-11 on every version: "Refer to HL7 Table 0167 - Substitution Status for suggested values."
        Marked(version: "2.3", segment: "RXD", index: 11, table: "0167"),
        Marked(version: "2.3.1", segment: "RXD", index: 11, table: "0167"),
        Marked(version: "2.4", segment: "RXD", index: 11, table: "0167"),
        Marked(version: "2.5.1", segment: "RXD", index: 11, table: "0167"),
        Marked(version: "2.6", segment: "RXD", index: 11, table: "0167"),
        Marked(version: "2.8.2", segment: "RXD", index: 11, table: "0167"),
        // v2.6 / v2.8.2 CH16 PSL-21: "Refer to User-defined Table 0532 ... for suggested values."
        Marked(version: "2.6", segment: "PSL", index: 21, table: "0532"),
        Marked(version: "2.8.2", segment: "PSL", index: 21, table: "0532"),
        // v2.7.1 prints the same sentences: CH06 sec 6.5.2.24 p36 (DG1-24), CH16 RFI-3,
        // IVC-13, PSG-4, PSL-47 ("Refer to HL7 Table 0136 ... for suggested values"),
        // CH04A RXD-11 p70 (Table 0167), CH16 PSL-21 p49 (User-defined Table 0532).
        Marked(version: "2.7.1", segment: "DG1", index: 24, table: "0136"),
        Marked(version: "2.7.1", segment: "RFI", index: 3, table: "0136"),
        Marked(version: "2.7.1", segment: "IVC", index: 13, table: "0136"),
        Marked(version: "2.7.1", segment: "PSG", index: 4, table: "0136"),
        Marked(version: "2.7.1", segment: "PSL", index: 47, table: "0136"),
        Marked(version: "2.7.1", segment: "RXD", index: 11, table: "0167"),
        Marked(version: "2.7.1", segment: "PSL", index: 21, table: "0532"),
        // v2.9, each read on its own page (technical correction text where it holds the chapter):
        // CH06 6.5.2.24 p45 (DG1-24), CH16 16.4.1.3 p30 (RFI-3), 16.4.2.13 p35 (IVC-13), 16.4.5.4 p44
        // (PSG-4), 16.4.6.47 p56 (PSL-47), CH04A 4A.4.5.11 p76 (RXD-11), CH16 16.4.6.21 p50 (PSL-21).
        Marked(version: "2.9", segment: "DG1", index: 24, table: "0136"),
        Marked(version: "2.9", segment: "RFI", index: 3, table: "0136"),
        Marked(version: "2.9", segment: "IVC", index: 13, table: "0136"),
        Marked(version: "2.9", segment: "PSG", index: 4, table: "0136"),
        Marked(version: "2.9", segment: "PSL", index: 47, table: "0136"),
        Marked(version: "2.9", segment: "RXD", index: 11, table: "0167"),
        Marked(version: "2.9", segment: "PSL", index: 21, table: "0532"),
        // v2.9 CH04A 4A.4.8.2 p101 (RXV-2) and 4A.4.8.7 p102 (RXV-7): "See HL7 Defined Table ... for example values."
        Marked(version: "2.9", segment: "RXV", index: 2, table: "0917"),
        Marked(version: "2.9", segment: "RXV", index: 7, table: "0918"),
    ]

    /// A minimal message carrying `value` at `segment-index`.
    private func wire(_ version: String, _ segment: String, _ index: Int, _ value: String) -> String {
        "MSH|^~\\&|HIS|FAC|LAB|FAC|||ADT^A01|MSG00001|P|\(version)\r"
            + segment + String(repeating: "|", count: index) + value + "\r"
    }

    /// The generated grammar table the Validator reads for `version`.
    private func grammars(_ version: Version) -> [String: SegmentGrammar] {
        switch version {
        case .v2_3: SegmentGrammarTable.v2_3
        case .v2_3_1: SegmentGrammarTable.v2_3_1
        case .v2_4: SegmentGrammarTable.v2_4
        case .v2_5_1: SegmentGrammarTable.v2_5_1
        case .v2_6: SegmentGrammarTable.v2_6
        case .v2_7_1, .v2_7: SegmentGrammarTable.v2_7_1
        case .v2_8_2, .v2_8: SegmentGrammarTable.v2_8_2
        case .v2_9: SegmentGrammarTable.v2_9
        }
    }

    private func tableIssues(_ wire: String, table: String) throws -> [ValidationIssue] {
        Validator().validate(try Parser().parse(wire)).issues.filter { $0.code == .valueNotInTable(table: table) }
    }

    @Test("An out-of-table value is silent at a field that cites its table for suggested values",
          arguments: enforced)
    func markedFieldIsOpen(_ field: Marked) throws {
        let version = try #require(Version(rawValue: field.version))
        let grammar = try #require(grammars(version)[field.segment]?.field(field.index))
        #expect(grammar.tableOpen)
        #expect(grammar.dataType == "ID" && grammar.table == field.table)
        #expect(try #require(HL7TableRegistry.table(field.table, version: version)).isClosed)
        #expect(try tableIssues(wire(field.version, field.segment, field.index, "Z"), table: field.table).isEmpty)
    }

    /// A segment carrying "Z" at every index in `values`, the rest empty.
    private func wire(_ version: String, _ segment: String, values: [Int]) -> String {
        let fields = (1...(values.max() ?? 1)).map { values.contains($0) ? "Z" : "" }
        return "MSH|^~\\&|HIS|FAC|LAB|FAC|||ADT^A01|MSG00001|P|\(version)\r"
            + segment + "|" + fields.joined(separator: "|") + "\r"
    }

    @Test("On the same wire, an unmarked sibling ID field on a closed table still raises",
          arguments: [("2.6", "DG1", 24, 18, "0136"), ("2.8.2", "DG1", 24, 18, "0136"), ("2.9", "DG1", 24, 18, "0136"),
                      ("2.4", "RXD", 11, 14, "0136"), ("2.8.2", "RXD", 11, 14, "0136"), ("2.9", "RXD", 11, 14, "0136")])
    func siblingStillChecked(version: String, segment: String, marked: Int, sibling: Int, table: String) throws {
        // DG1-18 Confidential Indicator and RXD-14 Needs Human Review cite Table 0136 "for valid values".
        let report = Validator().validate(try Parser().parse(wire(version, segment, values: [marked, sibling])))
        let hits = report.issues.filter { if case .valueNotInTable = $0.code { return true } else { return false } }
        #expect(hits.map(\.location.fieldIndex) == [sibling])
        #expect(hits.first?.code == .valueNotInTable(table: table))
    }

    @Test("RFI, IVC, PSG and PSL carry no other closed-table ID field; the same wire still validates the segment",
          arguments: [("2.6", "RFI", 3), ("2.6", "IVC", 13), ("2.6", "PSG", 4), ("2.6", "PSL", 47),
                      ("2.8.2", "RFI", 3), ("2.8.2", "IVC", 13), ("2.8.2", "PSG", 4), ("2.8.2", "PSL", 21),
                      ("2.9", "RFI", 3), ("2.9", "IVC", 13), ("2.9", "PSG", 4), ("2.9", "PSL", 21)])
    func segmentStillValidated(version: String, segment: String, marked: Int) throws {
        // No unmarked closed-table ID sibling exists on these segments, so the control is the
        // segment's required fields (index 1 is R on all four), reported on the same wire.
        let report = Validator().validate(try Parser().parse(wire(version, segment, values: [marked])))
        #expect(report.issues.contains {
            $0.code == .requiredFieldMissing && $0.location.segmentID == segment && $0.location.fieldIndex == 1
        })
        #expect(!report.issues.contains { if case .valueNotInTable = $0.code { return true } else { return false } })
    }

    /// Marked fields the scalar check never enforces: `IS` fields and composite (CE / CWE /
    /// CNE) fields, whose table binding is recorded but not wire-checked (ADR-016). The mark
    /// keeps the metadata faithful to each field's own prose.
    static let metadataOnly: [Marked] = [
        // 0185: PRD-6, CTD-6 on every version, PRD-14 from v2.6 ("User-defined Table 0185 ... for suggested values").
        Marked(version: "2.3", segment: "PRD", index: 6, table: "0185"),
        Marked(version: "2.3", segment: "CTD", index: 6, table: "0185"),
        Marked(version: "2.3.1", segment: "PRD", index: 6, table: "0185"),
        Marked(version: "2.3.1", segment: "CTD", index: 6, table: "0185"),
        Marked(version: "2.4", segment: "PRD", index: 6, table: "0185"),
        Marked(version: "2.4", segment: "CTD", index: 6, table: "0185"),
        Marked(version: "2.5.1", segment: "PRD", index: 6, table: "0185"),
        Marked(version: "2.5.1", segment: "CTD", index: 6, table: "0185"),
        Marked(version: "2.6", segment: "PRD", index: 6, table: "0185"),
        Marked(version: "2.6", segment: "CTD", index: 6, table: "0185"),
        Marked(version: "2.6", segment: "PRD", index: 14, table: "0185"),
        Marked(version: "2.8.2", segment: "PRD", index: 6, table: "0185"),
        Marked(version: "2.8.2", segment: "CTD", index: 6, table: "0185"),
        Marked(version: "2.8.2", segment: "PRD", index: 14, table: "0185"),
        // 0206: IAM-6, ARV-2 on v2.6 and v2.8.2 ("... for suggested values").
        Marked(version: "2.6", segment: "IAM", index: 6, table: "0206"),
        Marked(version: "2.6", segment: "ARV", index: 2, table: "0206"),
        Marked(version: "2.8.2", segment: "IAM", index: 6, table: "0206"),
        Marked(version: "2.8.2", segment: "ARV", index: 2, table: "0206"),
        // 0239: v2.3 PCR-2, PCR-9, PCR-11, PCR-13 ("user-defined table 0239 ... for suggested values").
        Marked(version: "2.3", segment: "PCR", index: 2, table: "0239"),
        Marked(version: "2.3", segment: "PCR", index: 9, table: "0239"),
        Marked(version: "2.3", segment: "PCR", index: 11, table: "0239"),
        Marked(version: "2.3", segment: "PCR", index: 13, table: "0239"),
        // 0323: IAM-6 on v2.4 and v2.5.1 ("... for suggested values").
        Marked(version: "2.4", segment: "IAM", index: 6, table: "0323"),
        Marked(version: "2.5.1", segment: "IAM", index: 6, table: "0323"),
        // 0371: OM4-7, SAC-27 on v2.5.1, v2.6, v2.8.2 ("The value set can be extended with user specific values.").
        Marked(version: "2.5.1", segment: "OM4", index: 7, table: "0371"),
        Marked(version: "2.5.1", segment: "SAC", index: 27, table: "0371"),
        Marked(version: "2.6", segment: "OM4", index: 7, table: "0371"),
        Marked(version: "2.6", segment: "SAC", index: 27, table: "0371"),
        Marked(version: "2.8.2", segment: "OM4", index: 7, table: "0371"),
        Marked(version: "2.8.2", segment: "SAC", index: 27, table: "0371"),
        // v2.9: CH11 11.8.4.6 p75 (CTD-6), 11.8.3.6 p68 (PRD-6), 11.8.3.14 p71 (PRD-14), CH07 7.4.4.23 p96
        // (PRT-23), 0185 "User-defined Table ... for suggested values"; CH03 3.4.7.6 p172 (IAM-6), 0206; CH08
        // 8.8.12.7 p55 (OM4-7), CH13 13.4.3.27 pp39-40 (SAC-27), 0371 "can be extended". The rest come from the
        // sweep, and their prints say "for suggested values":
        // CH04 4.14.3.11 p153 (BTX-11), 4.5.1.29 and 4.5.1.30 p66 (ORC-29, ORC-30), CH06 6.5.2.23 p44 (DG1-23),
        // 6.5.2.25 p45 (DG1-25), 6.5.3.11 p48 (DRG-11), 6.5.3.14 p49 (DRG-14),
        // CH13 13.4.4.2 and 13.4.4.3 p47 (INV-2, INV-3), 13.4.4.21 p51 (INV-21).
        Marked(version: "2.9", segment: "CTD", index: 6, table: "0185"),
        Marked(version: "2.9", segment: "PRD", index: 6, table: "0185"),
        Marked(version: "2.9", segment: "PRD", index: 14, table: "0185"),
        Marked(version: "2.9", segment: "PRT", index: 23, table: "0185"),
        Marked(version: "2.9", segment: "IAM", index: 6, table: "0206"),
        Marked(version: "2.9", segment: "OM4", index: 7, table: "0371"),
        Marked(version: "2.9", segment: "SAC", index: 27, table: "0371"),
        Marked(version: "2.9", segment: "BTX", index: 11, table: "0513"),
        Marked(version: "2.9", segment: "ORC", index: 29, table: "0482"),
        Marked(version: "2.9", segment: "ORC", index: 30, table: "0483"),
        Marked(version: "2.9", segment: "DG1", index: 23, table: "0728"),
        Marked(version: "2.9", segment: "DG1", index: 25, table: "0731"),
        Marked(version: "2.9", segment: "DRG", index: 11, table: "0415"),
        Marked(version: "2.9", segment: "DRG", index: 14, table: "0728"),
        Marked(version: "2.9", segment: "INV", index: 2, table: "0383"),
        Marked(version: "2.9", segment: "INV", index: 3, table: "0384"),
        Marked(version: "2.9", segment: "INV", index: 21, table: "0942"),
    ]

    @Test("A composite or IS field whose prose opens its table carries the mark", arguments: metadataOnly)
    func metadataFieldIsMarked(_ field: Marked) throws {
        let version = try #require(Version(rawValue: field.version))
        let grammar = try #require(grammars(version)[field.segment]?.field(field.index))
        #expect(grammar.tableOpen)
        #expect(grammar.dataType != "ID")
        #expect(try tableIssues(wire(field.version, field.segment, field.index, "Z"), table: field.table).isEmpty)
    }

    /// v2.9's marks, whole. A later seeding of the schemas can neither lose one nor gain an unread one.
    @Test("v2.9 marks exactly the fields its print opens")
    func v29MarksArePresent() {
        let marked = SegmentGrammarTable.v2_9.values.flatMap { grammar in
            grammar.fields.filter(\.tableOpen).map { "\(grammar.segmentID)-\($0.index)" }
        }
        let read = (Self.enforced + Self.metadataOnly).filter { $0.version == "2.9" }.map { "\($0.segment)-\($0.index)" }
        #expect(read.count == 26)
        #expect(Set(marked) == Set(read))
    }

    @Test("DPS-5 prints a value set that \"may need to be extended\", then \"for valid values\", on a CNE: not open")
    func dps5IsNotOpen() {
        #expect(SegmentGrammarTable.v2_9["DPS"]?.field(5)?.tableOpen == false)
    }

    @Test("ARV-2 opens its table on v2.8.2 only: v2.9 CH03 3.4.14.2 p200 prints \"for valid values\"")
    func arv2FollowsEachPrint() {
        #expect(SegmentGrammarTable.v2_8_2["ARV"]?.field(2)?.tableOpen == true)
        #expect(SegmentGrammarTable.v2_9["ARV"]?.field(2)?.tableOpen == false)
    }

    /// Table 0953's four fields print "for suggested values" and are enforced anyway, by the owner's ruling R30.
    @Test("v2.9's table 0953 fields stay unmarked", arguments: [("ARV", 8), ("BHS", 16), ("FHS", 16), ("MSH", 27)])
    func table0953FieldsStayUnmarked(segment: String, index: Int) {
        #expect(SegmentGrammarTable.v2_9[segment]?.field(index)?.tableOpen == false)
    }

    @Test("The same table still raises at a field that cites it for valid values",
          arguments: [("2.4", "PID", 24, "0136"), ("2.6", "PID", 24, "0136"), ("2.8.2", "PID", 24, "0136"), ("2.9", "PID", 24, "0136"),
                      ("2.3", "RXE", 9, "0167"), ("2.5.1", "RXE", 9, "0167"), ("2.8.2", "RXE", 9, "0167"), ("2.9", "RXE", 9, "0167")])
    func validValuesFieldStillClosed(version: String, segment: String, index: Int, table: String) throws {
        let v = try #require(Version(rawValue: version))
        #expect(grammars(v)[segment]?.field(index)?.tableOpen == false)
        #expect(try tableIssues(wire(version, segment, index, "Z"), table: table).count == 1)
    }

    // MARK: - Schema to grammar

    private struct Schema: Decodable {
        struct Field: Decodable {
            let index: Int
            let tableOpen: Bool?
            let tableOpenCitation: String?
        }
        let segmentID: String
        let fields: [Field]
    }

    @Test("tableOpen round-trips from every schema entry to the generated grammar, with a citation")
    func schemaRoundTrip() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/schemas")
        var marked = 0
        for version in Version.allCases {
            // `.v2_8` and `.v2_7` are validated against the v2.8.2 and v2.7.1 grammars and have no
            // schema directory of their own.
            guard version.grammarVersion == version else { continue }
            let dir = root.appendingPathComponent("v\(version.rawValue)")
            let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path)
            #expect(files != nil, "no schema directory for v\(version.rawValue)")
            guard let files else { continue }
            for file in files where file.hasSuffix(".json") {
                let schema = try JSONDecoder().decode(Schema.self, from: Data(contentsOf: dir.appendingPathComponent(file)))
                for field in schema.fields {
                    let open = field.tableOpen ?? false
                    let generated = grammars(version)[schema.segmentID]?.field(field.index)
                    #expect(generated?.tableOpen == open, "v\(version.rawValue) \(schema.segmentID)-\(field.index)")
                    if open {
                        marked += 1
                        #expect(field.tableOpenCitation?.contains("suggested") == true
                                    || field.tableOpenCitation?.contains("extended") == true
                                    || field.tableOpenCitation?.contains("example values") == true,
                                "v\(version.rawValue) \(schema.segmentID)-\(field.index) cites no prose")
                    }
                }
            }
        }
        #expect(marked > 0)
    }

    @Test("A field that is not marked defaults to a closed reading of its table")
    func defaultIsFalse() {
        let grammar = FieldGrammar(index: 1, name: "X", dataType: "ID", optionality: .optional,
                                   repeatability: .single, table: "0136")
        #expect(!grammar.tableOpen)
        let open = FieldGrammar(index: 1, name: "X", dataType: "ID", optionality: .optional,
                                repeatability: .single, table: "0136", tableOpen: true)
        #expect(open.tableOpen && open != grammar)
    }
}
