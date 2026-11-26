// SignatureCompatibilityTests+P02.swift
// ADR-014 pins for the additions of the P02 requirements. Changing any of them stops this
// file compiling.

import Foundation
import Testing
import HL7v2Kit

extension SignatureCompatibilityTests {
    @Test("Message.indexOfSegment(at:) keeps its signature")
    func indexOfSegmentSignature() {
        let index: (Message) -> (Path) -> Int? = Message.indexOfSegment(at:)
        _ = index
    }

    @Test("Version.MSH12Reading and Message.msh12Reading keep their signatures")
    func msh12ReadingSignature() {
        let reading: KeyPath<Message, Version.MSH12Reading> = \.msh12Reading
        let cases: [Version.MSH12Reading] = [.empty, .recognised(.v2_5_1), .unresolved(vid1: "")]
        let sendable: any Sendable = cases
        _ = (reading, sendable)
    }

    @Test("HL7TableRegistry.table(_:resolving:) keeps its signature")
    func resolvingTableLookupSignature() {
        let lookup: (String, Version) -> HL7Table? = HL7TableRegistry.table(_:resolving:)
        _ = lookup
    }

    @Test("FieldGrammar.tables and the initialiser that takes it keep their signatures")
    func fieldGrammarTablesSignature() {
        let tables: KeyPath<FieldGrammar, [String]> = \.tables
        let field = FieldGrammar(index: 10, name: "Race", dataType: "CWE", optionality: .optional,
                                 repeatability: .multiple, tables: ["0005"])
        #expect(field.tables == ["0005"] && field.table == nil)
        _ = tables
    }

    @Test("Parser.messageRanges(inCarried:) keeps its signature")
    func messageRangesSignature() {
        let ranges: (Data) -> [Range<Int>] = Parser.messageRanges(inCarried:)
        _ = ranges
    }
}
