// V291GrammarTests.swift
// HL7 v2.9.1 (ANSI/HL7 V2.9.1-2024) through the ADR-015 pipeline. Each pin is a value the
// September 2024 print states. No XSD is held for this version.

import Foundation
import Testing
@testable import HL7v2Kit

@Suite("v2.9.1 grammar")
struct V291GrammarTests {
    private var tables: [String: HL7Table] { HL7TableRegistry.v2_9_1 }

    private func codes(_ number: String) throws -> Set<String> {
        Set(try #require(tables[number]).entries.map(\.code))
    }

    private func description(_ number: String, _ code: String) throws -> String? {
        try #require(tables[number]).entries.first { $0.code == code }?.description
    }

    @Test("2.9.1 tables: one per Table Metadata block of Chapter 2C")
    func tableInventory() {
        #expect(tables.count == 799)
        // A count of what the pipeline holds, overrides included, not a figure the print states. The extractor says 5676: 0203 NNxxx is a pattern.
        #expect(tables.values.reduce(0) { $0 + $1.entries.count } == 5675)
        #expect(tables["0820"] != nil)     // new in 2.9.1
    }

    @Test("2.9.1 datatypes: 71 composites and 448 components")
    func datatypeInventory() {
        let grammars = DataTypeGrammarTable.v2_9_1
        #expect(grammars.count == 71)
        #expect(grammars.values.reduce(0) { $0 + $1.components.count } == 448)
    }

    @Test("Table 0953: the value set the print names, closed, same rows as v2.9")
    func table0953() throws {
        // CH02C pp 850-851: Type HL7-EXT, no rows, SecurityControlObservationValue
        // 2.16.840.1.113883.1.11.20471. Rows through the override, the same source as v2.9's.
        let table = try #require(tables["0953"])
        let earlier = try #require(HL7TableRegistry.v2_9["0953"])
        #expect(table.entries.count == 140)
        #expect(table.entries.map(\.code) == earlier.entries.map(\.code))
        #expect(table.isClosed)
    }

    @Test("Type HL7 is closed; User, External, HL7-EXT and undefined are not")
    func tableKinds() throws {
        let valueType = try #require(tables["0125"])                 // 2C 0125, Type HL7
        #expect(valueType.kind == .hl7 && valueType.isClosed)
        #expect(try #require(tables["0002"]).kind == .userDefined)   // 2C 0002, Type User
        #expect(try #require(tables["0133"]).permitsLocalExtensions) // 2C 0133, Type undefined
        let concepts = try #require(tables["0820"])                  // 2C 0820 p 771, Type External
        #expect(concepts.kind == .hl7 && concepts.permitsLocalExtensions)
        let orientation = try #require(tables["0823"])               // 2C 0823 p 775, Type HL7-EXT, prints rows
        #expect(orientation.kind == .hl7 && orientation.permitsLocalExtensions)
        // ADR-016: field prose calling the table user-defined decides the kind, over Type HL7 or HL7-EXT.
        let drg = try #require(tables["0731"])                       // DG1-25, CH06 6.5.2.25; 2C p 735 Type HL7
        #expect(drg.kind == .userDefined && !drg.isClosed && drg.entries.count == 5)
        let transfer = try #require(tables["0415"])                  // DRG-11, CH06 6.5.3.11 p 51; 2C pp 442-443 Type HL7
        #expect(transfer.kind == .userDefined && !transfer.isClosed && transfer.entries.map(\.code) == ["N", "E"])
        let reason = try #require(tables["0719"])                    // ARV-4, CH03 3.4.14.4; 2C p 730 Type HL7-EXT
        #expect(reason.kind == .userDefined && reason.permitsLocalExtensions)
        // Prose does not settle these, so the print's type stands. GSC-4 (CH03) says "HL7-defined Table 0828", RFR.2 and
        // OM1-58 "User-defined". TXA-24 (CH09) says "Table 0791 ... for valid values"; "User-defined Table 0791" at IN3-30 is a misprint of 0971.
        #expect(try #require(tables["0828"]).kind == .hl7)
        #expect(try #require(tables["0791"]).kind == .hl7)
        // Appendix A.6 indexes 0821 as User and prints rows; Chapter 2C governs: Type HL7-EXT, no rows (pp 772-773).
        let identity = try #require(tables["0821"])
        #expect(identity.kind == .hl7 && identity.permitsLocalExtensions && identity.entries.isEmpty)
        // 0828 prints Type HL7 and no rows (pp 779-780); Appendix A.6 prints four. Nothing to close over.
        let parameter = try #require(tables["0828"])
        #expect(parameter.entries.isEmpty && !parameter.isClosed)
    }

    @Test("Rows the 2.9.1 page prints and v2.9's does not")
    func rowsNewIn291() throws {
        #expect(try codes("0104").contains("2.9.1"))                 // p 97
        #expect(try codes("0202").contains("DSM"))                   // p 182
        #expect(try codes("0003").isSuperset(of: ["Q04", "R0R", "X01"]))      // p 33
        #expect(try codes("0203").isSuperset(of: ["GKV", "KZVA", "PKV", "ZANR"]))     // pp 188, 194, 197
        #expect(try codes("0396").isSuperset(of: ["DAR", "GLN", "SPCU", "ISO", "ALPHAID2023"]))
        #expect(try codes("0916").contains("FNA"))                   // p 812
        #expect(try codes("0931") == ["degF", "[degF]", "Cel"])      // p 827
        // A dashed LOINC Value is a code, not a heading.
        #expect(try codes("0820") == ["76691-5", "76690-7", "90778-2"])       // pp 771-772
        #expect(try codes("0823") == ["89217008", "20430005", "42035005", "UNK", "asked-declined"])     // p 776
    }

    @Test("Table 0005 prints no rows on 2.9.1, though v2.9 printed six")
    func raceIsEmpty() throws {
        #expect(try #require(tables["0005"]).entries.isEmpty)        // p 47, Concept Domain Only yes
        #expect(try #require(HL7TableRegistry.v2_9["0005"]).entries.count == 6)
    }

    @Test("A Value the page wraps is one code, and its pieces are not codes")
    func wrappedCodes() throws {
        let adverse = try codes("0514")                              // p 556
        #expect(adverse.contains("NONHTRREC") && !adverse.contains("NONHTRRE") && !adverse.contains("C"))
        #expect(adverse.contains("ACUTHEHTR") && adverse.contains("BACTCONTAM"))
        let filler = try codes("0278")                               // pp 278-279
        #expect(filler.contains("Discontinued") && !filler.contains("Discontinue") && !filler.contains("d"))
        #expect(filler.count == 12)
        let coding = try codes("0396")                               // pp 402-403
        #expect(coding.isSuperset(of: ["CDCINDUSTRY2010", "CDCOCCUPATION2010"]))
        #expect(!coding.contains("0") && !coding.contains("2010"))
        let priority = try codes("0485")                             // p 511
        #expect(priority.isSuperset(of: ["TM<integer>", "TH<integer>", "TD<integer>", "TW<integer>"]))
        #expect(!priority.contains(">") && !priority.contains("TM<integer"))
        let pattern = try codes("0335")                              // pp 326-327
        #expect(pattern.isSuperset(of: ["Q<integer>J<day#>", "Meal Related Timings"]))
        #expect(!pattern.contains("y#>") && !pattern.contains("Timings"))
        #expect(try codes("0393") == ["LINKSOFT_2.01", "MATCHWARE_1.2"])      // pp 395-396
        #expect(try codes("0211").isSuperset(of: ["CNS 11643-1992", "UNICODE UTF-8"]))    // p 208
        #expect(try !codes("0211").contains("1992"))
    }

    @Test("A row one space from its Display Name is a row")
    func oneSpaceRows() throws {
        let additive = try codes("0371")                             // pp 371-372
        #expect(additive.isSuperset(of: ["MICHTM", "MMDTM", "PHENOL", "THYMOL"]))
        #expect(!additive.contains("Products)"))
    }

    @Test("Table 0717: 76 rows, consent directives and legal authorities rebuilt from the print")
    func accessRestriction() throws {
        let access = try codes("0717")                               // pp 678-728
        #expect(access.count == 76)
        #expect(access.isSuperset(of: ["42CFRPart2CD", "42CFRPart2", "HIPAAAuthCD", "HIPAAAuth", "HIPAAROACD", "HIPAAROA",
                                       "HIPAAResearchAuthCD", "CompoundResearchCD", "GDPRResearchCD", "HIPAAPsyNotes",
                                       "Title38Section7332", "GDPRHLTHSOCSY", "GDPRVITALINTEREST"]))
        #expect(access.isDisjoint(with: ["CD", "D", "policy", "information", "uncontrolled", "exceptions", "entCD", "NTEREST"]))
    }

    @Test("A printed row that is no code is dropped")
    func nonValueRows() throws {
        #expect(try codes("0207").isDisjoint(with: ["Not", "present", "Not present"]))      // p 202
        #expect(try codes("0301").isSuperset(of: ["L", "M", "N"]))   // p 300
        #expect(try !codes("0301").contains("L,M,N"))
        #expect(try codes("0528").contains("AHS"))                   // the RPT example, CH02A p 77
    }

    @Test("Tables left open on 2.9.1")
    func openTables() throws {
        // By the print's words: "Z" codes are reserved (CH02 p8), "MAY be extended", "for suggested values".
        for number in ["0003", "0076", "0105", "0175", "0203", "0920"] {
            #expect(try #require(tables[number]).isClosed == false, "\(number)")
            #expect(try #require(tables[number]).kind == .hl7, "\(number)")
        }
        // Chapters print names no row holds: MFN_M19 and QBP_Q33 for 0354, the group DONOR (CH04 p163) for 0391.
        for number in ["0354", "0391"] { #expect(try #require(tables[number]).isClosed == false, "\(number)") }
        // Kind User, so never closed; the override records the print's own "suggested" and "unbounded".
        for number in ["0359", "0544"] {
            let table = try #require(tables[number])
            #expect(table.kind == .userDefined && table.permitsLocalExtensions, "\(number)")
        }
        // CH02 p71 and CH02A p87 say "for valid values", so closed, by the owner's ruling. v2.3 to v2.8.2 stay open.
        #expect(try #require(tables["0104"]).isClosed)
        #expect(try #require(tables["0391"]).entries.count == 132)      // Chapter 2C's rows stand, pp 389-393
        #expect(try #require(tables["0617"]).kind == .userDefined)   // XAD.18, CH02A p 92
        // 0203 NNxxx names a family of codes (p 192).
        let identifier = try #require(tables["0203"])
        #expect(!identifier.entries.contains { $0.code == "NNxxx" })
        #expect(identifier.patterns.contains { $0.code == "NNxxx" })
    }

    @Test("Display Names carry no Definition text, and a word broken at the column edge is whole")
    func displayNames() throws {
        #expect(try description("0203", "IND") == "Indigenous/Aboriginal")                  // p 188
        #expect(try description("0203", "AC") == "Accreditation/Certification Identifier")  // p 183
        #expect(try description("0203", "ESN") == "Staff Enterprise Number")                // p 188
        #expect(try description("0301", "DNS") == "Domain Name System")                     // p 299
        #expect(try description("0550", "BROCH") == "Bronchiole/Bronchiolar")               // p 585
        #expect(try description("0553", "RC") == "Referral Pre-Authorization")              // p 597
        #expect(try description("0717", "OOC") == "opt-out of personal information or effect collection in a registry or repository")
        #expect(try description("0278", "Discontinued")?.hasPrefix("The indicated appointment was discontinued") == true)
        // The page repeats the wrapped header cell `Display` / `Name`; it is no part of the row above it.
        #expect(try description("0950", "EOE") == "Expiration on event")                    // p 846
        #expect(try description("0951", "SI") == "Suspected interference")                  // p 848
        // Spaces the print sets on one line stay.
        #expect(try description("0396", "SDM") == "SNOMED- DICOM Microglossary")
    }

    private func component(_ type: String, _ index: Int) throws -> ComponentGrammar? {
        try #require(DataTypeGrammarTable.v2_9_1[type]).components.first { $0.index == index }
    }

    @Test("2.9.1 conditions: ERL.3 and SN.2 differ from v2.9, the rest carry after reading")
    func datatypeConditions() throws {
        // 2A.2.28.3 p 44: "when Field Repetition (ERL-4) and/or Component Number (ERL-5) are populated".
        #expect(try component("ERL", 3)?.condition == "4 populated OR 5 populated")
        #expect(try component("ERL", 5)?.condition == "6 populated")    // 2A.2.28.5 p 44
        // 2A.2.71 p 80 prints C, and 2A.2.71.2: "also conditionally required if the SN.1 (Comparator) component is populated".
        #expect(try component("SN", 2)?.optionalityCode == "C")
        #expect(try component("SN", 2)?.condition == "1 populated")
        // Comments column, 2A.2.52 component table p 60.
        #expect(try component("OSP", 2)?.condition == "3 empty")
        #expect(try component("OSP", 3)?.condition == "2 empty")
        #expect(try component("RPT", 6)?.condition == "5 populated")    // 2A.2.67.6 p 78
        #expect(try component("CWE", 16)?.condition == "15 populated")  // 2A.2.13.16 p 31
        #expect(try component("XCN", 1)?.condition == "2 empty")        // 2A.2.88.1 p 94
        #expect(try component("CWE", 3)?.conformanceCondition == "1 populated AND 14 empty")   // 2A.2.13.3 p 29
        #expect(try #require(try component("CNE", 20)).condition == nil)    // 2A.2.8.20 p 17: the print contradicts itself
        // 2A.2.56.15 p 66: a time stamp needs a person, and a person needs a time stamp. PPN.15 is printed O (p 64).
        let groups = try #require(DataTypeGrammarTable.v2_9_1["PPN"]).groupRequirements
        let person = try #require(groups.first { $0.name == "Performing person" })
        #expect(person.components == "1-14,16-26" && person.condition == "15 populated")
        let stamp = try #require(groups.first { $0.name == "Time stamp" })
        #expect(stamp.components == "15" && stamp.condition == "1-14 populated OR 16-26 populated")
        #expect(groups.count == 2)
    }

    @Test("RFR.2 is Sex, bound to 0001 and 0828 (the print wraps the cell inside the second number)")
    func referenceRangeSex() throws {
        let sex = try #require(try component("RFR", 2))                 // 2A.2.63 p 72
        #expect(sex.name == "Sex")
        #expect(sex.tables == ["0001", "0828"])
    }

    private var grammar: [String: SegmentGrammar] { SegmentGrammarTable.v2_9_1 }

    @Test("2.9.1 segments: v2.9's 187 and GSP, GSR, GSC (CH03 3.4.19 to 3.4.21)")
    func segmentInventory() {
        #expect(grammar.count == 190)
        for id in ["GSP", "GSR", "GSC"] { #expect(grammar[id] != nil, "\(id)") }
        #expect(SegmentGrammarTable.v2_9["GSP"] == nil)
    }

    @Test("2.9.1 adds IN1-56 and TXA-29 to 31, and prints OH2-5 correctly")
    func fieldGrowth() {
        #expect(grammar["IN1"]?.field(56) != nil)
        #expect(SegmentGrammarTable.v2_9["IN1"]?.field(56) == nil)
        for index in [29, 30, 31] { #expect(grammar["TXA"]?.field(index) != nil, "TXA-\(index)") }
        #expect(grammar["OH2"]?.field(5)?.name == "Industry")
    }

    @Test("A 2.9.1 message parses as v2.9.1 and validates against its own grammar")
    func dispatch() throws {
        let wire = "MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|20240301120000||ADT^A01^ADT_A01|MSG00001|P|2.9.1\r"
            + "EVN||20240301120000\rPID|1||SYN-0291^^^TESTFAC^MR||Testpatient^Sample||19800101|M\rPV1|1|I\r"
        let message = try Parser().parse(wire)
        #expect(message.version == .v2_9_1)
        #expect(message.version.grammarVersion == .v2_9_1)
        let codes = Validator(options: .strict).validate(message).issues.map(\.code)
        #expect(!codes.contains(.segmentNotInVersionGrammar))
        #expect(!codes.contains { if case .versionNotRecognised = $0 { return true } else { return false } })
    }

    @Test("MSH-26 is required when MSH-27 or MSH-28 is valued (CH02 2.13.9.26)")
    func securityClassificationCondition() {
        #expect(grammar["MSH"]?.field(26)?.condition == "MSH-27 populated OR MSH-28 populated")
    }

    @Test("2.9.1 prints no ROL requirement: - reads as B")
    func rolOptionality() throws {
        #expect(try #require(grammar["ROL"]).fields.allSatisfy { $0.optionality == .backwardCompat })
    }

    @Test("2.9.1 fixes MSH-6's repetition, and prints the action code as 1..1")
    func cellsThatDifferFromV29() throws {
        // CH01 p5, "Fix repetition of MSH-6"; CH02 MSH table p68 prints no Y. v2.9's p67 prints Y.
        #expect(grammar["MSH"]?.field(6)?.repeatability == .single)
        #expect(SegmentGrammarTable.v2_9["MSH"]?.field(6)?.repeatability == .multiple)
        // CH01 p5, "Address technical corrections for the OH* segments"; CH03 p220 prints 1..1 and 0206. v2.9's p211 prints 2..2 and no table.
        #expect(grammar["OH4"]?.field(2)?.length == "1..1")
        #expect(grammar["OH4"]?.field(2)?.table == "0206")
        #expect(SegmentGrammarTable.v2_9["OH4"]?.field(2)?.table == nil)
        // Others with an Action Code: CH04 pp 72, 142, 151, 186, 57; CH07 pp 62, 80, 122.
        for (id, index) in [("OBR", 55), ("BPX", 22), ("BTX", 21), ("BUI", 13), ("OBX", 31), ("SPM", 35), ("ORC", 35), ("CSR", 17)] {
            #expect(grammar[id]?.field(index)?.length == "1..1", "\(id)-\(index)")
        }
        #expect(grammar["ARV"]?.field(2)?.length == "1..1")     // CH03 p208; v2.9's p199 prints none
        #expect(grammar["IAM"]?.field(6)?.length == "1..1")     // CH03 p180
        // CH08 pp 31 and 32: a corrected name, and one the print sets with its suffix in both the table and the heading.
        #expect(grammar["OM1"]?.field(53)?.name == "Prior Results Instructions")
        #expect(grammar["OM1"]?.field(57)?.name == "Typical Turn-Around Time – (2)")
        #expect(grammar["IN3"]?.field(30)?.optionality == .conditional)     // CH06 p122, C(RE/ over X)
        // Not a difference, read for itself: CH02 pp 68 and 69 print 28 MSH fields, and 4..5 at MSH-2, BHS-2 (p55) and FHS-2 (p63).
        #expect(grammar["MSH"]?.fields.count == 28)
        for id in ["MSH", "BHS", "FHS"] { #expect(grammar[id]?.field(2)?.length == "4..5", "\(id)-2") }
    }

    /// A CWE carries no `table` in the grammar, so the binding is read from the schema.
    private func tables(_ segment: String, _ index: Int) throws -> [String] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/schemas/v2.9.1/\(segment).json")
        let schema = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let fields = try #require(schema["fields"] as? [[String: Any]])
        let field = try #require(fields.first { $0["index"] as? Int == index })
        return field["tables"] as? [String] ?? []
    }

    @Test("Bindings the 2.9.1 page prints, each on its own row")
    func tableBindings() throws {
        #expect(try tables("GSP", 5) == ["0821", "0822", "0823"])   // CH03 p221, the cell runs over three lines; 3.4.19.5 p222
        #expect(try tables("GSR", 4) == ["0001"])                   // CH03 p224
        #expect(try tables("GSC", 4) == ["0828"])                   // CH03 p227
        #expect(try tables("OM1", 50) == ["0661"])                  // CH08 p31; 8.8.9.50 p45; v2.9 prints 0446
        #expect(try tables("OM1", 58) == ["0001", "0828"])          // CH08 p32, the cell runs over two lines; 8.8.9.58 p47
        #expect(try tables("PRT", 24) == [])                        // CH07 p90; v2.9 prints 0328
        #expect(try tables("RXE", 2) == ["0292", "0479"])           // CH04A p59, `0292/0` over `479`; 4A.4.4.2
        #expect(try tables("RXA", 17) == ["0227"])                  // CH04A p122 and 4A.8.1.2; the main table p95 prints none
        #expect(try tables("TXA", 29) == ["0832"] && tables("TXA", 30) == ["0833"])  // CH09 p32
    }

    @Test("ADD and RDT are hand-authored from their 1-n rows (CH02 2.13.1 p55, CH05 5.4.8 p56)")
    func variableColumnSegments() {
        #expect(grammar["ADD"]?.field(1)?.variableColumns == true)
        #expect(grammar["RDT"]?.fields.count == 1)
        #expect(grammar["RDT"]?.field(1)?.variableColumns == true)
    }

    @Test("Each era read from the 2.9.1 print")
    func eras() {
        let version = Version.v2_9_1
        #expect(!version.printsMaximumLength)                       // CH02 2.4.5.0 p13, Normative Length
        #expect(!version.printsLengthSymbols)                       // CH02 2.4.5 defines neither symbol
        #expect(version.boundsSequenceID)                           // CH02A 2A.2.70 p80
        #expect(version.definesTruncationEscape)                    // CH02 2.6.2 p23
        #expect(version.escapeSequenceSection == "2.6")             // CH02 2.6 p22, not v2.9's 2.7
        #expect(version.readsFirstFieldAsDeleteSegment)             // CH02 2.9.4.1 p43
        #expect(version.table0953OID == "2.16.840.1.113883.12.953") // CH02C p851
        // CH02A 2A.2.21 to 2A.2.80: the twelve sections with no numbered component row. SNM (2A.2.72) separates this era from v2.6's.
        #expect(Validator.primitiveTypes(version) == ["DT", "DTM", "FT", "GTS", "ID", "IS", "NM", "SI", "SNM", "ST", "TM", "TX"])
        #expect(Version.v2_9.table0953OID == nil)
    }

    @Test("2.9.1 structures are complete and carry the new gender and sex segments")
    func structureInventory() throws {
        #expect(MessageStructureTable.completeVersions.contains(.v2_9_1))
        let adt = try #require(MessageStructureTable.structure("ADT_A01", version: .v2_9_1))
        let ids = adt.elements.flatMap(\.segmentIDs)
        for id in ["GSP", "GSR", "GSC"] { #expect(ids.contains(id), "\(id)") }
    }

    @Test("A well-formed ADT_A01 draws no structure finding")
    func wellFormedStructure() throws {
        var options = ValidationOptions.default
        options.messageStructureSeverity = .error
        let wire = "MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|20240301120000||ADT^A01^ADT_A01|MSG00001|P|2.9.1\r"
            + "EVN||20240301120000\rPID|1||SYN-0291^^^TESTFAC^MR||Testpatient^Sample\rPV1|1|I\r"
        let found = Validator(options: options).validate(try Parser().parse(wire)).issues.filter(\.code.isMessageStructure)
        #expect(found.isEmpty)
    }

    @Test("Every Table 0354 row of 2.9.1 is modelled or registered")
    func everyRowAccounted() throws {
        let rows = try #require(HL7TableRegistry.table("0354", version: .v2_9_1)).entries.map(\.code)
        #expect(rows.count == 261)
        let modelled = rows.filter { MessageStructureTable.structure($0, version: .v2_9_1) != nil }
        let registered = rows.filter { MessageStructureTable.registration($0, version: .v2_9_1) != nil }
        #expect(modelled.count == 193)
        #expect(registered.count == 68)
        #expect(Set(modelled).isDisjoint(with: registered))
    }

    // CH02C Table 0354 p 343: the Display Name 'Laboratory Fulfillment request with REL segment'
    // holds a segment ID, never an event. p 342: 'INV_U14' for INR^U14^INR_U14 (CH13 13.2.14 p 31).
    @Test("Table 0354 errata: no event from prose, and the misprinted ID is registered")
    func table0354Errata() throws {
        #expect(try #require(MessageStructureTable.structure("OML_O59", version: .v2_9_1)).triggers == ["OML^O59"])
        #expect(try #require(MessageStructureTable.structure("INR_U14", version: .v2_9_1)).triggers == ["INR^U14"])
        #expect(MessageStructureTable.registration("INV_U14", version: .v2_9_1) != nil)
    }

    // CH06 6.4.3 pp 9 and 10 and 6.4.8 pp 18 and 20 set a footnote mark a line above its row, which read as prose would end
    // the table at DB1; every print is checked against a required group after it.
    @Test("DFT_P03 and DFT_P11 read to the end of their tables")
    func footnoteAboveItsRow() throws {
        for id in ["DFT_P03", "DFT_P11"] {
            let ids = try #require(MessageStructureTable.structure(id, version: .v2_9_1)).elements.flatMap(\.segmentIDs)
            for segment in ["ORC", "FT1", "DG1", "DRG", "GT1", "IN1", "ACC"] { #expect(ids.contains(segment), "\(id) \(segment)") }
        }
    }

    // CH02 2.11.1 p 51 and CH05 5.2 to 5.8 print these as examples and templates on site-defined events (ruling G7).
    @Test("The widget and the Z-event examples are not structures of 2.9.1")
    func examplesExcluded() {
        for id in ["WRQ_Z02", "RSP_Z82", "RSP_Z84", "RSP_Z86", "RSP_Z88", "RSP_Z90", "RDY_Z80", "QBP_Z73", "RTB_Z74", "MFN_Znn"] {
            #expect(MessageStructureTable.structure(id, version: .v2_9_1) == nil, "\(id)")
        }
    }
}
