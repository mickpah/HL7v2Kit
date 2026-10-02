// VersionUnionAccessorTests.swift
// P9-5 (V282-C10, ADR-020): typed structs render from their base schema plus
// what the other supported versions define. Each later-version accessor agrees
// with path access, and the DocC names the versions each accessor applies to.

import Testing
import Foundation
@testable import HL7v2Kit

@Suite("Version-union typed accessors (P9-5)")
struct VersionUnionAccessorTests {

    private func msh(_ version: String) -> String {
        "MSH|^~\\&|LAB|FAC|HOSPITAL|FAC|||ORU^R01^ORU_R01|MSG00001|P|\(version)\r"
    }

    /// A segment with `count` fields, each set from `values` (index → wire text).
    private func segment(_ id: String, _ count: Int, _ values: [Int: String]) -> String {
        ([id] + (1...count).map { values[$0] ?? "" }).joined(separator: "|") + "\r"
    }

    static let generated = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/HL7v2Kit/Segment/Generated")

    /// The DocC block (the `///` lines) directly above `public var <name>:` in a generated struct.
    private func doc(_ segmentID: String, _ name: String) throws -> String {
        let text = try String(contentsOf: Self.generated.appendingPathComponent("\(segmentID).swift"), encoding: .utf8)
        let lines = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        let at = try #require(lines.firstIndex { $0.hasPrefix("public var \(name):") }, "\(segmentID).\(name) not generated")
        var block: [String] = []
        var i = at - 1
        while i >= 0, lines[i].hasPrefix("///") {
            block.insert(String(lines[i].dropFirst(3)).trimmingCharacters(in: .whitespaces), at: 0)
            i -= 1
        }
        return block.joined(separator: " ")
    }

    @Test("OBX-26..30 and OBX-8 Interpretation Codes (v2.8.2) agree with path access")
    func obxV282() throws {
        let obx = segment("OBX", 30, [
            1: "1", 2: "ST",
            3: "8867-4^Heart rate^LN" + String(repeating: "^", count: 11) + "2.16.840.1.113883.6.1",
            5: "72", 8: "N~H",
            26: "Y", 27: "RC1^Root cause^L", 28: "LPC1~LPC2", 29: "RSLT", 30: "PHY",
        ])
        let (message, typed) = try hydratedMessage(OBX.self, from: msh("2.8.2") + obx)
        #expect(typed.observationType == "RSLT")
        #expect(typed.observationType == message["OBX-29"])
        #expect(typed.observationSubType == message["OBX-30"])
        #expect(typed.patientResultsReleaseCategory == message["OBX-26"])
        #expect(typed.rootCause?.identifier == message["OBX-27.1"])
        #expect(typed.localProcessControlAll.map(\.identifier) == ["LPC1", "LPC2"])
        #expect(typed.interpretationCodes?.identifier == message["OBX-8.1"])
        #expect(typed.interpretationCodesAll.map(\.identifier) == ["N", "H"])
        #expect(typed.abnormalFlagsAll == ["N", "H"])
        let cwe = try #require(typed.observationIdentifier?.viewed(as: CWE.self))
        #expect(cwe.codingSystemOID == "2.16.840.1.113883.6.1")
        #expect(cwe.codingSystemOID == message["OBX-3.14"])
    }

    @Test("PID-40 (v2.8.2) patientTelecommunicationInformation agrees with path access")
    func pidV282() throws {
        let pid = segment("PID", 40, [1: "1", 3: "123^^^HOSP^MR", 40: "^NET^Internet^a@example.org~^PRN^PH^^61^2^98765432"])
        let (message, typed) = try hydratedMessage(PID.self, from: msh("2.8.2") + pid)
        #expect(typed.patientTelecommunicationInformation?.emailAddress == message["PID-40.4"])
        #expect(typed.patientTelecommunicationInformationAll.count == 2)
        #expect(typed.patientTelecommunicationInformationAll[1].localNumber == message["PID-40~2.7"])
    }

    @Test("ORC-32..34 and OBR-51..54 (v2.8.2) agree with path access")
    func orderV282() throws {
        let orc = segment("ORC", 34, [1: "NW", 32: "20260101", 33: "ALT1^^^HOSP^PLAC", 34: "WF1^Workflow^L"])
        let obr = segment("OBR", 54, [1: "1", 51: "G1^LAB", 52: "PG1^LAB", 53: "ALT2^^^HOSP^PLAC", 54: "P1&LAB^F1&LAB"])
        let message = try Parser().parse(msh("2.8.2") + orc + obr)
        let typedORC = try #require(message.firstSegment(ORC.self))
        let typedOBR = try #require(message.firstSegment(OBR.self))
        #expect(typedORC.advancedBeneficiaryNoticeDate == message["ORC-32"])
        #expect(typedORC.alternatePlacerOrderNumber?.id == message["ORC-33.1"])
        #expect(typedORC.orderWorkflowProfile?.identifier == message["ORC-34.1"])
        #expect(typedOBR.observationGroupID?.entityIdentifier == message["OBR-51.1"])
        #expect(typedOBR.parentObservationGroupID?.namespaceID == message["OBR-52.2"])
        #expect(typedOBR.alternatePlacerOrderNumber?.id == message["OBR-53.1"])
        #expect(typedOBR.parentOrder?.placerAssignedIdentifier == "P1")
        #expect(typedOBR.parentOrder?.placerAssignedIdentifier == message["OBR-54.1.1"])
    }

    @Test("A scalar field retyped to a composite later gains <name>As<T> (CON-18, ID to CWE in v2.6)")
    func asAccessor() throws {
        let con = segment("CON", 18, [1: "1", 18: "en^English^ISO6391"])
        let (message, typed) = try hydratedMessage(CON.self, from: msh("2.6") + con)
        #expect(typed.languageTranslatedToAsCWE?.identifier == message["CON-18.1"])
        #expect(typed.languageTranslatedToAsCWE?.text == message["CON-18.2"])
    }

    @Test("PRT (v2.8.2-only segment) typed accessors agree with path access")
    func prtV282() throws {
        let prt = segment("PRT", 22, [1: "P1^LAB", 2: "AD", 4: "OP^Ordering provider^HL70912", 5: "D1^Doe^Jane~D2^Roe^Rick"])
        let (message, typed) = try hydratedMessage(PRT.self, from: msh("2.8.2") + prt)
        #expect(typed.participation?.identifier == message["PRT-4.1"])
        #expect(typed.participationPersonAll.map(\.familyName) == ["Doe", "Roe"])
        #expect(typed.participationPersonAll[1].idNumber == message["PRT-5~2.1"])
    }

    @Test("A field that repeats only in a later version gets an All accessor (MRG-6, repeating from v2.8.2)")
    func repeatsLater() throws {
        let mrg = segment("MRG", 6, [1: "1^^^HOSP^MR", 6: "V1^^^HOSP^VN~V2^^^HOSP^VN"])
        let (message, typed) = try hydratedMessage(MRG.self, from: msh("2.8.2") + mrg)
        #expect(typed.priorAlternateVisitIdAll.map(\.id) == ["V1", "V2"])
        #expect(typed.priorAlternateVisitIdAll[1].id == message["MRG-6~2.1"])
        #expect(try doc("MRG", "priorAlternateVisitId").contains("Repeats in v2.8.2 only"))
        #expect(try doc("MRG", "priorAlternateVisitIdAll").contains("Repeats in v2.8.2 only"))
        #expect(try doc("AIL", "locationResourceIdAll").contains("Repeats in v2.5.1, v2.6, v2.8.2 only"))
    }

    @Test("A reserved v2.5.1 position later defined as an element gets its own accessor (OBX-20 Observation Site)")
    func meaningChange() throws {
        let obx = segment("OBX", 20, [1: "1", 2: "ST", 3: "X^Y^L", 20: "S1^Site one^L~S2^Site two^L"])
        let (message, typed) = try hydratedMessage(OBX.self, from: msh("2.6") + obx)
        #expect(typed.observationSite?.identifier == message["OBX-20.1"])
        #expect(typed.observationSiteAll.map(\.identifier) == ["S1", "S2"])
        let reserved = try doc("OBX", "reservedForHarmonization20")
        #expect(reserved.contains("v2.6, v2.8.2 define OBX-20 as `Observation Site`: use `observationSite`."))
        #expect(try doc("OBX", "observationSite").contains("v2.5.1 defines OBX-20 as `Reserved for harmonization with V2.6`: use `reservedForHarmonization20`."))
    }

    @Test("DocC names the versions each accessor applies to")
    func versionDocC() throws {
        let observationType = try doc("OBX", "observationType")
        #expect(observationType.contains("Defined in v2.8.2."))
        #expect(observationType.contains("On a message of another version this returns whatever OBX-29 holds on the wire"))
        #expect(try doc("OBX", "abnormalFlags").contains("Renamed `Interpretation Codes` in v2.8.2, which types it `CWE`: use `interpretationCodes`."))
        #expect(try doc("OBX", "observationIdentifier").contains("v2.6, v2.8.2 print `CWE`: use `viewed(as: CWE.self)`."))
        #expect(try doc("CON", "languageTranslatedTo").contains("v2.6, v2.8.2 print `CWE`: use `languageTranslatedToAsCWE`."))
        #expect(try doc("PV1", "bedStatus").contains("Defined in v2.3, v2.3.1, v2.4, v2.5.1, v2.6."))
        #expect(try doc("IN2", "militaryIdNumber").contains("v2.3 prints this element as `Champus ID Number`."))
        let text = try String(contentsOf: Self.generated.appendingPathComponent("PRT.swift"), encoding: .utf8)
        #expect(text.contains("/// Defined in HL7 v2.8.2."))
        let reserved = try doc("OBX", "reservedForHarmonization21")
        #expect(reserved.hasPrefix("OBX-21: Reserved for harmonization with V2.6. No data type: reserved position in v2.5.1."))
    }

    @Test("A same-type rename is a note on the base accessor; a retyped rename is its own accessor, worded as a rename")
    func renameWording() throws {
        let db1 = try String(contentsOf: Self.generated.appendingPathComponent("DB1.swift"), encoding: .utf8)
        #expect(!db1.contains("public var disabilityIndicator"))
        #expect(try doc("DB1", "disabledIndicator").contains("v2.4, v2.6, v2.8.2 print this element as `Disability Indicator`."))
        let producersID = try doc("OBX", "producersID")
        #expect(producersID.contains("Same element as `producersReference`, renamed in v2.6; typed as v2.6 prints it."))
        #expect(producersID.contains("v2.3, v2.3.1, v2.4 print this element as `Producer's ID` (`CE`): use `producersReference`."))
        #expect(try doc("OBX", "producersReference").contains("Renamed `Producer's ID` in v2.6, which types it `CWE`: use `producersID`."))
        #expect(try doc("CON", "relationshipToSubject").contains("Same element as `relationshipToSubjectTable`, renamed in v2.6; typed as v2.8.2 prints it."))
        #expect(try doc("MSH", "messageProfileIdentifier").contains("v2.4 prints `ID`, a scalar: the value reads as the first component."))
        let (message, typed) = try hydratedMessage(MFA.self, from: msh("2.4") + segment("MFA", 5, [1: "MAD", 5: "K1^Key^L"]))
        #expect(typed.primaryKeyValueMfaAsCE?.identifier == message["MFA-5.1"])
    }

    @Test("No two accessors in a struct read the same position with the same Swift type")
    func oneAccessorPerElementAndType() throws {
        // A deprecated alias forwards to another accessor (no `field(`/`repetitions(` body),
        // and an All accessor's array type never equals its singular's, so both pass.
        let files = try FileManager.default.contentsOfDirectory(atPath: Self.generated.path)
            .filter { $0.count == 9 && $0.hasSuffix(".swift") }
        #expect(files.count == 188)
        var duplicates: [String] = []
        for file in files.sorted() {
            let text = try String(contentsOf: Self.generated.appendingPathComponent(file), encoding: .utf8)
            let lines = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            var seen: [String: String] = [:]
            for (i, line) in lines.enumerated() where line.hasPrefix("public var ") && i + 1 < lines.count {
                let decl = line.dropFirst("public var ".count)
                guard let colon = decl.firstIndex(of: ":") else { continue }
                let name = String(decl[..<colon])
                let type = decl[decl.index(after: colon)...].dropLast().trimmingCharacters(in: .whitespaces)
                let body = lines[i + 1]
                guard body.hasPrefix("field(") || body.hasPrefix("repetitions("),
                      let open = body.firstIndex(of: "("),
                      let close = body.firstIndex(of: ")") else { continue }
                let key = "\(body[..<open])\(body[open...close]) \(type)"
                if let other = seen[key] {
                    duplicates.append("\(file.dropLast(6)): \(other) and \(name) both read \(key)")
                }
                seen[key] = name
            }
        }
        #expect(duplicates.isEmpty, "\(duplicates.count) duplicates: \(duplicates.prefix(20))")
    }

    @Test("Representative union signatures are pinned")
    func signatures() {
        let telecom: KeyPath<PID, [XTN]> = \.patientTelecommunicationInformationAll
        let interpretation: KeyPath<OBX, CWE?> = \.interpretationCodes
        let observationType: KeyPath<OBX, String?> = \.observationType
        let lpc: KeyPath<OBX, [CWE]> = \.localProcessControlAll
        let parentOrder: KeyPath<OBR, EIP?> = \.parentOrder
        let asCWE: KeyPath<CON, CWE?> = \.languageTranslatedToAsCWE
        let site: KeyPath<OBX, [CWE]> = \.observationSiteAll
        let mrg: KeyPath<MRG, [CX]> = \.priorAlternateVisitIdAll
        let pinned: [AnyKeyPath] = [telecom, interpretation, observationType, lpc, parentOrder, asCWE, site, mrg]
        #expect(pinned.count == 8)
    }
}
