// CompositeReleasedSurfaceTests.swift
// P9-3 (ADR-014, ADR-020): generating composite accessors must not change a
// released one. The snapshot below is every `public` declaration in v3.13.0's
// Sources/HL7v2Kit/Composite/ files (`git show v3.13.0:<path>`), normalised to
// its signature. Each must still be declared, with the same name and type, in
// the hand-written file or its generated `<T>+Components.swift`, and no view may
// declare an accessor name twice.

import Testing
import Foundation

@Suite("Released composite surface is unchanged (P9-3)")
struct CompositeReleasedSurfaceTests {

    /// `File|signature` for every public declaration at v3.13.0.
    static let releasedV3_13_0: [String] = [
        "CE|public struct CE: CompositeView",
        "CE|public static let requiredComponents: [RequiredComponent]",
        "CE|public let field: Field",
        "CE|public init(field: Field)",
        "CE|public var identifier: String?",
        "CE|public var text: String?",
        "CE|public var nameOfCodingSystem: String?",
        "CE|public var altIdentifier: String?",
        "CE|public var altText: String?",
        "CE|public var nameOfAltCodingSystem: String?",
        "CNE|public struct CNE: CompositeView",
        "CNE|public static let requiredComponents: [RequiredComponent]",
        "CNE|public let field: Field",
        "CNE|public init(field: Field)",
        "CNE|public var identifier: String?",
        "CNE|public var text: String?",
        "CNE|public var nameOfCodingSystem: String?",
        "CNE|public var altIdentifier: String?",
        "CNE|public var altText: String?",
        "CNE|public var nameOfAltCodingSystem: String?",
        "CWE|public struct CWE: CompositeView",
        "CWE|public static let requiredComponentSet: RequiredComponentSet?",
        "CWE|public let field: Field",
        "CWE|public init(field: Field)",
        "CWE|public var identifier: String?",
        "CWE|public var text: String?",
        "CWE|public var nameOfCodingSystem: String?",
        "CWE|public var altIdentifier: String?",
        "CWE|public var altText: String?",
        "CWE|public var nameOfAltCodingSystem: String?",
        "CWE|public var codingSystemVersionID: String?",
        "CWE|public var altCodingSystemVersionID: String?",
        "CWE|public var originalText: String?",
        "CX|public struct CX: CompositeView",
        "CX|public static let requiredComponents: [RequiredComponent]",
        "CX|public let field: Field",
        "CX|public init(field: Field)",
        "CX|public var id: String?",
        "CX|public var checkDigit: String?",
        "CX|public var checkDigitScheme: String?",
        "CX|public var assigningAuthorityNamespace: String?",
        "CX|public var identifierTypeCode: String?",
        "CX|public var assigningFacilityNamespace: String?",
        "CompositeView|public protocol CompositeView: Sendable, Equatable, Hashable",
        "CompositeView|public static var requiredComponents: [RequiredComponent]",
        "CompositeView|public static var requiredComponentSet: RequiredComponentSet?",
        "CompositeView|public init(repetition: Repetition)",
        "EI|public struct EI: CompositeView",
        "EI|public static let requiredComponents: [RequiredComponent]",
        "EI|public let field: Field",
        "EI|public init(field: Field)",
        "EI|public var entityIdentifier: String?",
        "EI|public var namespaceID: String?",
        "EI|public var universalID: String?",
        "EI|public var universalIDType: String?",
        "EIP|public struct EIP: CompositeView",
        "EIP|public static let requiredComponentSet: RequiredComponentSet?",
        "EIP|public let field: Field",
        "EIP|public init(field: Field)",
        "EIP|public var placerAssignedIdentifier: String?",
        "EIP|public var fillerAssignedIdentifier: String?",
        "HD|public struct HD: CompositeView",
        "HD|public static let requiredComponentSet: RequiredComponentSet?",
        "HD|public let field: Field",
        "HD|public init(field: Field)",
        "HD|public var namespaceID: String?",
        "HD|public var universalID: String?",
        "HD|public var universalIDType: String?",
        "MSG|public struct MSG: CompositeView",
        "MSG|public static let requiredComponents: [RequiredComponent]",
        "MSG|public let field: Field",
        "MSG|public init(field: Field)",
        "MSG|public var messageCode: String?",
        "MSG|public var triggerEvent: String?",
        "MSG|public var messageStructure: String?",
        "PL|public struct PL: CompositeView",
        "PL|public static let requiredComponentSet: RequiredComponentSet?",
        "PL|public let field: Field",
        "PL|public init(field: Field)",
        "PL|public var pointOfCare: String?",
        "PL|public var room: String?",
        "PL|public var bed: String?",
        "PL|public var facility: String?",
        "PT|public struct PT: CompositeView",
        "PT|public static let requiredComponents: [RequiredComponent]",
        "PT|public let field: Field",
        "PT|public init(field: Field)",
        "PT|public var processingID: String?",
        "PT|public var processingMode: String?",
        "RequiredComponent|public struct RequiredComponent: Sendable, Equatable, Hashable",
        "RequiredComponent|public let index: Int",
        "RequiredComponent|public let name: String",
        "RequiredComponent|public init(index: Int, name: String)",
        "RequiredComponentSet|public struct RequiredComponentSet: Sendable, Equatable, Hashable",
        "RequiredComponentSet|public enum Semantics: Sendable, Equatable, Hashable",
        "RequiredComponentSet|public let components: [RequiredComponent]",
        "RequiredComponentSet|public let semantics: Semantics",
        "RequiredComponentSet|public let description: String",
        "RequiredComponentSet|public init(",
        "RequiredComponentSet|public func isSatisfied(populatedIndices: Set<Int>) -> Bool",
        "VID|public struct VID: CompositeView",
        "VID|public static let requiredComponents: [RequiredComponent]",
        "VID|public let field: Field",
        "VID|public init(field: Field)",
        "VID|public var versionID: String?",
        "VID|public var internationalizationCode: String?",
        "VID|public var internationalVersionID: String?",
        "XAD|public struct XAD: CompositeView",
        "XAD|public static let requiredComponents: [RequiredComponent]",
        "XAD|public let field: Field",
        "XAD|public init(field: Field)",
        "XAD|public var streetAddress: String?",
        "XAD|public var otherDesignation: String?",
        "XAD|public var city: String?",
        "XAD|public var state: String?",
        "XAD|public var zip: String?",
        "XAD|public var country: String?",
        "XAD|public var addressType: String?",
        "XCN|public struct XCN: CompositeView",
        "XCN|public static let requiredComponents: [RequiredComponent]",
        "XCN|public let field: Field",
        "XCN|public init(field: Field)",
        "XCN|public var idNumber: String?",
        "XCN|public var familyName: String?",
        "XCN|public var givenName: String?",
        "XCN|public var middleName: String?",
        "XCN|public var suffix: String?",
        "XCN|public var prefix_: String?",
        "XON|public struct XON: CompositeView",
        "XON|public static let requiredComponents: [RequiredComponent]",
        "XON|public let field: Field",
        "XON|public init(field: Field)",
        "XON|public var organizationName: String?",
        "XON|public var organizationNameTypeCode: String?",
        "XON|public var identifierTypeCode: String?",
        "XON|public var organizationIdentifier: String?",
        "XPN|public struct XPN: CompositeView",
        "XPN|public static let requiredComponents: [RequiredComponent]",
        "XPN|public let field: Field",
        "XPN|public init(field: Field)",
        "XPN|public var familyName: String?",
        "XPN|public var givenName: String?",
        "XPN|public var middleName: String?",
        "XPN|public var suffix: String?",
        "XPN|public var prefix: String?",
        "XPN|public var nameTypeCode: String?",
        "XTN|public struct XTN: CompositeView",
        "XTN|public static let requiredComponentSet: RequiredComponentSet?",
        "XTN|public let field: Field",
        "XTN|public init(field: Field)",
        "XTN|public var telephoneNumber: String?",
        "XTN|public var telecommunicationUseCode: String?",
        "XTN|public var telecommunicationEquipmentType: String?",
        "XTN|public var emailAddress: String?",
        "XTN|public var countryCode: String?",
        "XTN|public var areaCityCode: String?",
        "XTN|public var localNumber: String?",
        "XTN|public var unformattedTelephoneNumber: String?",
    ]

    static let compositeRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // HL7v2KitTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // repository root
        .appendingPathComponent("Sources/HL7v2Kit/Composite")

    /// The normalised public signatures declared at HEAD for `file`: the
    /// hand-written file plus its generated extension, when there is one.
    static func signatures(_ file: String) -> [String] {
        let paths = [
            compositeRoot.appendingPathComponent("\(file).swift"),
            compositeRoot.appendingPathComponent("Generated/\(file)+Components.swift"),
        ]
        return paths.compactMap { try? String(contentsOf: $0, encoding: .utf8) }
            .flatMap { $0.components(separatedBy: "\n") }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("public ") }
            .map { line in
                var s = line
                if let brace = s.range(of: " {") { s = String(s[..<brace.lowerBound]) }
                if let assign = s.range(of: " = ") { s = String(s[..<assign.lowerBound]) }
                return s.trimmingCharacters(in: .whitespaces)
            }
    }

    @Test("Every v3.13.0 public composite declaration is still declared with the same name and type")
    func releasedSurfaceIsUnchanged() {
        #expect(Self.releasedV3_13_0.count == 158)
        for entry in Self.releasedV3_13_0 {
            let parts = entry.split(separator: "|", maxSplits: 1).map(String.init)
            #expect(Self.signatures(parts[0]).contains(parts[1]), "\(parts[0]): `\(parts[1])` changed or removed")
        }
    }

    @Test("No composite view declares an accessor name twice")
    func accessorNamesAreUnique() {
        // One accessor per component index any supported version defines.
        let views: [String: Int] = [
            "CE": 6, "CNE": 22, "CWE": 22, "CX": 12, "EI": 4, "EIP": 2, "HD": 3, "MSG": 3,
            "PL": 11, "PT": 2, "VID": 3, "XAD": 23, "XCN": 25, "XON": 10, "XPN": 15, "XTN": 18,
        ]
        for (view, expected) in views.sorted(by: { $0.key < $1.key }) {
            let names = Self.signatures(view)
                .filter { $0.hasPrefix("public var ") }
                .compactMap { $0.dropFirst("public var ".count).split(separator: ":").first.map(String.init) }
            let duplicates = Dictionary(grouping: names, by: { $0 }).filter { $0.value.count > 1 }.keys.sorted()
            #expect(duplicates.isEmpty, "\(view) declares \(duplicates) more than once")
            #expect(names.count == expected, "\(view): \(names.count) accessors, expected \(expected)")
        }
    }
}
