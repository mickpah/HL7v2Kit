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
        #expect(placer.first?.components[0].stringValue == "PLACER123")
        #expect(filler.first?.components[0].stringValue == "FILLER456")
        #expect(message["OBR-2.1"] == "PLACER123")
        #expect(message["OBR-3.1"] == "FILLER456")
    }

    @Test("OBR-4 (composite CE) universal service identifier")
    func obrUniversalServiceIdentifierAgrees() throws {
        let message = try Parser().parse(obrWire)
        let obr = try #require(message.firstSegment(OBR.self))
        let service = try #require(obr.universalServiceIdentifier)
        #expect(service.first?.components[0].stringValue == "GLU")
        #expect(service.first?.components[1].stringValue == "Glucose")
        #expect(message["OBR-4.1"] == "GLU")
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
        // XCN layout: ID^family^given. First component is empty in this
        // fixture; family is "Williams".
        #expect(provider.first?.components[1].stringValue == "Williams")
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
        #expect(obr.universalServiceIdentifier?.first?.components[0].stringValue == "GLU")
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
        #expect(phone.first?.components[0].stringValue == "(02)555-1234")
        #expect(message["PID-13.1"] == "(02)555-1234")
    }

    @Test("PID-15/16/17 (CE composites) language / marital / religion")
    func pidCEComposites() throws {
        let message = try Parser().parse(extendedPIDWire)
        let pid = try #require(message.firstSegment(PID.self))
        let language = try #require(pid.primaryLanguage)
        let marital = try #require(pid.maritalStatus)
        let religion = try #require(pid.religion)
        #expect(language.first?.components[0].stringValue == "en")
        #expect(marital.first?.components[1].stringValue == "Married")
        #expect(religion.first?.components[0].stringValue == "CAT")
    }

    @Test("PID-18 (CX) patient account number")
    func pidAccountNumberAgrees() throws {
        let message = try Parser().parse(extendedPIDWire)
        let pid = try #require(message.firstSegment(PID.self))
        let account = try #require(pid.patientAccountNumber)
        #expect(account.first?.components[0].stringValue == "ACC12345")
        #expect(message["PID-18.1"] == "ACC12345")
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
        let name = try #require(nk1.name)
        let relationship = try #require(nk1.relationship)
        #expect(name.first?.components[0].stringValue == "Smith")
        #expect(name.first?.components[1].stringValue == "Mary")
        #expect(relationship.first?.components[1].stringValue == "Spouse")
        #expect(message["NK1-2.1"] == "Smith")
        #expect(message["NK1-3.2"] == "Spouse")
    }

    @Test("NK1-5/6 (XTN composites) home + business phone")
    func nk1PhonesAgree() throws {
        let message = try Parser().parse(nk1Wire)
        let nk1 = try #require(message.firstSegment(NK1.self))
        let home = try #require(nk1.phoneNumber)
        let business = try #require(nk1.businessPhoneNumber)
        #expect(home.first?.components[0].stringValue == "(02)555-1234")
        #expect(business.first?.components[0].stringValue == "(02)555-5678")
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
        #expect(location.first?.components[0].stringValue == "WARD1")
        #expect(location.first?.components[1].stringValue == "ROOM2")
        #expect(location.first?.components[2].stringValue == "BED3")
        #expect(message["PV1-3.1"] == "WARD1")
    }

    @Test("PV1-7 (XCN composite repeats) attending doctor")
    func pv1AttendingDoctorAgrees() throws {
        let message = try Parser().parse(pv1Wire)
        let pv1 = try #require(message.firstSegment(PV1.self))
        let doctor = try #require(pv1.attendingDoctor)
        #expect(doctor.first?.components[0].stringValue == "DR123")
        #expect(doctor.first?.components[1].stringValue == "Jones")
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
        #expect(visit.first?.components[0].stringValue == "V001")
        #expect(message["PV1-19.1"] == "V001")
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
        #expect(nk1.name?.first?.components[0].stringValue == "Smith")
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
        #expect(allergen.first?.components[0].stringValue == "PENICILLIN")
        #expect(allergen.first?.components[1].stringValue == "Penicillin")
        #expect(message["AL1-3.1"] == "PENICILLIN")
        #expect(al1.allergyReactionCode == "Hives")
    }
}
