// AUMIMETableTests.swift
// P12 S3-2 item 2 (defect D2 of S3-1): the AU ADRM-2021 prints HL7 Table 0191
// (pp 167 to 168) and Table 0291 (title p 168, rows pp 169 to 170) with the IANA
// MIME rows: 0191 "application   Imported from IANA MIME Types updated
// 2016-09-27" and seven more types; 0291 "pdf   Portable Document Format MIME
// type: application/pdf", png, xml and emf, and "Other MIME subtypes types can
// be imported from: http://www.iana.org/assignments/media-types/media-types.xhtml"
// (p 170). Under the AU locale the ADRM's PDF display form `^application^pdf`
// (pp 248 to 249) is therefore valid; under the international locale the v2.4
// tables still reject it.

import Testing
@testable import HL7v2Kit

@Suite("AU ADRM renderings of Tables 0191 and 0291 (IANA MIME rows)")
struct AUMIMETableTests {
    private func wire(_ ed: String) -> String {
        "MSH|^~\\&|LAB|FAC|GP|FAC|20240101||ORU^R01^ORU_R01|MSG|P|2.4\r"
            + "OBX|1|ED|PDF^Display format in PDF^AUSPDI||\(ed)||||||F\r"
    }

    private func tableFindings(_ wire: String, locale: HL7Locale) throws -> [ValidationIssue] {
        let message = try Parser(locale: locale).parse(wire)
        return Validator(options: .strict, locale: locale).validate(message).issues.filter {
            if case .valueNotInTable = $0.code { return true }
            return false
        }
    }

    private func subtypeFindings(_ ed: String) throws -> [ValidationIssue] {
        let message = try Parser(locale: .auLocalisation).parse(wire(ed))
        return Validator(locale: .auLocalisation).validate(message).issues.filter {
            if case .profileConstraintViolation(let rule) = $0.code { return rule.hasPrefix("HL7au:00044.10.1.5/.6") }
            return false
        }
    }

    @Test("^application^pdf in an ED OBX-5 is clean under AU and the v2.4 table finding internationally")
    func pdfDisplay() throws {
        let pdf = wire("^application^pdf^Base64^JVBERi0xLjQK")
        #expect(try tableFindings(pdf, locale: .auLocalisation).isEmpty)
        let international = try tableFindings(pdf, locale: .international)
        #expect(international.map(\.code) == [.valueNotInTable(table: "0191"), .valueNotInTable(table: "0291")])
        #expect(international.map(\.location.pathDescription) == ["OBX[1]-5.2", "OBX[1]-5.3"])
    }

    @Test("The AU Table 0191 carries every printed row, the IANA MIME types among them")
    func table0191Rows() throws {
        let table = try #require(HL7TableRegistry.table("0191", locale: .auLocalisation))
        #expect(table.codes == ["AP", "AU", "FT", "IM", "multipart", "NS", "SD", "SI", "TEXT", "TX",
                                "application", "audio", "example", "image", "message", "model", "text", "video"])
        #expect(!table.isClosed)
    }

    @Test("The AU Table 0291 carries every printed row and is open to IANA subtypes")
    func table0291Rows() throws {
        let table = try #require(HL7TableRegistry.table("0291", locale: .auLocalisation))
        #expect(table.codes == ["BASIC", "DICOM", "FAX", "GIF", "HTML", "JOT", "JPEG", "Octet-stream", "PICT",
                                "PostScript", "RTF", "SGML", "TIFF", "x-hl7-cda-level-one", "XML",
                                "pdf", "png", "xml", "emf"])
        #expect(!table.isClosed)
    }

    @Test("An IANA subtype the ADRM does not list (text/plain) is not a table finding under AU, and still is internationally")
    func ianaSubtypeOpen() throws {
        let plain = wire("^text^plain^Base64^U3ludGhldGlj")
        #expect(try tableFindings(plain, locale: .auLocalisation).isEmpty)
        #expect(try tableFindings(plain, locale: .international).map(\.code)
                    == [.valueNotInTable(table: "0191"), .valueNotInTable(table: "0291")])
    }

    @Test("A registered IANA type the print does not list (font) is not a table finding under AU (0191 is open, p 168), and still is internationally")
    func unlistedIANATypeOpen() throws {
        let font = wire("^font^woff^Base64^AAAA")
        #expect(try tableFindings(font, locale: .auLocalisation).isEmpty)
        #expect(try tableFindings(font, locale: .international).map(\.code).contains(.valueNotInTable(table: "0191")))
    }

    @Test("Every MIME row of the AU Table 0291 has the type the ADRM pairs it with in the subtype map")
    func mimeRowsMapped() {
        #expect(HL7CodeTables.subtypeToTypeMap["pdf"]?.contains("application") == true)
        #expect(HL7CodeTables.subtypeToTypeMap["png"]?.contains("image") == true)
        #expect(HL7CodeTables.subtypeToTypeMap["xml"]?.contains("text") == true)
        #expect(HL7CodeTables.subtypeToTypeMap["xml"]?.contains("application") == true)
        #expect(HL7CodeTables.subtypeToTypeMap["emf"]?.contains("image") == true)
    }

    @Test("emf (image/emf, p 170) under another type of data fires HL7au:00044.10.1.6; under image it is silent")
    func emfPairing() throws {
        #expect(try subtypeFindings("^image^emf^Base64^AAAA").isEmpty)
        #expect(try subtypeFindings("^application^emf^Base64^AAAA").count == 1)
    }
}
