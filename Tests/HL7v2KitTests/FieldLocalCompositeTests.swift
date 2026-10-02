import Testing
@testable import HL7v2Kit

/// P5-6: a v2.3 to v2.4 `CM` field is validated against the components its own field
/// definition prints (``DataTypeGrammarTable/grammar(segment:field:version:)``), through the
/// one resolution point ``Validator/fieldGrammar(segment:field:dataType:version:)`` that
/// every composite-aware check calls.
@Suite("Field-local composite validation")
struct FieldLocalCompositeTests {
    private func wire(_ version: String, _ segment: String, _ field: Int, _ value: String) -> String {
        "MSH|^~\\&|HIS|FAC|PAYER|FAC|||BAR^P01|MSG00001|P|\(version)\r"
            + segment + String(repeating: "|", count: field) + value + "\r"
    }

    private func issues(_ wire: String, at path: String) throws -> [IssueCode] {
        Validator().validate(try Parser().parse(wire)).issues
            .filter { $0.location.pathDescription.hasPrefix(path) }
            .map(\.code)
    }

    private func tableCodes(_ wire: String) throws -> [IssueCode] {
        Validator().validate(try Parser().parse(wire)).issues.map(\.code)
            .filter { if case .valueNotInTable = $0 { return true } else { return false } }
    }

    @Test("One resolution point: the field-local grammar where the field prints one, else the datatype's")
    func resolution() throws {
        let local = try #require(DataTypeGrammarTable.grammar(segment: "IN3", field: 20, version: .v2_4))
        #expect(Validator.fieldGrammar(segment: "IN3", field: 20, dataType: "CM", version: .v2_4) == local)
        #expect(Validator.fieldGrammar(segment: "PID", field: 5, dataType: "XPN", version: .v2_4)
                == Validator.componentGrammar("XPN", version: .v2_4))
        #expect(Validator.fieldGrammar(segment: "PID", field: 5, dataType: "ST", version: .v2_4) == nil, "a primitive stays primitive")
        #expect(Validator.fieldGrammar(segment: "IN3", field: 20, dataType: "CM", version: .v2_5_1) == nil, "no CM from v2.5")
        #expect(Validator.fieldGrammar(segment: "IN3", field: nil, dataType: "CM", version: .v2_4) == nil)
    }

    @Test("P6-15: a field-local composite is width-checked", arguments: ["2.3", "2.3.1", "2.4"])
    func width(version: String) throws {
        let in3 = "IN3[1]-20"
        #expect(try issues(wire(version, "IN3", 20, "ER^Y^19990101^EXTRA"), at: in3) == [.extraComponentsInCompositeField])
        #expect(try issues(wire(version, "IN3", 20, "ER^Y^19990101"), at: in3).isEmpty)
        // OBR-15.1 is CE: six components, so a seventh subcomponent is extra.
        let obr = wire(version, "OBR", 15, "BLD&Blood&HL70070&&&&EXTRA")
        #expect(try issues(obr, at: "OBR[1]-15").contains(.extraComponentsInCompositeField))
    }

    @Test("P6-14: a primitive component of a field-local composite admits no subcomponents")
    func primitiveSubcomponents() throws {
        #expect(try issues(wire("2.4", "IN3", 20, "ER^Y&X"), at: "IN3[1]-20") == [.extraComponentsInPrimitiveField])
    }

    @Test("P6-7: a field-local TS component stays format-checked as a primitive", arguments: ["2.3", "2.3.1", "2.4"])
    func tsFormat(version: String) throws {
        #expect(try issues(wire(version, "IN3", 20, "ER^Y^19991301"), at: "IN3[1]-20.3") == [.valueFormatInvalid(dataType: "TS")])
        #expect(try issues(wire(version, "IN3", 20, "ER^Y^19991231"), at: "IN3[1]-20").isEmpty)
        #expect(try issues(wire(version, "IN3", 5, "AA^abc"), at: "IN3[1]-5.2") == [.valueFormatInvalid(dataType: "NM")])
    }

    @Test("Prose-defined components print no optionality, so nothing is required of them")
    func noRequiredComponents() throws {
        let codes = try issues(wire("2.4", "IN3", 20, "^^19991231"), at: "IN3[1]-20")
        #expect(codes.isEmpty)
    }

    @Test("Enforced closed HL7 ID bindings: BLG-1.1 0100 and PRA-5.3 0337")
    func idBindings() throws {
        for version in ["2.3", "2.3.1", "2.4"] {
            #expect(try tableCodes(wire(version, "BLG", 1, "X^19990101")) == [.valueNotInTable(table: "0100")], "v\(version)")
            #expect(try tableCodes(wire(version, "BLG", 1, "D^19990101")).isEmpty, "v\(version)")
        }
        for version in ["2.3.1", "2.4"] {
            #expect(try tableCodes(wire(version, "PRA", 5, "SP^^Q")) == [.valueNotInTable(table: "0337")], "v\(version)")
            #expect(try tableCodes(wire(version, "PRA", 5, "SP^^C")).isEmpty, "v\(version)")
        }
    }

    @Test("A CE component bound to a closed HL7 table: ERR-1.4 0357, OBR-15.1 0070, OBR-15.4 0163")
    func ceBindings() throws {
        for version in ["2.3.1", "2.4"] {
            #expect(try tableCodes(wire(version, "ERR", 1, "PID^1^16^999")) == [.valueNotInTable(table: "0357")])
            #expect(try tableCodes(wire(version, "ERR", 1, "PID^1^16^103&Table value not found&HL70357")).isEmpty)
        }
        for version in ["2.3", "2.3.1", "2.4"] {
            let bad = try issues(wire(version, "OBR", 15, "QQQ"), at: "OBR[1]-15")
            #expect(bad == [.valueNotInTable(table: "0070")], "v\(version)")
            #expect(try tableCodes(wire(version, "OBR", 15, "QQQ&&HL70070")) == [.valueNotInTable(table: "0070")])
            #expect(try tableCodes(wire(version, "OBR", 15, "BLD^^^QQ")) == [.valueNotInTable(table: "0163")])
            #expect(try tableCodes(wire(version, "OBR", 15, "BLD&Blood&HL70070^^^LA")).isEmpty)
        }
        #expect(try tableCodes(wire("2.4", "SAC", 6, "QQQ")) == [.valueNotInTable(table: "0070")])
        #expect(try tableCodes(wire("2.4", "TCC", 3, "BLD^^^QQ")) == [.valueNotInTable(table: "0163")])
    }

    @Test("Veterinary medicine may choose the tables for OBR-15: a non-HL7 coding system is silent")
    func otherCodingSystemSilent() throws {
        for version in ["2.3", "2.3.1", "2.4"] {
            #expect(try tableCodes(wire(version, "OBR", 15, "123038009&Specimen&SCT^^^456&Site&SCT")).isEmpty, "v\(version)")
            #expect(try tableCodes(wire(version, "OBR", 15, "QQQ&&99VET")).isEmpty, "v\(version)")
        }
        #expect(try tableCodes(wire("2.4", "ERR", 1, "PID^1^16^999&&L")).isEmpty)
    }

    @Test("PRA-7's misprinted '&' between two components is read as '^': its Subcomponents lines and example agree")
    func pra7Misprint() throws {
        for version in [Version.v2_3_1, .v2_4] {
            let pra7 = try #require(DataTypeGrammarTable.grammar(segment: "PRA", field: 7, version: version))
            #expect(pra7.components.map(\.dataType) == ["CE", "CE", "DT", "DT", "EI"], "\(version)")
            #expect(pra7.component(2)?.name == "Privilege class", "\(version)")
            // v2.4 CH15 example: PRA-7 "ADMIT&&ADT^MED&&L2^19941231".
            #expect(try issues(wire(version.rawValue, "PRA", 7, "ADMIT&&ADT^MED&&L2^19941231"), at: "PRA[1]-7").isEmpty)
        }
    }

    @Test("User-defined (IS) bindings stay open: IN3-5.1 0148, PV1-37.1 0113")
    func userTablesOpen() throws {
        #expect(try tableCodes(wire("2.4", "IN3", 5, "ZZ^3")).isEmpty)
        #expect(try tableCodes(wire("2.4", "PV1", 37, "ZZ^19990101")).isEmpty)
    }
}
