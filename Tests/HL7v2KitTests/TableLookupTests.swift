// TableLookupTests.swift
// The two code-table lookups: one reads a version's own print, the other the tables a
// message of that version is checked against (ADR-018).

import Testing
@testable import HL7v2Kit

@Suite("Code-table lookup")
struct TableLookupTests {
    @Test("The resolving lookup reads the grammar version's tables")
    func resolvingLookup() {
        #expect(HL7TableRegistry.table("0001", resolving: .v2_7) != nil)
        #expect(HL7TableRegistry.table("0001", resolving: .v2_7) == HL7TableRegistry.table("0001", version: .v2_7_1))
        #expect(HL7TableRegistry.table("0001", resolving: .v2_8) == HL7TableRegistry.table("0001", version: .v2_8_2))
        #expect(HL7TableRegistry.table("9999", resolving: .v2_7) == nil)
    }

    @Test("The version lookup stays literal: 2.7 and 2.8 own no tables")
    func versionLookupIsLiteral() {
        #expect(HL7TableRegistry.table("0001", version: .v2_7) == nil)
        #expect(HL7TableRegistry.table("0001", version: .v2_8) == nil)
    }

    @Test("For a version with its own tables the two lookups agree on every table")
    func lookupsAgree() {
        for version in Version.allCases where version.grammarVersion == version {
            let numbers = HL7TableRegistry.tables(for: version).keys
            #expect(!numbers.isEmpty, "\(version)")
            for number in numbers {
                #expect(HL7TableRegistry.table(number, resolving: version)
                        == HL7TableRegistry.table(number, version: version), "\(version) \(number)")
            }
        }
    }
}
