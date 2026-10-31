// SignatureCompatibilityTests+P00.swift
// ADR-014 pins for the P00 additions. Changing any of them stops this file compiling.

import Testing
import HL7v2Kit

extension SignatureCompatibilityTests {
    @Test("P00 S1-1: Message.trailingSegmentTerminator keeps its signature")
    func trailingSegmentTerminatorSignature() {
        let flag: WritableKeyPath<Message, Bool> = \.trailingSegmentTerminator
        _ = flag
    }

    @Test("P00 S1-3: ParseError.lineFeedAfterSegmentTerminator keeps its signature")
    func lineFeedErrorSignature() {
        let error: ParseError = .lineFeedAfterSegmentTerminator(position: 2)
        #expect(error == .lineFeedAfterSegmentTerminator(position: 2))
        #expect(error.description.contains("2"))
    }

    @Test("P00 S2-1: the path wildcards, the string form and values(at:) keep their signatures")
    func pathSyntaxSignatures() throws {
        let segmentWildcard: KeyPath<Path, Bool> = \.segmentWildcard
        let repetitionWildcard: KeyPath<Path, Bool> = \.repetitionWildcard
        let values: (Message) -> (Path) -> [String] = Message.values(at:)
        _ = (segmentWildcard, repetitionWildcard, values)
        let described: any CustomStringConvertible = try Path("PID-3")
        #expect(described.description == "PID-3")
    }

    @Test("P00 S2-2: PathValue and populatedPaths() keep their signatures")
    func enumerationSignatures() throws {
        let populated: (Message) -> () -> [PathValue] = Message.populatedPaths
        let pair = PathValue(path: try Path("PID-3"), value: "X")
        let path: KeyPath<PathValue, Path> = \.path
        let value: KeyPath<PathValue, String> = \.value
        _ = (populated, path, value)
        #expect(pair.value == "X")
    }
}
