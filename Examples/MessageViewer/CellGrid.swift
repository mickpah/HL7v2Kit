import HL7v2Kit

/// The colour of a cell: the worst validation severity on the field it shows.
/// `info` leaves a cell clean; the tooltip still lists it.
enum CellState: Equatable, Sendable {
    case clean, warning, error

    init(_ issues: [ValidationIssue]) {
        if issues.contains(where: { $0.severity == .error }) {
            self = .error
        } else if issues.contains(where: { $0.severity == .warning }) {
            self = .warning
        } else {
            self = .clean
        }
    }
}

struct Cell: Equatable, Sendable {
    let text: String
    /// `"PID-7 Date/Time of Birth"`: the field's name from the grammar of the message's version,
    /// or just `"ZAU-2"` for a segment the version does not define; the segment ID for cell 0.
    let title: String
    let state: CellState
    /// One line per issue on the cell, `"warning: ..."`.
    let notes: [String]

    /// What the mouse shows over the cell.
    var tooltip: String { ([title] + notes).joined(separator: "\n") }
}

struct Row: Equatable, Sendable {
    let segmentID: String
    /// Cell 0 is the segment ID; cell n is field n (so MSH-1 is the field separator).
    let cells: [Cell]
}

/// One row per segment, one cell per field, each cell carrying the issues located on it.
struct CellGrid: Equatable, Sendable {
    let rows: [Row]
    /// Issues whose segment is not in the message (a missing required segment, for example).
    let unplaced: [String]
    /// The report's totals, for the window's subtitle.
    let errorCount: Int
    let warningCount: Int

    init(message: Message, report: ValidationReport) {
        let chars = message.encodingCharacters
        let grammar = Self.grammar(for: message.version)
        // Key: segment ID, 1-based occurrence among segments with that ID (IssueLocation.segmentIndex),
        // field index (0 for a segment-level issue).
        var byCell: [String: [ValidationIssue]] = [:]
        var present: Set<String> = []
        var occurrence: [String: Int] = [:]
        var fieldCounts: [String: [Int]] = [:]
        var keys: [[String]] = []
        for segment in message.segments {
            let n = (occurrence[segment.segmentID] ?? 0) + 1
            occurrence[segment.segmentID] = n
            fieldCounts[segment.segmentID, default: []].append(segment.fields.count)
            present.insert("\(segment.segmentID)/\(n)")
            keys.append(segment.fields.indices.map { "\(segment.segmentID)/\(n)/\($0)" })
        }
        var unplaced: [String] = []
        for issue in report.issues {
            let at = issue.location
            // A few group-level checks pass an array position as segmentIndex rather than the
            // occurrence; such an issue may land on the wrong row of that ID, or be listed below.
            guard present.contains("\(at.segmentID)/\(at.segmentIndex)") else {
                unplaced.append("\(at.pathDescription): \(issue.message)")
                continue
            }
            // A field beyond the last one present (a missing trailing field) colours the ID cell.
            let field = at.fieldIndex.map { $0 < fieldCounts[at.segmentID]![at.segmentIndex - 1] ? $0 : 0 } ?? 0
            byCell["\(at.segmentID)/\(at.segmentIndex)/\(field)", default: []].append(issue)
        }
        self.unplaced = unplaced
        errorCount = report.errors.count
        warningCount = report.warnings.count
        rows = zip(message.segments, keys).map { segment, keys in
            Row(segmentID: segment.segmentID, cells: zip(segment.fields, keys).enumerated().map { i, pair in
                let (field, key) = pair
                let issues = byCell[key] ?? []
                // fields[0] is the parser's empty placeholder for the ID slot.
                let name = grammar[segment.segmentID]?.fields.first { $0.index == i }?.name
                return Cell(text: i == 0 ? segment.segmentID : Self.text(of: field, chars),
                            title: i == 0 ? segment.segmentID : "\(segment.segmentID)-\(i)" + (name.map { " " + $0 } ?? ""),
                            state: CellState(issues),
                            notes: issues.map { "\($0.severity): \($0.message)" })
            })
        }
    }

    /// Every issue, one per line, `"PID-7 Date/Time of Birth: warning: ..."`, for the clipboard.
    var issuesText: String {
        (rows.flatMap { row in row.cells.flatMap { cell in cell.notes.map { "\(cell.title): \($0)" } } } + unplaced)
            .joined(separator: "\n")
    }

    /// The segment grammars the validator applies to `version` (v2.7 and v2.8 read the next
    /// point release's tables, as the validator does).
    static func grammar(for version: Version) -> [String: SegmentGrammar] {
        switch version {
        case .v2_3: return SegmentGrammarTable.v2_3
        case .v2_3_1: return SegmentGrammarTable.v2_3_1
        case .v2_4: return SegmentGrammarTable.v2_4
        case .v2_5_1: return SegmentGrammarTable.v2_5_1
        case .v2_6: return SegmentGrammarTable.v2_6
        case .v2_7, .v2_7_1: return SegmentGrammarTable.v2_7_1
        case .v2_8, .v2_8_2: return SegmentGrammarTable.v2_8_2
        }
    }

    /// Pasted text may carry LF or CRLF line endings and trailing blank lines; HL7 wants one CR
    /// after every segment.
    static func wire(from text: String) -> String {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\r").replacingOccurrences(of: "\n", with: "\r")
            .split(separator: "\r", omittingEmptySubsequences: true)
        return lines.map { $0 + "\r" }.joined()
    }

    // remediation: values are shown decoded (no re-escaping); the kit keeps its encoder internal.
    private static func text(of field: Field, _ chars: EncodingCharacters) -> String {
        field.repetitions.map { repetition in
            repetition.components.map { component in
                component.subcomponents.map(\.value).joined(separator: String(chars.subcomponentSeparator))
            }.joined(separator: String(chars.componentSeparator))
        }.joined(separator: String(chars.repetitionSeparator))
    }
}
