// SignatureCompatibilityTests+SourceMap.swift
// ADR-014 pins for the source map (P01 R4). Changing any of them stops this file compiling.

import Foundation
import Testing
import HL7v2Kit

extension SignatureCompatibilityTests {
    @Test("R4: WireLocation, SourceMap (range(of:), location(at:), utf16Range(_:)) and Parser.sourceMap(of:) keep their signatures")
    func sourceMapSignatures() {
        let make: (String, Int, Int?, Int?, Int?, Int?) -> WireLocation =
            WireLocation.init(segmentID:segmentIndex:fieldIndex:repetitionIndex:componentIndex:subcomponentIndex:)
        let fromIssue: (IssueLocation) -> WireLocation = WireLocation.init(_:)
        let path: KeyPath<WireLocation, Path?> = \.path
        let text: KeyPath<SourceMap, String> = \.text
        let range: (SourceMap) -> (WireLocation) -> Range<Int>? = SourceMap.range(of:)
        let build: (Parser) -> (Data) throws(ParseError) -> SourceMap = Parser.sourceMap(of:)
        let place: (SourceMap) -> (Int) -> WireLocation? = SourceMap.location(at:)
        let utf16: (SourceMap) -> (Range<Int>) -> Range<Int> = SourceMap.utf16Range(_:)
        _ = (make, fromIssue, path, text, range, build, place, utf16)
    }

    @Test("R4: WireLocation's six properties keep their names and types")
    func wireLocationProperties() {
        let segmentID: KeyPath<WireLocation, String> = \.segmentID
        let segmentIndex: KeyPath<WireLocation, Int> = \.segmentIndex
        let field: KeyPath<WireLocation, Int?> = \.fieldIndex
        let repetition: KeyPath<WireLocation, Int?> = \.repetitionIndex
        let component: KeyPath<WireLocation, Int?> = \.componentIndex
        let subcomponent: KeyPath<WireLocation, Int?> = \.subcomponentIndex
        _ = (segmentID, segmentIndex, field, repetition, component, subcomponent)
    }
}
