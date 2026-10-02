// CompositeComponentTests.swift
// P9-3 (V251-C11, V282-C10): every composite view names every component any
// supported version defines, and every generated accessor agrees with path
// access. Components are placed in PID-3 because a view is structural: it
// reads whatever field it wraps.

import Testing
import Foundation
@testable import HL7v2Kit

@Suite("Composite views expose every component (P9-3)")
struct CompositeComponentTests {

    @Test("Every composite view names every component that any supported version defines")
    func viewsAreComplete() {
        let views: [(String, [Int: String])] = [
            ("CE", CE.componentAccessorNames), ("CNE", CNE.componentAccessorNames),
            ("CWE", CWE.componentAccessorNames), ("CX", CX.componentAccessorNames),
            ("EI", EI.componentAccessorNames), ("EIP", EIP.componentAccessorNames),
            ("HD", HD.componentAccessorNames), ("MSG", MSG.componentAccessorNames),
            ("PL", PL.componentAccessorNames), ("PT", PT.componentAccessorNames),
            ("VID", VID.componentAccessorNames), ("XAD", XAD.componentAccessorNames),
            ("XCN", XCN.componentAccessorNames), ("XON", XON.componentAccessorNames),
            ("XPN", XPN.componentAccessorNames), ("XTN", XTN.componentAccessorNames),
        ]
        for (type, names) in views {
            for version in Version.allCases {
                guard let grammar = DataTypeGrammarTable.grammar(type, version: version) else { continue }
                for component in grammar.components {
                    #expect(names[component.index] != nil,
                            "\(type).\(component.index) \(component.name) (v\(version.rawValue)) has no named accessor")
                }
            }
        }
    }

    /// `c1^c2^...^cN`: every component populated and distinct.
    private func populated(_ count: Int) -> String {
        (1...count).map { "c\($0)" }.joined(separator: "^")
    }

    /// Parse `value` into PID-3, view it as `V`, and check each accessor against `PID-3.<index>`.
    private func check<V: CompositeView>(
        _ type: V.Type,
        _ count: Int,
        _ accessors: [(Int, KeyPath<V, String?>)],
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let (message, pid) = try hydratedMessage(PID.self, from: TestWires.adt("PID|1||\(populated(count))"))
        let view = V(field: try #require(pid.field(3), sourceLocation: sourceLocation))
        for (index, keyPath) in accessors {
            let expected = message["PID-3.\(index)"]
            #expect(expected == "c\(index)", "fixture PID-3.\(index)", sourceLocation: sourceLocation)
            #expect(view[keyPath: keyPath] == expected, "\(V.self)-\(index)", sourceLocation: sourceLocation)
        }
    }

    @Test("CX-7..CX-12 agree with path access")
    func cx() throws {
        try check(CX.self, 12, [
            (7, \.effectiveDate), (8, \.expirationDate), (9, \.assigningJurisdiction),
            (10, \.assigningAgencyOrDepartment), (11, \.securityCheck), (12, \.securityCheckScheme),
        ])
    }

    @Test("XPN-6 and XPN-8..XPN-15 agree with path access")
    func xpn() throws {
        try check(XPN.self, 15, [
            (6, \.degree), (8, \.nameRepresentationCode), (9, \.nameContext), (10, \.nameValidityRange),
            (11, \.nameAssemblyOrder), (12, \.effectiveDate), (13, \.expirationDate),
            (14, \.professionalSuffix), (15, \.calledBy),
        ])
    }

    @Test("XAD-8..XAD-23 agree with path access")
    func xad() throws {
        try check(XAD.self, 23, [
            (8, \.otherGeographicDesignation), (9, \.countyParishCode), (10, \.censusTract),
            (11, \.addressRepresentationCode), (12, \.addressValidityRange), (13, \.effectiveDate),
            (14, \.expirationDate), (15, \.expirationReason), (16, \.temporaryIndicator),
            (17, \.badAddressIndicator), (18, \.addressUsage), (19, \.addressee), (20, \.comment),
            (21, \.preferenceOrder), (22, \.protectionCode), (23, \.addressIdentifier),
        ])
    }

    @Test("XCN-7..XCN-25 agree with path access")
    func xcn() throws {
        try check(XCN.self, 25, [
            (7, \.degree), (8, \.sourceTable), (9, \.assigningAuthorityNamespace), (10, \.nameTypeCode),
            (11, \.identifierCheckDigit), (12, \.checkDigitScheme), (13, \.identifierTypeCode),
            (14, \.assigningFacilityNamespace), (15, \.nameRepresentationCode), (16, \.nameContext),
            (17, \.nameValidityRange), (18, \.nameAssemblyOrder), (19, \.effectiveDate),
            (20, \.expirationDate), (21, \.professionalSuffix), (22, \.assigningJurisdiction),
            (23, \.assigningAgencyOrDepartment), (24, \.securityCheck), (25, \.securityCheckScheme),
        ])
    }

    @Test("XTN-8..XTN-11 and XTN-13..XTN-18 agree with path access")
    func xtn() throws {
        try check(XTN.self, 18, [
            (8, \.phoneExtension), (9, \.anyText), (10, \.extensionPrefix), (11, \.speedDialCode),
            (13, \.effectiveStartDate), (14, \.expirationDate), (15, \.expirationReason),
            (16, \.protectionCode), (17, \.sharedTelecommunicationIdentifier), (18, \.preferenceOrder),
        ])
    }

    @Test("PL-5..PL-11 agree with path access")
    func pl() throws {
        try check(PL.self, 11, [
            (5, \.locationStatus), (6, \.personLocationType), (7, \.building), (8, \.floor),
            (9, \.locationDescription), (10, \.comprehensiveLocationIdentifier),
            (11, \.assigningAuthorityForLocation),
        ])
    }

    @Test("CWE-10..CWE-22 agree with path access")
    func cwe() throws {
        try check(CWE.self, 22, [
            (10, \.secondAltIdentifier), (11, \.secondAltText), (12, \.nameOfSecondAltCodingSystem),
            (13, \.secondAltCodingSystemVersionID), (14, \.codingSystemOID), (15, \.valueSetOID),
            (16, \.valueSetVersionID), (17, \.altCodingSystemOID), (18, \.altValueSetOID),
            (19, \.altValueSetVersionID), (20, \.secondAltCodingSystemOID),
            (21, \.secondAltValueSetOID), (22, \.secondAltValueSetVersionID),
        ])
    }

    @Test("CNE-7..CNE-22 agree with path access")
    func cne() throws {
        try check(CNE.self, 22, [
            (7, \.codingSystemVersionID), (8, \.altCodingSystemVersionID), (9, \.originalText),
            (10, \.secondAltIdentifier), (11, \.secondAltText), (12, \.nameOfSecondAltCodingSystem),
            (13, \.secondAltCodingSystemVersionID), (14, \.codingSystemOID), (15, \.valueSetOID),
            (16, \.valueSetVersionID), (17, \.altCodingSystemOID), (18, \.altValueSetOID),
            (19, \.altValueSetVersionID), (20, \.secondAltCodingSystemOID),
            (21, \.secondAltValueSetOID), (22, \.secondAltValueSetVersionID),
        ])
    }

    @Test("XON-3..XON-6, XON-8 and XON-9 agree with path access")
    func xon() throws {
        try check(XON.self, 10, [
            (3, \.idNumber), (4, \.identifierCheckDigit), (5, \.checkDigitScheme),
            (6, \.assigningAuthorityNamespace), (8, \.assigningFacilityNamespace),
            (9, \.nameRepresentationCode),
        ])
    }

    @Test("A generated HD-typed component also reads as a typed HD through component(_:as:)")
    func generatedSubComposite() throws {
        let wire = TestWires.adt("PID|1||c1^c2^c3^c4^c5^c6^c7^c8^c9^c10^HOSP&1.2.36.1&ISO")
        let (message, pid) = try hydratedMessage(PID.self, from: wire)
        let pl = PL(field: try #require(pid.field(3)))
        #expect(pl.assigningAuthorityForLocation == "HOSP")
        #expect(pl.component(11, as: HD.self)?.universalID == message["PID-3.11.2"])
    }

    @Test("A generated accessor treats absent and empty components as the hand-written ones do")
    func absentAndEmpty() throws {
        let (_, short) = try hydratedMessage(PID.self, from: TestWires.adt("PID|1||c1"))
        let shortCX = CX(field: try #require(short.field(3)))
        #expect(shortCX.effectiveDate == nil)
        #expect(shortCX.checkDigit == nil)

        let (_, empty) = try hydratedMessage(PID.self, from: TestWires.adt("PID|1||^^^^^^^"))
        let emptyCX = CX(field: try #require(empty.field(3)))
        #expect(emptyCX.effectiveDate == "")
        #expect(emptyCX.effectiveDate == emptyCX.checkDigit)
        #expect(emptyCX.expirationDate == emptyCX.id)
    }

    @Test("A DR-typed component (no view) returns the range start; the documented field route gives the end")
    func nonViewComposite() throws {
        let wire = TestWires.adt("PID|1||c1^c2^c3^c4^c5^c6^c7^c8^c9^20200101&20251231")
        let (message, pid) = try hydratedMessage(PID.self, from: wire)
        let xpn = XPN(field: try #require(pid.field(3)))
        #expect(xpn.nameValidityRange == "20200101")
        #expect(xpn.nameValidityRange == message["PID-3.10.1"])
        // The route the generated DocC gives: components[index - 1].subcomponents[1] is DR.2.
        let end = xpn.field.repetitions.first?.components[9].subcomponents[1].value
        #expect(end == "20251231")
        #expect(end == message["PID-3.10.2"])
    }
}
