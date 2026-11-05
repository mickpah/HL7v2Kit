// SecurityLabelTableTests.swift
// Table 0953, Security Label Handling Instructions, on v2.9. CH02C pp 804 to 805 print it as HL7-EXT
// and send the reader to the value set's web rendering for its rows. CH02 2.14.9.27 and CH03 3.4.14.8
// call its values "suggested", and a CWE may carry a local code, so only a tuple claiming HL70953, or a
// first tuple that names nothing (CH02A 2A.3.13.3 requires CWE.3 there), is read against the table.

import Foundation
import Testing
@testable import HL7v2Kit

@Suite("v2.9 table 0953")
struct SecurityLabelTableTests {
    /// An ORU header with MSH-26 and MSH-27 as given (MSH-13 to 25 empty).
    static func msh(_ msh27: String, msh26: String = "", version: String = "2.9") -> String {
        "MSH|^~\\&|LAB|FAC|GP|FAC|20240101||ORU^R01^ORU_R01|MSG|P|\(version)"
            + String(repeating: "|", count: 14) + msh26 + "|" + msh27 + "\r"
    }

    /// A CWE with the given components valued, so a test names positions rather than counts carets.
    static func cwe(_ parts: [Int: String]) -> String {
        (1...parts.keys.max()!).map { parts[$0] ?? "" }.joined(separator: "^")
    }

    /// Every table finding on the wire, in any field: a check that spread would show here.
    static func findings(_ wire: String, options: ValidationOptions = .default,
                         locale: HL7Locale = .international) throws -> [ValidationIssue] {
        let message = try Parser(locale: locale).parse(wire)
        return Validator(options: options, locale: locale).validate(message).issues.filter {
            if case .valueNotInTable = $0.code { true } else { false }
        }
    }

    /// The components of MSH-27 drawing the finding. Any other finding fails the test.
    static func components(_ msh27: String) throws -> [Int?] {
        let found = try findings(msh(msh27))
        #expect(found.allSatisfy {
            $0.code == .valueNotInTable(table: "0953") && $0.location.segmentID == "MSH" && $0.location.fieldIndex == 27
        })
        return found.map(\.location.componentIndex)
    }

    @Test("The table holds the value set's 140 rows, closed; no earlier version has one")
    func table() throws {
        let table = try #require(HL7TableRegistry.table("0953", version: .v2_9))
        #expect(table.entries.count == 140)
        #expect(table.isClosed)
        // SecurityPolicy, ObligationPolicy, RefrainPolicy, PurposeOfUse, GeneralPurposeOfUse, one each.
        for code in ["AUTHPOL", "ANONY", "NODSCLCD", "CLINTRCH", "HMARKT"] {
            #expect(table.contains(code), "\(code)")
        }
        for version in Version.allCases.prefix(while: { $0 != .v2_9 }) {
            #expect(HL7TableRegistry.table("0953", version: version) == nil, "\(version)")
        }
    }

    @Test("A tuple claiming the table is read against it, in either case", arguments: ["HL70953", "hl70953"])
    func claim(system: String) throws {
        #expect(try Self.components("NODSCLCD^x^\(system)").isEmpty)
        let found = try Self.findings(Self.msh("BOGUS^x^\(system)"))
        #expect(found.map(\.code) == [.valueNotInTable(table: "0953")])
        #expect(found.first?.severity == .error)
        #expect(found.first?.location.fieldIndex == 27)
        #expect(found.first?.location.componentIndex == 1)
    }

    @Test("A first tuple naming nothing is read against the table")
    func bare() throws {
        #expect(try Self.components("BOGUS") == [1])
        #expect(try Self.components("BOGUS^x") == [1])
        #expect(try Self.components("NODSCLCD").isEmpty)
    }

    @Test("A tuple naming another system, by name or by OID, is not read")
    func anotherSystem() throws {
        #expect(try Self.components("SH1^x^L").isEmpty)
        #expect(try Self.components("BOGUS^x^99LOCAL").isEmpty)
        #expect(try Self.components(Self.cwe([1: "BOGUS", 14: "1.2.3"])).isEmpty)
        #expect(try Self.components(Self.cwe([1: "A", 3: "L", 4: "BOGUS", 6: "99LOCAL"])).isEmpty)
        #expect(try Self.components(Self.cwe([1: "A", 3: "L", 10: "BOGUS", 20: "1.2.3"])).isEmpty)
    }

    @Test("A second or third tuple naming nothing is not read")
    func laterTupleNamesNothing() throws {
        #expect(try Self.components("A^a^L^BOGUS").isEmpty)
        #expect(try Self.components(Self.cwe([1: "A", 3: "L", 10: "BOGUS"])).isEmpty)
        #expect(try Self.components(Self.cwe([4: "BOGUS"])).isEmpty)
    }

    @Test("A second or third tuple claiming the table is read, located at its identifier")
    func laterTupleClaims() throws {
        #expect(try Self.components("A^a^L^BOGUS^b^HL70953") == [4])
        #expect(try Self.components(Self.cwe([1: "A", 2: "a", 3: "L", 10: "BOGUS", 11: "b", 12: "HL70953"])) == [10])
        #expect(try Self.components("BOGUS^x^HL70953^WRONG^y^hl70953") == [1, 4])
    }

    @Test("A claim of HL70953 is read even beside an OID: the claim comes first")
    func claimBesideOID() throws {
        #expect(try Self.components(Self.cwe([1: "BOGUS", 3: "HL70953", 14: "1.2.3"])) == [1])
    }

    @Test("An empty or null identifier is not read")
    func emptyAndNull() throws {
        #expect(try Self.components("^x^HL70953").isEmpty)
        #expect(try Self.components("\"\"^x^HL70953").isEmpty)
        #expect(try Self.components("^text").isEmpty)
        #expect(try Self.components("\"\"").isEmpty)
    }

    @Test("A null system or OID names nothing, as in the component conditions")
    func nullNamesNothing() throws {
        #expect(try Self.components("BOGUS^x^\"\"") == [1])
        #expect(try Self.components(Self.cwe([1: "BOGUS", 14: "\"\""])) == [1])
        #expect(try Self.components("NODSCLCD^x^\"\"").isEmpty)
        #expect(try Self.components("A^a^L^BOGUS^b^\"\"").isEmpty)
    }

    @Test("A later repetition out of the table draws the finding, naming its repetition")
    func repetition() throws {
        let found = try Self.findings(Self.msh("NODSCLCD^x^HL70953~BOGUS^y^HL70953"))
        #expect(found.map(\.code) == [.valueNotInTable(table: "0953")])
        #expect(found.first?.message.contains("repetition 2") == true)
    }

    // Action S, because ARV-10 is required when ARV-2 is not S.
    static func arv(_ arv8: String) -> String {
        "MSH|^~\\&|SYN|FAC|HOSP|FAC|20240101120000||ADT^A01^ADT_A01|M1|P|2.9\r"
            + "ARV|1|S^Scope^HL70206|ALL^All^HL70717||||R^Restricted^HL70952|\(arv8)\r"
    }

    @Test("ARV-8 is read the same on a v2.9 wire")
    func arvField() throws {
        #expect(try Self.findings(Self.arv("NODSCLCD^x^HL70953~SH1^x^L")).isEmpty)
        let found = try Self.findings(Self.arv("NODSCLCD^x^HL70953~BOGUS^x^HL70953"))
        #expect(found.map(\.code) == [.valueNotInTable(table: "0953")])
        #expect(found.first?.location.segmentID == "ARV")
        #expect(found.first?.location.fieldIndex == 8)
        #expect(found.first?.location.componentIndex == 1)
        #expect(found.first?.message.contains("repetition 2") == true)
        #expect(try Self.findings(Self.arv("A^a^L^BOGUS^b^HL70953")).first?.location.componentIndex == 4)
    }

    @Test("BHS-16 and FHS-16 are read the same through the batch validator",
          arguments: [("BHS", "BTS"), ("FHS", "FTS")])
    func envelopeField(id: String, trailer: String) throws {
        func findings(_ value: String) throws -> [ValidationIssue] {
            let message = "MSH|^~\\&|SYN|FAC|HOSP|FAC|20240101120000||ADT^A01^ADT_A01|M1|P|2.9\rPID|1"
            let header = "\(id)|^~\\&" + String(repeating: "|", count: 14) + value
            let file = [header, message, "\(trailer)|1"].joined(separator: "\r") + "\r"
            return try BatchValidator().validate(BatchParser().parse(file)).batchIssues.filter {
                $0.location.segmentID == id && $0.code == .valueNotInTable(table: "0953")
            }
        }
        #expect(try findings("NODSCLCD^x^HL70953").isEmpty)
        #expect(try findings("SH1^x^L").isEmpty)
        let found = try findings("BOGUS^x^HL70953")
        #expect(found.count == 1)
        #expect(found.first?.location.fieldIndex == 16)
        #expect(found.first?.location.componentIndex == 1)
    }

    @Test("checkCodeTables off draws none")
    func optionOff() throws {
        var options = ValidationOptions.default
        options.checkCodeTables = false
        #expect(try Self.findings(Self.msh("BOGUS^x^HL70953"), options: options).isEmpty)
        #expect(try Self.findings(Self.msh("BOGUS"), options: options).isEmpty)
    }

    @Test("A local extension admits its code, and only its code")
    func localExtension() throws {
        var options = ValidationOptions.default
        options.localTableExtensions["0953"] = ["BOGUS"]
        #expect(try Self.findings(Self.msh("BOGUS^x^HL70953"), options: options).isEmpty)
        #expect(try Self.findings(Self.msh("OTHER^x^HL70953"), options: options).count == 1)
    }

    @Test("Under the AU locale: read on v2.9, where the code claims the table; never on v2.4")
    func auLocale() throws {
        let au = HL7Locale.auLocalisation
        #expect(try Self.findings(Self.msh("SH1^x^L"), locale: au).isEmpty)
        #expect(try Self.findings(Self.msh("BOGUS^x^HL70953"), locale: au).map(\.code) == [.valueNotInTable(table: "0953")])
        #expect(try Self.findings(Self.msh("BOGUS^x^HL70953", version: "2.4"), locale: au).isEmpty)
        #expect(try Self.findings(Self.msh("BOGUS", version: "2.4"), locale: au).isEmpty)
    }

    @Test("Other CWE fields stay silent, on an empty table and on a closed one")
    func otherCWEFields() throws {
        #expect(try Self.findings(Self.msh("", msh26: "BOGUS^x^HL70952")).isEmpty)
        // Not even claiming 0953, or naming nothing: the field is what binds the table.
        #expect(try Self.findings(Self.msh("", msh26: "BOGUS^x^HL70953")).isEmpty)
        #expect(try Self.findings(Self.msh("", msh26: "BOGUS")).isEmpty)
        // ERR-3 is a CWE bound to table 0357, which is closed.
        #expect(HL7TableRegistry.table("0357", version: .v2_9)?.isClosed == true)
        for err3 in ["BOGUS^x^HL70357", "BOGUS"] {
            let ack = "MSH|^~\\&|LAB|FAC|GP|FAC|20240101||ACK^R01^ACK|MSG|P|2.9\rMSA|AA|M1\rERR|||\(err3)|E\r"
            #expect(try Self.findings(ack).isEmpty, "\(err3)")
        }
    }

    @Test("The validator's list of fields bound to 0953 is each version's schema list", arguments: ["v2.9", "v2.9.1"])
    func boundFields(version: String) throws {
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/schemas/\(version)")
        var bound: Set<String> = []
        for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        where url.pathExtension == "json" {
            let schema = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
            for field in schema["fields"] as? [[String: Any]] ?? []
            where (field["tables"] as? [String])?.contains("0953") == true {
                #expect(field["dataType"] as? String == "CWE")
                bound.insert("\(url.deletingPathExtension().lastPathComponent)-\(field["index"] as? Int ?? 0)")
            }
        }
        #expect(bound == Set(Validator.table0953Fields.map { "\($0.key)-\($0.value)" }))
    }

    // MARK: - v2.9.1 (R35, R43)

    /// V291 CH02C p851 prints `Table OID 2.16.840.1.113883.12.953`. v2.9's Chapter 2C prints no Table OID at all.
    static let tableOID = "2.16.840.1.113883.12.953"

    static func findings291(_ msh27: String, locale: HL7Locale = .international) throws -> [ValidationIssue] {
        try findings(msh(msh27, version: "2.9.1"), locale: locale)
    }

    @Test("v2.9.1's table holds the same 140 rows, closed")
    func table291() throws {
        let table = try #require(HL7TableRegistry.table("0953", version: .v2_9_1))
        #expect(table.isClosed && table.entries.count == 140)
    }

    @Test("On v2.9.1 a tuple carrying the printed Table OID names the table, at its own OID component")
    func tableOIDNamesTheTable() throws {
        let first = try Self.findings291(Self.cwe([1: "BOGUS", 14: Self.tableOID]))
        #expect(first.map(\.location.componentIndex) == [1])
        #expect(first.first?.code == .valueNotInTable(table: "0953"))
        #expect(try Self.findings291(Self.cwe([1: "A", 3: "L", 4: "BOGUS", 17: Self.tableOID])).map(\.location.componentIndex) == [4])
        #expect(try Self.findings291(Self.cwe([1: "A", 3: "L", 10: "BOGUS", 20: Self.tableOID])).map(\.location.componentIndex) == [10])
        #expect(try Self.findings291(Self.cwe([1: "NODSCLCD", 14: Self.tableOID])).isEmpty)
    }

    @Test("On v2.9 that OID names nothing the print gives, so the tuple is another system's")
    func tableOIDOnV29() throws {
        #expect(try Self.findings(Self.msh(Self.cwe([1: "BOGUS", 14: Self.tableOID]))).isEmpty)
        #expect(try Self.findings(Self.msh(Self.cwe([1: "A", 3: "L", 4: "BOGUS", 17: Self.tableOID]))).isEmpty)
    }

    @Test("On v2.9.1 another OID, a local system and a later tuple naming nothing stay unread; HL70953 and a bare code are read")
    func otherTuples291() throws {
        #expect(try Self.findings291(Self.cwe([1: "BOGUS", 14: "1.2.3"])).isEmpty)
        #expect(try Self.findings291("SH1^x^L").isEmpty)
        #expect(try Self.findings291("A^a^L^BOGUS").isEmpty)
        #expect(try Self.findings291("BOGUS^x^HL70953").map(\.location.componentIndex) == [1])
        #expect(try Self.findings291("BOGUS").map(\.location.componentIndex) == [1])
    }

    /// R35's cost, pinned. p851 names code system ObservationValue 2.1.0 under the table and the rows hold none of its
    /// codes; the same page's value set description names the five sets the rows hold. Both sides are in the register.
    @Test("R35's cost on v2.9.1: A0^x^HL70953 draws valueNotInTable")
    func observationValueCost() throws {
        #expect(HL7TableRegistry.table("0953", version: .v2_9_1)?.contains("A0") == false)
        #expect(try Self.findings291("A0^x^HL70953").map(\.code) == [.valueNotInTable(table: "0953")])
        // The way a site admits a code, by the owner's ruling.
        var options = ValidationOptions.default
        options.localTableExtensions["0953"] = ["A0"]
        #expect(try Self.findings(Self.msh("A0^x^HL70953", version: "2.9.1"), options: options).isEmpty)
    }

    @Test("ARV-8 on v2.9.1 is read the same, and under the AU locale so is MSH-27")
    func otherFields291() throws {
        let arv = "MSH|^~\\&|SYN|FAC|HOSP|FAC|20240101120000||ADT^A01^ADT_A01|M1|P|2.9.1\r"
            + "ARV|1|S^Scope^HL70206|ALL^All^HL70717||||R^Restricted^HL70952|BOGUS^x^HL70953\r"
        let found = try Self.findings(arv)
        #expect(found.map(\.code) == [.valueNotInTable(table: "0953")])
        #expect(found.first?.location.segmentID == "ARV" && found.first?.location.fieldIndex == 8)
        #expect(try Self.findings291("BOGUS^x^HL70953", locale: .auLocalisation).map(\.code) == [.valueNotInTable(table: "0953")])
        #expect(try Self.findings291("SH1^x^L", locale: .auLocalisation).isEmpty)
    }

    /// V291 CH02 p55 (BHS-16), p64 (FHS-16): the row binds 0953, though CH02C p851's `where used` names only MSH-27 and ARV-8.
    @Test("BHS-16 and FHS-16 are read on v2.9.1", arguments: [("BHS", "BTS"), ("FHS", "FTS")])
    func envelopeField291(id: String, trailer: String) throws {
        func findings(_ value: String) throws -> [ValidationIssue] {
            let message = "MSH|^~\\&|SYN|FAC|HOSP|FAC|20240101120000||ADT^A01^ADT_A01|M1|P|2.9.1\rPID|1"
            let header = "\(id)|^~\\&" + String(repeating: "|", count: 14) + value
            let file = [header, message, "\(trailer)|1"].joined(separator: "\r") + "\r"
            return try BatchValidator().validate(BatchParser().parse(file)).batchIssues.filter {
                $0.location.segmentID == id && $0.code == .valueNotInTable(table: "0953")
            }
        }
        #expect(try findings("NODSCLCD^x^HL70953").isEmpty)
        #expect(try findings("BOGUS^x^HL70953").map(\.location.fieldIndex) == [16])
    }
}
