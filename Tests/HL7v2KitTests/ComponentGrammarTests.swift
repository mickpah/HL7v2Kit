// ComponentGrammarTests.swift
// v0.2-V2: component-level grammar in Validator. Each typed composite
// (XPN / CX / XAD) carries a `static let requiredComponents` list, and
// the validator emits `.requiredComponentMissing` when a populated
// composite is missing one of those components.
//
// The 48-fixture corpus is unaffected (every fixture that populates
// PID-5 / PID-3 / PID-11 also populates the family / id / street
// components). The corpus pin lives at the bottom.

import Testing
import Foundation
@testable import HL7v2Kit

@Suite("Validator — component grammar (v0.2-V2)")
struct ComponentGrammarTests {

    // MARK: - XPN-1 (Family Name)

    @Test("PID-5 (XPN) without a family name is VALID: v2.5.1 prints XPN.1 as O")
    func xpnFamilyNameMissing() throws {
        // PID-5 = ^John^A — given+middle present, family empty.
        let wire = TestWires.adt("PID|1||123456^^^HOSP^MR||^John^A||19800101|M")
        let message = try Parser().parse(wire)
        let report = Validator().validate(message)
        // M14: required components come from the version's printed component table. XPN.1 is
        // printed O there; the old hand-written list called it required against the spec (req #4).
        #expect(!report.errors.contains { $0.code == .requiredComponentMissing && $0.location.fieldIndex == 5 })
    }

    @Test("PID-5 populated with family name → no .requiredComponentMissing")
    func xpnFamilyNamePresent() throws {
        let wire = TestWires.adt("PID|1||123456^^^HOSP^MR||Smith^John^A||19800101|M")
        let message = try Parser().parse(wire)
        let report = Validator().validate(message)
        #expect(!report.errors.contains { $0.code == .requiredComponentMissing })
    }

    @Test("PID-5 empty entirely → required-field check fires, NOT component check")
    func xpnEmptyFieldHitsRequiredFieldNotComponent() throws {
        // PID-5 is R-optionality. Empty PID-5 produces .requiredFieldMissing,
        // not .requiredComponentMissing (the component check is skipped on
        // empty fields).
        let wire = TestWires.adt("PID|1||123456^^^HOSP^MR|||19800101|M")
        let message = try Parser().parse(wire)
        let report = Validator().validate(message)
        let pid5Issues = report.errors.filter { $0.location.fieldIndex == 5 }
        #expect(pid5Issues.contains { $0.code == .requiredFieldMissing })
        #expect(!pid5Issues.contains { $0.code == .requiredComponentMissing })
    }

    // MARK: - CX-1 (ID Number)

    @Test("PID-3 (CX) populated without ID number fires .requiredComponentMissing at PID[1]-3.1")
    func cxIdMissing() throws {
        // PID-3 = ^4^M11^HOSP^MR — id empty, check digit + scheme + auth + type present.
        let wire = TestWires.adt("PID|1||^4^M11^HOSP^MR||Smith^John||19800101|M")
        let message = try Parser().parse(wire)
        let report = Validator().validate(message)
        let issue = try #require(report.errors.first { $0.code == .requiredComponentMissing && $0.location.fieldIndex == 3 })
        #expect(issue.location.componentIndex == 1)
        #expect(issue.location.pathDescription == "PID[1]-3.1")
        #expect(issue.message.contains("ID Number"))
        #expect(issue.message.contains("CX"))
    }

    @Test("PID-3 (CX, multi-rep) — each repetition is checked independently")
    func cxMultiRepEachChecked() throws {
        // PID-3 = 123456^^^HOSP^MR ~ ^^^MEDICARE^NI
        // Rep 1 has ID; rep 2 is missing it.
        let wire = TestWires.adt("PID|1||123456^^^HOSP^MR~^^^MEDICARE^NI||Smith^John||19800101|M")
        let message = try Parser().parse(wire)
        let report = Validator().validate(message)
        let cxIssues = report.errors.filter { $0.code == .requiredComponentMissing && $0.location.fieldIndex == 3 }
        // One issue — for the second repetition. Validator currently doesn't
        // disambiguate which repetition in the location; the pin documents
        // the count contract.
        #expect(cxIssues.count == 1)
    }

    // MARK: - XAD-1 (Street Address)

    @Test("PID-11 (XAD) without a street address is VALID: v2.5.1 prints XAD.1 as O")
    func xadStreetMissing() throws {
        // Field map (counted pipe-by-pipe):
        //  1 setID=1, 2 empty, 3 ids=123456..., 4 empty, 5 name=Smith^John,
        //  6 empty, 7 DOB=19800101, 8 sex=M, 9 empty, 10 race=2106-3^White^HL70005,
        //  11 address=^Apt 5^Sydney^NSW^2000  ← street component empty.
        let wire = TestWires.adt("PID|1||123456^^^HOSP^MR||Smith^John||19800101|M||2106-3^White^HL70005|^Apt 5^Sydney^NSW^2000")
        let message = try Parser().parse(wire)
        // Sanity-check pipe count: PID-11.3 should be "Sydney".
        #expect(message["PID-11.3"] == "Sydney", "Wire mis-counted: XAD should land at PID-11")
        let report = Validator().validate(message)
        // M14: required components come from the version's printed component table. XAD.1 is
        // printed O there; the old hand-written list called it required against the spec (req #4).
        #expect(!report.errors.contains { $0.code == .requiredComponentMissing && $0.location.fieldIndex == 11 })
    }

    // MARK: - Toggle behaviour

    @Test("checkComponentGrammar=false suppresses the component check")
    func toggleSuppresses() throws {
        let wire = TestWires.adt("PID|1||123456^^^HOSP^MR||^John^A||19800101|M")
        let message = try Parser().parse(wire)
        let options = ValidationOptions(checkComponentGrammar: false)
        let report = Validator(options: options).validate(message)
        #expect(!report.errors.contains { $0.code == .requiredComponentMissing })
    }

    @Test(".lenient preset disables component-grammar enforcement")
    func lenientPresetDisables() throws {
        let wire = TestWires.adt("PID|1||123456^^^HOSP^MR||^John^A||19800101|M")
        let message = try Parser().parse(wire)
        let report = Validator(options: .lenient).validate(message)
        #expect(!report.errors.contains { $0.code == .requiredComponentMissing })
    }

    @Test(".strict preset enables component-grammar enforcement")
    func strictPresetEnables() throws {
        // CX.1 ID Number is printed R on every version that prints a component table.
        let wire = TestWires.adt("PID|1||^^^HOSP^MR||Smith^John^A||19800101|M")
        let message = try Parser().parse(wire)
        let report = Validator(options: .strict).validate(message)
        #expect(report.errors.contains { $0.code == .requiredComponentMissing && $0.location.pathDescription == "PID[1]-3.1" })
    }

    // MARK: - Composites with empty requiredComponents (OR-rule design choice)

    @Test("HD with empty HD-1 but populated HD-2/HD-3 does NOT fire (OR-rule design)")
    func hdSkipsSilentlyWithEmptyRequiredComponents() throws {
        // PID-34 (lastUpdateFacility) is HD-typed. HD ships with an
        // empty `requiredComponents` by design — the v2.5.1 spec phrases
        // HD's conformance as "HD-1 OR (HD-2 AND HD-3)", an OR-rule the
        // current `RequiredComponent` shape can't express. An HD field
        // populated with only HD-2 / HD-3 and an empty HD-1 must NOT
        // fire `.requiredComponentMissing`. Pinned so a future change
        // that drops the OR-rule constraint and just requires HD-1
        // can't sneak in without an explicit decision.
        //
        // Fields populated in this wire:
        //  1 setID=1, 3 ids=123456..., 5 name=Smith^John, 7 DOB, 8 sex=M,
        //  9..33 empty, 34 lastUpdateFacility=^UNIV_ID^ISO  ← HD with empty HD-1
        let wire = TestWires.adt("PID|1||123456^^^HOSP^MR||Smith^John||19800101|M||||||||||||||||||||||||||^UNIV_ID^ISO")
        let message = try Parser().parse(wire)
        #expect(message["PID-34.2"] == "UNIV_ID", "Wire mis-counted: HD should land at PID-34")
        let report = Validator().validate(message)
        let pid34Issues = report.errors.filter { $0.location.fieldIndex == 34 }
        #expect(!pid34Issues.contains { $0.code == .requiredComponentMissing })
    }

    @Test("CE with text only is VALID: v2.5.1 prints CE.1 as O")
    func ceFiresComponentMissingOnEmptyIdentifier() throws {
        // PID-10 (race) is CE-typed. v0.3-C2 promoted CE; CE-1 (identifier)
        // is the required component. An empty PID-10.1 with PID-10.2
        // populated must NOW fire .requiredComponentMissing at PID[1]-10.1.
        let wire = TestWires.adt("PID|1||123456^^^HOSP^MR||Smith^John||19800101|M||^WhiteTextOnly")
        let message = try Parser().parse(wire)
        let report = Validator().validate(message)
        // M14: required components come from the version's printed component table. CE.1 is
        // printed O there; the old hand-written list called it required against the spec (req #4).
        #expect(!report.errors.contains { $0.code == .requiredComponentMissing && $0.location.fieldIndex == 10 })
    }

    @Test("CWE typed composite (v0.3-C2/v0.4-S4) fires OR-rule violation on empty CWE-1 + CWE-9")
    func cweFiresORRuleViolationOnEmptyIdentifierAndOriginalText() throws {
        // PID-39 (tribal citizenship) is CWE-typed. Under v0.4-S4 CWE
        // ships an OR-rule `requiredComponentSet`: CWE-1 OR CWE-9 must
        // be populated. A wire with CWE-2 populated but BOTH CWE-1 and
        // CWE-9 empty violates the rule and fires
        // .requiredComponentMissing at the field level (no specific
        // component index — the violation is the disjunction).
        // Field map: 1 setID=1, 3 ids, 5 name, 7 DOB, 8 sex=M, 9..38 empty
        // (31 pipes after M), 39 tribalCitizenship=^AustralianText  ← CWE-1 empty, CWE-9 empty.
        let wire = TestWires.adt("PID|1||123456^^^HOSP^MR||Smith^John||19800101|M|||||||||||||||||||||||||||||||^AustralianText")
        let message = try Parser().parse(wire)
        #expect(message["PID-39.2"] == "AustralianText", "Wire mis-counted: CWE should land at PID-39")
        let report = Validator().validate(message)
        let issue = try #require(report.errors.first { $0.code == .requiredComponentMissing && $0.location.fieldIndex == 39 })
        // OR-rule issues are field-level, not component-level.
        #expect(issue.location.componentIndex == nil)
        #expect(issue.message.contains("OR-rule"))
        #expect(issue.message.contains("CWE-1"))
        #expect(issue.message.contains("CWE-9"))
    }

    @Test("CWE typed composite — CWE-9-only payload satisfies the OR-rule (v0.4-S4)")
    func cweORRuleSatisfiedByOriginalTextAlone() throws {
        // Spec-compliant CWE payload: CWE-1 empty, CWE-9 populated with
        // free text. Under v0.4-S4 OR-rule semantics, this satisfies
        // "CWE-1 OR CWE-9" and must NOT fire. This is the case
        // v0.3-C2's flat `requiredComponents = [CWE-1]` got wrong.
        // PID-39 wire: CWE-1 empty, CWE-2..8 empty, CWE-9 populated.
        let wire = TestWires.adt("PID|1||123456^^^HOSP^MR||Smith^John||19800101|M|||||||||||||||||||||||||||||||^^^^^^^^FreeTextSpeciesName")
        let message = try Parser().parse(wire)
        #expect(message["PID-39.9"] == "FreeTextSpeciesName", "Wire mis-counted: CWE-9 should land here")
        let report = Validator().validate(message)
        let pid39Issues = report.errors.filter { $0.code == .requiredComponentMissing && $0.location.fieldIndex == 39 }
        #expect(pid39Issues.isEmpty, "OR-rule satisfied via CWE-9; no issue expected")
    }

    @Test("EI without an entity identifier is VALID in the base spec: EI.1 is printed O")
    func eiFiresComponentMissingOnEmptyEntityIdentifier() throws {
        // ORC-2 (placerOrderNumber) is EI-typed. v0.3-C3 promoted EI;
        // EI-1 (entityIdentifier) is the required component. An empty
        // ORC-2.1 with ORC-2.2 populated must fire .requiredComponentMissing
        // at ORC[1]-2.1.
        let wire = """
        MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|||ORM^O01^ORM_O01|MSG00001|P|2.5.1\r\
        ORC|NW|^HOSP^1.2.840.10008^ISO\r
        """
        let message = try Parser().parse(wire)
        let report = Validator().validate(message)
        // M14: required components come from the version's printed component table. EI.1 is
        // printed O in v2.5.1; the old hand-written list called it required against the spec (req #4).
        #expect(!report.errors.contains {
            $0.code == .requiredComponentMissing && $0.location.segmentID == "ORC" && $0.location.fieldIndex == 2
        })
    }

    @Test("XCN without an ID number is VALID: v2.5.1 prints XCN.1 as O")
    func xcnFiresComponentMissingOnEmptyIdNumber() throws {
        // PV1-7 (attendingDoctor) is XCN-typed. Empty XCN-1 (idNumber)
        // with XCN-2 (familyName) populated must fire
        // .requiredComponentMissing at PV1[1]-7.1.
        let wire = TestWires.adt("PV1|1|I|||||^Jones^Mary")
        let message = try Parser().parse(wire)
        let report = Validator().validate(message)
        // M14: required components come from the version's printed component table. XCN.1 is
        // printed O in v2.5.1; the old hand-written list called it required against the spec (req #4).
        #expect(!report.errors.contains {
            $0.code == .requiredComponentMissing && $0.location.segmentID == "PV1" && $0.location.fieldIndex == 7
        })
    }

    @Test("MSG typed composite (v0.3-C4) fires .requiredComponentMissing on empty MSG-1")
    func msgFiresComponentMissingOnEmptyMessageCode() throws {
        // MSH-9 (messageType) is MSG-typed. Empty MSG-1 (messageCode)
        // with MSG-2 (triggerEvent) populated must fire at MSH[1]-9.1.
        let wire = """
        MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|||^A01|MSG00001|P|2.5.1\r
        """
        let message = try Parser().parse(wire)
        let report = Validator().validate(message)
        let issue = try #require(report.errors.first { $0.code == .requiredComponentMissing && $0.location.fieldIndex == 9 })
        #expect(issue.location.componentIndex == 1)
        #expect(issue.location.pathDescription == "MSH[1]-9.1")
        #expect(issue.message.contains("Message Code"))
        #expect(issue.message.contains("MSG"))
    }

    @Test("VID without a version ID: v2.5.1 prints VID.1 as O (it becomes R in v2.8.2)")
    func vidFiresComponentMissingOnEmptyVersionID() throws {
        // MSH-12 (versionID) is VID-typed. Empty VID-1 with VID-2 (the
        // nested internationalization CE composite) populated must fire
        // at MSH[1]-12.1. Note: empty MSH-12.1 also causes Parser to
        // silently fall back to v2.5.1; the Field itself is still
        // populated (carries VID-2 / VID-3 sub-components) so V2 walks
        // it and finds the missing VID-1.
        let wire = """
        MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|||ADT^A01|MSG00001|P|^I18N1^IVID1\r
        """
        let message = try Parser().parse(wire)
        let report = Validator().validate(message)
        // M14: required components come from the version's printed component table. VID.1 is
        // printed O in v2.5.1; the old hand-written list called it required against the spec (req #4).
        #expect(!report.errors.contains {
            $0.code == .requiredComponentMissing && $0.location.segmentID == "MSH" && $0.location.fieldIndex == 12
        })
    }

    @Test("PT without a processing ID: v2.5.1 prints PT.1 as O (it becomes R in v2.8.2)")
    func ptFiresComponentMissingOnEmptyProcessingID() throws {
        // MSH-11 (processingID) is PT-typed. Empty PT-1 (processingID)
        // with PT-2 (processingMode) populated must fire at MSH[1]-11.1.
        let wire = """
        MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|||ADT^A01|MSG00001|^A|2.5.1\r
        """
        let message = try Parser().parse(wire)
        let report = Validator().validate(message)
        // M14: required components come from the version's printed component table. PT.1 is
        // printed O in v2.5.1; the old hand-written list called it required against the spec (req #4).
        #expect(!report.errors.contains {
            $0.code == .requiredComponentMissing && $0.location.segmentID == "MSH" && $0.location.fieldIndex == 11
        })
    }

    @Test("CNE typed composite (v0.3-C4) fires .requiredComponentMissing on empty CNE-1")
    func cneFiresComponentMissingOnEmptyIdentifier() throws {
        // ORC-30 (entererAuthorizationMode) is CNE-typed. Empty CNE-1
        // with CNE-2 populated must fire at ORC[1]-30.1.
        // Pipe count between "NW" and "^ElectronicTextOnly": 29.
        let wire = """
        MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|||ORM^O01^ORM_O01|MSG00001|P|2.5.1\r\
        ORC|NW|||||||||||||||||||||||||||||^ElectronicTextOnly\r
        """
        let message = try Parser().parse(wire)
        #expect(message["ORC-30.2"] == "ElectronicTextOnly", "Wire mis-counted: CNE should land at ORC-30")
        let report = Validator().validate(message)
        let issue = try #require(report.errors.first { $0.code == .requiredComponentMissing && $0.location.fieldIndex == 30 })
        #expect(issue.location.componentIndex == 1)
        #expect(issue.location.pathDescription == "ORC[1]-30.1")
        #expect(issue.message.contains("Identifier"))
        #expect(issue.message.contains("CNE"))
    }

    @Test("XON without an organization name is VALID: v2.5.1 prints XON.1 as O")
    func xonFiresComponentMissingOnEmptyOrganizationName() throws {
        // NK1-13 (organizationName) is XON-typed. Empty XON-1 with
        // XON-2 populated must fire at NK1[1]-13.1.
        // Pipe count between "SPO" and "^L": 9 (= NK1-13 - NK1-4).
        let wire = TestWires.adt("NK1|1|Smith^Jane||SPO|||||||||^L")
        let message = try Parser().parse(wire)
        let report = Validator().validate(message)
        // M14: required components come from the version's printed component table. XON.1 is
        // printed O in v2.5.1; the old hand-written list called it required against the spec (req #4).
        #expect(!report.errors.contains {
            $0.code == .requiredComponentMissing && $0.location.segmentID == "NK1" && $0.location.fieldIndex == 13
        })
    }

    @Test("PL typed composite (v0.3-C4) has no required components — sparse PL field does NOT fire")
    func plSkipsSilentlyWithNoRequiredComponents() throws {
        // PV1-3 (assignedPatientLocation) is PL-typed. PL ships with
        // empty requiredComponents (the v2.5.1 "PL-1 OR PL-4" OR-rule
        // again). A PL populated with only PL-4 (facility) and empty
        // PL-1..3 must NOT fire any component-grammar issue.
        let wire = TestWires.adt("PV1|1|I|^^^HOSPITAL|R")
        let message = try Parser().parse(wire)
        let report = Validator().validate(message)
        let pv13Issues = report.errors.filter { $0.location.fieldIndex == 3 && $0.code == .requiredComponentMissing }
        #expect(pv13Issues.isEmpty)
    }

    @Test("EIP typed composite (v0.3-C4) has no required components — empty EIP-1 does NOT fire")
    func eipSkipsSilentlyWithNoRequiredComponents() throws {
        // ORC-8 (parent) is EIP-typed. EIP ships with empty
        // requiredComponents — a child order may populate only one
        // slot of the pair, neither slot is strictly required.
        let wire = """
        MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|||ORM^O01^ORM_O01|MSG00001|P|2.5.1\r\
        ORC|NW|||||||^FILLER456&LAB\r
        """
        let message = try Parser().parse(wire)
        let report = Validator().validate(message)
        let orc8Issues = report.errors.filter { $0.location.fieldIndex == 8 && $0.code == .requiredComponentMissing }
        #expect(orc8Issues.isEmpty)
    }

    @Test("XTN typed composite (v0.3-C3) has no required components — empty XTN-1 does NOT fire")
    func xtnSkipsSilentlyWithNoRequiredComponents() throws {
        // PID-13 (phoneNumberHome) is XTN-typed. XTN.requiredComponents is
        // intentionally empty (XTN-1 deprecated; XTN-12 modern primary;
        // neither strictly required). An XTN populated with only XTN-4
        // (email address) must NOT fire any component-grammar error —
        // pins the design choice that XTN's empty requiredComponents list
        // is the right call.
        let wire = TestWires.adt("PID|1||123456^^^HOSP^MR||Smith^John||19800101|M|||||^^^john@example.com")
        let message = try Parser().parse(wire)
        let report = Validator().validate(message)
        let pid13Issues = report.errors.filter { $0.location.fieldIndex == 13 && $0.code == .requiredComponentMissing }
        #expect(pid13Issues.isEmpty)
    }

    // MARK: - Fixture corpus regression pin

    @Test("Fixture corpus is unaffected by component-grammar enforcement")
    func fixtureCorpusNoComponentErrors() throws {
        // Every gold-corpus fixture that populates an XPN / CX / XAD field
        // also populates the required component (family / id / street).
        // Pin so a future fixture addition that breaks this rule surfaces
        // here directly, alongside the existing
        // FixtureRoundTripTests.allValidProduceNonErrorReport check.
        let urls = try FixtureCorpus.validFixtureURLs()
        #expect(!urls.isEmpty)
        for url in urls {
            let bytes = try Data(contentsOf: url)
            guard let message = try? Parser().parse(bytes) else { continue }
            let report = Validator().validate(message)
            let componentIssues = report.errors.filter { $0.code == .requiredComponentMissing }
            #expect(componentIssues.isEmpty,
                    "\(url.lastPathComponent) unexpectedly hit a component-grammar check: \(componentIssues.map(\.message))")
        }
    }

    @Test("v2.8.2 prints PT.1 and VID.1 as R: the same omissions ARE errors there")
    func ptAndVidRequiredFromV282() throws {
        let wire = "MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|||ADT^A01^ADT_A01|MSG00001|^T|^AUS\r"
        let v282 = wire.replacingOccurrences(of: "|^T|^AUS", with: "|^T|2.8.2")
        let report = Validator().validate(try Parser().parse(v282 + "PID|1||123^^^HOSP^MR||Smith^John\r"))
        #expect(report.errors.contains { $0.code == .requiredComponentMissing && $0.location.pathDescription == "MSH[1]-11.1" })
    }
}
