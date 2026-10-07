#if os(macOS)
import Foundation
import Testing
@testable import HL7v2Kit
@testable import MessageViewer

/// The `MessageViewer` example (`Examples/MessageViewer`) shows a message as a grid, one row per
/// segment and one cell per field, each cell coloured by the worst validation issue on it.
/// These tests cover the grid model; the SwiftUI view is not exercised here.
@Suite("MessageViewer example")
struct MessageViewerExampleTests {
    static let wire = QuickStartExampleTests.wire

    private static func grid(options: ValidationOptions, locale: HL7Locale = .international) throws -> CellGrid {
        let message = try Parser().parse(Self.wire)
        return CellGrid(message: message, report: Validator(options: options, locale: locale).validate(message))
    }

    @Test("under the default preset the sample draws one yellow cell, on PID-7")
    func defaultPreset() throws {
        let grid = try Self.grid(options: .default)
        #expect(grid.rows.map(\.segmentID) == ["MSH", "PID", "PV1", "OBR", "OBX"])
        #expect(grid.unplaced.isEmpty)
        let coloured = grid.rows.enumerated().flatMap { row in
            row.element.cells.enumerated().compactMap { cell in
                cell.element.state == .clean ? nil : (row.element.segmentID, cell.offset, cell.element.state)
            }
        }
        #expect(coloured.count == 1)
        #expect(coloured.first?.0 == "PID")
        #expect(coloured.first?.1 == 7)
        #expect(coloured.first?.2 == .warning)
        #expect(grid.rows[1].cells[7].notes.count == 1)
    }

    @Test("under strict AU the sample draws red cells")
    func strictAU() throws {
        let grid = try Self.grid(options: .strict, locale: .auLocalisation)
        let states = grid.rows.flatMap(\.cells).map(\.state)
        #expect(states.contains(.error))
        #expect(states.contains(.warning))
        #expect(grid.errorCount == 16)
        #expect(grid.warningCount == 1)
    }

    @Test("a row has the segment ID in cell 0 and one cell per field; MSH shows its separators")
    func rowShape() throws {
        let message = try Parser().parse(Self.wire)
        let grid = CellGrid(message: message, report: ValidationReport(issues: []))
        for (row, segment) in zip(grid.rows, message.segments) {
            #expect(row.cells.count == segment.fields.count)
            #expect(row.cells[0].text == segment.segmentID)
        }
        #expect(grid.rows[0].cells[1].text == "|")
        #expect(grid.rows[0].cells[2].text == #"^~\&"#)
        #expect(grid.rows[1].cells[3].text == "SYN-000123^^^SYNTH_PATH^MR")
        #expect(grid.rows[2].cells.count == 3)
    }

    @Test("an issue on the second OBX colours the second OBX row, not the first")
    func occurrenceMatching() throws {
        let message = try Parser().parse(Self.wire + #"OBX|2|NM|2823-3^Potassium^LN||4.1|mmol/L^mmol/L^UCUM|3.5-5.2|N|||F"# + "\r")
        let issue = ValidationIssue(
            severity: .error, code: .requiredFieldMissing,
            location: IssueLocation(segmentID: "OBX", segmentIndex: 2, fieldIndex: 5),
            message: "synthetic")
        let grid = CellGrid(message: message, report: ValidationReport(issues: [issue]))
        #expect(grid.rows.count == 6)
        #expect(grid.rows[4].cells[5].state == .clean)
        #expect(grid.rows[5].cells[5].state == .error)
        #expect(grid.rows[5].cells[5].notes == ["error: synthetic"])
    }

    @Test("a segment-level issue colours the ID cell; an issue on an absent segment is listed, not lost")
    func segmentLevelAndAbsent() throws {
        let message = try Parser().parse(Self.wire)
        let onSegment = ValidationIssue(
            severity: .warning, code: .requiredFieldMissing,
            location: IssueLocation(segmentID: "PV1", segmentIndex: 1), message: "whole segment")
        let absent = ValidationIssue(
            severity: .error, code: .requiredFieldMissing,
            location: IssueLocation(segmentID: "NK1", segmentIndex: 1), message: "missing")
        let grid = CellGrid(message: message, report: ValidationReport(issues: [onSegment, absent]))
        #expect(grid.rows[2].cells[0].state == .warning)
        #expect(grid.unplaced == ["NK1[1]: missing"])
    }

    @Test("an issue past the last field present lands on the ID cell, not nowhere")
    func trailingField() throws {
        let message = try Parser().parse(Self.wire)
        let issue = ValidationIssue(
            severity: .error, code: .requiredFieldMissing,
            location: IssueLocation(segmentID: "PV1", segmentIndex: 1, fieldIndex: 44), message: "PV1-44")
        let grid = CellGrid(message: message, report: ValidationReport(issues: [issue]))
        #expect(grid.rows[2].cells.count == 3)
        #expect(grid.rows[2].cells[0].state == .error)
        #expect(grid.unplaced.isEmpty)
    }

    @Test("pasted text with LF, CRLF or trailing blank lines becomes CR-terminated segments")
    func wireNormalisation() {
        #expect(CellGrid.wire(from: "MSH|a\nPID|b") == "MSH|a\rPID|b\r")
        #expect(CellGrid.wire(from: "MSH|a\r\nPID|b\r\n\r\n") == "MSH|a\rPID|b\r")
        #expect(CellGrid.wire(from: "MSH|a\r") == "MSH|a\r")
        #expect(CellGrid.wire(from: "\n\n") == "")
    }

    @Test("a cell is titled with its segment, field number and the field's name for the message version")
    func titles() throws {
        let message = try Parser().parse(Self.wire + "ZAU|x|y\r")
        let grid = CellGrid(message: message, report: ValidationReport(issues: []))
        #expect(grid.rows[0].cells[0].title == "MSH")
        #expect(grid.rows[0].cells[1].title == "MSH-1 Field Separator")
        #expect(grid.rows[1].cells[7].title == "PID-7 Date/Time of Birth")
        #expect(grid.rows[5].cells[2].title == "ZAU-2")
        #expect(grid.rows[1].cells[7].tooltip == "PID-7 Date/Time of Birth")
    }

    @Test("the tooltip is the title and then one line per issue")
    func tooltip() throws {
        let grid = try Self.grid(options: .default)
        let lines = grid.rows[1].cells[7].tooltip.split(separator: "\n")
        #expect(lines.count == 2)
        #expect(lines[0] == "PID-7 Date/Time of Birth")
        #expect(lines[1].hasPrefix("warning: "))
    }

    @Test("the issues text has one line per issue, titled")
    func issuesText() throws {
        let grid = try Self.grid(options: .default)
        let lines = grid.issuesText.split(separator: "\n")
        #expect(lines.count == 1)
        #expect(lines[0].hasPrefix("PID-7 Date/Time of Birth: warning: "))
        #expect(try Self.grid(options: .strict, locale: .auLocalisation).issuesText.split(separator: "\n").count == 17)
    }

    @Test("a cell takes the worst severity; info alone stays clean")
    func severityFolding() {
        func issue(_ severity: IssueSeverity) -> ValidationIssue {
            ValidationIssue(severity: severity, code: .requiredFieldMissing,
                            location: IssueLocation(segmentID: "PID", segmentIndex: 1, fieldIndex: 3), message: "x")
        }
        #expect(CellState([issue(.info)]) == .clean)
        #expect(CellState([]) == .clean)
        #expect(CellState([issue(.info), issue(.warning)]) == .warning)
        #expect(CellState([issue(.warning), issue(.error), issue(.info)]) == .error)
    }
}
#endif
