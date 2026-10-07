// AULocalTableExtensionTests.swift
// P12 S2-3 item 1: the AU overlay's Table 0203 value sets honour
// `ValidationOptions.localTableExtensions["0203"]`. Every supported version
// lets a site extend an HL7 table locally (v2.4 CH02 sec 2.7.6; v2.5.1 CH02
// sec 2.5.3.6, "the table itself may be extended to accommodate locally
// defined values"), and the AU profile's points name the table, not a closed
// subset: HL7au:00044.1.3 (CX-5, p 449), 00044.7.4 (XCN-13, p 455) and
// 00104.7.3.1 (PRD-7.3, p 473) each read "valued from HL7 Table 0203". A
// value the caller declares for 0203 is therefore a valid value on all three;
// a declaration for another table does not reach them.

import Testing
@testable import HL7v2Kit

@Suite("AU Table 0203 value sets honour local table extensions (HL7au:00044.1.3, 00044.7.4, 00104.7.3.1)")
struct AULocalTableExtensionTests {
    private func findings(_ wire: String, extensions: [String: Set<String>], point: String) throws -> [ValidationIssue] {
        var options = ValidationOptions()
        options.localTableExtensions = extensions
        let message = try Parser(locale: .auLocalisation).parse(wire)
        return Validator(options: options, locale: .auLocalisation).validate(message).issues.filter {
            if case .profileConstraintViolation(let rule) = $0.code { return rule.hasPrefix(point) }
            return false
        }
    }

    private var oru: String {
        "MSH|^~\\&|LAB|FAC|GP|FAC|20240101||ORU^R01^ORU_R01|MSG|P|2.4\r"
    }

    private var pidWire: String { oru + "PID|1||12345678^^^AUSHIC^ZZ\r" }

    private var xcnWire: String {
        // OBR-16 Ordering Provider (XCN), XCN-13 = ZZ.
        oru + "PID|1||12345678^^^AUSHIC^MC\r"
            + TestWires.segment("OBR", [1: "1", 2: "P1^H", 3: "F1^L^1.2.36^ISO", 4: "GLU^Glucose^L",
                                        16: "12345^Citizen^Jane^^^^^^AUSHIC^L^^^ZZ"]) + "\r"
    }

    private var prdWire: String {
        "MSH|^~\\&|GP|FAC|SPEC|FAC|||REF^I12|MSG00001|P|2.4\r"
            + "PRD|AP^Authoring Provider^HL70286|Doe^John\r"
            + "PRD|IR^Intended Recipient^HL70286|Smith^Alice|||||049960CT^AUSHICPR^ZZ\r"
            + "PID|1||X^^^F^MR\r"
            + "OBR|1|P1^H^1.2.36.1^ISO|F1^L^1.2.36.2^ISO|REFER^Referral^L\r"
            + "OBX|1|ED|PDF^Display format in PDF^AUSPDI||src^application^pdf^Base64^AAAA|||||F\r"
    }

    @Test("A declared 0203 extension is silent on PID-3.5, XCN-13 and PRD-7.3")
    func declaredExtensionSilent() throws {
        let declared: [String: Set<String>] = ["0203": ["ZZ"]]
        #expect(try findings(pidWire, extensions: declared, point: "HL7au:00044.1.3").isEmpty)
        #expect(try findings(xcnWire, extensions: declared, point: "HL7au:00044.7.4").isEmpty)
        #expect(try findings(prdWire, extensions: declared, point: "HL7au:00104.7.3.1").isEmpty)
    }

    @Test("Without the declaration each point still fires")
    func undeclaredFires() throws {
        #expect(try findings(pidWire, extensions: [:], point: "HL7au:00044.1.3").count == 1)
        #expect(try findings(xcnWire, extensions: [:], point: "HL7au:00044.7.4").count == 1)
        #expect(try findings(prdWire, extensions: [:], point: "HL7au:00104.7.3.1").count == 1)
    }

    @Test("A declaration for another table (0363) does not silence Table 0203")
    func otherTableDoesNotSilence() throws {
        let other: [String: Set<String>] = ["0363": ["ZZ"]]
        #expect(try findings(pidWire, extensions: other, point: "HL7au:00044.1.3").count == 1)
        #expect(try findings(xcnWire, extensions: other, point: "HL7au:00044.7.4").count == 1)
        #expect(try findings(prdWire, extensions: other, point: "HL7au:00104.7.3.1").count == 1)
    }

    @Test("Extension matching is exact: a declared ZZ does not admit zz")
    func extensionMatchIsExact() throws {
        let declared: [String: Set<String>] = ["0203": ["ZZ"]]
        let lower = oru + "PID|1||12345678^^^AUSHIC^zz\r"
        #expect(try findings(lower, extensions: declared, point: "HL7au:00044.1.3").count == 1)
    }
}
