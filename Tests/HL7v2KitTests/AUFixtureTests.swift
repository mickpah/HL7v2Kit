// AUFixtureTests.swift
// P12 S3-1: whole-message evidence for the AU localisation profile
// (ADRM-2021, HL7AUSD-STD-OO-ADRM-2021.1). The fixtures are synthetic,
// written from scratch for this suite (Tests/Fixtures/README.md), one per
// message the ADRM localises. Each parses, round-trips byte for byte and is
// checked under `.strict` with the AU locale (the four caller assertions set,
// and unset) and with the international locale. The fire and silent pairs
// then change one field of a clean fixture and pin the one AU rule that
// change breaks, per shipped rule family.
//
// Two classes of finding are named here rather than hidden:
// - The ADRM prints longer field lengths than v2.4 for MSH-12, ORC-2/3,
//   OBR-2/3 and RF1-6 among others (the "Australian variation" notes, pp 38,
//   209, 283 and 327). The AU locale applies them (P12 S3-2, defect D1 of
//   S3-1), so the fixtures are clean there; under the international locale
//   the v2.4 length warning on the same values is the correct v2.4 finding.
// - `au_ref_i12.hl7` follows the Chapter 7 structure (p 324) and declares no
//   Appendix 8 profile, so it draws HL7au:000040.4 (p 446), which requires
//   every Referral to declare a simplified profile: the ADRM itself leaves no
//   internal version ID for a Chapter 7 REF (Table 0104x, p 42).

import Testing
import Foundation
@testable import HL7v2Kit

@Suite("AU fixtures (ADRM-2021, whole messages)")
struct AUFixtureTests {

    /// Every AU fixture, one per message the ADRM localises.
    static let fixtures = [
        "au_oru_r01_pathology.hl7",
        "au_oru_r01_radiology.hl7",
        "au_orm_o01.hl7",
        "au_osr_q06.hl7",
        "au_ref_i12.hl7",
        "au_ref_i12_simplified.hl7",
        "au_rri_i12.hl7",
        "au_orr_o02.hl7",
    ]

    static let batchFixture = "au_batch_oru_r01.hl7"

    /// `.strict` with the four AU caller assertions set: the message comes
    /// from a pathology sender, is intended for display, travels by SMD with
    /// NASH certificates, and draws PRD-7 authorities from Table 0363.
    static var asserted: ValidationOptions {
        var options = ValidationOptions.strict
        options.auPathologySender = true
        options.auDisplayIntended = true
        options.auNASHTransport = true
        options.auAssigningAuthorityTable = true
        return options
    }

    /// The ADRM-2021 field lengths that replace the v2.4 ones, as printed
    /// (the full list and pages: `AUFieldLengthTests.variations`).
    static let adrmLengths: [String: Int] = Dictionary(
        uniqueKeysWithValues: AUFieldLengthTests.variations.map { ("\($0.segment)-\($0.field)", $0.adrm) }
    )

    static func wire(_ name: String) throws -> String {
        try String(contentsOf: FixtureCorpus.fixtureURL(named: name), encoding: .utf8)
    }

    static func issues(_ wire: String, locale: HL7Locale = .auLocalisation,
                       options: ValidationOptions = asserted) throws -> [ValidationIssue] {
        let message = try Parser(locale: locale).parse(wire)
        return Validator(options: options, locale: locale).validate(message).issues
    }

    static func describe(_ issues: [ValidationIssue]) -> String {
        issues.map { "\($0.severity) \($0.location.pathDescription) \($0.message)" }.joined(separator: "\n")
    }

    /// A v2.4 length finding on a field whose ADRM length the value is within.
    static func isADRMLengthVariance(_ issue: ValidationIssue) -> Bool {
        guard case .fieldLengthOutOfRange(_, let actual) = issue.code,
              let field = issue.location.fieldIndex,
              let printed = adrmLengths["\(issue.location.segmentID)-\(field)"] else { return false }
        return actual <= printed
    }

    static func rule(_ issue: ValidationIssue) -> String? {
        if case .profileConstraintViolation(let rule) = issue.code { return rule }
        return nil
    }

    /// The findings a fixture draws by construction under the AU locale (see the header).
    static func expectedAU(_ name: String, _ issue: ValidationIssue) -> Bool {
        name == "au_ref_i12.hl7" && rule(issue)?.hasPrefix("HL7au:000040.4") == true
    }

    /// Checks an AU-locale run: nothing but the expected findings.
    static func checkAU(_ name: String, _ found: [ValidationIssue]) {
        let rest = found.filter { !expectedAU(name, $0) }
        #expect(rest.isEmpty, "\(name):\n\(describe(rest))")
        if name == "au_ref_i12.hl7" {
            #expect(found.filter { expectedAU(name, $0) }.map(\.location.pathDescription) == ["MSH[1]-12.3", "MSH[1]-12.3"])
        }
    }

    // MARK: - Whole fixtures

    @Test("Each AU fixture parses and round-trips byte for byte", arguments: fixtures)
    func roundTrips(name: String) throws {
        let data = try Data(contentsOf: FixtureCorpus.fixtureURL(named: name))
        let message = try Parser(locale: .auLocalisation).parse(data)
        #expect(message.serialize() == data)
    }

    @Test("Each AU fixture is clean under .strict, AU locale, all four assertions set", arguments: fixtures)
    func cleanAsserted(name: String) throws {
        Self.checkAU(name, try Self.issues(Self.wire(name)))
    }

    @Test("Each AU fixture is clean under .strict, AU locale, no assertion set", arguments: fixtures)
    func cleanUnasserted(name: String) throws {
        Self.checkAU(name, try Self.issues(Self.wire(name), options: .strict))
    }

    @Test("Under the international locale each AU fixture draws only the v2.4 length findings the ADRM varies",
          arguments: fixtures)
    func cleanInternational(name: String) throws {
        let found = try Self.issues(Self.wire(name), locale: .international, options: .strict)
        let rest = found.filter { !Self.isADRMLengthVariance($0) || $0.severity != .warning }
        #expect(rest.isEmpty, "\(name):\n\(Self.describe(rest))")
    }

    // MARK: - Fire and silent pairs, one per shipped rule family

    struct RulePair: Sendable, CustomTestStringConvertible {
        let family: String
        let fixture: String
        let old: String
        let new: String
        let rule: String
        let path: String
        var testDescription: String { family }
    }

    static let h1 = "1.2.36.1.2001.1003.0.0000000000001001"

    static let pairs: [RulePair] = [
        RulePair(family: "NASH transport", fixture: "au_oru_r01_radiology.hl7",
                 old: "SYNTH_IMAGING^\(h1)^ISO|SYNTH_CIS", new: "SYNTH_IMAGING^\(h1)^DNS|SYNTH_CIS",
                 rule: "HL7au:00044.2.3", path: "MSH[1]-4.3"),
        RulePair(family: "identifier components (CX)", fixture: "au_oru_r01_pathology.hl7",
                 old: "&ISO^MR||Synthetic^Alex", new: "&ISO^||Synthetic^Alex",
                 rule: "HL7au:00044.1.3", path: "PID[1]-3.5"),
        RulePair(family: "display OBX", fixture: "au_oru_r01_pathology.hl7",
                 old: "OBX|3|ED|HTML", new: "OBX|3|FT|HTML",
                 rule: "HL7au:000008.1.3", path: "OBX[3]-2.1"),
        RulePair(family: "coding-system precedence", fixture: "au_oru_r01_pathology.hl7",
                 old: "OBX|1|NM|718-7^Haemoglobin^LN|", new: "OBX|1|NM|HB^Haemoglobin^L^718-7^Haemoglobin^LN|",
                 rule: "HL7au:00044.4.4", path: "OBX[1]-3.6"),
        RulePair(family: "separators (MSH-2 escape)", fixture: "au_oru_r01_pathology.hl7",
                 old: "MSH|^~\\&|", new: "MSH|^~#&|",
                 rule: "HL7au:000024", path: "MSH[1]-2.1"),
        RulePair(family: "MSH-6 on orders", fixture: "au_orm_o01.hl7",
                 old: "|SYNTH_LIS|SYNTH_LAB^\(h1)^ISO|", new: "|SYNTH_LIS||",
                 rule: "HL7au:000001", path: "MSH[1]-6"),
        RulePair(family: "UCUM", fixture: "au_oru_r01_pathology.hl7",
                 old: "|140|g/L^g/L^UCUM|", new: "|140|g/L^g/L^ISO+|",
                 rule: "HL7au:00050.1.5", path: "OBX[1]-6.3"),
    ]

    static func mutated(_ pair: RulePair) throws -> String {
        let wire = try wire(pair.fixture)
        try #require(wire.components(separatedBy: pair.old).count == 2, "\(pair.old) is not unique in \(pair.fixture)")
        return wire.replacingOccurrences(of: pair.old, with: pair.new)
    }

    static func hits(_ issues: [ValidationIssue], _ prefix: String) -> [ValidationIssue] {
        issues.filter { rule($0)?.hasPrefix(prefix) == true }
    }

    @Test("Fire and silent pair per AU rule family", arguments: pairs)
    func firePair(pair: RulePair) throws {
        #expect(Self.hits(try Self.issues(Self.wire(pair.fixture)), pair.rule).isEmpty)
        let fired = Self.hits(try Self.issues(Self.mutated(pair)), pair.rule)
        #expect(fired.map(\.location.pathDescription) == [pair.path], "\(Self.describe(fired))")
    }

    static func dropping(_ segments: Set<String>, from name: String) throws -> String {
        try wire(name).split(separator: "\r").filter { !segments.contains(String($0.prefix(3))) }
            .joined(separator: "\r") + "\r"
    }

    @Test("Required segments (00060.1): an ORU without PID fires under the AU ORU^R01 structure")
    func requiredSegmentPair() throws {
        let name = "au_oru_r01_radiology.hl7"
        #expect(Self.hits(try Self.issues(Self.wire(name)), "HL7au:00060.1").isEmpty)
        let fired = Self.hits(try Self.issues(Self.dropping(["PID", "PV1"], from: name)), "HL7au:00060.1")
        #expect(fired.count == 1 && fired.first?.message.contains("PID") == true, "\(Self.describe(fired))")
    }

    @Test("Appendix 8 structure: dropping the display OBX fires 00060.1 on the simplified REF only")
    func appendix8Pair() throws {
        let simplified = "au_ref_i12_simplified.hl7"
        #expect(Self.hits(try Self.issues(Self.wire(simplified)), "HL7au:00060.1").isEmpty)
        let fired = Self.hits(try Self.issues(Self.dropping(["OBX"], from: simplified)), "HL7au:00060.1")
        #expect(fired.count == 1 && fired.first?.message.contains("OBX") == true, "\(Self.describe(fired))")
        // The Chapter 7 structure prints [{OBX}]: the same change is silent there.
        #expect(Self.hits(try Self.issues(Self.dropping(["OBX"], from: "au_ref_i12.hl7")), "HL7au:00060.1").isEmpty)
    }

    // MARK: - The S3-1 defects, fixed in P12 S3-2

    @Test("The Level 2 MSH-12 the ADRM requires (61 characters, LEN 250 p 37) is clean under the AU locale")
    func adrmMSH12Length() throws {
        let found = try Self.issues(Self.wire("au_ref_i12_simplified.hl7"))
        let msh12 = found.filter { $0.location.segmentID == "MSH" && $0.location.fieldIndex == 12 }
        #expect(msh12.isEmpty, "\(Self.describe(msh12))")
    }

    static let htmlDisplay = "OBX|3|ED|HTML^Display format in HTML^AUSPDI||^TEXT^HTML^Base64^"
        + "PHA+RnVsbCBibG9vZCBjb3VudDogc3ludGhldGljIHJlc3VsdHMuPC9wPg==|"
    static let pdfDisplay = "OBX|3|ED|PDF^Display format in PDF^AUSPDI||^application^pdf^Base64^JVBERi0xLjQK|"

    @Test("Suspected defect: the ADRM PDF display form ^application^pdf (Tables 0191 and 0291 as the ADRM prints them, pp 167 to 168) is rejected under the AU locale")
    func adrmPDFDisplay() throws {
        let wire = try Self.wire("au_oru_r01_pathology.hl7")
        try #require(wire.components(separatedBy: Self.htmlDisplay).count == 2)
        let found = try Self.issues(wire.replacingOccurrences(of: Self.htmlDisplay, with: Self.pdfDisplay))
        let tables = found.filter { if case .valueNotInTable = $0.code { return true }; return false }
        withKnownIssue("ADRM-2021 renderings of Tables 0191 and 0291 (IANA MIME rows) are not in the AU locale") {
            #expect(tables.isEmpty, "\(Self.describe(tables))")
        }
        // Every other AU rule accepts the ADRM's PDF form.
        let rest = found.filter { !tables.contains($0) }
        #expect(rest.isEmpty, "\(Self.describe(rest))")
    }

    // MARK: - Batch

    static func batchWire() throws -> String {
        try String(contentsOf: FixtureCorpus.batchFixtureURL(named: batchFixture), encoding: .utf8)
    }

    static func batchReport(_ wire: String) throws -> BatchValidationReport {
        BatchValidator(options: asserted, locale: .auLocalisation).validate(try BatchParser().parse(wire))
    }

    @Test("The AU batch fixture validates clean through BatchValidator under the AU locale")
    func batchClean() throws {
        let report = try Self.batchReport(Self.batchWire())
        #expect(report.batchIssues.isEmpty, "\(Self.describe(report.batchIssues))")
        #expect(report.messageReports.count == 2)
        for messageReport in report.messageReports {
            #expect(messageReport.issues.isEmpty, "\(Self.describe(messageReport.issues))")
        }
    }

    @Test("Batch headers: an FHS field separator other than | fires HL7au:000024.1 at FHS-1")
    func batchSeparatorPair() throws {
        let wire = try Self.batchWire()
        let header = try #require(wire.split(separator: "\r").first.map(String.init))
        let mutated = wire.replacingOccurrences(of: header, with: header.replacingOccurrences(of: "|", with: "!"))
        let fired = Self.hits(try Self.batchReport(mutated).batchIssues, "HL7au:000024.1")
        #expect(fired.map(\.location.pathDescription) == ["FHS[1]-1"], "\(Self.describe(fired))")
    }
}
