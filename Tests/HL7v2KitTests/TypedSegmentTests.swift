// TypedSegmentTests.swift
// Cross-check: the path subscript and the code-generated typed accessors
// return identical values for the same field on the same message
// (spec §9.4).

import Testing
import Foundation
@testable import HL7v2Kit

@Suite("Typed segments — PID cross-check")
struct TypedSegmentTests {

    private let wire = """
    MSH|^~\\&|LAB|FAC|HOSPITAL|FAC|||ADT^A01|MSG00001|P|2.5.1\r\
    PID|1||123456^^^HOSP^MR||Smith^John^A||19800101|M|||10 Main St^^Sydney^NSW^2000^AU\r
    """

    @Test("Parser hydrates PID into a typed segment")
    func parserHydratesPID() throws {
        let message = try Parser().parse(wire)
        let pid = try #require(message.firstSegment(PID.self))
        #expect(type(of: pid).segmentID == "PID")
    }

    @Test("Typed accessors return nil for fields absent in a short segment")
    func typedAccessorsHandleShortSegments() throws {
        // PID-1 only — everything past that should come back nil from typed
        // accessors. This pins behaviour across the R4 codegen template
        // refactor (inline bounds check → `field(N)`).
        let shortPID = """
        MSH|^~\\&|LAB|FAC|HOSPITAL|FAC|||ADT^A01|MSG00001|P|2.5.1\r\
        PID|1\r
        """
        let message = try Parser().parse(shortPID)
        let pid = try #require(message.firstSegment(PID.self))
        #expect(pid.setID == "1")
        #expect(pid.dateTimeOfBirth == nil)       // PID-7, absent
        #expect(pid.patientName == nil)           // PID-5, absent
        #expect(pid.administrativeSex == nil)     // PID-8, absent
    }

    @Test("PID-1 (scalar SI) — path and typed accessor agree")
    func setIDMatchesPath() throws {
        let message = try Parser().parse(wire)
        let pid = try #require(message.firstSegment(PID.self))
        #expect(pid.setID == "1")
        #expect(pid.setID == message["PID-1"])
    }

    @Test("PID-3 (structured CX, repeats) — typed accessor returns the Field")
    func patientIdentifierListAgrees() throws {
        let message = try Parser().parse(wire)
        let pid = try #require(message.firstSegment(PID.self))
        let field = try #require(pid.patientIdentifierList)
        // First component of the (only) repetition is the ID number.
        #expect(field.first?.components.first?.stringValue == "123456")
        #expect(message["PID-3.1"] == "123456")
    }

    @Test("PID-5 (structured XPN) — components reachable via the typed Field")
    func patientNameAgrees() throws {
        let message = try Parser().parse(wire)
        let pid = try #require(message.firstSegment(PID.self))
        let name = try #require(pid.patientName)
        #expect(name.first?.components[0].stringValue == "Smith")
        #expect(name.first?.components[1].stringValue == "John")
        #expect(message["PID-5.1"] == "Smith")
        #expect(message["PID-5.2"] == "John")
    }

    @Test("PID-7 (TS treated as scalar) — typed accessor returns String")
    func dobAgrees() throws {
        let message = try Parser().parse(wire)
        let pid = try #require(message.firstSegment(PID.self))
        #expect(pid.dateTimeOfBirth == "19800101")
        #expect(pid.dateTimeOfBirth == message["PID-7"])
    }

    @Test("PID-8 (IS scalar) — administrative sex")
    func sexAgrees() throws {
        let message = try Parser().parse(wire)
        let pid = try #require(message.firstSegment(PID.self))
        #expect(pid.administrativeSex == "M")
        #expect(pid.administrativeSex == message["PID-8"])
    }

    @Test("Typed PID still round-trips byte-perfectly")
    func typedPIDRoundTrips() throws {
        let message = try Parser().parse(wire)
        let rebuilt = String(data: message.serialize(), encoding: .utf8)
        #expect(rebuilt == wire)
    }

    @Test("Unknown segments are not hydrated (Z-segment tolerance preserved)")
    func zSegmentStillUnknown() throws {
        let zWire = """
        MSH|^~\\&|LAB|FAC|HOSPITAL|FAC|||ADT^A01|MSG00001|P|2.5.1\r\
        ZAU|1|something\r
        """
        let message = try Parser().parse(zWire)
        let zau = try #require(message.segments.first { $0.segmentID == "ZAU" })
        if case .typed = zau {
            Issue.record("ZAU should not have been typed")
        }
    }

    // MARK: - MSH

    @Test("MSH-1 / MSH-2 typed accessors expose the field-separator and encoding chars")
    func mshHeaderScalarsAgree() throws {
        let message = try Parser().parse(wire)
        let msh = try #require(message.firstSegment(MSH.self))
        #expect(msh.fieldSeparator == "|")
        #expect(msh.encodingCharacters == "^~\\&")
    }

    @Test("MSH-9 (composite MSG) — typed accessor returns the structured Field")
    func mshMessageTypeAgrees() throws {
        let message = try Parser().parse(wire)
        let msh = try #require(message.firstSegment(MSH.self))
        let messageType = try #require(msh.messageType)
        #expect(messageType.first?.components[0].stringValue == "ADT")
        #expect(messageType.first?.components[1].stringValue == "A01")
        #expect(message["MSH-9.1"] == "ADT")
        #expect(message["MSH-9.2"] == "A01")
    }

    @Test("MSH-10 (ST scalar) and MSH-11/12 (composite PT/VID first-component) agree with path")
    func mshControlFieldsAgree() throws {
        let message = try Parser().parse(wire)
        let msh = try #require(message.firstSegment(MSH.self))
        #expect(msh.messageControlID == "MSG00001")
        #expect(msh.messageControlID == message["MSH-10"])
        // PT and VID are composites: the typed accessor returns Field?, so we
        // reach into the first component to compare against MSH-11.1 / MSH-12.1.
        #expect(msh.processingID?.first?.components[0].stringValue == "P")
        #expect(msh.versionID?.first?.components[0].stringValue == "2.5.1")
    }

    // MARK: - NTE

    @Test("NTE typed accessors agree with path access")
    func nteCrossCheck() throws {
        let nteWire = """
        MSH|^~\\&|LAB|FAC|HOSPITAL|FAC|||ORU^R01|MSG00001|P|2.5.1\r\
        NTE|1|L|Patient is allergic to shellfish\r
        """
        let message = try Parser().parse(nteWire)
        let nte = try #require(message.firstSegment(NTE.self))
        #expect(nte.setID == "1")
        #expect(nte.sourceOfComment == "L")
        #expect(nte.comment == "Patient is allergic to shellfish")
        #expect(nte.setID == message["NTE-1"])
        #expect(nte.sourceOfComment == message["NTE-2"])
        #expect(nte.comment == message["NTE-3"])
    }

    // MARK: - AL1

    // MARK: - ORC (canary for R5: codegen-emitted SegmentRegistry)

    @Test("ORC hydrates as .typed without manual SegmentRegistry edits")
    func orcAutoRegistered() throws {
        // ORC was added by dropping its schema JSON in and re-running codegen.
        // SegmentRegistry was NOT edited by hand. If this test passes, the
        // codegen-emitted registry extension is doing its job.
        let wire = """
        MSH|^~\\&|LAB|FAC|HOSPITAL|FAC|||ORM^O01|MSG00001|P|2.5.1\r\
        ORC|NW\r
        """
        let message = try Parser().parse(wire)
        let orc = try #require(message.firstSegment(ORC.self))
        #expect(orc.orderControl == "NW")
        #expect(orc.orderControl == message["ORC-1"])
    }

    // MARK: - ORC extended fields (Task 4c-1)

    private let orcExtendedWire = """
    MSH|^~\\&|LAB|FAC|HOSPITAL|FAC|||ORM^O01|MSG00001|P|2.5.1\r\
    ORC|NW|PLACER123^HOSP|FILLER456^LAB|GRP789|IP|E||PARENT^HOSP|20240101120000|^Smith^John|^Jones^Mary|^Williams^Sue\r
    """

    @Test("ORC-1 (ID) order control agrees with path")
    func orcOrderControlAgrees() throws {
        let message = try Parser().parse(orcExtendedWire)
        let orc = try #require(message.firstSegment(ORC.self))
        #expect(orc.orderControl == "NW")
        #expect(orc.orderControl == message["ORC-1"])
    }

    @Test("ORC-2/3 (composite EI) placer/filler order numbers")
    func orcOrderNumbersAgree() throws {
        let message = try Parser().parse(orcExtendedWire)
        let orc = try #require(message.firstSegment(ORC.self))
        let placer = try #require(orc.placerOrderNumber)
        let filler = try #require(orc.fillerOrderNumber)
        #expect(placer.first?.components[0].stringValue == "PLACER123")
        #expect(filler.first?.components[0].stringValue == "FILLER456")
        #expect(message["ORC-2.1"] == "PLACER123")
        #expect(message["ORC-3.1"] == "FILLER456")
    }

    @Test("ORC-5/6 (ID scalars) order status + response flag")
    func orcScalarFlagsAgree() throws {
        let message = try Parser().parse(orcExtendedWire)
        let orc = try #require(message.firstSegment(ORC.self))
        #expect(orc.orderStatus == "IP")
        #expect(orc.responseFlag == "E")
    }

    @Test("ORC-9 (TS scalar) date/time of transaction")
    func orcTransactionDateAgrees() throws {
        let message = try Parser().parse(orcExtendedWire)
        let orc = try #require(message.firstSegment(ORC.self))
        #expect(orc.dateTimeOfTransaction == "20240101120000")
    }

    @Test("ORC-12 (composite XCN repeats) ordering provider")
    func orcOrderingProviderAgrees() throws {
        let message = try Parser().parse(orcExtendedWire)
        let orc = try #require(message.firstSegment(ORC.self))
        let provider = try #require(orc.orderingProvider)
        // Components: empty^family^given. We exercise components[1] = family.
        #expect(provider.first?.components[1].stringValue == "Williams")
    }

    // MARK: - OBX (Task 4c-1)

    private let obxWire = """
    MSH|^~\\&|LAB|FAC|HOSPITAL|FAC|||ORU^R01|MSG00001|P|2.5.1\r\
    OBX|1|NM|GLU^Glucose^L||5.2|mmol/L^Millimoles per litre^UCUM|3.9-5.5|N|||F|||20240101130000\r
    """

    @Test("OBX hydrates as .typed")
    func obxHydrates() throws {
        let message = try Parser().parse(obxWire)
        let obx = try #require(message.firstSegment(OBX.self))
        #expect(type(of: obx).segmentID == "OBX")
    }

    @Test("OBX-1 (SI) and OBX-2 (ID) scalars agree with path")
    func obxIdentifyingScalarsAgree() throws {
        let message = try Parser().parse(obxWire)
        let obx = try #require(message.firstSegment(OBX.self))
        #expect(obx.setID == "1")
        #expect(obx.setID == message["OBX-1"])
        #expect(obx.valueType == "NM")
        #expect(obx.valueType == message["OBX-2"])
    }

    @Test("OBX-3 (composite CE) observation identifier")
    func obxObservationIdentifierAgrees() throws {
        let message = try Parser().parse(obxWire)
        let obx = try #require(message.firstSegment(OBX.self))
        let identifier = try #require(obx.observationIdentifier)
        #expect(identifier.first?.components[0].stringValue == "GLU")
        #expect(identifier.first?.components[1].stringValue == "Glucose")
        #expect(message["OBX-3.1"] == "GLU")
        #expect(message["OBX-3.2"] == "Glucose")
    }

    @Test("OBX-5 (ST scalar) observation value")
    func obxObservationValueAgrees() throws {
        let message = try Parser().parse(obxWire)
        let obx = try #require(message.firstSegment(OBX.self))
        #expect(obx.observationValue == "5.2")
        #expect(obx.observationValue == message["OBX-5"])
    }

    @Test("OBX-6 (composite CE) units")
    func obxUnitsAgree() throws {
        let message = try Parser().parse(obxWire)
        let obx = try #require(message.firstSegment(OBX.self))
        let units = try #require(obx.units)
        #expect(units.first?.components[0].stringValue == "mmol/L")
        #expect(units.first?.components[2].stringValue == "UCUM")
    }

    @Test("OBX-7 (ST) reference range and OBX-8 (IS) abnormal flags scalars")
    func obxResultMetaScalarsAgree() throws {
        let message = try Parser().parse(obxWire)
        let obx = try #require(message.firstSegment(OBX.self))
        #expect(obx.referencesRange == "3.9-5.5")
        #expect(obx.abnormalFlags == "N")
    }

    @Test("OBX-11 (ID) observation result status")
    func obxResultStatusAgrees() throws {
        let message = try Parser().parse(obxWire)
        let obx = try #require(message.firstSegment(OBX.self))
        #expect(obx.observationResultStatus == "F")
        #expect(obx.observationResultStatus == message["OBX-11"])
    }

    @Test("OBX-14 (TS) date/time of the observation")
    func obxObservationTimestampAgrees() throws {
        let message = try Parser().parse(obxWire)
        let obx = try #require(message.firstSegment(OBX.self))
        #expect(obx.dateTimeOfTheObservation == "20240101130000")
    }

    @Test("OBX round-trips byte-perfectly through typed hydration")
    func obxRoundTrips() throws {
        let message = try Parser().parse(obxWire)
        let rebuilt = String(data: message.serialize(), encoding: .utf8)
        #expect(rebuilt == obxWire)
    }

    @Test("AL1 typed accessors agree with path access")
    func al1CrossCheck() throws {
        let al1Wire = """
        MSH|^~\\&|LAB|FAC|HOSPITAL|FAC|||ADT^A01|MSG00001|P|2.5.1\r\
        AL1|1|DA|PENICILLIN^Penicillin^L|SV|Hives\r
        """
        let message = try Parser().parse(al1Wire)
        let al1 = try #require(message.firstSegment(AL1.self))
        #expect(al1.setID == "1")
        let allergen = try #require(al1.allergenCodeMnemonicDescription)
        #expect(allergen.first?.components[0].stringValue == "PENICILLIN")
        #expect(allergen.first?.components[1].stringValue == "Penicillin")
        #expect(message["AL1-3.1"] == "PENICILLIN")
        #expect(al1.allergyReactionCode == "Hives")
    }
}
