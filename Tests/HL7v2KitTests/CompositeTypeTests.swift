// CompositeTypeTests.swift
// Typed composite data types — v0.2-C1 (XPN / CX / XAD), v0.3-C2 (CE /
// CWE), v0.3-C3 (EI / XCN / XTN). Exercises every named accessor on
// each composite, the `.field` migration path for callers using
// v0.1.x-style component indexing, multi-repetition access via
// `.field.repetitions`, and the cross-check invariant (typed accessor
// == matching path string).

import Testing
import Foundation
@testable import HL7v2Kit

@Suite("Composite types — XPN / CX / XAD / CE / CWE / EI / XCN / XTN")
struct CompositeTypeTests {

    // MARK: - XPN (Extended Person Name)

    // PID-5 = LegalSurname^Patrick^James^III^DR^^L
    //         family^given^middle^suffix^prefix^^nameTypeCode
    private let xpnRichWire = """
    MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|||ADT^A01|MSG00001|P|2.5.1\r\
    PID|1||000001^^^HOSP^MR||LegalSurname^Patrick^James^III^DR^^L\r
    """

    @Test("XPN exposes familyName / givenName / middleName / suffix / prefix / nameTypeCode")
    func xpnNamedAccessors() throws {
        let message = try Parser().parse(xpnRichWire)
        let pid = try #require(message.firstSegment(PID.self))
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
    private let xpnRepeatingWire = """
    MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|||ADT^A01|MSG00001|P|2.5.1\r\
    PID|1||000001^^^HOSP^MR||Married^Jane^^^^^L~Maiden^Jane^^^^^M\r
    """

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
        let wire = """
        MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|||ADT^A01|MSG00001|P|2.5.1\r\
        PID|1||000001^^^HOSP^MR||OnlyFamily\r
        """
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
    private let cxRichWire = """
    MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|||ADT^A01|MSG00001|P|2.5.1\r\
    PID|1||123456^4^M11^HOSP^MR^FAC||Smith^John\r
    """

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
    private let cxRepeatingWire = """
    MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|||ADT^A01|MSG00001|P|2.5.1\r\
    PID|1||MRN001^^^HOSP^MR~URN9999^^^MEDICARE^NI||Smith^John\r
    """

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
    private let xadRichWire = """
    MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|||ADT^A01|MSG00001|P|2.5.1\r\
    PID|1||000001^^^HOSP^MR||Smith^John||19800101|M||2106-3^White^HL70005|10 Main St^Apt 5^Sydney^NSW^2000^AU^H\r
    """

    @Test("XAD exposes streetAddress / otherDesignation / city / state / zip / country / addressType")
    func xadNamedAccessors() throws {
        let message = try Parser().parse(xadRichWire)
        let pid = try #require(message.firstSegment(PID.self))
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
    private let ceRichWire = """
    MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|||ADT^A01|MSG00001|P|2.5.1\r\
    PID|1||000001^^^HOSP^MR||Smith^John||19800101|M|||||||en^English^ISO639-2\r
    """

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
    private let ceRepeatingWire = """
    MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|||ADT^A01|MSG00001|P|2.5.1\r\
    PID|1||000001^^^HOSP^MR||Smith^John||19800101|M||2106-3^White^HL70005~2028-9^Asian^HL70005\r
    """

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
    private let cweRichWire = """
    MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|||ADT^A01|MSG00001|P|2.5.1\r\
    PID|1||000001^^^HOSP^MR||Smith^John||19800101|M|||||||||||||||||||||||||||||||100^Australian^HL70171\r
    """

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
    private let xcnRichWire = """
    MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|||ADT^A01|MSG00001|P|2.5.1\r\
    PV1|1|I|||||DR123^Jones^Mary^Anne^Jr^Dr\r
    """

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
    private let xcnRepeatingWire = """
    MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|||ADT^A01|MSG00001|P|2.5.1\r\
    PV1|1|I|||||||CN001^Brown^Alex~CN002^Davis^Lee\r
    """

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
    private let xtnRichWire = """
    MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|||ADT^A01|MSG00001|P|2.5.1\r\
    PID|1||000001^^^HOSP^MR||Smith^John||19800101|M|||||(02)555-1234^PRN^PH^john@example.com^61^2^5551234^^^^^+61255551234\r
    """

    @Test("XTN exposes telephoneNumber / use / equipment / email / country / area / local / unformatted accessors")
    func xtnNamedAccessors() throws {
        let message = try Parser().parse(xtnRichWire)
        let phone = try #require(message.firstSegment(PID.self)?.phoneNumberHome)
        #expect(phone.telephoneNumber == "(02)555-1234")
        #expect(phone.telecommunicationUseCode == "PRN")
        #expect(phone.telecommunicationEquipmentType == "PH")
        #expect(phone.emailAddress == "john@example.com")
        #expect(phone.countryCode == "61")
        #expect(phone.areaCityCode == "2")
        #expect(phone.localNumber == "5551234")
        #expect(phone.unformattedTelephoneNumber == "+61255551234")
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
    private let xtnRepeatingWire = """
    MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|||ADT^A01|MSG00001|P|2.5.1\r\
    PID|1||000001^^^HOSP^MR||Smith^John||19800101|M|||||(02)555-1234^PRN^PH~0412345678^PRN^CP\r
    """

    @Test("XTN multi-repetition — wrap each Repetition for typed view")
    func xtnMultiRepetitionAccess() throws {
        let message = try Parser().parse(xtnRepeatingWire)
        let phone = try #require(message.firstSegment(PID.self)?.phoneNumberHome)
        // Named accessors → first repetition (home phone).
        #expect(phone.telephoneNumber == "(02)555-1234")
        #expect(phone.telecommunicationEquipmentType == "PH")
        // Second repetition reached via .field (mobile).
        #expect(phone.field.repetitions.count == 2)
        let mobile = XTN(repetition: phone.field.repetitions[1])
        #expect(mobile.telephoneNumber == "0412345678")
        #expect(mobile.telecommunicationEquipmentType == "CP")
    }

    // MARK: - Round-trip preservation

    @Test("Composite-bearing messages still round-trip byte-perfectly through XPN/CX/XAD/CE/CWE/EI/XCN/XTN")
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
        ] {
            let message = try Parser().parse(wire)
            let rebuilt = String(data: message.serialize(), encoding: .utf8)
            #expect(rebuilt == wire, "Composite wire round-trip drift")
        }
    }
}
