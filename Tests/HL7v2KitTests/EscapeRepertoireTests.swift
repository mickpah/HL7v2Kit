// EscapeRepertoireTests.swift
// #13: a value with no wire text (built in code, set by an edit) writes a `\…\` run as an escape
// only when the standard defines it (v2.5.1 Chapter 2 sections 2.7.1 to 2.7.6; `\P\` from v2.7).
// Any other run is text, so its escape characters are written `\E\`.

import Testing
import Foundation
@testable import HL7v2Kit

@Suite("Escape repertoire for values written in code")
struct EscapeRepertoireTests {
    static let enc = EncodingCharacters.default

    @Test("A run the standard defines is written as the escape", arguments: [
        #"\H\240*\N\"#, #"\P\"#, #"\Z1\"#, #"\ZLOCAL\"#, #"\C2842\"#, #"\M2442\"#, #"\M242844\"#,
        #"\.br\"#, #"\.fi\"#, #"\.nf\"#, #"\.ce\"#, #"\.sp\"#, #"\.sp2\"#, #"\.sp 2\"#,
        #"\.in+4\"#, #"\.in-4\"#, #"\.in4\"#, #"\.ti-4\"#, #"\.sk3\"#,
        #"\C2d41\"#,   // hex digits in either case, as the decoder reads \X..\
    ])
    func repertoireCopied(_ value: String) {
        #expect(EscapeSequences.encode(value, encoding: Self.enc) == value)
    }

    @Test("Any other run is text: its escape characters are written as the escape escape", arguments: zip([
        #"C:\Users\me"#, #"\Q\"#, #"\Z\"#, #"\C28\"#, #"\C28421\"#, #"\CZZZZ\"#, #"\M24\"#, #"\M24284\"#,
        #"\.xx\"#, #"\.br2\"#, #"\.in\"#, #"\.sk-1\"#, #"\.sp \"#, #"\X41\"#, #"\F\"#, #"\XZZ\"#,
        // Only .in and .ti take a sign; one space at most; H, N and P take no data.
        #"\.sp+2\"#, #"\.sp  2\"#, #"\Hx\"#,
    ], [
        #"C:\E\Users\E\me"#, #"\E\Q\E\"#, #"\E\Z\E\"#, #"\E\C28\E\"#, #"\E\C28421\E\"#, #"\E\CZZZZ\E\"#,
        #"\E\M24\E\"#, #"\E\M24284\E\"#, #"\E\.xx\E\"#, #"\E\.br2\E\"#, #"\E\.in\E\"#, #"\E\.sk-1\E\"#,
        #"\E\.sp \E\"#, #"\E\X41\E\"#, #"\E\F\E\"#, #"\E\XZZ\E\"#,
        #"\E\.sp+2\E\"#, #"\E\.sp  2\E\"#, #"\E\Hx\E\"#,
    ]))
    func otherRunsAreText(_ value: String, _ wire: String) {
        #expect(EscapeSequences.encode(value, encoding: Self.enc) == wire)
        #expect(EscapeSequences.decode(wire, encoding: Self.enc) == value)
    }

    @Test("A parsed unknown escape copied as a string is written as text; the original keeps its wire text")
    func copiedValueIsText() throws {
        let msh = #"MSH|^~\&|APP|FAC|||20260101||ADT^A01^ADT_A01|C1|P|2.5.1"#
        var message = try Parser().parse(msh + "\r" + #"NTE|1||\Users\"# + "\rNTE|2||x\r")
        let copied = try #require(message["NTE[1]-3"])
        try message.set(copied, at: Path("NTE[2]-3"))
        let expected = msh + "\r" + #"NTE|1||\Users\"# + "\r" + #"NTE|2||\E\Users\E\"# + "\r"
        #expect(message.serialize() == Data(expected.utf8))
    }
}
