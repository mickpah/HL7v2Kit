// CompositeTypeTests.swift
// Typed composite data types — v0.2-C1 (XPN / CX / XAD), v0.3-C2 (CE /
// CWE), v0.3-C3 (EI / XCN / XTN), v0.3-C4 (HD / MSG / PT / VID / PL /
// CNE / XON / EIP). Exercises every named accessor on each composite,
// the `.field` migration path for callers using v0.1.x-style component
// indexing, multi-repetition access via `.field.repetitions`, and the
// cross-check invariant (typed accessor == matching path string).

import Testing
import Foundation
@testable import HL7v2Kit

@Suite("Composite types — all v2.5.1 typed-segment composites")
struct CompositeTypeTests {

    // MARK: - XPN (Extended Person Name)

    // PID-5 = LegalSurname^Patrick^James^III^DR^^L
    //         family^given^middle^suffix^prefix^^nameTypeCode
    private let xpnRichWire = TestWires.adt("PID|1||000001^^^HOSP^MR||LegalSurname^Patrick^James^III^DR^^L")

    @Test("XPN exposes familyName / givenName / middleName / suffix / prefix / nameTypeCode")
    func xpnNamedAccessors() throws {
        let pid = try hydrated(PID.self, from: xpnRichWire)
        let name = try #require(pid.patientName)
        #expect(name.familyName == "LegalSurname")
        #expect(name.givenName == "Patrick")
        #expect(name.middleName == "James")
        #expect(name.suffix == "III")
        #expect(name.prefix == "DR")
        #expect(name.nameTypeCode == "L")
    }

    @Test("XPN cross-checks each named accessor against the path API")
    func xpnAgreesWithPath() throws {
        let message = try Parser().parse(xpnRichWire)
        let name = try #require(message.firstSegment(PID.self)?.patientName)
        #expect(name.familyName == message["PID-5.1"])
        #expect(name.givenName == message["PID-5.2"])
        #expect(name.middleName == message["PID-5.3"])
        #expect(name.suffix == message["PID-5.4"])
        #expect(name.prefix == message["PID-5.5"])
        #expect(name.nameTypeCode == message["PID-5.7"])
    }

    @Test("XPN.field migration path — callers can still walk components by index")
    func xpnFieldMigrationPath() throws {
        let message = try Parser().parse(xpnRichWire)
        let name = try #require(message.firstSegment(PID.self)?.patientName)
        // The v0.1.x access pattern continues to work via .field, with one
        // extra hop. Useful for callers walking unexposed components.
        #expect(name.field.first?.components[0].stringValue == "LegalSurname")
        #expect(name.field.first?.components[1].stringValue == "Patrick")
    }

    // PID-5 with two repetitions: "L"egal followed by "M"aiden.
    private let xpnRepeatingWire = TestWires.adt("PID|1||000001^^^HOSP^MR||Married^Jane^^^^^L~Maiden^Jane^^^^^M")

    @Test("XPN reads from the FIRST repetition; walk .field.repetitions for the rest")
    func xpnMultiRepetitionAccess() throws {
        let message = try Parser().parse(xpnRepeatingWire)
        let name = try #require(message.firstSegment(PID.self)?.patientName)
        // Named accessors → first repetition.
        #expect(name.familyName == "Married")
        #expect(name.nameTypeCode == "L")
        // Other repetitions reached via .field.
        #expect(name.field.repetitions.count == 2)
        let maiden = XPN(repetition: name.field.repetitions[1])
        #expect(maiden.familyName == "Maiden")
        #expect(maiden.nameTypeCode == "M")
    }

    @Test("XPN absent / empty components return nil rather than empty string")
    func xpnAbsentComponentsReturnNil() throws {
        let wire = TestWires.adt("PID|1||000001^^^HOSP^MR||OnlyFamily")
        let message = try Parser().parse(wire)
        let name = try #require(message.firstSegment(PID.self)?.patientName)
        #expect(name.familyName == "OnlyFamily")
        #expect(name.givenName == nil)
        #expect(name.suffix == nil)
        #expect(name.nameTypeCode == nil)
    }

    // MARK: - CX (Extended Composite ID)

    // PID-3 typical AU shape: 123456^4^M11^HOSP^MR^FAC
    //                         id^cd^cdScheme^assignAuth^typeCode^assignFacility
    private let cxRichWire = TestWires.adt("PID|1||123456^4^M11^HOSP^MR^FAC||Smith^John")

    @Test("CX exposes id / checkDigit / checkDigitScheme / typeCode / authority / facility")
    func cxNamedAccessors() throws {
        let message = try Parser().parse(cxRichWire)
        let identifier = try #require(message.firstSegment(PID.self)?.patientIdentifierList)
        #expect(identifier.id == "123456")
        #expect(identifier.checkDigit == "4")
        #expect(identifier.checkDigitScheme == "M11")
        #expect(identifier.assigningAuthorityNamespace == "HOSP")
        #expect(identifier.identifierTypeCode == "MR")
        #expect(identifier.assigningFacilityNamespace == "FAC")
    }

    @Test("CX cross-checks each named accessor against the path API")
    func cxAgreesWithPath() throws {
        let message = try Parser().parse(cxRichWire)
        let identifier = try #require(message.firstSegment(PID.self)?.patientIdentifierList)
        #expect(identifier.id == message["PID-3.1"])
        #expect(identifier.checkDigit == message["PID-3.2"])
        #expect(identifier.assigningAuthorityNamespace == message["PID-3.4"])
        #expect(identifier.identifierTypeCode == message["PID-3.5"])
    }

    // PID-3 with two repetitions: MRN and URN.
    private let cxRepeatingWire = TestWires.adt("PID|1||MRN001^^^HOSP^MR~URN9999^^^MEDICARE^NI||Smith^John")

    @Test("CX multi-repetition access — wrap each Repetition for typed view")
    func cxMultiRepetitionAccess() throws {
        let message = try Parser().parse(cxRepeatingWire)
        let first = try #require(message.firstSegment(PID.self)?.patientIdentifierList)
        #expect(first.id == "MRN001")
        #expect(first.identifierTypeCode == "MR")
        #expect(first.field.repetitions.count == 2)
        let second = CX(repetition: first.field.repetitions[1])
        #expect(second.id == "URN9999")
        #expect(second.identifierTypeCode == "NI")
    }

    // MARK: - XAD (Extended Address)

    // PID-11 = 10 Main St^Apt 5^Sydney^NSW^2000^AU^H
    //          street^otherDes^city^state^zip^country^addressType
    private let xadRichWire = TestWires.adt("PID|1||000001^^^HOSP^MR||Smith^John||19800101|M||2106-3^White^HL70005|10 Main St^Apt 5^Sydney^NSW^2000^AU^H")

    @Test("XAD exposes streetAddress / otherDesignation / city / state / zip / country / addressType")
    func xadNamedAccessors() throws {
        let pid = try hydrated(PID.self, from: xadRichWire)
        let address = try #require(pid.patientAddress)
        #expect(address.streetAddress == "10 Main St")
        #expect(address.otherDesignation == "Apt 5")
        #expect(address.city == "Sydney")
        #expect(address.state == "NSW")
        #expect(address.zip == "2000")
        #expect(address.country == "AU")
        #expect(address.addressType == "H")
    }

    @Test("XAD cross-checks each named accessor against the path API")
    func xadAgreesWithPath() throws {
        let message = try Parser().parse(xadRichWire)
        let address = try #require(message.firstSegment(PID.self)?.patientAddress)
        #expect(address.streetAddress == message["PID-11.1"])
        #expect(address.city == message["PID-11.3"])
        #expect(address.state == message["PID-11.4"])
        #expect(address.zip == message["PID-11.5"])
        #expect(address.country == message["PID-11.6"])
        #expect(address.addressType == message["PID-11.7"])
    }

    // MARK: - CE (Coded Element) — v0.3-C2

    // PID-15 (primary language) = en^English^ISO639-2.
    // Field map: 1 setID=1, 3 ids, 5 name, 7 DOB, 8 sex=M, 9..14 empty
    // (7 pipes after M), 15 language=en^English^ISO639-2.
    private let ceRichWire = TestWires.adt("PID|1||000001^^^HOSP^MR||Smith^John||19800101|M|||||||en^English^ISO639-2")

    @Test("CE exposes identifier / text / nameOfCodingSystem / alt-* accessors")
    func ceNamedAccessors() throws {
        let message = try Parser().parse(ceRichWire)
        let language = try #require(message.firstSegment(PID.self)?.primaryLanguage)
        #expect(language.identifier == "en")
        #expect(language.text == "English")
        #expect(language.nameOfCodingSystem == "ISO639-2")
        #expect(language.altIdentifier == nil)
    }

    @Test("CE cross-checks each named accessor against the path API")
    func ceAgreesWithPath() throws {
        let message = try Parser().parse(ceRichWire)
        let language = try #require(message.firstSegment(PID.self)?.primaryLanguage)
        #expect(language.identifier == message["PID-15.1"])
        #expect(language.text == message["PID-15.2"])
        #expect(language.nameOfCodingSystem == message["PID-15.3"])
    }

    // PID-10 (race) is CE, repeating. Two repetitions: White / Asian.
    private let ceRepeatingWire = TestWires.adt("PID|1||000001^^^HOSP^MR||Smith^John||19800101|M||2106-3^White^HL70005~2028-9^Asian^HL70005")

    @Test("CE multi-repetition — wrap each Repetition for typed view")
    func ceMultiRepetitionAccess() throws {
        let message = try Parser().parse(ceRepeatingWire)
        let race = try #require(message.firstSegment(PID.self)?.race)
        #expect(race.identifier == "2106-3")
        #expect(race.text == "White")
        #expect(race.field.repetitions.count == 2)
        let asian = CE(repetition: race.field.repetitions[1])
        #expect(asian.identifier == "2028-9")
        #expect(asian.text == "Asian")
    }

    // MARK: - CWE (Coded with Exceptions) — v0.3-C2

    // PID-39 (tribal citizenship) = 100^Australian^HL70171.
    // Field map: 1 setID=1, 3 ids, 5 name, 7 DOB, 8 sex=M, 9..38 empty
    // (31 pipes after M), 39 tribalCitizenship=100^Australian^HL70171.
    private let cweRichWire = TestWires.adt("PID|1||000001^^^HOSP^MR||Smith^John||19800101|M|||||||||||||||||||||||||||||||100^Australian^HL70171")

    @Test("CWE exposes identifier / text / coding-system / alt-* / originalText accessors")
    func cweNamedAccessors() throws {
        let message = try Parser().parse(cweRichWire)
        #expect(message["PID-39.1"] == "100", "Wire mis-counted: CWE should land at PID-39")
        let citizenship = try #require(message.firstSegment(PID.self)?.tribalCitizenship)
        #expect(citizenship.identifier == "100")
        #expect(citizenship.text == "Australian")
        #expect(citizenship.nameOfCodingSystem == "HL70171")
        #expect(citizenship.originalText == nil)  // CWE-9 not populated
    }

    @Test("CWE cross-checks each named accessor against the path API")
    func cweAgreesWithPath() throws {
        let message = try Parser().parse(cweRichWire)
        let citizenship = try #require(message.firstSegment(PID.self)?.tribalCitizenship)
        #expect(citizenship.identifier == message["PID-39.1"])
        #expect(citizenship.text == message["PID-39.2"])
        #expect(citizenship.nameOfCodingSystem == message["PID-39.3"])
    }

    @Test("CWE.field migration path — callers can still walk components by index")
    func cweFieldMigrationPath() throws {
        let message = try Parser().parse(cweRichWire)
        let citizenship = try #require(message.firstSegment(PID.self)?.tribalCitizenship)
        // v0.1.x access pattern still works via .field with one extra hop.
        #expect(citizenship.field.first?.components[0].stringValue == "100")
        #expect(citizenship.field.first?.components[1].stringValue == "Australian")
    }

    // MARK: - EI (Entity Identifier) — v0.3-C3

    // ORC-2 (placerOrderNumber) is a single-rep EI. Wire populates all
    // four EI components so each named accessor has a non-empty value
    // to read.
    private let eiRichWire = """
    MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|||ORM^O01|MSG00001|P|2.5.1\r\
    ORC|NW|PLACER123^HOSP^1.2.840.10008^ISO\r
    """

    @Test("EI exposes entityIdentifier / namespaceID / universalID / universalIDType accessors")
    func eiNamedAccessors() throws {
        let message = try Parser().parse(eiRichWire)
        let placer = try #require(message.firstSegment(ORC.self)?.placerOrderNumber)
        #expect(placer.entityIdentifier == "PLACER123")
        #expect(placer.namespaceID == "HOSP")
        #expect(placer.universalID == "1.2.840.10008")
        #expect(placer.universalIDType == "ISO")
    }

    @Test("EI cross-checks each named accessor against the path API")
    func eiAgreesWithPath() throws {
        let message = try Parser().parse(eiRichWire)
        let placer = try #require(message.firstSegment(ORC.self)?.placerOrderNumber)
        #expect(placer.entityIdentifier == message["ORC-2.1"])
        #expect(placer.namespaceID == message["ORC-2.2"])
        #expect(placer.universalID == message["ORC-2.3"])
        #expect(placer.universalIDType == message["ORC-2.4"])
    }

    @Test("EI.field migration path — callers can still walk components by index")
    func eiFieldMigrationPath() throws {
        let message = try Parser().parse(eiRichWire)
        let placer = try #require(message.firstSegment(ORC.self)?.placerOrderNumber)
        #expect(placer.field.first?.components[0].stringValue == "PLACER123")
        #expect(placer.field.first?.components[3].stringValue == "ISO")
    }

    // MARK: - XCN (Extended Composite ID for Persons) — v0.3-C3

    // PV1-7 (attendingDoctor) is multi-rep XCN. First rep populates the
    // first six XCN components — every named accessor has a value.
    private let xcnRichWire = TestWires.adt("PV1|1|I|||||DR123^Jones^Mary^Anne^Jr^Dr")

    @Test("XCN exposes idNumber / familyName / givenName / middleName / suffix / prefix_ accessors")
    func xcnNamedAccessors() throws {
        let message = try Parser().parse(xcnRichWire)
        let doctor = try #require(message.firstSegment(PV1.self)?.attendingDoctor)
        #expect(doctor.idNumber == "DR123")
        #expect(doctor.familyName == "Jones")
        #expect(doctor.givenName == "Mary")
        #expect(doctor.middleName == "Anne")
        #expect(doctor.suffix == "Jr")
        #expect(doctor.prefix_ == "Dr")
    }

    @Test("XCN cross-checks each named accessor against the path API")
    func xcnAgreesWithPath() throws {
        let message = try Parser().parse(xcnRichWire)
        let doctor = try #require(message.firstSegment(PV1.self)?.attendingDoctor)
        #expect(doctor.idNumber == message["PV1-7.1"])
        #expect(doctor.familyName == message["PV1-7.2"])
        #expect(doctor.givenName == message["PV1-7.3"])
        #expect(doctor.middleName == message["PV1-7.4"])
        #expect(doctor.suffix == message["PV1-7.5"])
        #expect(doctor.prefix_ == message["PV1-7.6"])
    }

    // PV1-9 (consultingDoctor) with two repetitions: a primary and a
    // backup consultant.
    private let xcnRepeatingWire = TestWires.adt("PV1|1|I|||||||CN001^Brown^Alex~CN002^Davis^Lee")

    @Test("XCN multi-repetition — wrap each Repetition for typed view")
    func xcnMultiRepetitionAccess() throws {
        let message = try Parser().parse(xcnRepeatingWire)
        let consult = try #require(message.firstSegment(PV1.self)?.consultingDoctor)
        // Named accessors → first repetition.
        #expect(consult.idNumber == "CN001")
        #expect(consult.familyName == "Brown")
        // Second repetition reached via .field.
        #expect(consult.field.repetitions.count == 2)
        let backup = XCN(repetition: consult.field.repetitions[1])
        #expect(backup.idNumber == "CN002")
        #expect(backup.familyName == "Davis")
    }

    // MARK: - XTN (Extended Telecommunication) — v0.3-C3

    // PID-13 (phoneNumberHome) is a multi-rep XTN. First rep populates
    // XTN-1 (legacy phone) + XTN-2 (use) + XTN-3 (equipment) + XTN-4
    // (email) + XTN-5/6/7 (country/area/local) + XTN-12 (unformatted).
    // Field map for the XTN: phone^use^equip^email^cc^area^local^^^^^unformatted
    // Components 8/9/10/11 left empty so XTN-12 is at the right slot.
    private let xtnRichWire = TestWires.adt("PID|1||000001^^^HOSP^MR||Smith^John||19800101|M|||||(02)5550-1234^PRN^PH^john@example.com^61^2^55501234^^^^^+61255501234")

    @Test("XTN exposes telephoneNumber / use / equipment / email / country / area / local / unformatted accessors")
    func xtnNamedAccessors() throws {
        let message = try Parser().parse(xtnRichWire)
        let phone = try #require(message.firstSegment(PID.self)?.phoneNumberHome)
        #expect(phone.telephoneNumber == "(02)5550-1234")
        #expect(phone.telecommunicationUseCode == "PRN")
        #expect(phone.telecommunicationEquipmentType == "PH")
        #expect(phone.emailAddress == "john@example.com")
        #expect(phone.countryCode == "61")
        #expect(phone.areaCityCode == "2")
        #expect(phone.localNumber == "55501234")
        #expect(phone.unformattedTelephoneNumber == "+61255501234")
    }

    @Test("XTN cross-checks each named accessor against the path API")
    func xtnAgreesWithPath() throws {
        let message = try Parser().parse(xtnRichWire)
        let phone = try #require(message.firstSegment(PID.self)?.phoneNumberHome)
        #expect(phone.telephoneNumber == message["PID-13.1"])
        #expect(phone.telecommunicationUseCode == message["PID-13.2"])
        #expect(phone.telecommunicationEquipmentType == message["PID-13.3"])
        #expect(phone.emailAddress == message["PID-13.4"])
        #expect(phone.countryCode == message["PID-13.5"])
        #expect(phone.areaCityCode == message["PID-13.6"])
        #expect(phone.localNumber == message["PID-13.7"])
        #expect(phone.unformattedTelephoneNumber == message["PID-13.12"])
    }

    // PID-13 with two repetitions: a home phone and a mobile.
    private let xtnRepeatingWire = TestWires.adt("PID|1||000001^^^HOSP^MR||Smith^John||19800101|M|||||(02)5550-1234^PRN^PH~0255505678^PRN^CP")

    @Test("XTN multi-repetition — wrap each Repetition for typed view")
    func xtnMultiRepetitionAccess() throws {
        let message = try Parser().parse(xtnRepeatingWire)
        let phone = try #require(message.firstSegment(PID.self)?.phoneNumberHome)
        // Named accessors → first repetition (home phone).
        #expect(phone.telephoneNumber == "(02)5550-1234")
        #expect(phone.telecommunicationEquipmentType == "PH")
        // Second repetition reached via .field (mobile).
        #expect(phone.field.repetitions.count == 2)
        let mobile = XTN(repetition: phone.field.repetitions[1])
        #expect(mobile.telephoneNumber == "0255505678")
        #expect(mobile.telecommunicationEquipmentType == "CP")
    }

    // MARK: - HD (Hierarchic Designator) — v0.3-C4

    // MSH-3 (sendingApplication) is single-rep HD. All 3 components populated.
    private let hdRichWire = """
    MSH|^~\\&|HIS^1.2.840.10008^ISO|FAC|HOSPITAL|FAC|||ADT^A01|MSG00001|P|2.5.1\r
    """

    @Test("HD exposes namespaceID / universalID / universalIDType accessors")
    func hdNamedAccessors() throws {
        let message = try Parser().parse(hdRichWire)
        let app = try #require(message.firstSegment(MSH.self)?.sendingApplication)
        #expect(app.namespaceID == "HIS")
        #expect(app.universalID == "1.2.840.10008")
        #expect(app.universalIDType == "ISO")
    }

    @Test("HD cross-checks each named accessor against the path API")
    func hdAgreesWithPath() throws {
        let message = try Parser().parse(hdRichWire)
        let app = try #require(message.firstSegment(MSH.self)?.sendingApplication)
        #expect(app.namespaceID == message["MSH-3.1"])
        #expect(app.universalID == message["MSH-3.2"])
        #expect(app.universalIDType == message["MSH-3.3"])
    }

    // MARK: - MSG (Message Type) — v0.3-C4

    // MSH-9 (messageType) is single-rep MSG; the common wire already
    // populates MSG-1 / MSG-2.
    private let msgRichWire = """
    MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|||ADT^A01^ADT_A01|MSG00001|P|2.5.1\r
    """

    @Test("MSG exposes messageCode / triggerEvent / messageStructure accessors")
    func msgNamedAccessors() throws {
        let message = try Parser().parse(msgRichWire)
        let mt = try #require(message.firstSegment(MSH.self)?.messageType)
        #expect(mt.messageCode == "ADT")
        #expect(mt.triggerEvent == "A01")
        #expect(mt.messageStructure == "ADT_A01")
    }

    @Test("MSG cross-checks each named accessor against the path API")
    func msgAgreesWithPath() throws {
        let message = try Parser().parse(msgRichWire)
        let mt = try #require(message.firstSegment(MSH.self)?.messageType)
        #expect(mt.messageCode == message["MSH-9.1"])
        #expect(mt.triggerEvent == message["MSH-9.2"])
        #expect(mt.messageStructure == message["MSH-9.3"])
    }

    // MARK: - PT (Processing Type) — v0.3-C4

    // MSH-11 (processingID) PT with both components populated.
    private let ptRichWire = """
    MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|||ADT^A01|MSG00001|P^A|2.5.1\r
    """

    @Test("PT exposes processingID / processingMode accessors")
    func ptNamedAccessors() throws {
        let message = try Parser().parse(ptRichWire)
        let pt = try #require(message.firstSegment(MSH.self)?.processingID)
        #expect(pt.processingID == "P")
        #expect(pt.processingMode == "A")
    }

    @Test("PT cross-checks each named accessor against the path API")
    func ptAgreesWithPath() throws {
        let message = try Parser().parse(ptRichWire)
        let pt = try #require(message.firstSegment(MSH.self)?.processingID)
        #expect(pt.processingID == message["MSH-11.1"])
        #expect(pt.processingMode == message["MSH-11.2"])
    }

    // MARK: - VID (Version Identifier) — v0.3-C4

    // MSH-12 (versionID) with the optional nested CE components populated.
    // VID-2 / VID-3 each populate their CE-1 (identifier subcomponent).
    private let vidRichWire = """
    MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|||ADT^A01|MSG00001|P|2.5.1^I18N1^IVID1\r
    """

    @Test("VID exposes versionID / internationalizationCode / internationalVersionID accessors")
    func vidNamedAccessors() throws {
        let message = try Parser().parse(vidRichWire)
        let v = try #require(message.firstSegment(MSH.self)?.versionID)
        #expect(v.versionID == "2.5.1")
        #expect(v.internationalizationCode == "I18N1")
        #expect(v.internationalVersionID == "IVID1")
    }

    @Test("VID cross-checks each named accessor against the path API")
    func vidAgreesWithPath() throws {
        let message = try Parser().parse(vidRichWire)
        let v = try #require(message.firstSegment(MSH.self)?.versionID)
        #expect(v.versionID == message["MSH-12.1"])
    }

    // MARK: - PL (Person Location) — v0.3-C4

    // PV1-3 (assignedPatientLocation) with all four exposed PL components.
    private let plRichWire = TestWires.adt("PV1|1|I|WARD1^ROOM2^BED3^HOSPITAL|R")

    @Test("PL exposes pointOfCare / room / bed / facility accessors")
    func plNamedAccessors() throws {
        let message = try Parser().parse(plRichWire)
        let loc = try #require(message.firstSegment(PV1.self)?.assignedPatientLocation)
        #expect(loc.pointOfCare == "WARD1")
        #expect(loc.room == "ROOM2")
        #expect(loc.bed == "BED3")
        #expect(loc.facility == "HOSPITAL")
    }

    @Test("PL cross-checks each named accessor against the path API")
    func plAgreesWithPath() throws {
        let message = try Parser().parse(plRichWire)
        let loc = try #require(message.firstSegment(PV1.self)?.assignedPatientLocation)
        #expect(loc.pointOfCare == message["PV1-3.1"])
        #expect(loc.room == message["PV1-3.2"])
        #expect(loc.bed == message["PV1-3.3"])
        #expect(loc.facility == message["PV1-3.4"])
    }

    // MARK: - CNE (Coded with No Exceptions) — v0.3-C4

    // ORC-30 (entererAuthorizationMode) is CNE. Field map: ORC populates
    // ORC-1 (orderControl=NW) + 28 empties (ORC-2..29) + ORC-30 CNE.
    // Pipe count between "NW" and "EL": 29 (= ORC-30 - ORC-1).
    private let cneRichWire = """
    MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|||ORM^O01|MSG00001|P|2.5.1\r\
    ORC|NW|||||||||||||||||||||||||||||EL^Electronic^HL70483\r
    """

    @Test("CNE exposes identifier / text / nameOfCodingSystem accessors")
    func cneNamedAccessors() throws {
        let message = try Parser().parse(cneRichWire)
        #expect(message["ORC-30.1"] == "EL", "Wire mis-counted: CNE should land at ORC-30")
        let mode = try #require(message.firstSegment(ORC.self)?.entererAuthorizationMode)
        #expect(mode.identifier == "EL")
        #expect(mode.text == "Electronic")
        #expect(mode.nameOfCodingSystem == "HL70483")
    }

    @Test("CNE cross-checks each named accessor against the path API")
    func cneAgreesWithPath() throws {
        let message = try Parser().parse(cneRichWire)
        let mode = try #require(message.firstSegment(ORC.self)?.entererAuthorizationMode)
        #expect(mode.identifier == message["ORC-30.1"])
        #expect(mode.text == message["ORC-30.2"])
        #expect(mode.nameOfCodingSystem == message["ORC-30.3"])
    }

    // MARK: - XON (Extended Composite Name and Identification for Organizations) — v0.3-C4

    // NK1-13 (organizationName) is XON. NK1-1=1, 2=name, 3 empty, 4=SPO,
    // 5..12 empty (9 pipes between SPO and XON value: 13-4=9), 13=XON.
    // Field map for the XON: name^typeCode^^^^^idTypeCode^^^orgID
    private let xonRichWire = TestWires.adt("NK1|1|Smith^Jane||SPO|||||||||CityHospital^L^^^^^NPI^^^1234567890")

    @Test("XON exposes organizationName / typeCode / identifierTypeCode / organizationIdentifier accessors")
    func xonNamedAccessors() throws {
        let message = try Parser().parse(xonRichWire)
        let org = try #require(message.firstSegment(NK1.self)?.organizationName)
        #expect(org.organizationName == "CityHospital")
        #expect(org.organizationNameTypeCode == "L")
        #expect(org.identifierTypeCode == "NPI")
        #expect(org.organizationIdentifier == "1234567890")
    }

    @Test("XON cross-checks each named accessor against the path API")
    func xonAgreesWithPath() throws {
        let message = try Parser().parse(xonRichWire)
        let org = try #require(message.firstSegment(NK1.self)?.organizationName)
        #expect(org.organizationName == message["NK1-13.1"])
        #expect(org.organizationNameTypeCode == message["NK1-13.2"])
        #expect(org.identifierTypeCode == message["NK1-13.7"])
        #expect(org.organizationIdentifier == message["NK1-13.10"])
    }

    // MARK: - EIP (Entity Identifier Pair) — v0.3-C4

    // ORC-8 (parent) is EIP. Each component is a nested EI; the named
    // accessors return the first subcomponent of each (EI-1).
    // Field map for the EIP: placer&placerNS&placerOID&ISO^filler&fillerNS&fillerOID&ISO
    // (component-separator between the two EIs; subcomponent-separator
    // between the EI's sub-fields.)
    private let eipRichWire = """
    MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|||ORM^O01|MSG00001|P|2.5.1\r\
    ORC|NW|||||||PLACER123&HOSP&1.2.840.10008&ISO^FILLER456&LAB&1.2.840.10009&ISO\r
    """

    @Test("EIP exposes placerAssignedIdentifier / fillerAssignedIdentifier accessors")
    func eipNamedAccessors() throws {
        let message = try Parser().parse(eipRichWire)
        let parent = try #require(message.firstSegment(ORC.self)?.parent)
        #expect(parent.placerAssignedIdentifier == "PLACER123")
        #expect(parent.fillerAssignedIdentifier == "FILLER456")
    }

    @Test("EIP cross-checks each named accessor against the path API")
    func eipAgreesWithPath() throws {
        let message = try Parser().parse(eipRichWire)
        let parent = try #require(message.firstSegment(ORC.self)?.parent)
        // EIP-1.1 is the first subcomponent of EIP-1; path syntax doesn't
        // address subcomponents directly. Cross-check via the .field
        // migration path: components[0].subcomponents[0].value.
        #expect(parent.placerAssignedIdentifier == parent.field.first?.components[0].subcomponents.first?.value)
        #expect(parent.fillerAssignedIdentifier == parent.field.first?.components[1].subcomponents.first?.value)
    }

    // MARK: - Round-trip preservation

    @Test("Composite-bearing messages still round-trip byte-perfectly through all 16 typed composites")
    func compositeRoundTripsByteIdentical() throws {
        // The composite structs are *views* over Field, not owners — the
        // segment still owns the bytes. Round-trip must be unaffected by
        // introducing typed accessors.
        for wire in [
            xpnRichWire, xpnRepeatingWire,
            cxRichWire, cxRepeatingWire,
            xadRichWire,
            ceRichWire, ceRepeatingWire,
            cweRichWire,
            eiRichWire,
            xcnRichWire, xcnRepeatingWire,
            xtnRichWire, xtnRepeatingWire,
            hdRichWire,
            msgRichWire,
            ptRichWire,
            vidRichWire,
            plRichWire,
            cneRichWire,
            xonRichWire,
            eipRichWire,
        ] {
            let message = try Parser().parse(wire)
            let rebuilt = String(data: message.serialize(), encoding: .utf8)
            #expect(rebuilt == wire, "Composite wire round-trip drift")
        }
    }
}
