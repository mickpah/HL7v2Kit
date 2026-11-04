// V29GrammarTests.swift
// HL7 v2.9 through the ADR-015 pipeline. Each pin is a value the v2.9 text prints (ANSI December
// 2019, technical correction of January 2021); the citation sits beside it.

import Testing
@testable import HL7v2Kit

@Suite("v2.9 grammar")
struct V29GrammarTests {
    private var tables: [String: HL7Table] { HL7TableRegistry.v2_9 }

    @Test("v2.9 tables: one per Table Metadata block of Chapter 2C")
    func tableInventory() {
        #expect(tables.count == 789)
        #expect(tables.values.reduce(0) { $0 + $1.entries.count } == 5448)   // the extractor counts 5449: 0203 NNxxx is a pattern row
        // Chapter 2C prints 0070 no longer; v2.8.2 had it.
        #expect(tables["0070"] == nil)
    }

    @Test("Type HL7 is closed, User is user-defined, HL7-EXT and undefined never close")
    func tableKinds() throws {
        let valueType = try #require(tables["0125"])                 // 2C 0125, Type HL7
        #expect(valueType.kind == .hl7)
        #expect(!valueType.permitsLocalExtensions)
        #expect(valueType.entries.contains { $0.code == "CD" })
        let marital = try #require(tables["0002"])                   // 2C 0002, Type User
        #expect(marital.kind == .userDefined)
        let access = try #require(tables["0719"])                    // Appendix A index, HL7-EXT
        #expect(access.kind == .hl7)
        #expect(access.permitsLocalExtensions)
        let provider = try #require(tables["0133"])                  // 2C 0133, Type undefined
        #expect(provider.kind == .hl7)
        #expect(provider.permitsLocalExtensions)
    }

    @Test("A table v2.9 moved to an outside code system prints no rows")
    func externalisedTable() throws {
        // 2C 0078 prints a code system OID and no Coded Content block.
        #expect(try #require(tables["0078"]).entries.isEmpty)
    }

    @Test("A Value that looks like a heading is a code: Table 0005 prints 1002-5 to 2131-1")
    func dashedCodes() throws {
        let race = try #require(tables["0005"])                      // 2C 0005, footer page 37
        #expect(race.entries.map(\.code) == ["1002-5", "2028-9", "2054-5", "2076-8", "2106-3", "2131-1"])
    }

    @Test("A Value the page wraps over two lines is one code")
    func wrappedCodes() throws {
        let adverse = try #require(tables["0514"])                   // 2C 0514, footer page 435
        #expect(adverse.entries.contains { $0.code == "ACUTHEHTR" })
        #expect(adverse.entries.contains { $0.code == "NONHTRREC" })
        let coding = try #require(tables["0396"])                    // 2C 0396, footer pages 313 to 335
        #expect(coding.entries.contains { $0.code == "CDCEDACUITY" })
        #expect(coding.entries.contains { $0.code == "ALPHAID2006" })
        #expect(!coding.entries.contains { $0.code == "UITY" })
    }

    @Test("Table 0104 prints 2.9 and stays open to a locally agreed version")
    func versionId() throws {
        let version = try #require(tables["0104"])                   // 2C 0104, footer page 75
        #expect(version.entries.contains { $0.code == "2.9" })
        #expect(version.permitsLocalExtensions)
    }

    @Test("v2.9 datatypes: 71 composites and 448 components from CH02A")
    func datatypeInventory() throws {
        let grammars = DataTypeGrammarTable.v2_9
        #expect(grammars.count == 71)
        #expect(grammars.values.reduce(0) { $0 + $1.components.count } == 448)
        #expect(try #require(grammars["CWE"]).components.count == 22)    // Tables cross page breaks
        #expect(try #require(grammars["XAD"]).components.count == 23)
    }

    @Test("v2.9 conditions: ERL and OSP are new, PPN reads both ways, CNE.20 stays unmodelled")
    func datatypeConditions() throws {
        let grammars = DataTypeGrammarTable.v2_9
        func condition(_ type: String, _ index: Int) throws -> String? {
            try #require(grammars[type]).components.first { $0.index == index }?.condition
        }
        #expect(try condition("ERL", 3) == "5 populated")               // 2A.3.28.3, page 44
        #expect(try condition("ERL", 5) == "6 populated")               // 2A.3.28.5, page 44
        #expect(try condition("OSP", 2) == "3 empty")                   // 2A.3.52 component table, page 59
        #expect(try condition("OSP", 3) == "2 empty")
        #expect(try condition("RPT", 6) == "5 populated")               // 2A.3.67.6, page 78
        #expect(try condition("CNE", 20) == nil)                        // the print contradicts itself
        // 2A.3.56.15, page 66: a time stamp needs a person, and a person needs a time stamp.
        let groups = try #require(grammars["PPN"]).groupRequirements
        let person = try #require(groups.first { $0.name == "Performing person" })
        #expect(person.components == "1-14,16-26" && person.condition == "15 populated")
        let stamp = try #require(groups.first { $0.name == "Time stamp" })
        #expect(stamp.components == "15" && stamp.condition == "1-14 populated OR 16-26 populated")
        #expect(groups.count == 2)
        // PPN.15 is printed O in v2.9, so it carries no component condition.
        #expect(try condition("PPN", 15) == nil)
    }

    private var grammar: [String: SegmentGrammar] { SegmentGrammarTable.v2_9 }

    @Test("v2.9 segments: v2.8.2's 180 and seven new ones; ZL7 is an example, not a segment")
    func segmentInventory() {
        #expect(grammar.count == 187)
        for id in ["CTR", "DEV", "DST", "OH1", "OH2", "OH3", "OH4"] { #expect(grammar[id] != nil, "\(id)") }
        #expect(grammar["ZL7"] == nil)      // CH08 8.6.1: "proposed example only"
        #expect(grammar["QRD"] == nil)      // Appendix A lists it; no chapter defines it
    }

    @Test("MSH prints 28 fields; MSH-26 and MSH-27 bind tables 0952 and 0953")
    func mshFields() throws {
        let msh = try #require(grammar["MSH"])                  // CH02 2.14.9
        #expect(msh.fields.count == 28)
        #expect(msh.field(26)?.optionality == .conditional)
        // CWE fields carry no enforced `table` link (only ID and IS do); the binding to 0952 and
        // 0953 is the schema's `tables`, which the audit holds to the print.
        #expect(msh.field(26)?.dataType == "CWE" && msh.field(26)?.table == nil)
        #expect(msh.field(27)?.dataType == "CWE" && msh.field(27)?.table == nil)
        #expect(msh.field(27)?.repeatability == .multiple)
        #expect(msh.field(28)?.dataType == "ST")
        #expect(msh.field(2)?.length == "4..5")
    }

    @Test("ROL's printed - reads as B: CH15 15.4.7, retained for backward compatibility")
    func rolOptionality() throws {
        let rol = try #require(grammar["ROL"])
        #expect(rol.fields.count == 14)
        #expect(rol.fields.allSatisfy { $0.optionality == .backwardCompat })
    }

    @Test("OH2-5 is printed 54 by mistake, between OH2-4 and OH2-6")
    func oh2Misprint() throws {
        let oh2 = try #require(grammar["OH2"])
        #expect(oh2.field(5)?.name == "Industry")
        #expect(oh2.field(54) == nil)
    }

    @Test("ADD and RDT are hand-authored from their 1-n rows (CH02 2.14.1, CH05 5.5.8)")
    func variableColumnSegments() {
        #expect(grammar["ADD"]?.field(1)?.variableColumns == true)
        #expect(grammar["RDT"]?.fields.count == 1)
        #expect(grammar["RDT"]?.field(1)?.variableColumns == true)
    }

    @Test("A 2.9 message parses as v2.9 and validates against its own grammar")
    func dispatch() throws {
        let wire = "MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|20240301120000||ADT^A01^ADT_A01|MSG00001|P|2.9\r"
            + "EVN||20240301120000\rPID|1||123456^^^HOSP^MR||Smith^John||19800101|M\rPV1|1|I\r"
        let message = try Parser().parse(wire)
        #expect(message.version == .v2_9)
        #expect(message.version.grammarVersion == .v2_9)
        let codes = Validator(options: .strict).validate(message).issues.map(\.code)
        #expect(!codes.contains(.segmentNotInVersionGrammar))
        #expect(!codes.contains { if case .versionNotRecognised = $0 { return true } else { return false } })
    }

    @Test("\\P\\ is defined on v2.9: CH02 section 2.7.1")
    func truncationEscape() {
        #expect(Version.v2_9.definesTruncationEscape)
    }

    private static func mshWithField27(_ value: String) -> String {
        "MSH|^~\\&|LAB|FAC|GP|FAC|20240101||ORU^R01^ORU_R01|MSG|P|2.9"
            + String(repeating: "|", count: 15) + value + "\r"
    }

    @Test("MSH-26 is required when MSH-27 or MSH-28 is valued (CH02 2.14.9.26)")
    func securityClassificationCondition() throws {
        #expect(grammar["MSH"]?.field(26)?.condition == "MSH-27 populated OR MSH-28 populated")
        let issues = Validator().validate(try Parser().parse(Self.mshWithField27("SH1"))).issues
        #expect(issues.contains { $0.location.segmentID == "MSH" && $0.location.fieldIndex == 26 })
    }

    @Test("MSH-26 is optional when neither is valued")
    func securityClassificationOptional() throws {
        let issues = Validator().validate(try Parser().parse(Self.mshWithField27(""))).issues
        #expect(!issues.contains { $0.location.segmentID == "MSH" && $0.location.fieldIndex == 26 })
    }

    @Test("Every C field of v2.9 has a condition or a registered reason")
    func noBareConditionals() {
        #expect(bareConditionals(grammar) == Self.registeredBareConditionals)      // TestSupport.swift
    }

    /// Fields printed C whose rule the condition language cannot state, or the print leaves
    /// unstated. Each has a row in the permanent-limitations register.
    static let registeredBareConditionals: Set<String> = [
        // The text states no predicate on the field.
        "ADJ-7", "AIS-5", "ARQ-24", "BHS-16", "BHS-17", "CSP-4", "DG1-22", "DMI-2", "DMI-3", "DMI-4", "DMI-5",
        "FHS-16", "FHS-17", "GOL-22", "IVC-23", "OBX-5", "OBX-22", "PRB-28", "PSL-10", "PSL-12", "PSL-13",
        "PSL-14", "PSL-15", "PSL-16", "PTH-7", "QPD-2", "REL-1", "RXC-10", "RXE-10", "RXE-18", "RXE-19",
        "RXG-32", "RXO-31", "RXV-20", "RXV-21", "SCH-26", "TXA-22",
        // The rule turns on what the message cannot show: exchange state, intent, terminology, clinical
        // data or site policy.
        "AUT-6", "ARQ-2", "ARQ-3", "CER-12", "IAM-7", "OBR-48", "PRT-1", "RXA-7", "RXA-12",
        "RXC-11", "RXD-5", "RXD-8", "RXE-11", "RXE-16", "RXE-17", "RXE-22", "RXG-14", "RXG-33", "RXO-5",
        "RXO-15", "RXO-17", "SAC-3", "SAC-4", "SCH-3", "SCH-24", "SID-1", "SID-2", "SID-3", "SID-4", "TXA-11",
        // "All updating or modifying trigger events", which Chapter 10 does not list.
        "AIG-2", "AIL-2", "AIP-2", "AIS-2", "RGS-2",
        // Stated, but only approximately in this language: a predicate could misfire.
        "OBX-4", "PTH-6", "RXE-15",
    ]

    @Test("v2.9 structures are complete; ADT_A01 is modelled")
    func structureInventory() throws {
        #expect(MessageStructureTable.completeVersions.contains(.v2_9))
        let adt = try #require(MessageStructureTable.structure("ADT_A01", version: .v2_9))
        #expect(adt.triggers.contains("ADT^A01"))
    }

    @Test("A well-formed ADT_A01 draws no structure finding")
    func wellFormedStructure() throws {
        var options = ValidationOptions.default
        options.messageStructureSeverity = .error
        let wire = "MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|20240301120000||ADT^A01^ADT_A01|MSG00001|P|2.9\r"
            + "EVN||20240301120000\rPID|1||123456^^^HOSP^MR||Smith^John\rPV1|1|I\r"
        let found = Validator(options: options).validate(try Parser().parse(wire)).issues.filter(\.code.isMessageStructure)
        #expect(found.isEmpty)
    }

    @Test("Every Table 0354 row of v2.9 is modelled or registered")
    func everyRowAccounted() throws {
        let rows = try #require(HL7TableRegistry.table("0354", version: .v2_9)).entries.map(\.code)
        #expect(rows.count == 261)
        let modelled = rows.filter { MessageStructureTable.structure($0, version: .v2_9) != nil }
        let registered = rows.filter { MessageStructureTable.registration($0, version: .v2_9) != nil }
        #expect(modelled.count == 193)
        #expect(registered.count == 68)
        #expect(Set(modelled).isDisjoint(with: registered))
    }

    // CH02C Table 0354 p 269: the Display Name 'Laboratory Fulfillment request with REL segment'
    // holds a segment ID, never an event. p 268: 'INV_U14' for INR^U14^INR_U14 (CH13 13.3.14 p 30).
    @Test("Table 0354 errata: no event from prose, and the misprinted ID is registered")
    func table0354Errata() throws {
        #expect(try #require(MessageStructureTable.structure("OML_O59", version: .v2_9)).triggers == ["OML^O59"])
        #expect(try #require(MessageStructureTable.structure("INR_U14", version: .v2_9)).triggers == ["INR^U14"])
        #expect(MessageStructureTable.registration("INV_U14", version: .v2_9) != nil)
    }

    // Layout the reader had to learn, against the page: CH16 section numbers end in a dot (16.3.1.,
    // p 5); CH06 footnote marks stand a space from the bracket or over a wrapped ID (DFT_P11 p 16,
    // 'DG1' under '7'); DRG_O43 closes a group with '--- DONOR_OBSERVATIONS begin' (CH04 p 167).
    @Test("Chapter 16 headings, Chapter 6 footnote marks and the DRG_O43 mark read as printed")
    func layoutRules() throws {
        #expect(try #require(MessageStructureTable.structure("EHC_E01", version: .v2_9)).citation.contains("section 16.3.1 "))
        let p11 = try #require(MessageStructureTable.structure("DFT_P11", version: .v2_9))
        #expect(p11.elements.contains(.group("DIAGNOSIS", min: 0, max: nil, elements: [.segment("DG1", min: 1, max: 1)])))
        // CH11 11.6.1 p 26 prints 'ROL' with no '|'; without the erratum ROL and PRT read as one alternative.
        #expect(try #require(MessageStructureTable.structure("CCM_I21", version: .v2_9)).citation.contains("ROL_GROUP") == false)
        let donor = try #require(MessageStructureTable.structure("DRG_O43", version: .v2_9))
        #expect(donor.citation.contains("section 4.16.10"))
        #expect(MessageStructureTable.structure("WRQ_Z02", version: .v2_9) == nil)
    }
}
