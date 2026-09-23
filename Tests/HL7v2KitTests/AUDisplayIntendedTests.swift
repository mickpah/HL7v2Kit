import Testing
@testable import HL7v2Kit

/// M30 — HL7au:00044.4.3: the CE <text> component must be valued as what is
/// intended for display, "in some locations user display is not intended and
/// the text may be blank". The locations are not on the wire; the caller
/// asserts that display is intended.
@Suite("AU display-intended assertion")
struct AUDisplayIntendedTests {
    private func issues(_ segment: String, intended: Bool, locale: HL7Locale = .auLocalisation) throws -> [ValidationIssue] {
        var options = ValidationOptions()
        options.auDisplayIntended = intended
        let message = try Parser(locale: locale).parse(TestWires.oru(segment))
        return Validator(options: options, locale: locale).validate(message).issues
            .filter { $0.message.contains("00044.4.3") }
    }

    // OBR-4 Universal Service Identifier is CE on v2.5.1.
    private let noText = "OBR|1|P1^PLACER|F1^FILLER|26604-1^^LN|||20240101120000"
    private let withText = "OBR|1|P1^PLACER|F1^FILLER|26604-1^Full blood count^LN|||20240101120000"

    @Test("Asserted: a CE with an identifier and no text fires at CE-2")
    func fires() throws {
        let found = try issues(noText, intended: true)
        #expect(found.count == 1 && found.first?.location.fieldIndex == 4 && found.first?.location.componentIndex == 2)
    }

    @Test("Asserted: text present passes")
    func passes() throws {
        #expect(try issues(withText, intended: true).isEmpty)
    }

    @Test("Unasserted, or outside the AU locale, the carve-out stands and nothing fires")
    func silent() throws {
        #expect(try issues(noText, intended: false).isEmpty)
        #expect(try issues(noText, intended: true, locale: .international).isEmpty)
    }
}
