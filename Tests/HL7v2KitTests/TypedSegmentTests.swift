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
        let pid = try hydrated(PID.self, from: wire)
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
        let pid = try hydrated(PID.self, from: shortPID)
        #expect(pid.setID == "1")
        #expect(pid.dateTimeOfBirth == nil)       // PID-7, absent
        #expect(pid.patientName == nil)           // PID-5, absent
        #expect(pid.administrativeSex == nil)     // PID-8, absent
    }

    @Test("PID-1 (scalar SI) — path and typed accessor agree")
    func setIDMatchesPath() throws {
        let (message, pid) = try hydratedMessage(PID.self, from: wire)
        #expect(pid.setID == "1")
        #expect(pid.setID == message["PID-1"])
    }

    @Test("PID-3 (CX composite) — typed accessor exposes the ID via .id")
    func patientIdentifierListAgrees() throws {
        let (message, pid) = try hydratedMessage(PID.self, from: wire)
        let identifier = try #require(pid.patientIdentifierList)
        #expect(identifier.id == "123456")
        #expect(identifier.id == message["PID-3.1"])
    }

    @Test("PID-5 (XPN composite) — typed accessor exposes family/given names")
    func patientNameAgrees() throws {
        let (message, pid) = try hydratedMessage(PID.self, from: wire)
        let name = try #require(pid.patientName)
        #expect(name.familyName == "Smith")
        #expect(name.givenName == "John")
        #expect(name.familyName == message["PID-5.1"])
        #expect(name.givenName == message["PID-5.2"])
    }

    @Test("PID-7 (TS treated as scalar) — typed accessor returns String")
    func dobAgrees() throws {
        let (message, pid) = try hydratedMessage(PID.self, from: wire)
        #expect(pid.dateTimeOfBirth == "19800101")
        #expect(pid.dateTimeOfBirth == message["PID-7"])
    }

    @Test("PID-8 (IS scalar) — administrative sex")
    func sexAgrees() throws {
        let (message, pid) = try hydratedMessage(PID.self, from: wire)
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
        let msh = try hydrated(MSH.self, from: wire)
        #expect(msh.fieldSeparator == "|")
        #expect(msh.encodingCharacters == "^~\\&")
    }

    @Test("MSH-9 (composite MSG) — typed accessor returns the structured Field")
    func mshMessageTypeAgrees() throws {
        let (message, msh) = try hydratedMessage(MSH.self, from: wire)
        let messageType = try #require(msh.messageType)
        #expect(messageType.messageCode == "ADT")
        #expect(messageType.triggerEvent == "A01")
        #expect(message["MSH-9.1"] == "ADT")
        #expect(message["MSH-9.2"] == "A01")
    }

    @Test("MSH-10 (ST scalar) and MSH-11/12 (composites PT/VID) agree with path")
    func mshControlFieldsAgree() throws {
        let (message, msh) = try hydratedMessage(MSH.self, from: wire)
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
        let nteWire = TestWires.oru("NTE|1|L|Patient is allergic to shellfish")
        let (message, nte) = try hydratedMessage(NTE.self, from: nteWire)
        #expect(nte.setID == "1")
        #expect(nte.sourceOfComment == "L")
        #expect(nte.comment == "Patient is allergic to shellfish")
        #expect(nte.setID == message["NTE-1"])
        #expect(nte.sourceOfComment == message["NTE-2"])
        #expect(nte.comment == message["NTE-3"])
    }

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
        let (message, orc) = try hydratedMessage(ORC.self, from: wire)
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
        let (message, orc) = try hydratedMessage(ORC.self, from: orcExtendedWire)
        #expect(orc.orderControl == "NW")
        #expect(orc.orderControl == message["ORC-1"])
    }

    @Test("ORC-2/3 (composite EI) placer/filler order numbers")
    func orcOrderNumbersAgree() throws {
        let (message, orc) = try hydratedMessage(ORC.self, from: orcExtendedWire)
        let placer = try #require(orc.placerOrderNumber)
        let filler = try #require(orc.fillerOrderNumber)
        #expect(placer.entityIdentifier == "PLACER123")
        #expect(filler.entityIdentifier == "FILLER456")
        #expect(message["ORC-2.1"] == "PLACER123")
        #expect(message["ORC-3.1"] == "FILLER456")
    }

    @Test("ORC-5/6 (ID scalars) order status + response flag")
    func orcScalarFlagsAgree() throws {
        let orc = try hydrated(ORC.self, from: orcExtendedWire)
        #expect(orc.orderStatus == "IP")
        #expect(orc.responseFlag == "E")
    }

    @Test("ORC-9 (TS scalar) date/time of transaction")
    func orcTransactionDateAgrees() throws {
        let orc = try hydrated(ORC.self, from: orcExtendedWire)
        #expect(orc.dateTimeOfTransaction == "20240101120000")
    }

    @Test("ORC-12 (composite XCN repeats) ordering provider")
    func orcOrderingProviderAgrees() throws {
        let orc = try hydrated(ORC.self, from: orcExtendedWire)
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
        let (message, orc) = try hydratedMessage(ORC.self, from: orcFringeWire)
        let abn = try #require(orc.advancedBeneficiaryNoticeCode)
        #expect(abn.identifier == "ABN1")
        #expect(abn.identifier == message["ORC-20.1"])
    }

    @Test("ORC-21 (XON) ordering facility name + ORC-22 (XAD) facility address")
    func orcOrderingFacilityNameAndAddressAgree() throws {
        let (message, orc) = try hydratedMessage(ORC.self, from: orcFringeWire)
        let name = try #require(orc.orderingFacilityName)        // XON typed (v0.3-C4)
        let addr = try #require(orc.orderingFacilityAddress)     // XAD typed
        #expect(name.organizationName == "FacilityName")
        #expect(addr.streetAddress == "1 Hospital Rd")
        #expect(addr.city == "Sydney")
        #expect(addr.city == message["ORC-22.3"])
    }

    @Test("ORC-27 (TS scalar) filler's expected availability date/time")
    func orcExpectedAvailabilityAgrees() throws {
        let (message, orc) = try hydratedMessage(ORC.self, from: orcFringeWire)
        #expect(orc.fillersExpectedAvailabilityDateTime == "20240301140000")
        #expect(orc.fillersExpectedAvailabilityDateTime == message["ORC-27"])
    }

    @Test("ORC-28 (CWE) confidentiality code + ORC-29 (CWE) order type")
    func orcConfidentialityAndOrderTypeAgree() throws {
        let (message, orc) = try hydratedMessage(ORC.self, from: orcFringeWire)
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
        let orc = try hydrated(ORC.self, from: orcFringeWire)
        let mode = try #require(orc.entererAuthorizationMode)
        #expect(mode.identifier == "EL")
        #expect(mode.text == "Electronic")
    }

    @Test("ORC-31 (CWE) parent universal service identifier")
    func orcParentUniversalServiceIdentifierAgrees() throws {
        let (message, orc) = try hydratedMessage(ORC.self, from: orcFringeWire)
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

    private let obxWire = TestWires.oru("OBX|1|NM|GLU^Glucose^L||5.2|mmol/L^Millimoles per litre^UCUM|3.9-5.5|N|||F|||20240101130000")

    @Test("OBX hydrates as .typed")
    func obxHydrates() throws {
        let obx = try hydrated(OBX.self, from: obxWire)
        #expect(type(of: obx).segmentID == "OBX")
    }

    @Test("OBX-1 (SI) and OBX-2 (ID) scalars agree with path")
    func obxIdentifyingScalarsAgree() throws {
        let (message, obx) = try hydratedMessage(OBX.self, from: obxWire)
        #expect(obx.setID == "1")
        #expect(obx.setID == message["OBX-1"])
        #expect(obx.valueType == "NM")
        #expect(obx.valueType == message["OBX-2"])
    }

    @Test("OBX-3 (composite CE) observation identifier")
    func obxObservationIdentifierAgrees() throws {
        let (message, obx) = try hydratedMessage(OBX.self, from: obxWire)
        let identifier = try #require(obx.observationIdentifier)
        #expect(identifier.identifier == "GLU")
        #expect(identifier.text == "Glucose")
        #expect(identifier.identifier == message["OBX-3.1"])
        #expect(identifier.text == message["OBX-3.2"])
    }

    @Test("OBX-5 (ST scalar) observation value")
    func obxObservationValueAgrees() throws {
        let (message, obx) = try hydratedMessage(OBX.self, from: obxWire)
        #expect(obx.observationValue == "5.2")
        #expect(obx.observationValue == message["OBX-5"])
    }

    @Test("OBX-6 (composite CE) units")
    func obxUnitsAgree() throws {
        let obx = try hydrated(OBX.self, from: obxWire)
        let units = try #require(obx.units)
        #expect(units.identifier == "mmol/L")
        #expect(units.nameOfCodingSystem == "UCUM")
    }

    @Test("OBX-7 (ST) reference range and OBX-8 (IS) abnormal flags scalars")
    func obxResultMetaScalarsAgree() throws {
        let obx = try hydrated(OBX.self, from: obxWire)
        #expect(obx.referencesRange == "3.9-5.5")
        #expect(obx.abnormalFlags == "N")
    }

    @Test("OBX-11 (ID) observation result status")
    func obxResultStatusAgrees() throws {
        let (message, obx) = try hydratedMessage(OBX.self, from: obxWire)
        #expect(obx.observationResultStatus == "F")
        #expect(obx.observationResultStatus == message["OBX-11"])
    }

    @Test("OBX-14 (TS) date/time of the observation")
    func obxObservationTimestampAgrees() throws {
        let obx = try hydrated(OBX.self, from: obxWire)
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
    private let obrWire = TestWires.oru("OBR|1|PLACER123^HOSP|FILLER456^LAB|GLU^Glucose^L|||20240101120000|20240101130000||^Smith^John|L|||20240101115000||^Williams^Sue||||PLACER1|FILLER1|20240101140000|||F")

    @Test("OBR hydrates as .typed")
    func obrHydrates() throws {
        let obr = try hydrated(OBR.self, from: obrWire)
        #expect(type(of: obr).segmentID == "OBR")
    }

    @Test("OBR-1 (SI scalar) set ID agrees with path")
    func obrSetIDAgrees() throws {
        let (message, obr) = try hydratedMessage(OBR.self, from: obrWire)
        #expect(obr.setID == "1")
        #expect(obr.setID == message["OBR-1"])
    }

    @Test("OBR-2/3 (composite EI) placer/filler order numbers")
    func obrOrderNumbersAgree() throws {
        let (message, obr) = try hydratedMessage(OBR.self, from: obrWire)
        let placer = try #require(obr.placerOrderNumber)
        let filler = try #require(obr.fillerOrderNumber)
        #expect(placer.entityIdentifier == "PLACER123")
        #expect(filler.entityIdentifier == "FILLER456")
        #expect(message["OBR-2.1"] == "PLACER123")
        #expect(message["OBR-3.1"] == "FILLER456")
    }

    @Test("OBR-4 (composite CE) universal service identifier")
    func obrUniversalServiceIdentifierAgrees() throws {
        let (message, obr) = try hydratedMessage(OBR.self, from: obrWire)
        let service = try #require(obr.universalServiceIdentifier)
        #expect(service.identifier == "GLU")
        #expect(service.text == "Glucose")
        #expect(service.identifier == message["OBR-4.1"])
        #expect(message["OBR-4.2"] == "Glucose")
    }

    @Test("OBR-7/8 (TS scalars) observation start + end timestamps")
    func obrObservationTimestampsAgree() throws {
        let (message, obr) = try hydratedMessage(OBR.self, from: obrWire)
        #expect(obr.observationDateTime == "20240101120000")
        #expect(obr.observationEndDateTime == "20240101130000")
        #expect(obr.observationDateTime == message["OBR-7"])
    }

    @Test("OBR-11 (ID scalar) specimen action code")
    func obrSpecimenActionCodeAgrees() throws {
        let (message, obr) = try hydratedMessage(OBR.self, from: obrWire)
        #expect(obr.specimenActionCode == "L")
        #expect(obr.specimenActionCode == message["OBR-11"])
    }

    @Test("OBR-14 (TS scalar) specimen received timestamp")
    func obrSpecimenReceivedAgrees() throws {
        let obr = try hydrated(OBR.self, from: obrWire)
        #expect(obr.specimenReceivedDateTime == "20240101115000")
    }

    @Test("OBR-16 (composite XCN repeats) ordering provider")
    func obrOrderingProviderAgrees() throws {
        let (message, obr) = try hydratedMessage(OBR.self, from: obrWire)
        let provider = try #require(obr.orderingProvider)
        // XCN layout: ID^family^given. XCN-1 (id) is empty in this
        // fixture; XCN-2 (familyName) is "Williams".
        #expect(provider.familyName == "Williams")
        #expect(message["OBR-16.2"] == "Williams")
    }

    @Test("OBR-20/21 (ST scalars) placer/filler text fields")
    func obrPlacerFillerFieldsAgree() throws {
        let obr = try hydrated(OBR.self, from: obrWire)
        #expect(obr.fillerField1 == "PLACER1")
        #expect(obr.fillerField2 == "FILLER1")
    }

    @Test("OBR-22 (TS scalar) results report status change date/time")
    func obrResultsReportStatusChangeAgrees() throws {
        let obr = try hydrated(OBR.self, from: obrWire)
        #expect(obr.resultsReportStatusChangeDateTime == "20240101140000")
    }

    @Test("OBR-25 (ID scalar) result status")
    func obrResultStatusAgrees() throws {
        let (message, obr) = try hydratedMessage(OBR.self, from: obrWire)
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
        let wire = TestWires.oru("PID|1||123456^^^HOSP^MR||Smith^John^A", "OBR|1|PLACER123^HOSP|FILLER456^LAB|GLU^Glucose^L", "OBX|1|NM|GLU^Glucose^L||5.2|mmol/L||N|||F")
        let (message, pid) = try hydratedMessage(PID.self, from: wire)
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
    private let extendedPIDWire = TestWires.adt("PID|1||123456^^^HOSP^MR||Smith^John^A||19800101|M||2106-3^White^HL70005|10 Main St^^Sydney^NSW^2000^AU||(02)555-1234||en^English^ISO639|M^Married^HL70002|CAT^Catholic^HL70006|ACC12345|||||Sydney||||||20231215120000|Y")

    @Test("PID-13 (XTN composite) home phone number")
    func pidHomePhoneAgrees() throws {
        let (message, pid) = try hydratedMessage(PID.self, from: extendedPIDWire)
        let phone = try #require(pid.phoneNumberHome)
        #expect(phone.telephoneNumber == "(02)555-1234")
        #expect(message["PID-13.1"] == "(02)555-1234")
    }

    @Test("PID-15/16/17 (CE composites) language / marital / religion")
    func pidCEComposites() throws {
        let pid = try hydrated(PID.self, from: extendedPIDWire)
        let language = try #require(pid.primaryLanguage)
        let marital = try #require(pid.maritalStatus)
        let religion = try #require(pid.religion)
        #expect(language.identifier == "en")
        #expect(marital.text == "Married")
        #expect(religion.identifier == "CAT")
    }

    @Test("PID-18 (CX) patient account number")
    func pidAccountNumberAgrees() throws {
        let (message, pid) = try hydratedMessage(PID.self, from: extendedPIDWire)
        let account = try #require(pid.patientAccountNumber)
        #expect(account.id == "ACC12345")
        #expect(account.id == message["PID-18.1"])
    }

    @Test("PID-23 (ST) birth place")
    func pidBirthPlaceAgrees() throws {
        let (message, pid) = try hydratedMessage(PID.self, from: extendedPIDWire)
        #expect(pid.birthPlace == "Sydney")
        #expect(pid.birthPlace == message["PID-23"])
    }

    @Test("PID-29/30 (TS + ID scalars) death date and indicator")
    func pidDeathFieldsAgree() throws {
        let pid = try hydrated(PID.self, from: extendedPIDWire)
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
    private let fringePIDWire = TestWires.adt("PID|1||123456^^^HOSP^MR||Smith^John^A||19800101|M||2106-3^White^HL70005|10 Main St^^Sydney^NSW^2000^AU||(02)555-1234||en^English^ISO639|M^Married^HL70002|CAT^Catholic^HL70006|ACC12345|||||Sydney||||||20231215120000|Y|N|US|20240301080000|HOSP^FAC^ISO|L1^Human^HL70447||||100^Australian^HL70171")

    @Test("PID-31 (ID scalar) identity unknown indicator")
    func pidIdentityUnknownIndicatorAgrees() throws {
        let (message, pid) = try hydratedMessage(PID.self, from: fringePIDWire)
        #expect(pid.identityUnknownIndicator == "N")
        #expect(pid.identityUnknownIndicator == message["PID-31"])
    }

    @Test("PID-32 (IS scalar) identity reliability code")
    func pidIdentityReliabilityCodeAgrees() throws {
        let (message, pid) = try hydratedMessage(PID.self, from: fringePIDWire)
        #expect(pid.identityReliabilityCode == "US")
        #expect(pid.identityReliabilityCode == message["PID-32"])
    }

    @Test("PID-33 (TS scalar) last update date/time")
    func pidLastUpdateDateTimeAgrees() throws {
        let (message, pid) = try hydratedMessage(PID.self, from: fringePIDWire)
        #expect(pid.lastUpdateDateTime == "20240301080000")
        #expect(pid.lastUpdateDateTime == message["PID-33"])
    }

    @Test("PID-34 (HD composite) last update facility")
    func pidLastUpdateFacilityAgrees() throws {
        let (message, pid) = try hydratedMessage(PID.self, from: fringePIDWire)
        let facility = try #require(pid.lastUpdateFacility)
        #expect(facility.namespaceID == "HOSP")
        #expect(facility.universalIDType == "ISO")
        #expect(message["PID-34.1"] == "HOSP")
        #expect(message["PID-34.3"] == "ISO")
    }

    @Test("PID-35 (CE composite) species code")
    func pidSpeciesCodeAgrees() throws {
        let (message, pid) = try hydratedMessage(PID.self, from: fringePIDWire)
        let species = try #require(pid.speciesCode)
        #expect(species.identifier == "L1")
        #expect(species.text == "Human")
        #expect(species.identifier == message["PID-35.1"])
        #expect(species.text == message["PID-35.2"])
    }

    @Test("PID-39 (CWE composite) tribal citizenship")
    func pidTribalCitizenshipAgrees() throws {
        let (message, pid) = try hydratedMessage(PID.self, from: fringePIDWire)
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
    private let nk1Wire = TestWires.adt("NK1|1|Smith^Mary|SPO^Spouse^HL70063|10 Main St^^Sydney^NSW^2000^AU|(02)555-1234|(02)555-5678||||Manager")

    @Test("NK1 hydrates as .typed")
    func nk1Hydrates() throws {
        let nk1 = try hydrated(NK1.self, from: nk1Wire)
        #expect(type(of: nk1).segmentID == "NK1")
    }

    @Test("NK1-1 (SI) set ID and NK1-10 (ST) job title scalars")
    func nk1ScalarsAgree() throws {
        let (message, nk1) = try hydratedMessage(NK1.self, from: nk1Wire)
        #expect(nk1.setID == "1")
        #expect(nk1.nextOfKinJobTitle == "Manager")
        #expect(nk1.setID == message["NK1-1"])
        #expect(nk1.nextOfKinJobTitle == message["NK1-10"])
    }

    @Test("NK1-2 (XPN) name and NK1-3 (CE) relationship composites")
    func nk1NameAndRelationshipAgree() throws {
        let (message, nk1) = try hydratedMessage(NK1.self, from: nk1Wire)
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
        let nk1 = try hydrated(NK1.self, from: nk1Wire)
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
    private let pv1Wire = TestWires.adt("PV1|1|I|WARD1^ROOM2^BED3^HOSPITAL|R|||DR123^Jones^Mary|||MED||||7||N|||V001")

    @Test("PV1 hydrates as .typed")
    func pv1Hydrates() throws {
        let pv1 = try hydrated(PV1.self, from: pv1Wire)
        #expect(type(of: pv1).segmentID == "PV1")
    }

    @Test("PV1-1/2/4 (SI + IS scalars) set ID, patient class, admit type")
    func pv1ClassAndAdmitAgree() throws {
        let (message, pv1) = try hydratedMessage(PV1.self, from: pv1Wire)
        #expect(pv1.setID == "1")
        #expect(pv1.patientClass == "I")
        #expect(pv1.admissionType == "R")
        #expect(pv1.patientClass == message["PV1-2"])
    }

    @Test("PV1-3 (PL composite) assigned patient location")
    func pv1LocationAgrees() throws {
        let (message, pv1) = try hydratedMessage(PV1.self, from: pv1Wire)
        let location = try #require(pv1.assignedPatientLocation)
        #expect(location.pointOfCare == "WARD1")
        #expect(location.room == "ROOM2")
        #expect(location.bed == "BED3")
        #expect(message["PV1-3.1"] == "WARD1")
    }

    @Test("PV1-7 (XCN composite repeats) attending doctor")
    func pv1AttendingDoctorAgrees() throws {
        let (message, pv1) = try hydratedMessage(PV1.self, from: pv1Wire)
        let doctor = try #require(pv1.attendingDoctor)
        #expect(doctor.idNumber == "DR123")
        #expect(doctor.familyName == "Jones")
        #expect(message["PV1-7.1"] == "DR123")
    }

    @Test("PV1-10/14/16 (IS scalars) hospital service, admit source, VIP indicator")
    func pv1AdminScalarsAgree() throws {
        let pv1 = try hydrated(PV1.self, from: pv1Wire)
        #expect(pv1.hospitalService == "MED")
        #expect(pv1.admitSource == "7")
        #expect(pv1.vipIndicator == "N")
    }

    @Test("PV1-19 (CX composite) visit number")
    func pv1VisitNumberAgrees() throws {
        let (message, pv1) = try hydratedMessage(PV1.self, from: pv1Wire)
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
        let wire = TestWires.adt("PID|1||123456^^^HOSP^MR||Smith^John^A||19800101|M", "PV1|1|I|WARD1^ROOM2^BED3|R|||DR123^Jones^Mary|||MED", "NK1|1|Smith^Mary|SPO^Spouse|10 Main St")
        let (message, pid) = try hydratedMessage(PID.self, from: wire)
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
        let (message, al1) = try hydratedMessage(AL1.self, from: al1Wire)
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
    private let evnWire = TestWires.adt("EVN|A01|20240320101500|||DOC123^Jones^Mary||HOSP^FAC^ISO")

    @Test("EVN hydrates as .typed")
    func evnHydrates() throws {
        let evn = try hydrated(EVN.self, from: evnWire)
        #expect(type(of: evn).segmentID == "EVN")
    }

    @Test("EVN-1 (ID) event type code + EVN-2 (TS) recorded date/time scalars")
    func evnScalarsAgree() throws {
        let (message, evn) = try hydratedMessage(EVN.self, from: evnWire)
        #expect(evn.eventTypeCode == "A01")
        #expect(evn.recordedDateTime == "20240320101500")
        #expect(evn.eventTypeCode == message["EVN-1"])
        #expect(evn.recordedDateTime == message["EVN-2"])
    }

    @Test("EVN-5 (XCN composite) operator ID + EVN-7 (HD composite) event facility")
    func evnCompositesAgree() throws {
        let (message, evn) = try hydratedMessage(EVN.self, from: evnWire)
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
        let msa = try hydrated(MSA.self, from: msaWire)
        #expect(type(of: msa).segmentID == "MSA")
    }

    @Test("MSA-1/2/3 (ID + ST scalars) ack code, control ID, text message")
    func msaScalarsAgree() throws {
        let (message, msa) = try hydratedMessage(MSA.self, from: msaWire)
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
        let err = try hydrated(ERR.self, from: errWire)
        #expect(type(of: err).segmentID == "ERR")
    }

    @Test("ERR-3 (CWE composite) HL7 error code + ERR-4 (ID) severity scalar")
    func errCoreFieldsAgree() throws {
        let (message, err) = try hydratedMessage(ERR.self, from: errWire)
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
        let fixtureURL = FixtureCorpus.fixtureURL(named: "ack_application_accept.hl7")
        let bytes = try Data(contentsOf: fixtureURL)
        let (message, msa) = try hydratedMessage(MSA.self, from: bytes)
        #expect(msa.acknowledgmentCode == "AA")
        // Fixture must still round-trip byte-perfectly post-T1.
        let rebuilt = message.serialize()
        #expect(rebuilt == bytes)
    }

    @Test("ack_application_error.hl7 hydrates MSA + ERR as typed")
    func ackErrorFixtureHydratesMSAAndERR() throws {
        let fixtureURL = FixtureCorpus.fixtureURL(named: "ack_application_error.hl7")
        let bytes = try Data(contentsOf: fixtureURL)
        let (message, msa) = try hydratedMessage(MSA.self, from: bytes)
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
    private let pd1Wire = TestWires.adt("PD1|||GOOD_HEALTH^L^1^^^HOSP^XX||N||Y|Y|N||N^Normal^HL70215|Y|20240101")

    @Test("PD1 hydrates as .typed")
    func pd1Hydrates() throws {
        let pd1 = try hydrated(PD1.self, from: pd1Wire)
        #expect(type(of: pd1).segmentID == "PD1")
    }

    @Test("PD1-3 (XON composite) patient primary facility + PD1-5 (IS) student indicator")
    func pd1PrimaryFacilityAndStudentAgree() throws {
        let (message, pd1) = try hydratedMessage(PD1.self, from: pd1Wire)
        let facility = try #require(pd1.patientPrimaryFacility)
        #expect(facility.organizationName == "GOOD_HEALTH")
        #expect(facility.organizationName == message["PD1-3.1"])
        #expect(pd1.studentIndicator == "N")
        #expect(pd1.studentIndicator == message["PD1-5"])
    }

    @Test("PD1-11 (CE composite) publicity code + PD1-12 (ID) protection indicator")
    func pd1PublicityAndProtectionAgree() throws {
        let pd1 = try hydrated(PD1.self, from: pd1Wire)
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
    private let dg1Wire = TestWires.adt("DG1|1||I10^Essential hypertension^ICD10||20240315090000|A|||||||||1|DR123^Jones^Mary")

    @Test("DG1 hydrates as .typed")
    func dg1Hydrates() throws {
        let dg1 = try hydrated(DG1.self, from: dg1Wire)
        #expect(type(of: dg1).segmentID == "DG1")
    }

    @Test("DG1-1 (SI) set ID + DG1-6 (IS) diagnosis type scalars")
    func dg1ScalarsAgree() throws {
        let (message, dg1) = try hydratedMessage(DG1.self, from: dg1Wire)
        #expect(dg1.setID == "1")
        #expect(dg1.diagnosisType == "A")
        #expect(dg1.setID == message["DG1-1"])
        #expect(dg1.diagnosisType == message["DG1-6"])
    }

    @Test("DG1-3 (CE composite) diagnosis code + DG1-5 (TS) diagnosis date")
    func dg1DiagnosisCodeAndDateAgree() throws {
        let (message, dg1) = try hydratedMessage(DG1.self, from: dg1Wire)
        let code = try #require(dg1.diagnosisCode)
        #expect(code.identifier == "I10")
        #expect(code.text == "Essential hypertension")
        #expect(code.nameOfCodingSystem == "ICD10")
        #expect(dg1.diagnosisDateTime == "20240315090000")
        #expect(code.identifier == message["DG1-3.1"])
    }

    @Test("DG1-15 (ID) diagnosis priority + DG1-16 (XCN composite) diagnosing clinician")
    func dg1PriorityAndClinicianAgree() throws {
        let (message, dg1) = try hydratedMessage(DG1.self, from: dg1Wire)
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
    private let in1Wire = TestWires.adt("IN1|1|HBF^Medibank Private^L|MED001|MEDIBANK PRIVATE|PO BOX 9999^^Sydney^NSW^2000^AU||(02)555-7777|GRP123|||N|20240101|20241231")

    @Test("IN1 hydrates as .typed")
    func in1Hydrates() throws {
        let in1 = try hydrated(IN1.self, from: in1Wire)
        #expect(type(of: in1).segmentID == "IN1")
    }

    @Test("IN1-1 (SI) set ID + IN1-2 (CE composite) insurance plan ID")
    func in1IdentityFieldsAgree() throws {
        let (message, in1) = try hydratedMessage(IN1.self, from: in1Wire)
        #expect(in1.setID == "1")
        let plan = try #require(in1.insurancePlanID)
        #expect(plan.identifier == "HBF")
        #expect(plan.text == "Medibank Private")
        #expect(plan.identifier == message["IN1-2.1"])
    }

    @Test("IN1-3 (CX composite) insurance company ID + IN1-4 (XON) company name")
    func in1CompanyAgree() throws {
        let (message, in1) = try hydratedMessage(IN1.self, from: in1Wire)
        let companyID = try #require(in1.insuranceCompanyID)
        let companyName = try #require(in1.insuranceCompanyName)
        #expect(companyID.id == "MED001")
        #expect(companyName.organizationName == "MEDIBANK PRIVATE")
        #expect(companyID.id == message["IN1-3.1"])
        #expect(companyName.organizationName == message["IN1-4.1"])
    }

    @Test("IN1-5 (XAD) company address + IN1-7 (XTN) phone")
    func in1AddressAndPhoneAgree() throws {
        let in1 = try hydrated(IN1.self, from: in1Wire)
        let address = try #require(in1.insuranceCompanyAddress)
        let phone = try #require(in1.insuranceCoPhoneNumber)
        #expect(address.streetAddress == "PO BOX 9999")
        #expect(address.city == "Sydney")
        #expect(phone.telephoneNumber == "(02)555-7777")
    }

    @Test("IN1-8 (ST) group number + IN1-12 (DT) plan effective date")
    func in1GroupAndDateAgree() throws {
        let in1 = try hydrated(IN1.self, from: in1Wire)
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
        let fixtureURL = FixtureCorpus.fixtureURL(named: "adt_a01_with_insurance.hl7")
        let bytes = try Data(contentsOf: fixtureURL)
        let (message, in1) = try hydratedMessage(IN1.self, from: bytes)
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
        let (message, seg) = try hydratedMessage(NK1.self, from: wire)
        #expect(seg.setID == "1")
        #expect(seg.contactPersonSocialSecurityNumber == "123-45-6789")   // NK1-37 (new)
        #expect(seg.contactPersonSocialSecurityNumber == message["NK1-37"])
    }

    // v1.1 (ADR-015): the extraction pipeline's golden audit against the v2.5.1 PDFs
    // caught 11 metadata defects + 2 incomplete segments in the pre-pipeline canonical
    // schemas. These pins guard the corrections so they can never silently regress.
    @Test("v1.1/v1.6: OBR completed to 50 fields, OBX to 25 (were 47 / 17)")
    func v1_1CompletedFieldCounts() {
        let table = SegmentGrammarTable.v2_5_1
        #expect(table["OBR"]?.fields.count == 50)
        // v1.6 depth audit: OBX is 25, not 24 — v1.1 added 18..24 but stopped one row
        // short of the v2.5.1 table. OBX-25 is Performing Organization Medical Director.
        #expect(table["OBX"]?.fields.count == 25)
        #expect(table["OBX"]?.field(25)?.dataType == "XCN")
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
        let (message, pv2) = try hydratedMessage(PV2.self, from: wire)
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
        let (message, rgs) = try hydratedMessage(RGS.self, from: wire)
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

    // v1.3 (M5 sweep, master-files/referral batch): MFI/MFE/MFA + OM1–OM7 (CH08),
    // RF1/AUT/PRD/CTD (CH11). Canonical v2.5.1 depths pinned + registry hydration.
    @Test("v1.3: master-files + referral segments — canonical depths + registration")
    func v1_3MasterFilesReferralCanonical() throws {
        let t = SegmentGrammarTable.v2_5_1
        #expect(t["MFI"]?.fields.count == 6)
        #expect(t["MFE"]?.fields.count == 5)
        #expect(t["MFA"]?.fields.count == 6)
        // v1.5 correction: OM1 47 / OM4 14 / OM6 2 are the true §8.8 depths. The earlier
        // 49 / 17 / 3 pins counted phantom rows the extractor produced from wrapped LEN
        // digits (OM6's "10240" split as a bare "0" row, etc.) — see the v1.5 hardening
        // note in docs/design/segment-coverage-extraction.md.
        #expect(t["OM1"]?.fields.count == 47)
        #expect(t["OM2"]?.fields.count == 10)
        #expect(t["OM3"]?.fields.count == 7)
        #expect(t["OM4"]?.fields.count == 14)
        #expect(t["OM5"]?.fields.count == 3)
        #expect(t["OM6"]?.fields.count == 2)
        #expect(t["OM7"]?.fields.count == 24)
        #expect(t["RF1"]?.fields.count == 11)
        #expect(t["AUT"]?.fields.count == 10)
        #expect(t["PRD"]?.fields.count == 9)
        #expect(t["CTD"]?.fields.count == 7)

        let wire = "MSH|^~\\&|A|B|C|D|20240101120000||MFN^M01|M1|P|2.5.1\r"
            + "MFI|CDM^^HL70175\r" + "MFE|MAD\r" + "MFA|MAA\r"
            + "OM1|1\r" + "OM2|1\r" + "OM3|1\r" + "OM4|1\r" + "OM5|1\r" + "OM6|1\r" + "OM7|1\r"
            + "RF1|P\r" + "AUT|A^^HL7\r" + "PRD|RP^^HL7\r" + "CTD|CN^^HL7\r"
        let (message, mfi) = try hydratedMessage(MFI.self, from: wire)
        #expect(mfi.masterFileIdentifier != nil)              // MFI-1 (CE) hydrates via typed accessor
        for present in [message.firstSegment(MFE.self) != nil, message.firstSegment(MFA.self) != nil,
                        message.firstSegment(OM1.self) != nil, message.firstSegment(OM7.self) != nil,
                        message.firstSegment(RF1.self) != nil, message.firstSegment(AUT.self) != nil,
                        message.firstSegment(PRD.self) != nil, message.firstSegment(CTD.self) != nil] {
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
        let (message, tq1) = try hydratedMessage(TQ1.self, from: wire)
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

    // v1.4 (M5 sweep, query/lab batch): QPD/QRD/QRF/QAK/QID/RCP/RDF/RDT (CH05) +
    // EQU/SAC/INV/TCC/TCD/EQP (CH13). Canonical depths + registry hydration.
    @Test("v1.4: query + lab-automation segments — canonical depths + registration")
    func v1_4QueryLabCanonical() throws {
        let t = SegmentGrammarTable.v2_5_1
        #expect(t["QPD"]?.fields.count == 2)
        #expect(t["QRD"]?.fields.count == 12)
        #expect(t["QRF"]?.fields.count == 10)
        #expect(t["QAK"]?.fields.count == 6)
        #expect(t["QID"]?.fields.count == 2)
        #expect(t["RCP"]?.fields.count == 7)
        #expect(t["RDF"]?.fields.count == 2)
        #expect(t["RDT"]?.fields.count == 1)
        #expect(t["EQU"]?.fields.count == 5)
        #expect(t["SAC"]?.fields.count == 44)
        #expect(t["INV"]?.fields.count == 20)
        #expect(t["TCC"]?.fields.count == 14)
        #expect(t["TCD"]?.fields.count == 8)
        #expect(t["EQP"]?.fields.count == 5)   // v1.5: was 6 — phantom row from wrapped LEN "65536"
        // v1.5: RDT is a "1-n" variable-column segment (§5.5.8) — one spec-defined field.
        // Pinned by identity, not just count: the pre-v1.5 schema also had exactly one
        // field, but it was extractor garbage (name "", dataType "s").
        let rdt1 = try #require(t["RDT"]?.fields.first)
        #expect(rdt1.index == 1)
        #expect(rdt1.name == "Column Value")
        #expect(rdt1.dataType == "varies")
        #expect(rdt1.optionality == .required)
        // Lab-automation segments are v2.4+ (CH13 starts at v2.4) — absent on v2.3.
        // The v2.4 tables themselves are pinned by the Sprint 0 test below.
        #expect(SegmentGrammarTable.v2_3["SAC"] == nil)
        // v2.3 query segments live in CH2 (CH5 is an empty placeholder in v2.3).
        #expect(SegmentGrammarTable.v2_3["QRD"]?.fields.count == 12)

        let wire = "MSH|^~\\&|A|B|C|D|20240101120000||QBP^Q11|M1|P|2.5.1\r"
            + "QPD|Q^^HL7|tag1\r" + "RCP|I\r"
            + "QRD|20240101120000\r" + "QRF|X\r" + "QAK|tag1|OK\r" + "QID|q1\r"
            + "RDF|1\r" + "RDT|v\r"
            + "EQU|E1\r" + "SAC|AC1\r" + "INV|I1\r" + "TCC|T1\r" + "TCD|T1\r" + "EQP|EV\r"
        let (message, qrd) = try hydratedMessage(QRD.self, from: wire)
        #expect(qrd.queryDateTime == message["QRD-1"])
        for present in [message.firstSegment(QPD.self) != nil, message.firstSegment(RCP.self) != nil,
                        message.firstSegment(QRF.self) != nil, message.firstSegment(QAK.self) != nil,
                        message.firstSegment(QID.self) != nil, message.firstSegment(RDF.self) != nil,
                        message.firstSegment(RDT.self) != nil, message.firstSegment(EQU.self) != nil,
                        message.firstSegment(SAC.self) != nil, message.firstSegment(INV.self) != nil,
                        message.firstSegment(TCC.self) != nil, message.firstSegment(TCD.self) != nil,
                        message.firstSegment(EQP.self) != nil] {
            #expect(present)
        }
    }

    // v1.7 (M5 sweep): CH13 clinical-lab-automation completion — ISD/NDS/CNS/ECD/ECR/SID.
    // CH13 was introduced in v2.4, so these six exist on v2.4/v2.5.1/v2.6/v2.8.2 only;
    // v2.3 and v2.3.1 have no CH13 at all. Depths are identical across those four
    // versions, but the datatypes are NOT — this pins the divergence so a future
    // regeneration can't silently converge them (the v1.6 lesson).
    @Test("v1.7: CH13 lab-automation segments — depths, registration, per-version datatypes")
    func v1_7LabAutomationCanonical() throws {
        let t = SegmentGrammarTable.v2_5_1
        #expect(t["ISD"]?.fields.count == 3)
        #expect(t["NDS"]?.fields.count == 4)
        #expect(t["CNS"]?.fields.count == 6)
        #expect(t["ECD"]?.fields.count == 5)
        #expect(t["ECR"]?.fields.count == 3)
        #expect(t["SID"]?.fields.count == 4)
        // CH13 is v2.4+ — absent from the two legacy dialects.
        #expect(SegmentGrammarTable.v2_3["ISD"] == nil)
        #expect(SegmentGrammarTable.v2_3_1["SID"] == nil)
        #expect(SegmentGrammarTable.v2_4["ISD"]?.fields.count == 3)

        // Per-version datatype promotions: CE → CWE and TS → DTM in v2.6.
        #expect(t["NDS"]?.field(2)?.dataType == "TS")
        #expect(SegmentGrammarTable.v2_6["NDS"]?.field(2)?.dataType == "DTM")
        #expect(t["NDS"]?.field(3)?.dataType == "CE")
        #expect(SegmentGrammarTable.v2_6["NDS"]?.field(3)?.dataType == "CWE")
        // ECR-3 Command Response Parameters is ST in v2.4, widened to TX in v2.5.1.
        #expect(SegmentGrammarTable.v2_4["ECR"]?.field(3)?.dataType == "ST")
        #expect(t["ECR"]?.field(3)?.dataType == "TX")
        // ECD-4 Requested Completion Time: O (v2.4) → B (v2.5.1) → withdrawn in v2.8.2,
        // where it correctly carries NO datatype (the v1.5 "empty DT is fine when W/X" rule).
        #expect(SegmentGrammarTable.v2_4["ECD"]?.field(4)?.optionality == .optional)
        #expect(t["ECD"]?.field(4)?.optionality == .backwardCompat)
        #expect(SegmentGrammarTable.v2_8_2["ECD"]?.field(4)?.optionality == .withdrawn)
        #expect(SegmentGrammarTable.v2_8_2["ECD"]?.field(4)?.dataType == "")
        // Per-version element-name divergence — v2.6 dropped ISD-1's parenthetical and
        // closed up SID-1's spacing. Verified in the v2.6 CH13 attribute table.
        #expect(t["ISD"]?.field(1)?.name == "Reference Interaction Number (unique identifier)")
        #expect(SegmentGrammarTable.v2_6["ISD"]?.field(1)?.name == "Reference Interaction Number")
        #expect(t["SID"]?.field(1)?.name == "Application / Method Identifier")
        #expect(SegmentGrammarTable.v2_6["SID"]?.field(1)?.name == "Application/Method Identifier")

        let wire = "MSH|^~\\&|A|B|C|D|20240101120000||ORU^R01|M1|P|2.5.1\r"
            + "ISD|1||ACTIVE^^HL70387\r" + "NDS|1|20240101120000|W^^HL70367|N1^^HL7\r"
            + "CNS|1|9\r" + "ECD|1|CMD^^HL70368|Y\r" + "ECR|OK^^HL70387|20240101120000\r"
            + "SID|M1^^HL7|LOT9|C7|MFR^^HL70385\r"
        let (message, sid) = try hydratedMessage(SID.self, from: wire)
        #expect(sid.substanceLotNumber == message["SID-2"])          // typed accessor == path
        #expect(sid.applicationMethodIdentifier?.identifier == "M1")  // CE composite view
        for present in [message.firstSegment(ISD.self) != nil, message.firstSegment(NDS.self) != nil,
                        message.firstSegment(CNS.self) != nil, message.firstSegment(ECD.self) != nil,
                        message.firstSegment(ECR.self) != nil] {
            #expect(present)
        }
    }

    // Sprint 0 (v2.x coverage): the v2.4 lab-automation PRESENCE defect. v1.4 authored
    // EQU/SAC/INV/TCC/TCD/EQP as "v2.5+", but v2.4 CH13 defines all six — ~94 fields missing
    // from the AU-critical version. A depth-only audit never sees an ABSENT segment; the
    // presence predicate in scripts/audit-schemas.py now does. Divergences below were read
    // from the v2.4 CH13 attribute tables, not inferred from v2.5.1.
    @Test("Sprint 0: v2.4 lab-automation segments — presence, depths, per-version divergence")
    func sprint0V2_4LabAutomationPresence() throws {
        let t = SegmentGrammarTable.v2_4
        let c = SegmentGrammarTable.v2_5_1
        #expect(t["EQU"]?.fields.count == 5)
        #expect(t["SAC"]?.fields.count == 44)
        #expect(t["INV"]?.fields.count == 18)   // v2.5.1 adds INV-19/20
        #expect(t["INV"]?.field(19) == nil)
        #expect(t["TCC"]?.fields.count == 14)
        #expect(t["TCD"]?.fields.count == 8)
        #expect(t["EQP"]?.fields.count == 5)
        // CH13 starts at v2.4 — absent from both legacy dialects.
        #expect(SegmentGrammarTable.v2_3["EQU"] == nil)
        #expect(SegmentGrammarTable.v2_3_1["SAC"] == nil)
        // v2.4-era datatypes: CM where v2.5.1 has SPS, CE where it has CWE; no B/C flags yet.
        #expect(t["SAC"]?.field(6)?.dataType == "CM")
        #expect(t["SAC"]?.field(6)?.optionality == .optional)
        #expect(c["SAC"]?.field(6)?.dataType == "SPS")
        #expect(c["SAC"]?.field(6)?.optionality == .conditional)
        #expect(t["SAC"]?.field(27)?.dataType == "CE")
        #expect(t["SAC"]?.field(43)?.dataType == "CE")
        #expect(t["TCC"]?.field(3)?.dataType == "CM")
        #expect(t["TCC"]?.field(3)?.optionality == .optional)
        #expect(c["TCC"]?.field(3)?.optionality == .backwardCompat)
        #expect(t["INV"]?.field(14)?.optionality == .optional)
        #expect(c["INV"]?.field(14)?.optionality == .backwardCompat)
        // Per-version element names — taken from v2.4's own table, never copied.
        #expect(t["SAC"]?.field(22)?.name == "Available Volume")
        #expect(c["SAC"]?.field(22)?.name == "Available Specimen Volume")
        #expect(t["SAC"]?.field(43)?.name == "Special Handling Considerations")
        #expect(c["SAC"]?.field(43)?.name == "Special Handling Code")
    }

    // Sprint 0 §3, batch CH15 (personnel management): STF/PRA/ORG/AFF/LAN/EDU authored on
    // v2.4 (Tier 1) and v2.5.1 (canonical — typed structs are emitted from v2.5.1 only) from
    // each version's own attribute table. v2.3/v2.3.1 follow in their own sprint. CER is
    // v2.5+ and is NOT a v2.4 segment (the sprint plan's CH15 list was wrong about that).
    @Test("Sprint 0 §3 CH15: STF/PRA/ORG/AFF/LAN/EDU — depths, registration, per-version divergence")
    func sprint0Ch15Personnel() throws {
        let c = SegmentGrammarTable.v2_5_1
        let t = SegmentGrammarTable.v2_4
        #expect(c["STF"]?.fields.count == 38)
        #expect(c["PRA"]?.fields.count == 12)
        #expect(c["ORG"]?.fields.count == 12)
        #expect(c["AFF"]?.fields.count == 5)
        #expect(c["LAN"]?.fields.count == 4)
        #expect(c["EDU"]?.fields.count == 9)
        // v2.4 is shallower on STF (29) and EDU (8); the other four are depth-identical.
        #expect(t["STF"]?.fields.count == 29)
        #expect(t["STF"]?.field(30) == nil)
        #expect(t["EDU"]?.fields.count == 8)
        #expect(t["PRA"]?.fields.count == 12)
        #expect(t["ORG"]?.fields.count == 12)
        #expect(t["AFF"]?.fields.count == 5)
        #expect(t["LAN"]?.fields.count == 4)
        // STF/PRA also exist in v2.3 / v2.3.1 (CH8 there); the other four are v2.4+.
        let l = SegmentGrammarTable.v2_3
        #expect(l["STF"]?.fields.count == 26)
        #expect(SegmentGrammarTable.v2_3_1["STF"]?.fields.count == 26)
        #expect(l["PRA"]?.fields.count == 8)
        #expect(SegmentGrammarTable.v2_3_1["PRA"]?.fields.count == 8)
        #expect(l["ORG"] == nil)
        #expect(SegmentGrammarTable.v2_3_1["EDU"] == nil)
        // STF-1 was R in v2.3, C from v2.4; STF-3 repeats only from v2.3.1; STF-16/17 were
        // ID/IS in v2.3 and CE from v2.3.1.
        #expect(l["STF"]?.field(1)?.optionality == .required)
        #expect(t["STF"]?.field(1)?.optionality == .conditional)
        #expect(l["STF"]?.field(3)?.repeatability == .single)
        #expect(SegmentGrammarTable.v2_3_1["STF"]?.field(3)?.repeatability == .multiple)
        #expect(l["STF"]?.field(16)?.dataType == "ID")
        #expect(l["STF"]?.field(17)?.dataType == "IS")
        #expect(SegmentGrammarTable.v2_3_1["STF"]?.field(16)?.dataType == "CE")
        #expect(l["STF"]?.field(9)?.name == "Service")
        // PRA-1: ST/R (v2.3) → CE/R (v2.3.1) → CE/C (v2.4+); PRA-9..12 are v2.4+.
        #expect(l["PRA"]?.field(1)?.dataType == "ST")
        #expect(SegmentGrammarTable.v2_3_1["PRA"]?.field(1)?.dataType == "CE")
        #expect(SegmentGrammarTable.v2_3_1["PRA"]?.field(1)?.optionality == .required)
        #expect(t["PRA"]?.field(1)?.optionality == .conditional)
        #expect(l["PRA"]?.field(9) == nil)
        // v2.4-era datatypes: CM where v2.5.1 has the named composites.
        #expect(t["STF"]?.field(12)?.dataType == "CM")
        #expect(c["STF"]?.field(12)?.dataType == "DIN")
        #expect(t["PRA"]?.field(5)?.dataType == "CM")
        #expect(c["PRA"]?.field(5)?.dataType == "SPD")
        #expect(c["PRA"]?.field(6)?.dataType == "PLN")
        #expect(c["PRA"]?.field(7)?.dataType == "PIP")
        // PRA-6 became B in v2.5.1; O in v2.4.
        #expect(t["PRA"]?.field(6)?.optionality == .optional)
        #expect(c["PRA"]?.field(6)?.optionality == .backwardCompat)
        // Per-version element names, from each version's own table.
        #expect(t["STF"]?.field(2)?.name == "Staff ID Code")
        #expect(c["STF"]?.field(2)?.name == "Staff Identifier List")
        #expect(t["STF"]?.field(11)?.name == "Office/Home Address")
        #expect(c["STF"]?.field(11)?.name == "Office/Home Address/Birthplace")
        // v2.4 EDU spec defects, normalised (recorded in segment-coverage-extraction.md):
        // EDU-2's OPT cell is blank in the PDF (v2.5.1: O); EDU-4's name is set
        // "ParticipationDate" in the table but spaced in its own definition heading.
        #expect(t["EDU"]?.field(2)?.optionality == .optional)
        #expect(t["EDU"]?.field(4)?.name == "Academic Degree Program Participation Date Range")

        let wire = "MSH|^~\\&|A|B|C|D|20240101120000||MFN^M02|M1|P|2.5.1\r"
            + "STF|S1^^HL7|ID1|Smith^J||F||A|||||||||||Registrar\r"
            + "PRA|P1^^HL7||||||||||\r" + "ORG|1|OU1^^HL7\r" + "AFF|1|Org^^HL7\r"
            + "LAN|1|en^English^ISO639\r" + "EDU|1|MD\r"
        let (message, stf) = try hydratedMessage(STF.self, from: wire)
        #expect(stf.jobTitle == message["STF-18"])              // typed accessor == path
        #expect(stf.jobTitle == "Registrar")
        let edu = try #require(message.firstSegment(EDU.self))
        #expect(edu.academicDegree == "MD")
        for present in [message.firstSegment(PRA.self) != nil, message.firstSegment(ORG.self) != nil,
                        message.firstSegment(AFF.self) != nil, message.firstSegment(LAN.self) != nil] {
            #expect(present)
        }
    }

    // Sprint 0 §3, batch CH04 (orders): BLG/ODS/ODT/RQ1/RQD on every AU-priority version
    // (v2.3 / v2.3.1 / v2.4 / v2.5.1). BLG lives in CH04, not CH06 — the segment v1.9
    // deliberately left out of the financial sweep.
    @Test("Sprint 0 §3 CH04: BLG/ODS/ODT/RQ1/RQD — depths, registration, per-version divergence")
    func sprint0Ch04Orders() throws {
        let c = SegmentGrammarTable.v2_5_1
        for (id, depth) in [("BLG", 4), ("ODS", 4), ("ODT", 3), ("RQ1", 7), ("RQD", 10)] {
            #expect(c[id]?.fields.count == depth, "v2.5.1 \(id)")
        }
        // Identical depth on v2.3 / v2.3.1 / v2.4 except BLG (3 — BLG-4 Charge Type Reason
        // is v2.5+); BLG-1 is CM before v2.5.1's CCD.
        for t in [SegmentGrammarTable.v2_3, SegmentGrammarTable.v2_3_1, SegmentGrammarTable.v2_4] {
            #expect(t["BLG"]?.fields.count == 3)
            #expect(t["BLG"]?.field(1)?.dataType == "CM")
            #expect(t["ODS"]?.fields.count == 4)
            #expect(t["ODT"]?.fields.count == 3)
            #expect(t["RQ1"]?.fields.count == 7)
            #expect(t["RQD"]?.fields.count == 10)
        }
        #expect(c["BLG"]?.field(1)?.dataType == "CCD")
        #expect(c["BLG"]?.field(4)?.dataType == "CWE")
        // BLG-3 Account ID is the legacy CK in v2.3 only; CX from v2.3.1.
        #expect(SegmentGrammarTable.v2_3["BLG"]?.field(3)?.dataType == "CK")
        #expect(SegmentGrammarTable.v2_3_1["BLG"]?.field(3)?.dataType == "CX")
        // RQ1-2's name drifts every version: "Manufactured ID" → "Manufacturer ID" →
        // "Manufacturer Identifier" (v2.4 and v2.5.1). Each from its own table.
        #expect(SegmentGrammarTable.v2_3["RQ1"]?.field(2)?.name == "Manufactured ID")
        #expect(SegmentGrammarTable.v2_3_1["RQ1"]?.field(2)?.name == "Manufacturer ID")
        #expect(SegmentGrammarTable.v2_4["RQ1"]?.field(2)?.name == "Manufacturer Identifier")

        let wire = "MSH|^~\\&|A|B|C|D|20240101120000||OMD^O03|M1|P|2.5.1\r"
            + "ODS|D|AM^^HL7|LOW^^HL7|no salt\r" + "ODT|TRAY^^HL7||text\r"
            + "BLG|D|CH|ACC1\r" + "RQ1|9.99\r" + "RQD|1|IC1^^HL7\r"
        let (message, ods) = try hydratedMessage(ODS.self, from: wire)
        #expect(ods.textInstruction == message["ODS-4"])
        #expect(ods.type == "D")
        let blg = try #require(message.firstSegment(BLG.self))
        #expect(blg.chargeType == "CH")
        for present in [message.firstSegment(ODT.self) != nil, message.firstSegment(RQ1.self) != nil,
                        message.firstSegment(RQD.self) != nil] {
            #expect(present)
        }
    }

    // Sprint 0 §3, batch CH02 (control / envelopes): BHS/FHS/BTS/FTS/DSC/ADD on every
    // AU-priority version. BatchParser / StreamingBatchParser have framed FHS/BHS/BTS/FTS
    // since v0.3 with NO schemas behind them — this closes that parser/schema coherence gap.
    // ADD-1 is a `1-n` row (like RDT-1): hand-authored, whitelisted in the depth audit.
    @Test("Sprint 0 §3 CH02: BHS/FHS/BTS/FTS/DSC/ADD — depths, registration, per-version divergence")
    func sprint0Ch02Envelopes() throws {
        let c = SegmentGrammarTable.v2_5_1
        let all = [SegmentGrammarTable.v2_3, SegmentGrammarTable.v2_3_1, SegmentGrammarTable.v2_4, c]
        for t in all {
            #expect(t["BHS"]?.fields.count == 12)
            #expect(t["FHS"]?.fields.count == 12)
            #expect(t["BTS"]?.fields.count == 3)
            #expect(t["FTS"]?.fields.count == 2)
            #expect(t["ADD"]?.fields.count == 1)
            #expect(t["ADD"]?.field(1)?.dataType == "ST")
        }
        // DSC-2 Continuation Style is v2.4+.
        #expect(SegmentGrammarTable.v2_3["DSC"]?.fields.count == 1)
        #expect(SegmentGrammarTable.v2_3_1["DSC"]?.fields.count == 1)
        #expect(SegmentGrammarTable.v2_4["DSC"]?.fields.count == 2)
        #expect(c["DSC"]?.fields.count == 2)
        // The four sending/receiving application/facility fields are ST through v2.4 and
        // HD from v2.5.1 — on both envelopes.
        for idx in 3...6 {
            #expect(SegmentGrammarTable.v2_4["BHS"]?.field(idx)?.dataType == "ST")
            #expect(c["BHS"]?.field(idx)?.dataType == "HD")
            #expect(SegmentGrammarTable.v2_4["FHS"]?.field(idx)?.dataType == "ST")
            #expect(c["FHS"]?.field(idx)?.dataType == "HD")
        }
        #expect(c["BHS"]?.field(1)?.optionality == .required)
        #expect(c["BTS"]?.field(3)?.repeatability == .multiple)

        let wire = "MSH|^~\\&|A|B|C|D|20240101120000||ADT^A01|M1|P|2.5.1\r"
            + "DSC|PTR1|I\r" + "ADD|more text\r"
            + "BHS|^~\\&|A|B|C|D|20240101120000||batch1||CTRL9\r" + "BTS|1|done\r"
            + "FHS|^~\\&|A|B|C|D|20240101120000||file1||FCTRL\r" + "FTS|1|end\r"
        let (message, dsc) = try hydratedMessage(DSC.self, from: wire)
        #expect(dsc.continuationPointer == message["DSC-1"])
        #expect(dsc.continuationStyle == "I")
        // BHS-1 / FHS-1 are the field separator and BHS-2 / FHS-2 the encoding characters,
        // exactly like MSH-1/2 — so the parser applies the same rule, and the serialiser
        // mirrors it (the wire must round-trip byte-for-byte).
        let bhs = try #require(message.firstSegment(BHS.self))
        #expect(bhs.batchControlId == "CTRL9")
        #expect(message["BHS-1"] == "|")
        #expect(message["BHS-2"] == "^~\\&")
        #expect(message["FHS-3"] == "A")
        #expect(message["FHS-11"] == "FCTRL")
        #expect(String(decoding: message.serialize(), as: UTF8.self) == wire)
        let add = try #require(message.firstSegment(ADD.self))
        #expect(add.addendumContinuationPointer == "more text")
        for present in [message.firstSegment(BTS.self) != nil, message.firstSegment(FHS.self) != nil,
                        message.firstSegment(FTS.self) != nil] {
            #expect(present)
        }
    }

    // Sprint 0 §3, batch CH05 (the v2.3-era query family): DSP/EQL/ERQ/SPR/URD/URS/VTQ on
    // every AU-priority version (they live in CH2 in v2.3 / v2.3.1) and QRI (v2.4+). SPR is
    // the segment whose table was wrongly committed as RDT before v1.5-S1 — now authored
    // under its own caption. All depths and datatypes are identical across the four versions;
    // the only cross-version delta was a PDF "Query/ Response" spacing artifact, normalised.
    @Test("Sprint 0 §3 CH05: DSP/EQL/ERQ/QRI/SPR/URD/URS/VTQ — depths, registration, QRI is v2.4+")
    func sprint0Ch05Queries() throws {
        let depths = [("DSP", 5), ("EQL", 4), ("ERQ", 3), ("SPR", 4), ("URD", 7), ("URS", 9), ("VTQ", 5)]
        for t in [SegmentGrammarTable.v2_3, SegmentGrammarTable.v2_3_1,
                  SegmentGrammarTable.v2_4, SegmentGrammarTable.v2_5_1] {
            for (id, depth) in depths {
                #expect(t[id]?.fields.count == depth, "\(id)")
            }
            #expect(t["SPR"]?.field(2)?.name == "Query/Response Format Code")
            #expect(t["SPR"]?.field(4)?.dataType == "QIP")
        }
        #expect(SegmentGrammarTable.v2_3["QRI"] == nil)
        #expect(SegmentGrammarTable.v2_3_1["QRI"] == nil)
        #expect(SegmentGrammarTable.v2_4["QRI"]?.fields.count == 3)
        #expect(SegmentGrammarTable.v2_5_1["QRI"]?.fields.count == 3)

        let wire = "MSH|^~\\&|A|B|C|D|20240101120000||VQQ^Q07|M1|P|2.5.1\r"
            + "VTQ|tag1|T|VQ1^^HL7|VT1^^HL7\r" + "SPR|tag1|T|SP1^^HL7\r" + "EQL|tag1|T|EQ1^^HL7|select *\r"
            + "ERQ|tag1|EV1^^HL7\r" + "URD||R\r" + "URS|ALL\r" + "DSP|1||line one\r" + "QRI|95\r"
        let (message, vtq) = try hydratedMessage(VTQ.self, from: wire)
        #expect(vtq.queryResponseFormatCode == message["VTQ-2"])
        #expect(vtq.queryTag == "tag1")
        let urd = try #require(message.firstSegment(URD.self))
        #expect(urd.ruWhatSubjectDefinition == nil)        // hand-tuned name: ruX, not rUX
        #expect(urd.reportPriority == "R")
        let dsp = try #require(message.firstSegment(DSP.self))
        #expect(dsp.dataLine == "line one")
        for present in [message.firstSegment(SPR.self) != nil, message.firstSegment(EQL.self) != nil,
                        message.firstSegment(ERQ.self) != nil, message.firstSegment(URS.self) != nil,
                        message.firstSegment(QRI.self) != nil] {
            #expect(present)
        }
    }

    // Sprint 0 §3, batch E (CH03 admin + CH06 financial + CH07): IAM/NPU/PDA + BLC/RMI + FAC.
    // IAM/PDA/BLC/RMI are v2.4+; NPU and FAC exist on all four AU-priority versions.
    // IAM (adverse reactions) is the AU-relevant ADT segment the batch is sequenced around.
    @Test("Sprint 0 §3 E: IAM/NPU/PDA/BLC/RMI/FAC — depths, registration, per-version divergence")
    func sprint0BatchEAdminFinancialFacility() throws {
        let c = SegmentGrammarTable.v2_5_1
        let t = SegmentGrammarTable.v2_4
        for table in [t, c] {
            #expect(table["IAM"]?.fields.count == 20)
            #expect(table["PDA"]?.fields.count == 9)
            #expect(table["BLC"]?.fields.count == 2)
            #expect(table["RMI"]?.fields.count == 3)
        }
        for table in [SegmentGrammarTable.v2_3, SegmentGrammarTable.v2_3_1, t, c] {
            #expect(table["NPU"]?.fields.count == 2)
            #expect(table["FAC"]?.fields.count == 12)
            #expect(table["FAC"]?.field(5)?.optionality == .optional)
            #expect(table["FAC"]?.field(5)?.repeatability == .multiple)
        }
        #expect(SegmentGrammarTable.v2_3["IAM"] == nil)
        #expect(SegmentGrammarTable.v2_3_1["PDA"] == nil)
        // IAM-7 Allergy Unique Identifier: R in v2.4, relaxed to C in v2.5.1.
        #expect(t["IAM"]?.field(7)?.optionality == .required)
        #expect(c["IAM"]?.field(7)?.optionality == .conditional)
        // v2.3 FAC: FAC-1 is plain "Facility ID"; FAC-3/-9/-11 are single (repeat from
        // v2.3.1). FAC-5..8 are O + repeating — the wrapped "RP/" header hid that column
        // from the extractor until the Sprint 0 header-key fix.
        #expect(SegmentGrammarTable.v2_3["FAC"]?.field(1)?.name == "Facility ID")
        #expect(SegmentGrammarTable.v2_3_1["FAC"]?.field(1)?.name == "Facility ID-FAC")
        #expect(SegmentGrammarTable.v2_3["FAC"]?.field(3)?.repeatability == .single)
        #expect(SegmentGrammarTable.v2_3_1["FAC"]?.field(3)?.repeatability == .multiple)
        #expect(SegmentGrammarTable.v2_3["FAC"]?.field(9)?.repeatability == .single)

        let wire = "MSH|^~\\&|A|B|C|D|20240101120000||ADT^A60|M1|P|2.5.1\r"
            + "IAM|1|DA^^HL70127|PCN^^ATC|SV^^HL70128||A^^HL70323|EI1\r"
            + "NPU|W^201^1\r" + "PDA|C10^^I10\r" + "BLC|WBL^^HL70426|1^unit\r"
            + "RMI|INC1^^HL7|20240101120000|TYPE1^^HL7\r"
            + "FAC|F1^^HL7|A|1 Main St^^Town^ST^0000|555-0100|||||AUTH^Signer\r"
        let (message, iam) = try hydratedMessage(IAM.self, from: wire)
        #expect(iam.allergyUniqueIdentifier?.entityIdentifier == message["IAM-7"])   // EI composite view
        #expect(iam.setIdIam == "1")
        let fac = try #require(message.firstSegment(FAC.self))
        #expect(fac.facilityType == "A")
        for present in [message.firstSegment(NPU.self) != nil, message.firstSegment(PDA.self) != nil,
                        message.firstSegment(BLC.self) != nil, message.firstSegment(RMI.self) != nil] {
            #expect(present)
        }
    }

    // v1.8 (M5 sweep): CH07 completion — the product-experience family
    // (PES/PEO/PCR/PDC/PSH) and the clinical-trials family (CSR/CSP/CSS/CTI). All nine
    // exist on every supported version at the SAME depth, so the divergence is entirely
    // in datatypes and element names — exactly what a depth-only check would miss.
    @Test("v1.8: CH07 product-experience + clinical-trials — depths, registration, divergence")
    func v1_8ProductExperienceClinicalTrials() throws {
        let t = SegmentGrammarTable.v2_5_1
        #expect(t["PES"]?.fields.count == 13)
        #expect(t["PEO"]?.fields.count == 25)
        #expect(t["PCR"]?.fields.count == 23)
        #expect(t["PDC"]?.fields.count == 15)
        #expect(t["PSH"]?.fields.count == 14)
        #expect(t["CSR"]?.fields.count == 16)
        #expect(t["CSP"]?.fields.count == 4)
        #expect(t["CSS"]?.fields.count == 3)
        #expect(t["CTI"]?.fields.count == 3)
        // Present on all six versions at identical depth.
        for table in [SegmentGrammarTable.v2_3, SegmentGrammarTable.v2_3_1,
                      SegmentGrammarTable.v2_4, SegmentGrammarTable.v2_6,
                      SegmentGrammarTable.v2_8_2] {
            #expect(table["PEO"]?.fields.count == 25)
            #expect(table["CSR"]?.fields.count == 16)
        }

        // TS → DTM in v2.6 (CSR-6 Date/Time of Patient Study Registration).
        #expect(t["CSR"]?.field(6)?.dataType == "TS")
        #expect(SegmentGrammarTable.v2_6["CSR"]?.field(6)?.dataType == "DTM")
        // v2.3 spec typo, faithfully rendered: PDC-14/15 say "Marked", corrected to
        // "Marketed" in v2.4. The attribute table AND the definition heading agree, so
        // this is the spec's own error, not an extraction artifact.
        #expect(SegmentGrammarTable.v2_3["PDC"]?.field(14)?.name == "Date First Marked")
        #expect(SegmentGrammarTable.v2_4["PDC"]?.field(14)?.name == "Date First Marketed")
        // Renames: CTI-1 shortened after v2.3; PEO-14 gained "Description" in v2.6.
        #expect(SegmentGrammarTable.v2_3["CTI"]?.field(1)?.name == "Sponsor Study Identifier")
        #expect(t["CTI"]?.field(1)?.name == "Sponsor Study ID")
        #expect(t["PEO"]?.field(14)?.name == "Event From Original Reporter")
        #expect(SegmentGrammarTable.v2_6["PEO"]?.field(14)?.name == "Event Description from Original Reporter")

        let wire = "MSH|^~\\&|A|B|C|D|20240101120000||PEX^P07|M1|P|2.5.1\r"
            + "PES|S1\r" + "PEO|E1^^HL7\r" + "PCR|P1^^HL7\r" + "PDC|M1^^HL7\r" + "PSH|R1\r"
            + "CSR|ST1\r" + "CSP|PH1^^HL7\r" + "CSS|TP1^^HL7\r" + "CTI|ST1\r"
        let (message, csr) = try hydratedMessage(CSR.self, from: wire)
        #expect(csr.sponsorStudyId != nil)                 // CSR-1 (EI) hydrates
        for present in [message.firstSegment(PES.self) != nil, message.firstSegment(PEO.self) != nil,
                        message.firstSegment(PCR.self) != nil, message.firstSegment(PDC.self) != nil,
                        message.firstSegment(PSH.self) != nil, message.firstSegment(CSP.self) != nil,
                        message.firstSegment(CSS.self) != nil, message.firstSegment(CTI.self) != nil] {
            #expect(present)
        }
    }

    // v1.9 (M5 sweep): CH06 financial completion — FT1/PR1/ACC/UB1/UB2/DRG (all six
    // versions) + ABS/GP1/GP2 (v2.4+). Unlike v1.8's uniform-depth batch, these grow
    // substantially across the standard, so the depths themselves carry the version signal.
    @Test("v1.9: CH06 financial — per-version depths, registration, P12 conditionals")
    func v1_9FinancialCanonical() throws {
        let t = SegmentGrammarTable.v2_5_1
        #expect(t["FT1"]?.fields.count == 31)
        #expect(t["PR1"]?.fields.count == 20)
        #expect(t["ACC"]?.fields.count == 11)
        #expect(t["UB1"]?.fields.count == 23)
        #expect(t["UB2"]?.fields.count == 17)
        #expect(t["DRG"]?.fields.count == 11)
        #expect(t["ABS"]?.fields.count == 14)
        #expect(t["GP1"]?.fields.count == 5)
        #expect(t["GP2"]?.fields.count == 14)

        // Growth across the standard — the depths are the divergence here.
        #expect(SegmentGrammarTable.v2_3["FT1"]?.fields.count == 25)
        #expect(SegmentGrammarTable.v2_3_1["FT1"]?.fields.count == 26)   // v2.3.1 errata +1
        #expect(SegmentGrammarTable.v2_8_2["FT1"]?.fields.count == 43)
        #expect(SegmentGrammarTable.v2_3["PR1"]?.fields.count == 15)
        #expect(SegmentGrammarTable.v2_3_1["PR1"]?.fields.count == 16)   // v2.3.1 errata +1
        #expect(SegmentGrammarTable.v2_8_2["PR1"]?.fields.count == 25)
        #expect(SegmentGrammarTable.v2_3["ACC"]?.fields.count == 6)
        #expect(SegmentGrammarTable.v2_8_2["ACC"]?.fields.count == 13)
        // DRG nearly triples in v2.6 (11 → 33).
        #expect(SegmentGrammarTable.v2_4["DRG"]?.fields.count == 11)
        #expect(SegmentGrammarTable.v2_6["DRG"]?.fields.count == 33)
        // UB1/UB2 are static across every version.
        #expect(SegmentGrammarTable.v2_3["UB1"]?.fields.count == 23)
        #expect(SegmentGrammarTable.v2_8_2["UB2"]?.fields.count == 17)
        // ABS/GP1/GP2 arrived in v2.4 — absent from the two legacy dialects.
        #expect(SegmentGrammarTable.v2_3["ABS"] == nil)
        #expect(SegmentGrammarTable.v2_3_1["GP1"] == nil)
        #expect(SegmentGrammarTable.v2_4["GP2"]?.fields.count == 14)

        // PR1-19/20 arrived in v2.5 and both cite the P12 trigger event, so they ship
        // predicates rather than joining the permanent-limitation register.
        #expect(t["PR1"]?.field(19)?.condition == "triggerEvent = P12")
        #expect(t["PR1"]?.field(20)?.condition == "triggerEvent = P12")
        #expect(SegmentGrammarTable.v2_8_2["PR1"]?.field(20)?.condition == "triggerEvent = P12")
        #expect(SegmentGrammarTable.v2_4["PR1"]?.field(19) == nil)   // PR1 caps at 18 in v2.4

        let wire = "MSH|^~\\&|A|B|C|D|20240101120000||DFT^P03|M1|P|2.5.1\r"
            + "FT1|1\r" + "PR1|1||P1^^HL7\r" + "ACC|20240101120000\r"
            + "UB1|1\r" + "UB2|1\r" + "DRG|D1^^HL7\r" + "ABS|1\r" + "GP1|A\r" + "GP2|1\r"
        let (message, pr1) = try hydratedMessage(PR1.self, from: wire)
        #expect(pr1.setIdPr1 == message["PR1-1"])          // typed accessor == path
        for present in [message.firstSegment(FT1.self) != nil, message.firstSegment(ACC.self) != nil,
                        message.firstSegment(UB1.self) != nil, message.firstSegment(UB2.self) != nil,
                        message.firstSegment(DRG.self) != nil, message.firstSegment(ABS.self) != nil,
                        message.firstSegment(GP1.self) != nil, message.firstSegment(GP2.self) != nil] {
            #expect(present)
        }
    }
}
