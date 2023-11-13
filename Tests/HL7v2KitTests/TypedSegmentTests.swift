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

    @Test("PID-3 (CX composite) — typed accessor exposes the ID via .id")
    func patientIdentifierListAgrees() throws {
        let message = try Parser().parse(wire)
        let pid = try #require(message.firstSegment(PID.self))
        let identifier = try #require(pid.patientIdentifierList)
        #expect(identifier.id == "123456")
        #expect(identifier.id == message["PID-3.1"])
    }

    @Test("PID-5 (XPN composite) — typed accessor exposes family/given names")
    func patientNameAgrees() throws {
        let message = try Parser().parse(wire)
        let pid = try #require(message.firstSegment(PID.self))
        let name = try #require(pid.patientName)
        #expect(name.familyName == "Smith")
        #expect(name.givenName == "John")
        #expect(name.familyName == message["PID-5.1"])
        #expect(name.givenName == message["PID-5.2"])
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
        #expect(messageType.messageCode == "ADT")
        #expect(messageType.triggerEvent == "A01")
        #expect(message["MSH-9.1"] == "ADT")
        #expect(message["MSH-9.2"] == "A01")
    }

    @Test("MSH-10 (ST scalar) and MSH-11/12 (composites PT/VID) agree with path")
    func mshControlFieldsAgree() throws {
        let message = try Parser().parse(wire)
        let msh = try #require(message.firstSegment(MSH.self))
        #expect(msh.messageControlID == "MSG00001")
        #expect(msh.messageControlID == message["MSH-10"])
        // PT and VID are now typed composites (v0.3-C4): named accessors
        // return the first subcomponent of MSH-11.1 / MSH-12.1.
        #expect(msh.processingID?.processingID == "P")
        #expect(msh.versionID?.versionID == "2.5.1")
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
        #expect(placer.entityIdentifier == "PLACER123")
        #expect(filler.entityIdentifier == "FILLER456")
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
        // Components: empty^family^given. We exercise XCN-2 = family.
        #expect(provider.familyName == "Williams")
    }

    // MARK: - ORC fringe fields 20–31 (Task v0.2-F1)

    // ORC populating ORC-1 + ORC-20..31 only; fields 2..19 left empty so the
    // wire is short and the pipe count is checkable by hand. Field map (the
    // gap between ORC-1's NW and ORC-20's value is 19 separators — 1 closing
    // field 1, 18 for empty fields 2..19):
    //  1 orderControl=NW
    //  2..19 empty (18 separators)
    // 20 advancedBeneficiaryNoticeCode=ABN1^Notice^HL7        (CE)
    // 21 orderingFacilityName=FacilityName                     (XON scalar-ish)
    // 22 orderingFacilityAddress=1 Hospital Rd^^Sydney^NSW^2000^AU  (XAD)
    // 23 orderingFacilityPhoneNumber=(02)555-9999              (XTN)
    // 24 orderingProviderAddress=2 Clinic St^^Sydney^NSW^2000^AU    (XAD)
    // 25 orderStatusModifier=MOD1^Modifier^HL7                 (CWE)
    // 26 advancedBeneficiaryNoticeOverrideReason=WAIVED^Waived^HL7  (CWE)
    // 27 fillersExpectedAvailabilityDateTime=20240301140000    (TS)
    // 28 confidentialityCode=R^Restricted^HL70177              (CWE)
    // 29 orderType=I^Inpatient^HL70482                          (CWE)
    // 30 entererAuthorizationMode=EL^Electronic^HL70483         (CNE)
    // 31 parentUniversalServiceIdentifier=PAR^Parent^HL70222   (CWE)
    private let orcFringeWire = """
    MSH|^~\\&|LAB|FAC|HOSPITAL|FAC|||ORM^O01|MSG00001|P|2.5.1\r\
    ORC|NW|||||||||||||||||||ABN1^Notice^HL7|FacilityName|1 Hospital Rd^^Sydney^NSW^2000^AU|(02)555-9999|2 Clinic St^^Sydney^NSW^2000^AU|MOD1^Modifier^HL7|WAIVED^Waived^HL7|20240301140000|R^Restricted^HL70177|I^Inpatient^HL70482|EL^Electronic^HL70483|PAR^Parent^HL70222\r
    """

    @Test("ORC-20 (CE composite) advanced beneficiary notice code")
    func orcAdvancedBeneficiaryNoticeCodeAgrees() throws {
        let message = try Parser().parse(orcFringeWire)
        let orc = try #require(message.firstSegment(ORC.self))
        let abn = try #require(orc.advancedBeneficiaryNoticeCode)
        #expect(abn.identifier == "ABN1")
        #expect(abn.identifier == message["ORC-20.1"])
    }

    @Test("ORC-21 (XON) ordering facility name + ORC-22 (XAD) facility address")
    func orcOrderingFacilityNameAndAddressAgree() throws {
        let message = try Parser().parse(orcFringeWire)
        let orc = try #require(message.firstSegment(ORC.self))
        let name = try #require(orc.orderingFacilityName)        // XON typed (v0.3-C4)
        let addr = try #require(orc.orderingFacilityAddress)     // XAD typed
        #expect(name.organizationName == "FacilityName")
        #expect(addr.streetAddress == "1 Hospital Rd")
        #expect(addr.city == "Sydney")
        #expect(addr.city == message["ORC-22.3"])
    }

    @Test("ORC-27 (TS scalar) filler's expected availability date/time")
    func orcExpectedAvailabilityAgrees() throws {
        let message = try Parser().parse(orcFringeWire)
        let orc = try #require(message.firstSegment(ORC.self))
        #expect(orc.fillersExpectedAvailabilityDateTime == "20240301140000")
        #expect(orc.fillersExpectedAvailabilityDateTime == message["ORC-27"])
    }

    @Test("ORC-28 (CWE) confidentiality code + ORC-29 (CWE) order type")
    func orcConfidentialityAndOrderTypeAgree() throws {
        let message = try Parser().parse(orcFringeWire)
        let orc = try #require(message.firstSegment(ORC.self))
        let confidentiality = try #require(orc.confidentialityCode)
        let orderType = try #require(orc.orderType)
        #expect(confidentiality.identifier == "R")
        #expect(orderType.identifier == "I")
        #expect(confidentiality.text == "Restricted")
        #expect(orderType.text == "Inpatient")
        #expect(confidentiality.text == message["ORC-28.2"])
        #expect(orderType.text == message["ORC-29.2"])
    }

    @Test("ORC-30 (CNE composite) enterer authorization mode")
    func orcEntererAuthorizationModeAgrees() throws {
        let message = try Parser().parse(orcFringeWire)
        let orc = try #require(message.firstSegment(ORC.self))
        let mode = try #require(orc.entererAuthorizationMode)
        #expect(mode.identifier == "EL")
        #expect(mode.text == "Electronic")
    }

    @Test("ORC-31 (CWE) parent universal service identifier")
    func orcParentUniversalServiceIdentifierAgrees() throws {
        let message = try Parser().parse(orcFringeWire)
        let orc = try #require(message.firstSegment(ORC.self))
        let parent = try #require(orc.parentUniversalServiceIdentifier)
        #expect(parent.identifier == "PAR")
        #expect(parent.identifier == message["ORC-31.1"])
    }

    @Test("ORC fringe-field wire round-trips byte-perfectly")
    func orcFringeRoundTrips() throws {
        let message = try Parser().parse(orcFringeWire)
        let rebuilt = String(data: message.serialize(), encoding: .utf8)
        #expect(rebuilt == orcFringeWire)
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
        #expect(identifier.identifier == "GLU")
        #expect(identifier.text == "Glucose")
        #expect(identifier.identifier == message["OBX-3.1"])
        #expect(identifier.text == message["OBX-3.2"])
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
        #expect(units.identifier == "mmol/L")
        #expect(units.nameOfCodingSystem == "UCUM")
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

    // MARK: - OBR (Task 4c-2)

    // Real lab-side OBR — set ID, placer/filler orders, universal service
    // identifier (CE), specimen/observation timestamps, ordering provider
    // (XCN repeats), placer/filler text fields, result status.
    //
    // Field map (1-indexed):
    //  1 setID=1, 2 placer=PLACER123^HOSP, 3 filler=FILLER456^LAB,
    //  4 service=GLU^Glucose^L, 5/6 empty, 7 obs=20240101120000,
    //  8 obs-end=20240101130000, 9 empty, 10 collector=^Smith^John,
    //  11 specimen-action=L, 12/13 empty, 14 specimen-received=20240101115000,
    //  15 empty, 16 ordering-provider=^Williams^Sue,
    //  17/18/19 empty, 20 filler-1=PLACER1, 21 filler-2=FILLER1,
    //  22 results-report=20240101140000, 23/24 empty, 25 result-status=F.
    private let obrWire = """
    MSH|^~\\&|LAB|FAC|HOSPITAL|FAC|||ORU^R01|MSG00001|P|2.5.1\r\
    OBR|1|PLACER123^HOSP|FILLER456^LAB|GLU^Glucose^L|||20240101120000|20240101130000||^Smith^John|L|||20240101115000||^Williams^Sue||||PLACER1|FILLER1|20240101140000|||F\r
    """

    @Test("OBR hydrates as .typed")
    func obrHydrates() throws {
        let message = try Parser().parse(obrWire)
        let obr = try #require(message.firstSegment(OBR.self))
        #expect(type(of: obr).segmentID == "OBR")
    }

    @Test("OBR-1 (SI scalar) set ID agrees with path")
    func obrSetIDAgrees() throws {
        let message = try Parser().parse(obrWire)
        let obr = try #require(message.firstSegment(OBR.self))
        #expect(obr.setID == "1")
        #expect(obr.setID == message["OBR-1"])
    }

    @Test("OBR-2/3 (composite EI) placer/filler order numbers")
    func obrOrderNumbersAgree() throws {
        let message = try Parser().parse(obrWire)
        let obr = try #require(message.firstSegment(OBR.self))
        let placer = try #require(obr.placerOrderNumber)
        let filler = try #require(obr.fillerOrderNumber)
        #expect(placer.entityIdentifier == "PLACER123")
        #expect(filler.entityIdentifier == "FILLER456")
        #expect(message["OBR-2.1"] == "PLACER123")
        #expect(message["OBR-3.1"] == "FILLER456")
    }

    @Test("OBR-4 (composite CE) universal service identifier")
    func obrUniversalServiceIdentifierAgrees() throws {
        let message = try Parser().parse(obrWire)
        let obr = try #require(message.firstSegment(OBR.self))
        let service = try #require(obr.universalServiceIdentifier)
        #expect(service.identifier == "GLU")
        #expect(service.text == "Glucose")
        #expect(service.identifier == message["OBR-4.1"])
        #expect(message["OBR-4.2"] == "Glucose")
    }

    @Test("OBR-7/8 (TS scalars) observation start + end timestamps")
    func obrObservationTimestampsAgree() throws {
        let message = try Parser().parse(obrWire)
        let obr = try #require(message.firstSegment(OBR.self))
        #expect(obr.observationDateTime == "20240101120000")
        #expect(obr.observationEndDateTime == "20240101130000")
        #expect(obr.observationDateTime == message["OBR-7"])
    }

    @Test("OBR-11 (ID scalar) specimen action code")
    func obrSpecimenActionCodeAgrees() throws {
        let message = try Parser().parse(obrWire)
        let obr = try #require(message.firstSegment(OBR.self))
        #expect(obr.specimenActionCode == "L")
        #expect(obr.specimenActionCode == message["OBR-11"])
    }

    @Test("OBR-14 (TS scalar) specimen received timestamp")
    func obrSpecimenReceivedAgrees() throws {
        let message = try Parser().parse(obrWire)
        let obr = try #require(message.firstSegment(OBR.self))
        #expect(obr.specimenReceivedDateTime == "20240101115000")
    }

    @Test("OBR-16 (composite XCN repeats) ordering provider")
    func obrOrderingProviderAgrees() throws {
        let message = try Parser().parse(obrWire)
        let obr = try #require(message.firstSegment(OBR.self))
        let provider = try #require(obr.orderingProvider)
        // XCN layout: ID^family^given. XCN-1 (id) is empty in this
        // fixture; XCN-2 (familyName) is "Williams".
        #expect(provider.familyName == "Williams")
        #expect(message["OBR-16.2"] == "Williams")
    }

    @Test("OBR-20/21 (ST scalars) placer/filler text fields")
    func obrPlacerFillerFieldsAgree() throws {
        let message = try Parser().parse(obrWire)
        let obr = try #require(message.firstSegment(OBR.self))
        #expect(obr.fillerField1 == "PLACER1")
        #expect(obr.fillerField2 == "FILLER1")
    }

    @Test("OBR-22 (TS scalar) results report status change date/time")
    func obrResultsReportStatusChangeAgrees() throws {
        let message = try Parser().parse(obrWire)
        let obr = try #require(message.firstSegment(OBR.self))
        #expect(obr.resultsReportStatusChangeDateTime == "20240101140000")
    }

    @Test("OBR-25 (ID scalar) result status")
    func obrResultStatusAgrees() throws {
        let message = try Parser().parse(obrWire)
        let obr = try #require(message.firstSegment(OBR.self))
        #expect(obr.resultStatus == "F")
        #expect(obr.resultStatus == message["OBR-25"])
    }

    @Test("OBR round-trips byte-perfectly through typed hydration")
    func obrRoundTrips() throws {
        let message = try Parser().parse(obrWire)
        let rebuilt = String(data: message.serialize(), encoding: .utf8)
        #expect(rebuilt == obrWire)
    }

    @Test("OBR + OBX together: full ORU^R01 result message round-trips")
    func oruR01RoundTrips() throws {
        let wire = """
        MSH|^~\\&|LAB|FAC|HOSPITAL|FAC|||ORU^R01|MSG00001|P|2.5.1\r\
        PID|1||123456^^^HOSP^MR||Smith^John^A\r\
        OBR|1|PLACER123^HOSP|FILLER456^LAB|GLU^Glucose^L\r\
        OBX|1|NM|GLU^Glucose^L||5.2|mmol/L||N|||F\r
        """
        let message = try Parser().parse(wire)
        let pid = try #require(message.firstSegment(PID.self))
        let obr = try #require(message.firstSegment(OBR.self))
        let obx = try #require(message.firstSegment(OBX.self))
        #expect(pid.setID == "1")
        #expect(obr.setID == "1")
        #expect(obx.setID == "1")
        #expect(obr.universalServiceIdentifier?.identifier == "GLU")
        #expect(obx.observationValue == "5.2")
        let rebuilt = String(data: message.serialize(), encoding: .utf8)
        #expect(rebuilt == wire)
    }

    // MARK: - Extended PID (Task 4c-3)

    // PID extended through PID-30 (death indicator). Wire construction is
    // pipe-count sensitive — verified by splitting "PID|...|" on "|" and
    // confirming each populated value lands at the expected 1-based index.
    // Field map:
    //  1 setID=1
    //  2 empty
    //  3 identifier list=123456^^^HOSP^MR
    //  4 empty
    //  5 name=Smith^John^A
    //  6 empty
    //  7 DOB=19800101
    //  8 sex=M
    //  9 empty
    // 10 race=2106-3^White^HL70005
    // 11 address=10 Main St^^Sydney^NSW^2000^AU
    // 12 empty
    // 13 home phone=(02)555-1234
    // 14 empty
    // 15 language=en^English^ISO639
    // 16 marital=M^Married^HL70002
    // 17 religion=CAT^Catholic^HL70006
    // 18 account=ACC12345
    // 19 SSN empty (deprecated)
    // 20 license empty (deprecated)
    // 21 mother empty
    // 22 ethnic empty
    // 23 birth place=Sydney
    // 24 multiple birth empty
    // 25 birth order empty
    // 26 citizenship empty
    // 27 veterans empty
    // 28 nationality empty
    // 29 death date=20231215120000
    // 30 death indicator=Y
    private let extendedPIDWire = """
    MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|||ADT^A01|MSG00001|P|2.5.1\r\
    PID|1||123456^^^HOSP^MR||Smith^John^A||19800101|M||2106-3^White^HL70005|10 Main St^^Sydney^NSW^2000^AU||(02)555-1234||en^English^ISO639|M^Married^HL70002|CAT^Catholic^HL70006|ACC12345|||||Sydney||||||20231215120000|Y\r
    """

    @Test("PID-13 (XTN composite) home phone number")
    func pidHomePhoneAgrees() throws {
        let message = try Parser().parse(extendedPIDWire)
        let pid = try #require(message.firstSegment(PID.self))
        let phone = try #require(pid.phoneNumberHome)
        #expect(phone.telephoneNumber == "(02)555-1234")
        #expect(message["PID-13.1"] == "(02)555-1234")
    }

    @Test("PID-15/16/17 (CE composites) language / marital / religion")
    func pidCEComposites() throws {
        let message = try Parser().parse(extendedPIDWire)
        let pid = try #require(message.firstSegment(PID.self))
        let language = try #require(pid.primaryLanguage)
        let marital = try #require(pid.maritalStatus)
        let religion = try #require(pid.religion)
        #expect(language.identifier == "en")
        #expect(marital.text == "Married")
        #expect(religion.identifier == "CAT")
    }

    @Test("PID-18 (CX) patient account number")
    func pidAccountNumberAgrees() throws {
        let message = try Parser().parse(extendedPIDWire)
        let pid = try #require(message.firstSegment(PID.self))
        let account = try #require(pid.patientAccountNumber)
        #expect(account.id == "ACC12345")
        #expect(account.id == message["PID-18.1"])
    }

    @Test("PID-23 (ST) birth place")
    func pidBirthPlaceAgrees() throws {
        let message = try Parser().parse(extendedPIDWire)
        let pid = try #require(message.firstSegment(PID.self))
        #expect(pid.birthPlace == "Sydney")
        #expect(pid.birthPlace == message["PID-23"])
    }

    @Test("PID-29/30 (TS + ID scalars) death date and indicator")
    func pidDeathFieldsAgree() throws {
        let message = try Parser().parse(extendedPIDWire)
        let pid = try #require(message.firstSegment(PID.self))
        #expect(pid.patientDeathDateAndTime == "20231215120000")
        #expect(pid.patientDeathIndicator == "Y")
    }

    @Test("Extended PID round-trips byte-perfectly")
    func extendedPIDRoundTrips() throws {
        let message = try Parser().parse(extendedPIDWire)
        let rebuilt = String(data: message.serialize(), encoding: .utf8)
        #expect(rebuilt == extendedPIDWire)
    }

    // MARK: - PID fringe fields 31–39 (Task v0.2-F1)

    // PID extended through PID-39. Same prefix as extendedPIDWire (1..30),
    // continuing with the v0.2-F1 fringe fields. Field map (for the fringe
    // tail only — fields 1..30 are identical to extendedPIDWire above):
    // 31 identityUnknownIndicator=N
    // 32 identityReliabilityCode=US
    // 33 lastUpdateDateTime=20240301080000
    // 34 lastUpdateFacility=HOSP^FAC^ISO         (HD: namespace^universal^univType)
    // 35 speciesCode=L1^Human^HL70447            (CE: identifier^text^codingSys)
    // 36 breedCode empty (human)
    // 37 strain empty (human)
    // 38 productionClassCode empty (human)
    // 39 tribalCitizenship=100^Australian^HL70171  (CWE)
    private let fringePIDWire = """
    MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|||ADT^A01|MSG00001|P|2.5.1\r\
    PID|1||123456^^^HOSP^MR||Smith^John^A||19800101|M||2106-3^White^HL70005|10 Main St^^Sydney^NSW^2000^AU||(02)555-1234||en^English^ISO639|M^Married^HL70002|CAT^Catholic^HL70006|ACC12345|||||Sydney||||||20231215120000|Y|N|US|20240301080000|HOSP^FAC^ISO|L1^Human^HL70447||||100^Australian^HL70171\r
    """

    @Test("PID-31 (ID scalar) identity unknown indicator")
    func pidIdentityUnknownIndicatorAgrees() throws {
        let message = try Parser().parse(fringePIDWire)
        let pid = try #require(message.firstSegment(PID.self))
        #expect(pid.identityUnknownIndicator == "N")
        #expect(pid.identityUnknownIndicator == message["PID-31"])
    }

    @Test("PID-32 (IS scalar) identity reliability code")
    func pidIdentityReliabilityCodeAgrees() throws {
        let message = try Parser().parse(fringePIDWire)
        let pid = try #require(message.firstSegment(PID.self))
        #expect(pid.identityReliabilityCode == "US")
        #expect(pid.identityReliabilityCode == message["PID-32"])
    }

    @Test("PID-33 (TS scalar) last update date/time")
    func pidLastUpdateDateTimeAgrees() throws {
        let message = try Parser().parse(fringePIDWire)
        let pid = try #require(message.firstSegment(PID.self))
        #expect(pid.lastUpdateDateTime == "20240301080000")
        #expect(pid.lastUpdateDateTime == message["PID-33"])
    }

    @Test("PID-34 (HD composite) last update facility")
    func pidLastUpdateFacilityAgrees() throws {
        let message = try Parser().parse(fringePIDWire)
        let pid = try #require(message.firstSegment(PID.self))
        let facility = try #require(pid.lastUpdateFacility)
        #expect(facility.namespaceID == "HOSP")
        #expect(facility.universalIDType == "ISO")
        #expect(message["PID-34.1"] == "HOSP")
        #expect(message["PID-34.3"] == "ISO")
    }

    @Test("PID-35 (CE composite) species code")
    func pidSpeciesCodeAgrees() throws {
        let message = try Parser().parse(fringePIDWire)
        let pid = try #require(message.firstSegment(PID.self))
        let species = try #require(pid.speciesCode)
        #expect(species.identifier == "L1")
        #expect(species.text == "Human")
        #expect(species.identifier == message["PID-35.1"])
        #expect(species.text == message["PID-35.2"])
    }

    @Test("PID-39 (CWE composite) tribal citizenship")
    func pidTribalCitizenshipAgrees() throws {
        let message = try Parser().parse(fringePIDWire)
        let pid = try #require(message.firstSegment(PID.self))
        let citizenship = try #require(pid.tribalCitizenship)
        #expect(citizenship.identifier == "100")
        #expect(citizenship.text == "Australian")
        #expect(citizenship.identifier == message["PID-39.1"])
    }

    @Test("PID fringe-field wire round-trips byte-perfectly")
    func fringePIDRoundTrips() throws {
        let message = try Parser().parse(fringePIDWire)
        let rebuilt = String(data: message.serialize(), encoding: .utf8)
        #expect(rebuilt == fringePIDWire)
    }

    // MARK: - NK1 (Task 4c-3)

    // NK1 next-of-kin. Field map (1-indexed):
    //  1 setID=1, 2 name=Smith^Mary, 3 relationship=SPO^Spouse^HL70063,
    //  4 address=10 Main St^^Sydney^NSW^2000^AU,
    //  5 home phone=(02)555-1234, 6 business=(02)555-5678,
    //  7/8/9 empty, 10 job title=Manager, 11/12/13 empty.
    private let nk1Wire = """
    MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|||ADT^A01|MSG00001|P|2.5.1\r\
    NK1|1|Smith^Mary|SPO^Spouse^HL70063|10 Main St^^Sydney^NSW^2000^AU|(02)555-1234|(02)555-5678||||Manager\r
    """

    @Test("NK1 hydrates as .typed")
    func nk1Hydrates() throws {
        let message = try Parser().parse(nk1Wire)
        let nk1 = try #require(message.firstSegment(NK1.self))
        #expect(type(of: nk1).segmentID == "NK1")
    }

    @Test("NK1-1 (SI) set ID and NK1-10 (ST) job title scalars")
    func nk1ScalarsAgree() throws {
        let message = try Parser().parse(nk1Wire)
        let nk1 = try #require(message.firstSegment(NK1.self))
        #expect(nk1.setID == "1")
        #expect(nk1.nextOfKinJobTitle == "Manager")
        #expect(nk1.setID == message["NK1-1"])
        #expect(nk1.nextOfKinJobTitle == message["NK1-10"])
    }

    @Test("NK1-2 (XPN) name and NK1-3 (CE) relationship composites")
    func nk1NameAndRelationshipAgree() throws {
        let message = try Parser().parse(nk1Wire)
        let nk1 = try #require(message.firstSegment(NK1.self))
        let name = try #require(nk1.name)                        // XPN typed
        let relationship = try #require(nk1.relationship)        // CE typed (v0.3-C2)
        #expect(name.familyName == "Smith")
        #expect(name.givenName == "Mary")
        #expect(relationship.text == "Spouse")
        #expect(name.familyName == message["NK1-2.1"])
        #expect(relationship.text == message["NK1-3.2"])
    }

    @Test("NK1-5/6 (XTN composites) home + business phone")
    func nk1PhonesAgree() throws {
        let message = try Parser().parse(nk1Wire)
        let nk1 = try #require(message.firstSegment(NK1.self))
        let home = try #require(nk1.phoneNumber)
        let business = try #require(nk1.businessPhoneNumber)
        #expect(home.telephoneNumber == "(02)555-1234")
        #expect(business.telephoneNumber == "(02)555-5678")
    }

    @Test("NK1 round-trips byte-perfectly through typed hydration")
    func nk1RoundTrips() throws {
        let message = try Parser().parse(nk1Wire)
        let rebuilt = String(data: message.serialize(), encoding: .utf8)
        #expect(rebuilt == nk1Wire)
    }

    // MARK: - PV1 (Task 4c-3)

    // PV1 patient visit. Field map (1-indexed):
    //  1 setID=1, 2 patientClass=I (Inpatient),
    //  3 location=WARD1^ROOM2^BED3^HOSPITAL, 4 admitType=R (Routine),
    //  5/6 empty, 7 attending=DR123^Jones^Mary,
    //  8/9 empty, 10 service=MED,
    //  11/12/13 empty, 14 admitSource=7,
    //  15 empty, 16 vip=N,
    //  17/18 empty, 19 visit number=V001, 20 empty.
    private let pv1Wire = """
    MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|||ADT^A01|MSG00001|P|2.5.1\r\
    PV1|1|I|WARD1^ROOM2^BED3^HOSPITAL|R|||DR123^Jones^Mary|||MED||||7||N|||V001\r
    """

    @Test("PV1 hydrates as .typed")
    func pv1Hydrates() throws {
        let message = try Parser().parse(pv1Wire)
        let pv1 = try #require(message.firstSegment(PV1.self))
        #expect(type(of: pv1).segmentID == "PV1")
    }

    @Test("PV1-1/2/4 (SI + IS scalars) set ID, patient class, admit type")
    func pv1ClassAndAdmitAgree() throws {
        let message = try Parser().parse(pv1Wire)
        let pv1 = try #require(message.firstSegment(PV1.self))
        #expect(pv1.setID == "1")
        #expect(pv1.patientClass == "I")
        #expect(pv1.admissionType == "R")
        #expect(pv1.patientClass == message["PV1-2"])
    }

    @Test("PV1-3 (PL composite) assigned patient location")
    func pv1LocationAgrees() throws {
        let message = try Parser().parse(pv1Wire)
        let pv1 = try #require(message.firstSegment(PV1.self))
        let location = try #require(pv1.assignedPatientLocation)
        #expect(location.pointOfCare == "WARD1")
        #expect(location.room == "ROOM2")
        #expect(location.bed == "BED3")
        #expect(message["PV1-3.1"] == "WARD1")
    }

    @Test("PV1-7 (XCN composite repeats) attending doctor")
    func pv1AttendingDoctorAgrees() throws {
        let message = try Parser().parse(pv1Wire)
        let pv1 = try #require(message.firstSegment(PV1.self))
        let doctor = try #require(pv1.attendingDoctor)
        #expect(doctor.idNumber == "DR123")
        #expect(doctor.familyName == "Jones")
        #expect(message["PV1-7.1"] == "DR123")
    }

    @Test("PV1-10/14/16 (IS scalars) hospital service, admit source, VIP indicator")
    func pv1AdminScalarsAgree() throws {
        let message = try Parser().parse(pv1Wire)
        let pv1 = try #require(message.firstSegment(PV1.self))
        #expect(pv1.hospitalService == "MED")
        #expect(pv1.admitSource == "7")
        #expect(pv1.vipIndicator == "N")
    }

    @Test("PV1-19 (CX composite) visit number")
    func pv1VisitNumberAgrees() throws {
        let message = try Parser().parse(pv1Wire)
        let pv1 = try #require(message.firstSegment(PV1.self))
        let visit = try #require(pv1.visitNumber)
        #expect(visit.id == "V001")
        #expect(visit.id == message["PV1-19.1"])
    }

    @Test("PV1 round-trips byte-perfectly through typed hydration")
    func pv1RoundTrips() throws {
        let message = try Parser().parse(pv1Wire)
        let rebuilt = String(data: message.serialize(), encoding: .utf8)
        #expect(rebuilt == pv1Wire)
    }

    // MARK: - Full ADT^A01 integration (4c-3 capstone)

    @Test("MSH + PID + PV1 + NK1: full ADT^A01 admit message round-trips")
    func adtA01FullRoundTrip() throws {
        let wire = """
        MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|||ADT^A01|MSG00001|P|2.5.1\r\
        PID|1||123456^^^HOSP^MR||Smith^John^A||19800101|M\r\
        PV1|1|I|WARD1^ROOM2^BED3|R|||DR123^Jones^Mary|||MED\r\
        NK1|1|Smith^Mary|SPO^Spouse|10 Main St\r
        """
        let message = try Parser().parse(wire)
        let pid = try #require(message.firstSegment(PID.self))
        let pv1 = try #require(message.firstSegment(PV1.self))
        let nk1 = try #require(message.firstSegment(NK1.self))
        #expect(pid.administrativeSex == "M")
        #expect(pv1.patientClass == "I")
        #expect(nk1.name?.familyName == "Smith")
        let rebuilt = String(data: message.serialize(), encoding: .utf8)
        #expect(rebuilt == wire)
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
        #expect(allergen.identifier == "PENICILLIN")
        #expect(allergen.text == "Penicillin")
        #expect(allergen.identifier == message["AL1-3.1"])
        #expect(al1.allergyReactionCode == "Hives")
    }

    // MARK: - EVN (v0.4-T1: ADT event-type segment)

    // EVN minimal: event code in EVN-1 (B, retained for backward compat),
    // EVN-2 recorded date/time (R), EVN-7 event facility populated.
    private let evnWire = """
    MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|||ADT^A01|MSG00001|P|2.5.1\r\
    EVN|A01|20240320101500|||DOC123^Jones^Mary||HOSP^FAC^ISO\r
    """

    @Test("EVN hydrates as .typed")
    func evnHydrates() throws {
        let message = try Parser().parse(evnWire)
        let evn = try #require(message.firstSegment(EVN.self))
        #expect(type(of: evn).segmentID == "EVN")
    }

    @Test("EVN-1 (ID) event type code + EVN-2 (TS) recorded date/time scalars")
    func evnScalarsAgree() throws {
        let message = try Parser().parse(evnWire)
        let evn = try #require(message.firstSegment(EVN.self))
        #expect(evn.eventTypeCode == "A01")
        #expect(evn.recordedDateTime == "20240320101500")
        #expect(evn.eventTypeCode == message["EVN-1"])
        #expect(evn.recordedDateTime == message["EVN-2"])
    }

    @Test("EVN-5 (XCN composite) operator ID + EVN-7 (HD composite) event facility")
    func evnCompositesAgree() throws {
        let message = try Parser().parse(evnWire)
        let evn = try #require(message.firstSegment(EVN.self))
        let operatorID = try #require(evn.operatorID)
        let facility = try #require(evn.eventFacility)
        #expect(operatorID.idNumber == "DOC123")
        #expect(operatorID.familyName == "Jones")
        #expect(facility.namespaceID == "HOSP")
        #expect(facility.universalIDType == "ISO")
        #expect(operatorID.idNumber == message["EVN-5.1"])
        #expect(facility.namespaceID == message["EVN-7.1"])
    }

    @Test("EVN round-trips byte-perfectly through typed hydration")
    func evnRoundTrips() throws {
        let message = try Parser().parse(evnWire)
        let rebuilt = String(data: message.serialize(), encoding: .utf8)
        #expect(rebuilt == evnWire)
    }

    // MARK: - MSA (v0.4-T1: ACK body)

    private let msaWire = """
    MSH|^~\\&|HIS|FAC|SENDER|FAC|||ACK|MSG10022|P|2.5.1\r\
    MSA|AA|MSG10001|Message accepted\r
    """

    @Test("MSA hydrates as .typed")
    func msaHydrates() throws {
        let message = try Parser().parse(msaWire)
        let msa = try #require(message.firstSegment(MSA.self))
        #expect(type(of: msa).segmentID == "MSA")
    }

    @Test("MSA-1/2/3 (ID + ST scalars) ack code, control ID, text message")
    func msaScalarsAgree() throws {
        let message = try Parser().parse(msaWire)
        let msa = try #require(message.firstSegment(MSA.self))
        #expect(msa.acknowledgmentCode == "AA")
        #expect(msa.messageControlID == "MSG10001")
        #expect(msa.textMessage == "Message accepted")
        #expect(msa.acknowledgmentCode == message["MSA-1"])
        #expect(msa.messageControlID == message["MSA-2"])
    }

    @Test("MSA round-trips byte-perfectly through typed hydration")
    func msaRoundTrips() throws {
        let message = try Parser().parse(msaWire)
        let rebuilt = String(data: message.serialize(), encoding: .utf8)
        #expect(rebuilt == msaWire)
    }

    // MARK: - ERR (v0.4-T1: negative-ACK error detail)

    // ERR with v2.5.1-style ERR-2 (ERL) location + ERR-3 (CWE) HL7 error code
    // + ERR-4 (ID) severity. ERR-1 (ELD) populated for backward compat.
    private let errWire = """
    MSH|^~\\&|HIS|FAC|SENDER|FAC|||ACK|MSG10023|P|2.5.1\r\
    ERR|PID^1^3^1||101^Required field missing^HL70357|E||PID-3-1 expected\r
    """

    @Test("ERR hydrates as .typed")
    func errHydrates() throws {
        let message = try Parser().parse(errWire)
        let err = try #require(message.firstSegment(ERR.self))
        #expect(type(of: err).segmentID == "ERR")
    }

    @Test("ERR-3 (CWE composite) HL7 error code + ERR-4 (ID) severity scalar")
    func errCoreFieldsAgree() throws {
        let message = try Parser().parse(errWire)
        let err = try #require(message.firstSegment(ERR.self))
        let hl7Code = try #require(err.hl7ErrorCode)
        #expect(hl7Code.identifier == "101")
        #expect(hl7Code.text == "Required field missing")
        #expect(err.severity == "E")
        #expect(hl7Code.identifier == message["ERR-3.1"])
        #expect(hl7Code.text == message["ERR-3.2"])
        #expect(err.severity == message["ERR-4"])
    }

    @Test("ERR round-trips byte-perfectly through typed hydration")
    func errRoundTrips() throws {
        let message = try Parser().parse(errWire)
        let rebuilt = String(data: message.serialize(), encoding: .utf8)
        #expect(rebuilt == errWire)
    }

    // MARK: - ACK fixture auto-pickup (regression: existing ACK fixtures
    //         now hydrate MSA / ERR as typed without fixture changes)

    @Test("ack_application_accept.hl7 hydrates MSA as typed")
    func ackAcceptFixtureHydratesMSA() throws {
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/ack_application_accept.hl7")
        let bytes = try Data(contentsOf: fixtureURL)
        let message = try Parser().parse(bytes)
        let msa = try #require(message.firstSegment(MSA.self))
        #expect(msa.acknowledgmentCode == "AA")
        // Fixture must still round-trip byte-perfectly post-T1.
        let rebuilt = message.serialize()
        #expect(rebuilt == bytes)
    }

    @Test("ack_application_error.hl7 hydrates MSA + ERR as typed")
    func ackErrorFixtureHydratesMSAAndERR() throws {
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/ack_application_error.hl7")
        let bytes = try Data(contentsOf: fixtureURL)
        let message = try Parser().parse(bytes)
        let msa = try #require(message.firstSegment(MSA.self))
        let err = try #require(message.firstSegment(ERR.self))
        #expect(msa.acknowledgmentCode == "AE")
        let hl7Code = try #require(err.hl7ErrorCode)
        #expect(hl7Code.identifier == "101")
        // Fixture must still round-trip byte-perfectly post-T1.
        let rebuilt = message.serialize()
        #expect(rebuilt == bytes)
    }

    // MARK: - PD1 (v0.4-T2: Patient Additional Demographic)

    // PD1 with PD1-3 primary facility, PD1-5 student indicator, PD1-7 living
    // will, PD1-11 publicity code, PD1-12 protection indicator.
    private let pd1Wire = """
    MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|||ADT^A01|MSG00001|P|2.5.1\r\
    PD1|||GOOD_HEALTH^L^1^^^HOSP^XX||N||Y|Y|N||N^Normal^HL70215|Y|20240101\r
    """

    @Test("PD1 hydrates as .typed")
    func pd1Hydrates() throws {
        let message = try Parser().parse(pd1Wire)
        let pd1 = try #require(message.firstSegment(PD1.self))
        #expect(type(of: pd1).segmentID == "PD1")
    }

    @Test("PD1-3 (XON composite) patient primary facility + PD1-5 (IS) student indicator")
    func pd1PrimaryFacilityAndStudentAgree() throws {
        let message = try Parser().parse(pd1Wire)
        let pd1 = try #require(message.firstSegment(PD1.self))
        let facility = try #require(pd1.patientPrimaryFacility)
        #expect(facility.organizationName == "GOOD_HEALTH")
        #expect(facility.organizationName == message["PD1-3.1"])
        #expect(pd1.studentIndicator == "N")
        #expect(pd1.studentIndicator == message["PD1-5"])
    }

    @Test("PD1-11 (CE composite) publicity code + PD1-12 (ID) protection indicator")
    func pd1PublicityAndProtectionAgree() throws {
        let message = try Parser().parse(pd1Wire)
        let pd1 = try #require(message.firstSegment(PD1.self))
        let publicity = try #require(pd1.publicityCode)
        #expect(publicity.identifier == "N")
        #expect(publicity.text == "Normal")
        #expect(pd1.protectionIndicator == "Y")
        #expect(pd1.protectionIndicatorEffectiveDate == "20240101")
    }

    @Test("PD1 round-trips byte-perfectly through typed hydration")
    func pd1RoundTrips() throws {
        let message = try Parser().parse(pd1Wire)
        let rebuilt = String(data: message.serialize(), encoding: .utf8)
        #expect(rebuilt == pd1Wire)
    }

    // MARK: - DG1 (v0.4-T2: Diagnosis)

    // DG1 with set ID, diagnosis code (CE), date/time, diagnosis type,
    // priority, diagnosing clinician. After DG1-6 ("A"), 9 pipes skip
    // through DG1-7..DG1-14 (8 empty fields) and land "1" at DG1-15;
    // one more pipe opens DG1-16 carrying the XCN clinician.
    private let dg1Wire = """
    MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|||ADT^A01|MSG00001|P|2.5.1\r\
    DG1|1||I10^Essential hypertension^ICD10||20240315090000|A|||||||||1|DR123^Jones^Mary\r
    """

    @Test("DG1 hydrates as .typed")
    func dg1Hydrates() throws {
        let message = try Parser().parse(dg1Wire)
        let dg1 = try #require(message.firstSegment(DG1.self))
        #expect(type(of: dg1).segmentID == "DG1")
    }

    @Test("DG1-1 (SI) set ID + DG1-6 (IS) diagnosis type scalars")
    func dg1ScalarsAgree() throws {
        let message = try Parser().parse(dg1Wire)
        let dg1 = try #require(message.firstSegment(DG1.self))
        #expect(dg1.setID == "1")
        #expect(dg1.diagnosisType == "A")
        #expect(dg1.setID == message["DG1-1"])
        #expect(dg1.diagnosisType == message["DG1-6"])
    }

    @Test("DG1-3 (CE composite) diagnosis code + DG1-5 (TS) diagnosis date")
    func dg1DiagnosisCodeAndDateAgree() throws {
        let message = try Parser().parse(dg1Wire)
        let dg1 = try #require(message.firstSegment(DG1.self))
        let code = try #require(dg1.diagnosisCode)
        #expect(code.identifier == "I10")
        #expect(code.text == "Essential hypertension")
        #expect(code.nameOfCodingSystem == "ICD10")
        #expect(dg1.diagnosisDateTime == "20240315090000")
        #expect(code.identifier == message["DG1-3.1"])
    }

    @Test("DG1-15 (ID) diagnosis priority + DG1-16 (XCN composite) diagnosing clinician")
    func dg1PriorityAndClinicianAgree() throws {
        let message = try Parser().parse(dg1Wire)
        let dg1 = try #require(message.firstSegment(DG1.self))
        #expect(dg1.diagnosisPriority == "1")
        let clinician = try #require(dg1.diagnosingClinician)
        #expect(clinician.idNumber == "DR123")
        #expect(clinician.familyName == "Jones")
        #expect(clinician.idNumber == message["DG1-16.1"])
    }

    @Test("DG1 round-trips byte-perfectly through typed hydration")
    func dg1RoundTrips() throws {
        let message = try Parser().parse(dg1Wire)
        let rebuilt = String(data: message.serialize(), encoding: .utf8)
        #expect(rebuilt == dg1Wire)
    }

    // MARK: - IN1 (v0.4-T3: Insurance — billing-essentials subset, 25 fields)

    // IN1 with set ID, insurance plan CE, company ID CX, company name XON,
    // company address XAD, group number, plan effective date.
    private let in1Wire = """
    MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|||ADT^A01|MSG00001|P|2.5.1\r\
    IN1|1|HBF^Medibank Private^L|MED001|MEDIBANK PRIVATE|PO BOX 9999^^Sydney^NSW^2000^AU||(02)555-7777|GRP123|||N|20240101|20241231\r
    """

    @Test("IN1 hydrates as .typed")
    func in1Hydrates() throws {
        let message = try Parser().parse(in1Wire)
        let in1 = try #require(message.firstSegment(IN1.self))
        #expect(type(of: in1).segmentID == "IN1")
    }

    @Test("IN1-1 (SI) set ID + IN1-2 (CE composite) insurance plan ID")
    func in1IdentityFieldsAgree() throws {
        let message = try Parser().parse(in1Wire)
        let in1 = try #require(message.firstSegment(IN1.self))
        #expect(in1.setID == "1")
        let plan = try #require(in1.insurancePlanID)
        #expect(plan.identifier == "HBF")
        #expect(plan.text == "Medibank Private")
        #expect(plan.identifier == message["IN1-2.1"])
    }

    @Test("IN1-3 (CX composite) insurance company ID + IN1-4 (XON) company name")
    func in1CompanyAgree() throws {
        let message = try Parser().parse(in1Wire)
        let in1 = try #require(message.firstSegment(IN1.self))
        let companyID = try #require(in1.insuranceCompanyID)
        let companyName = try #require(in1.insuranceCompanyName)
        #expect(companyID.id == "MED001")
        #expect(companyName.organizationName == "MEDIBANK PRIVATE")
        #expect(companyID.id == message["IN1-3.1"])
        #expect(companyName.organizationName == message["IN1-4.1"])
    }

    @Test("IN1-5 (XAD) company address + IN1-7 (XTN) phone")
    func in1AddressAndPhoneAgree() throws {
        let message = try Parser().parse(in1Wire)
        let in1 = try #require(message.firstSegment(IN1.self))
        let address = try #require(in1.insuranceCompanyAddress)
        let phone = try #require(in1.insuranceCoPhoneNumber)
        #expect(address.streetAddress == "PO BOX 9999")
        #expect(address.city == "Sydney")
        #expect(phone.telephoneNumber == "(02)555-7777")
    }

    @Test("IN1-8 (ST) group number + IN1-12 (DT) plan effective date")
    func in1GroupAndDateAgree() throws {
        let message = try Parser().parse(in1Wire)
        let in1 = try #require(message.firstSegment(IN1.self))
        #expect(in1.groupNumber == "GRP123")
        #expect(in1.planEffectiveDate == "20240101")
        #expect(in1.planExpirationDate == "20241231")
    }

    @Test("IN1 round-trips byte-perfectly through typed hydration")
    func in1RoundTrips() throws {
        let message = try Parser().parse(in1Wire)
        let rebuilt = String(data: message.serialize(), encoding: .utf8)
        #expect(rebuilt == in1Wire)
    }

    @Test("adt_a01_with_insurance.hl7 fixture hydrates IN1 as typed (T3 capstone)")
    func adtWithInsuranceFixtureHydratesIN1() throws {
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/adt_a01_with_insurance.hl7")
        let bytes = try Data(contentsOf: fixtureURL)
        let message = try Parser().parse(bytes)
        let in1 = try #require(message.firstSegment(IN1.self))
        #expect(in1.setID == "1")
        let plan = try #require(in1.insurancePlanID)
        #expect(plan.identifier == "HBF")
        #expect(plan.text == "Medibank Private")
        let companyID = try #require(in1.insuranceCompanyID)
        #expect(companyID.id == "MED001")
        // Fixture must still round-trip byte-perfectly post-T3.
        let rebuilt = message.serialize()
        #expect(rebuilt == bytes)
    }

    // MARK: - v0.19: canonical v2.5.1 NK1/PV1/IN1 extended to full field depth

    @Test("v0.19: v2.5.1 grammar carries full NK1 (39) / PV1 (52) / IN1 (53)")
    func v0_19FullCanonicalFieldCounts() {
        let table = SegmentGrammarTable.v2_5_1
        #expect(table["NK1"]?.fields.count == 39)
        #expect(table["PV1"]?.fields.count == 52)
        #expect(table["IN1"]?.fields.count == 53)
        // Newly-added fields carry their spec datatype.
        #expect(table["NK1"]?.field(35)?.dataType == "CE")   // Race
        #expect(table["PV1"]?.field(44)?.dataType == "TS")   // Admit Date/Time
        #expect(table["IN1"]?.field(36)?.dataType == "ST")   // Policy Number
        // Required fields held after extension.
        #expect(table["PV1"]?.field(2)?.optionality == .required)
        #expect(table["IN1"]?.field(2)?.optionality == .required)
    }

    @Test("v0.19: a new scalar typed accessor hydrates and agrees with the path")
    func v0_19ExtendedTypedAccessor() throws {
        // NK1-37 (Contact Person SSN, ST scalar) populated. NK1 base ends at
        // NK1-3; 34 pipes advance f3→f37 (field index = pipe count from f3),
        // so the SSN lands at NK1-37.
        let nk1 = "NK1|1||SPO^Spouse" + String(repeating: "|", count: 34) + "123-45-6789"
        let wire = "MSH|^~\\&|A|B|C|D|20240101120000||ADT^A01|M1|P|2.5.1\r"
            + "PID|1||X^^^F^MR||Doe^Jane\r" + nk1 + "\r"
        let message = try Parser().parse(wire)
        let seg = try #require(message.firstSegment(NK1.self))
        #expect(seg.setID == "1")
        #expect(seg.contactPersonSocialSecurityNumber == "123-45-6789")   // NK1-37 (new)
        #expect(seg.contactPersonSocialSecurityNumber == message["NK1-37"])
    }

    // v1.1 (ADR-015): the extraction pipeline's golden audit against the v2.5.1 PDFs
    // caught 11 metadata defects + 2 incomplete segments in the pre-pipeline canonical
    // schemas. These pins guard the corrections so they can never silently regress.
    @Test("v1.1: OBR completed to 50 fields, OBX to 24 (were 47 / 17)")
    func v1_1CompletedFieldCounts() {
        let table = SegmentGrammarTable.v2_5_1
        #expect(table["OBR"]?.fields.count == 50)
        #expect(table["OBX"]?.fields.count == 24)
        // Newly-authored trailing fields carry their v2.5.1 spec datatype.
        #expect(table["OBR"]?.field(48)?.dataType == "CWE")  // Medically Necessary Duplicate Procedure Reason
        #expect(table["OBR"]?.field(49)?.dataType == "IS")   // Result Handling (IS in v2.5.1)
        #expect(table["OBX"]?.field(18)?.dataType == "EI")   // Equipment Instance Identifier
        #expect(table["OBX"]?.field(24)?.dataType == "XAD")  // Performing Organization Address
        // OBX-20/21/22 are "Reserved for harmonization with V2.6" in v2.5.1 (X).
        #expect(table["OBX"]?.field(20)?.optionality == .notSupported)
        #expect(table["OBX"]?.field(22)?.optionality == .notSupported)
    }

    @Test("v1.1: corrected optionality — backward-compat (B) and withdrawn (W) fields")
    func v1_1CorrectedOptionality() {
        let table = SegmentGrammarTable.v2_5_1
        // B (backward-compatibility) fields the pre-pipeline authoring flattened to O.
        #expect(table["PV1"]?.field(9)?.optionality == .backwardCompat)   // Consulting Doctor
        #expect(table["PV1"]?.field(40)?.optionality == .backwardCompat)  // Bed Status
        #expect(table["PV1"]?.field(52)?.optionality == .backwardCompat)  // Other Healthcare Provider
        #expect(table["IN1"]?.field(38)?.optionality == .backwardCompat)  // Policy Limit - Amount
        #expect(table["IN1"]?.field(40)?.optionality == .backwardCompat)  // Room Rate - Semi-Private
        #expect(table["IN1"]?.field(41)?.optionality == .backwardCompat)  // Room Rate - Private
        // MSA-5 is Withdrawn in v2.5.1 (was mis-modelled as X/ST).
        #expect(table["MSA"]?.field(5)?.optionality == .withdrawn)
    }

    @Test("v1.1: corrected repeatability — RP/# read straight from the spec column")
    func v1_1CorrectedRepeatability() {
        let table = SegmentGrammarTable.v2_5_1
        #expect(table["NK1"]?.field(26)?.repeatability == .multiple)  // Mother's Maiden Name (Y)
        #expect(table["PID"]?.field(38)?.repeatability == .multiple)  // Production Class Code (2)
        #expect(table["PV1"]?.field(45)?.repeatability == .multiple)  // Discharge Date/Time (Y)
        #expect(table["PV1"]?.field(50)?.repeatability == .single)    // Alternate Visit ID (blank, was over-marked)
    }

    // v1.2 (M5 sweep): 6 new typed segments — PV2, MRG, DB1 (CH03) + GT1, IN2,
    // IN3 (CH06). Canonical v2.5.1 depths pinned; hydration via the auto-generated
    // registry confirmed; typed accessor ↔ path access agreement checked.
    @Test("v1.2: new segments PV2/MRG/DB1/GT1/IN2/IN3 — canonical depths + registration")
    func v1_2NewSegmentsCanonical() {
        let t = SegmentGrammarTable.v2_5_1
        #expect(t["PV2"]?.fields.count == 49)
        #expect(t["MRG"]?.fields.count == 7)
        #expect(t["DB1"]?.fields.count == 8)
        #expect(t["GT1"]?.fields.count == 57)
        #expect(t["IN2"]?.fields.count == 72)
        #expect(t["IN3"]?.fields.count == 25)
        // IN3-8 "Operator" — swiftName is the Swift keyword `operator`, emitted
        // backtick-escaped by codegen; the grammar name stays faithful.
        #expect(t["IN3"]?.field(8)?.name == "Operator")
    }

    @Test("v1.2: new segments hydrate as .typed and agree with path access")
    func v1_2NewSegmentsHydrate() throws {
        let wire = "MSH|^~\\&|A|B|C|D|20240101120000||ADT^A01|M1|P|2.5.1\r"
            + "PID|1||X^^^F^MR||Doe^Jane\r"
            + "PV2||||||||||||Annual checkup\r"          // PV2-12 Visit Description (ST)
            + "MRG|OLD123^^^F^MR\r"                        // MRG-1 Prior Patient Identifier List (CX)
            + "DB1|1\r"                                    // DB1-1 Set ID (SI)
            + "GT1|1\r"                                    // GT1-1 Set ID (SI)
            + "IN2\r" + "IN3|1\r"
        let message = try Parser().parse(wire)

        let pv2 = try #require(message.firstSegment(PV2.self))
        #expect(pv2.visitDescription == "Annual checkup")
        #expect(pv2.visitDescription == message["PV2-12"])

        let gt1 = try #require(message.firstSegment(GT1.self))
        #expect(gt1.setIdGt1 == "1")
        #expect(gt1.setIdGt1 == message["GT1-1"])

        // The rest hydrate as .typed via the auto-generated registry.
        #expect(message.firstSegment(MRG.self) != nil)
        #expect(message.firstSegment(DB1.self) != nil)
        #expect(message.firstSegment(IN2.self) != nil)
        #expect(message.firstSegment(IN3.self) != nil)
    }

    // v1.3 (M5 sweep): 14 new typed segments — SPM (CH07), ROL (CH15), the CH10
    // scheduling family (SCH/RGS/AIS/AIG/AIL/AIP/APR/ARQ), blood-product BPO/BPX/BTX
    // and RXA (CH04). Canonical v2.5.1 depths pinned + registry hydration.
    @Test("v1.3: new segments — canonical depths + RXA base table (not the vaccine profile)")
    func v1_3NewSegmentsCanonical() {
        let t = SegmentGrammarTable.v2_5_1
        #expect(t["SPM"]?.fields.count == 29)
        #expect(t["ROL"]?.fields.count == 12)
        #expect(t["SCH"]?.fields.count == 27)
        #expect(t["RGS"]?.fields.count == 3)
        #expect(t["AIS"]?.fields.count == 12)
        #expect(t["AIG"]?.fields.count == 14)
        #expect(t["AIL"]?.fields.count == 12)
        #expect(t["AIP"]?.fields.count == 12)
        #expect(t["APR"]?.fields.count == 5)
        #expect(t["ARQ"]?.fields.count == 25)
        #expect(t["BPO"]?.fields.count == 14)
        #expect(t["BPX"]?.fields.count == 21)
        #expect(t["BTX"]?.fields.count == 19)
        // RXA must be the base "Pharmacy/Treatment Administration" table (26 fields),
        // NOT the "Segment Uses in Vaccine Messages" profile table that follows it.
        #expect(t["RXA"]?.fields.count == 26)
        #expect(t["RXA"]?.field(5)?.name == "Administered Code")
    }

    @Test("v1.3: new segments hydrate as .typed and agree with path access")
    func v1_3NewSegmentsHydrate() throws {
        let wire = "MSH|^~\\&|A|B|C|D|20240101120000||SIU^S12|M1|P|2.5.1\r"
            + "SCH|A^^^F|B^^^F\r" + "RGS|1\r"
            + "AIS|1\r" + "AIG|1\r" + "AIL|1\r" + "AIP|1\r" + "APR\r" + "ARQ|A^^^F\r"
            + "SPM|1\r" + "ROL|R1^^^F|AD\r" + "BPO|1\r" + "BPX|1\r" + "BTX|1\r" + "RXA|0|1\r"
        let message = try Parser().parse(wire)
        let rgs = try #require(message.firstSegment(RGS.self))
        #expect(rgs.setIdRgs == "1")
        #expect(rgs.setIdRgs == message["RGS-1"])
        for present in [message.firstSegment(SPM.self) != nil, message.firstSegment(ROL.self) != nil,
                        message.firstSegment(SCH.self) != nil, message.firstSegment(AIS.self) != nil,
                        message.firstSegment(AIG.self) != nil, message.firstSegment(AIL.self) != nil,
                        message.firstSegment(AIP.self) != nil, message.firstSegment(APR.self) != nil,
                        message.firstSegment(ARQ.self) != nil, message.firstSegment(BPO.self) != nil,
                        message.firstSegment(BPX.self) != nil, message.firstSegment(BTX.self) != nil,
                        message.firstSegment(RXA.self) != nil] {
            #expect(present)
        }
    }

    // v1.2 (M5 sweep): 8 new order/pharmacy/timing typed segments — TQ1, TQ2, RXO,
    // RXR, RXC, RXE, RXD, RXG (CH04). Typed count 21 → 29.
    @Test("v1.2: order/pharmacy segments — canonical depths + registration")
    func v1_2PharmacySegmentsCanonical() {
        let t = SegmentGrammarTable.v2_5_1
        #expect(t["TQ1"]?.fields.count == 14)
        #expect(t["TQ2"]?.fields.count == 10)
        #expect(t["RXO"]?.fields.count == 28)
        #expect(t["RXR"]?.fields.count == 6)
        #expect(t["RXC"]?.fields.count == 9)
        #expect(t["RXE"]?.fields.count == 44)
        #expect(t["RXD"]?.fields.count == 33)
        #expect(t["RXG"]?.fields.count == 26)
    }

    @Test("v1.2: order/pharmacy segments hydrate as .typed and agree with path access")
    func v1_2PharmacySegmentsHydrate() throws {
        let wire = "MSH|^~\\&|A|B|C|D|20240101120000||ORM^O01|M1|P|2.5.1\r"
            + "TQ1|1\r"                                     // TQ1-1 Set ID (SI)
            + "RXR|PO\r"                                    // RXR-1 Route (CE) — component .id = "PO"
            + "TQ2\r" + "RXO\r" + "RXC\r" + "RXE\r" + "RXD\r" + "RXG\r"
        let message = try Parser().parse(wire)

        let tq1 = try #require(message.firstSegment(TQ1.self))
        #expect(tq1.setIdTq1 == "1")
        #expect(tq1.setIdTq1 == message["TQ1-1"])

        // All 8 hydrate as .typed via the auto-generated registry.
        #expect(message.firstSegment(TQ2.self) != nil)
        #expect(message.firstSegment(RXO.self) != nil)
        #expect(message.firstSegment(RXR.self) != nil)
        #expect(message.firstSegment(RXC.self) != nil)
        #expect(message.firstSegment(RXE.self) != nil)
        #expect(message.firstSegment(RXD.self) != nil)
        #expect(message.firstSegment(RXG.self) != nil)
    }

    // v1.2: per-version depth grows monotonically for the pharmacy family
    // (extractor SEQ-detection fix recovered the v2.3 CH4 tables that a fixed-offset
    // slice had silently dropped).
    @Test("v1.2: pharmacy per-version depths (RXE / RXO across versions)")
    func v1_2PharmacyPerVersion() {
        #expect(SegmentGrammarTable.v2_3["RXE"]?.fields.count == 30)
        #expect(SegmentGrammarTable.v2_4["RXE"]?.fields.count == 31)
        #expect(SegmentGrammarTable.v2_6["RXE"]?.fields.count == 44)
        #expect(SegmentGrammarTable.v2_8_2["RXE"]?.fields.count == 45)
        #expect(SegmentGrammarTable.v2_3["RXO"]?.fields.count == 22)
        #expect(SegmentGrammarTable.v2_8_2["RXO"]?.fields.count == 36)
        // TQ1/TQ2 are v2.5+ — absent on the older tables.
        #expect(SegmentGrammarTable.v2_3["TQ1"] == nil)
        #expect(SegmentGrammarTable.v2_6["TQ1"]?.fields.count == 14)
    }
}
