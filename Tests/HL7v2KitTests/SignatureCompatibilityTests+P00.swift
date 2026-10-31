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

    @Test("P00 S3-1: the editing methods and MessageEditError keep their signatures")
    func editingSignatures() throws {
        var message = try Parser().parse("MSH|^~\\&|A|B|C|D|20260101||ADT^A01|M1|P|2.5.1\rPID|1\r")
        let set: (inout Message, String, Path) throws -> Void = { try $0.set($1, at: $2) }
        let clear: (inout Message, Path) throws -> Void = { try $0.clear(at: $1) }
        let insert: (inout Message, String, Path) throws -> Void = { try $0.insertRepetition($1, at: $2) }
        try set(&message, "X", Path("PID-5"))
        try clear(&message, Path("PID-5"))
        try insert(&message, "Y", Path("PID-3~1"))
        let path = try Path("PID-3")
        let errors: [MessageEditError] = [
            .segmentNotFound(segmentID: "ZZZ", occurrence: 1), .delimiterField(segmentID: "MSH", field: 2),
            .wildcardPath(path), .notARepetition(path), .invalidPath(path),
            .unsupportedCharacterEncoding(declared: "X"),
            .characterNotEncodable(.ascii),
        ]
        #expect(errors.count == 7)
        let _: KeyPath<Message, Version> = \.version
        let _: KeyPath<Message, CharacterEncoding> = \.characterEncoding
        #expect(message["PID-3"] == "Y")
    }

    @Test("P00 S4-1: ZSegmentGrammar and ValidationOptions.zSegmentGrammars keep their signatures")
    func zSegmentGrammarSignatures() {
        let grammars: WritableKeyPath<ValidationOptions, [ZSegmentGrammar]> = \.zSegmentGrammars
        let grammar: KeyPath<ZSegmentGrammar, SegmentGrammar> = \.grammar
        let scope: KeyPath<ZSegmentGrammar, Set<String>> = \.sendingApplications
        let empty = SegmentGrammar(segmentID: "ZAU", version: "2.5.1", fields: [])
        let unscoped = ZSegmentGrammar(empty)
        let scoped = ZSegmentGrammar(empty, sendingApplications: ["LAB"])
        _ = (grammars, grammar, scope)
        #expect(unscoped.sendingApplications.isEmpty)
        #expect(scoped.sendingApplications == ["LAB"])
        #expect(ValidationOptions.default.zSegmentGrammars.isEmpty)
    }
}
