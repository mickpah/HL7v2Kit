#!/usr/bin/env swift
// extract-code-tables.swift — M6-O6 code-table extraction pipeline (ADR-015).
//
// Dev-time authoring aid: reads an HL7 Final-Standard code-table PDF, runs
// `pdftotext -layout` (poppler), and emits one JSON file per printed table into
// Resources/tables/v<version>/<NNNN>.json — the input HL7v2KitCodegen turns into
// `HL7TableRegistry+v<X_Y_Z>.swift`. NOT part of the shipped package; poppler is
// a contributor prerequisite only (Package.swift.dependencies stays empty).
//
// Usage:
//   swift scripts/extract-code-tables.swift <pdf> <version> <outDir>
//   # or, much faster:
//   xcrun swiftc -O scripts/extract-code-tables.swift -o /tmp/tablesbin
//   /tmp/tablesbin docs/standards/HL7_v251_PDF/V251_Appendix_A.pdf 2.5.1 Resources/tables/v2.5.1
//
// Options:
//   --report   print every row the parser could not classify as a clean
//              two-column value row, with the decision it took. Use this when
//              re-extracting a new source: it is the eyeball list.
//
// Two source layouts are supported.
//
// A. Appendix A (v2.3, v2.3.1, v2.4, v2.5.1, v2.6)
//    Section "HL7 AND USER-DEFINED TABLES - ALPHABETIC SORT" is the index: one
//    line per table, `<kind> <number> <name> <chapter/field refs>`. Section
//    "... - NUMERIC SORT" prints the values: a caption line `<kind> [number]
//    <name>` (v2.3/v2.3.1 print the number, v2.4+ do not) followed by value rows
//    `<number> <code> <description>`. Because every value row repeats the table
//    number, rows are accumulated by number and the caption is only needed for
//    the kind/name of a table the index missed. Page furniture interrupts a
//    table across page breaks and is skipped without ending it.
//
// B. Chapter 2C (v2.8.2)
//    Heading `2.C.2.<n> <number> – <name>`, a Table Metadata block, a caption
//    `HL7 Table <number> – <name>` / `User-defined Table ...`, then a
//    `Value  Description [ Comment ]` column header and the rows. The header
//    seeds the columns and the rows correct them, because Chapter 2C does not
//    always align the two. A page footer ends the rows (the header is reprinted
//    on the next page), so a footnote set below it does not join the table.
//
// Tables the index names but the values section never enumerates are emitted
// with `entries: []` — the registry stays honest about "known but unenumerated"
// rather than silently omitting the table.
//
// Resources/tables/overrides.json is a hand-kept overlay, keyed by version and
// then by table number (kind / permitsLocalExtensions / citation / dropCodes /
// renameCodes / fixDescriptions / addEntries / createName / patterns, plus a note documenting
// what was verified). Every entry is version-scoped:
// an artifact of one version's printing must never be able to silently alter
// another version's table. The file lives at the root of Resources/tables,
// which the codegen's tables pass ignores because it only enumerates `v*`
// directories.

import Foundation

// MARK: - shell out to pdftotext -layout

func runPdftotext(_ pdf: String) -> String {
    let candidates = ["/opt/homebrew/bin/pdftotext", "/usr/local/bin/pdftotext", "/usr/bin/pdftotext"]
    let exe = candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? "pdftotext"
    let p = Process()
    p.executableURL = URL(fileURLWithPath: exe)
    p.arguments = ["-layout", "-enc", "UTF-8", pdf, "-"]
    let out = Pipe()
    p.standardOutput = out
    p.standardError = Pipe()
    do { try p.run() } catch {
        FileHandle.standardError.write("error: could not run pdftotext (\(exe)): \(error)\n".data(using: .utf8)!)
        exit(2)
    }
    let data = out.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return String(data: data, encoding: .utf8) ?? ""
}

// MARK: - small regex helper

struct RE {
    let re: NSRegularExpression
    init(_ pattern: String, _ options: NSRegularExpression.Options = []) {
        // Patterns are literals in this file; a bad one is a programming error.
        re = try! NSRegularExpression(pattern: pattern, options: options)
    }
    /// Capture groups of the first match, `nil` when the pattern does not match.
    /// Index 0 is the whole match; an unmatched optional group yields "".
    func groups(_ s: String) -> [String]? {
        let ns = s as NSString
        guard let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (0..<m.numberOfRanges).map { i in
            let r = m.range(at: i)
            return r.location == NSNotFound ? "" : ns.substring(with: r)
        }
    }
    func matches(_ s: String) -> Bool { groups(s) != nil }
}

// MARK: - model

final class Table {
    let number: String
    var name: String
    var kind: String            // "HL7" | "User"
    /// The spec names an outside authority as the source of the values (v2.6
    /// prints `undefined`, v2.8.2 `Externally-defined` / `External` /
    /// `Imported`). The printed rows are then a pointer, never the value set,
    /// so the table is emitted with `permitsLocalExtensions: true`.
    var externallyDefined: Bool
    var codes: [String] = []
    var descriptions: [String] = []
    init(number: String, name: String, kind: String, externallyDefined: Bool = false) {
        self.number = number
        self.name = name
        self.kind = kind
        self.externallyDefined = externallyDefined
    }
}

struct Override {
    var kind: String?
    var permitsLocalExtensions: Bool?
    var citation: String?
    var dropCodes: [String] = []
    /// Hand-verified corrections of a value the source PDF misprints exactly
    /// once, so the separator-variant rule below has no sibling to learn from.
    var renameCodes: [String: String] = [:]
    /// Hand-verified corrections of a printed description, keyed by code, where the
    /// source misprints the description column (v2.4 Table 0290 prints the value again
    /// before the character for rows 51 to 63: "51 z"). The row keeps its place.
    var fixDescriptions: [String: String] = [:]
    /// Rows the source PDF omits but the version's DEFINING chapter prints
    /// (v2.5.1 Appendix A prints 0210 with AND only; Chapter 2A sec 2.A.60.4
    /// prints AND and OR). `[code, description]` pairs, appended in order.
    var addEntries: [[String]] = []
    /// The table's printed name when the override CREATES a table the source PDF
    /// omits: v2.3 prints 0298, 0299, 0301 and 0336 with their rows in the chapters
    /// and not in Appendix A, the only PDF this extractor reads for v2.3. Needs `kind`
    /// and `addEntries` (the transcribed rows) and a `citation` naming the chapter.
    var createName: String?
    /// Printed rows that name a FAMILY of codes rather than one code (v2.3.1 to v2.8.2
    /// Table 0203 "NNxxx": "National Person Identifier where the xxx is the ISO table 3166
    /// 3-character (alphabetic) country code"). `[{"code": <printed value>, "regex":
    /// <anchored regex>}]`; the matching row moves from `entries` to `patterns`.
    var patterns: [[String: String]] = []
}

// MARK: - shared line classification

/// Page headers/footers that interrupt a table across a page break. They end
/// any pending wrapped-description continuation but never end the table.
let furniture: [RE] = [
    RE("^Health Level Seven"),
    RE("All rights reserved"),
    RE("^Page [A-Z0-9]"),
    RE("Appendix A: Data Definition Tables"),
    RE("^Final Standard"),
    RE("Final Standard\\.?$"),
    RE("^(January|February|March|April|May|June|July|August|September|October|November|December) [0-9]{4}\\."),
    RE("^Type\\s+Table\\s+Name"),
    RE("^Chapter [0-9]+:"),
    RE("^©"),
    RE("^HL7 Version"),
]

func isFurniture(_ s: String) -> Bool { furniture.contains { $0.matches(s) } }

/// The ownership token the spec prints, mapped onto HL7Table.Kind's two owners.
///
/// Both layouts print a third class for a table whose values an outside body
/// maintains: v2.6's index calls it `undefined` (0227 MVX, 0291 MIME subtypes,
/// 0292 CVX, 0340, 0399 ISO 3166, 0834) and v2.8.2's caption calls it
/// `Externally-defined` / `External` / `Imported`. HL7 owns the table number
/// and a site may not invent values for it, so the kind is `HL7`; the printed
/// rows are a pointer rather than the value set, so the table is also marked
/// `externallyDefined` and emitted with `permitsLocalExtensions: true`, which
/// is what stops it ever validating as a closed set.
func kindOfToken(_ token: String) -> (kind: String, external: Bool) {
    let t = token.lowercased()
    if t.hasPrefix("hl7") { return ("HL7", false) }
    if t.hasPrefix("undef") || t.hasPrefix("extern") || t.hasPrefix("imported") {
        return ("HL7", true)
    }
    return ("User", false)
}

/// `true` for a Value cell that cannot be a code. A printed value never ends
/// in a colon: only a `Note:` leading a paragraph the spec sets under the table
/// does (v2.8.2 0200 and 0301 both print one directly beneath the last row).
func isNoteLead(_ cell: String) -> Bool { cell.hasSuffix(":") }

/// Rows the spec prints in place of values when a table has none.
let noValuesPhrase = RE("^(no suggested values|no values defined|no values are defined|needs values)", [.caseInsensitive])

/// Split a line on runs of two or more spaces, keeping each column's offset.
func splitCells(_ s: String) -> [(text: String, offset: Int)] {
    let chars = Array(s)
    var cells: [(String, Int)] = []
    var i = 0
    while i < chars.count {
        while i < chars.count, chars[i] == " " { i += 1 }
        guard i < chars.count else { break }
        let start = i
        var end = i
        while i < chars.count {
            if chars[i] == " " {
                if i + 1 < chars.count, chars[i + 1] == " " { break }
                i += 1
            } else {
                end = i
                i += 1
            }
        }
        cells.append((String(chars[start...end]), start))
        while i < chars.count, chars[i] == " " { i += 1 }
    }
    return cells
}

func splitColumns(_ s: String) -> [String] { splitCells(s).map(\.text) }

/// Description column of the most recent two-column row of each table. A page
/// break re-lays the columns, so this is rolling rather than first-seen: a
/// one-column row is judged against the row layout printed beside it.
var lastDescCol: [String: Int] = [:]

/// Value column of the most recent two-column row of each table, tracked for
/// the same reason: a note the spec outdents to the left of the Value column
/// (v2.3.1 0078 "For microbiology susceptibilities only:") is not a value row.
var lastCodeCol: [String: Int] = [:]

/// The Table column sits at the left of every observed Appendix A layout. A
/// four-digit run further right is part of a value or a description (v2.4 table
/// 0356 wraps the code `ISO 2022-1994` across two lines), never a row number.
let maxTableNumberColumn = 20

func clean(_ line: String) -> String {
    var s = line.replacingOccurrences(of: "\u{0C}", with: "")
    s = s.replacingOccurrences(of: "\r", with: "")
    while s.hasSuffix(" ") { s.removeLast() }
    return s
}

/// Column of the first non-space character, or -1 for a blank line.
func indent(_ s: String) -> Int {
    for (i, c) in Array(s).enumerated() where c != " " { return i }
    return -1
}

/// Column at which `needle` starts inside `hay`, or -1.
func column(of needle: String, in hay: String) -> Int {
    guard let r = hay.range(of: needle) else { return -1 }
    return hay.distance(from: hay.startIndex, to: r.lowerBound)
}

func padNumber(_ n: String) -> String {
    n.count >= 4 ? n : String(repeating: "0", count: 4 - n.count) + n
}

// MARK: - layout A: Appendix A (v2.3 .. v2.6)

let reIndexRow = RE("^\\s*(HL7|User|undefined)\\s+([0-9]{1,4})\\s+(\\S.*)$")
let reCaptionNumbered = RE("^(HL7|User|undefined|undef)\\s+([0-9]{1,4})\\s+(\\S.*)$")
let reCaptionPlain = RE("^(HL7|User|undefined|undef)\\s{2,}(\\S.*)$")
let reValueRow = RE("^\\s+([0-9]{4})\\s\\s+(\\S.*)$")
let reValuesHeader = RE("^\\s*Type\\s+Table\\s+Name\\s+Value\\s+Description")

struct Row { var table: String; var index: Int; var codeCol: Int; var descCol: Int }

func extractAppendixA(_ text: String, report: Bool) -> ([String: Table], [String]) {
    var index: [String: (kind: String, name: String, external: Bool)] = [:]
    var order: [String] = []
    var tables: [String: Table] = [:]
    var notes: [String] = []

    var inIndex = false
    var inValues = false
    var pendingCaption: (kind: String, name: String, external: Bool)? = nil
    var lastRow: Row? = nil

    func table(_ number: String, kind: String, name: String, external: Bool) -> Table {
        if let t = tables[number] { return t }
        let t = Table(number: number, name: name, kind: kind, externallyDefined: external)
        tables[number] = t
        order.append(number)
        return t
    }

    let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map { clean(String($0)) }

    /// `true` when the next printed line continues this one in the Value column
    /// — the signature of a sentence the source PDF bled into the column and
    /// truncated, as against a complete row whose code and description merely
    /// collided (v2.4 0335 `Q<integer>J`, v2.3.1 0359 `2`).
    func continuesInValueColumn(after i: Int, valueColumn: Int) -> Bool {
        var j = i + 1
        while j < lines.count, lines[j].trimmingCharacters(in: .whitespaces).isEmpty { j += 1 }
        guard j < lines.count else { return false }
        let next = lines[j]
        if reValueRow.matches(next) { return false }
        if let f = next.first, f == "H" || f == "U" || f == "u" { return false }
        if isFurniture(next.trimmingCharacters(in: .whitespaces)) { return false }
        guard let first = splitCells(next).first else { return false }
        return abs(first.offset - valueColumn) <= 6
    }

    for (lineNumber, raw) in lines.enumerated() {
        let s = raw.trimmingCharacters(in: .whitespaces)
        if s.isEmpty { lastRow = nil; continue }

        if s.contains("HL7 AND USER-DEFINED TABLES") {
            if s.contains("ALPHABETIC SORT") { inIndex = true; inValues = false; lastRow = nil; continue }
            if s.contains("NUMERIC SORT") { inIndex = false; inValues = true; lastRow = nil; continue }
        }
        if s.hasPrefix("A.") && s.contains("DATA ELEMENT NAMES") {
            inIndex = false; inValues = false; lastRow = nil; continue
        }
        if isFurniture(s) { lastRow = nil; continue }
        if reValuesHeader.matches(raw) { lastRow = nil; continue }

        if inIndex {
            guard let g = reIndexRow.groups(raw) else { continue }
            let number = padNumber(g[2])
            let name = splitColumns(g[3]).first ?? g[3]
            if number == "0000" { continue }        // v2.6 prints a placeholder "no table" row
            if index[number] == nil {
                let k = kindOfToken(g[1])
                index[number] = (k.kind, name, k.external)
            }
            continue
        }
        guard inValues else { continue }

        // Value row — the table number repeats on every row.
        if let g = reValueRow.groups(raw), indent(raw) <= maxTableNumberColumn {
            let number = padNumber(g[1])
            let rest = g[2]
            let restCol = column(of: rest, in: raw)
            let t: Table
            if let existing = tables[number] {
                t = existing
            } else if let idx = index[number] {
                t = table(number, kind: idx.kind, name: idx.name, external: idx.external)
            } else if let cap = pendingCaption {
                t = table(number, kind: cap.kind, name: cap.name, external: cap.external)
            } else {
                t = table(number, kind: "User", name: "", external: false)
                notes.append("\(number): no caption and no index entry — kind defaulted to User")
            }
            pendingCaption = nil

            let cells = splitCells(rest)
            let chunks = cells.map(\.text)
            if cells.count >= 2, isNoteLead(cells[0].text) {
                lastRow = nil
                if report { notes.append("\(number): SKIPPED note row: \(rest)") }
                continue
            }
            if cells.count >= 2 {
                t.codes.append(cells[0].text)
                t.descriptions.append(cells[1...].map(\.text).joined(separator: " "))
                let descCol = restCol + cells[1].offset
                lastDescCol[number] = descCol
                lastCodeCol[number] = restCol
                lastRow = Row(table: number, index: t.codes.count - 1,
                              codeCol: restCol, descCol: descCol)
                continue
            }
            // One column only. Where it sits decides what it is.
            let only = chunks.first ?? ""
            if only.isEmpty { lastRow = nil; continue }
            let established = lastDescCol[number] ?? -1
            if established >= 0 && restCol >= established - 4 {
                // Empty Value column: a "no suggested values" marker or a note
                // the spec prints under the table ("or user-defined codes",
                // "See Chapter 8 ... for values"). Never a code.
                lastRow = nil
                if report { notes.append("\(number): SKIPPED note row (empty Value column): \(only)") }
                continue
            }
            if noValuesPhrase.matches(only) {
                lastRow = nil
                if report { notes.append("\(number): SKIPPED no-values marker: \(only)") }
                continue
            }
            if let codeCol = lastCodeCol[number], restCol < codeCol - 6 {
                // Outdented to the left of the Value column: a note, not a row.
                lastRow = nil
                if report { notes.append("\(number): SKIPPED outdented note row: \(only)") }
                continue
            }
            if !only.contains(" ") {
                t.codes.append(only)
                t.descriptions.append("")
                lastRow = Row(table: number, index: t.codes.count - 1, codeCol: restCol, descCol: -1)
                continue
            }
            // A table that prints no descriptions at all (v2.6 0391 Segment
            // group) has no description column to split against, so the whole
            // cell is the code — but only when it is shaped like one. Prose the
            // PDF bled into the column always carries lower-case words.
            if established < 0 && only.uppercased() == only
                && !continuesInValueColumn(after: lineNumber, valueColumn: restCol) {
                t.codes.append(only)
                t.descriptions.append("")
                lastRow = Row(table: number, index: t.codes.count - 1, codeCol: restCol, descCol: -1)
                if report { notes.append("\(number): description-less table, whole cell taken as the code: \(only)") }
                continue
            }
            // Space-separated at the Value column: the code and its description
            // collided. Accept the first token as the code when the remainder
            // lands on the description column this table has established, or
            // when the row is complete (nothing continues it in the Value
            // column). Otherwise it is a sentence the PDF bled into the column.
            let firstTok = String(only.split(separator: " ")[0])
            let remainder = only.dropFirst(firstTok.count).trimmingCharacters(in: .whitespaces)
            let remCol = restCol + cells[0].offset + only.count - remainder.count
            let aligned = established >= 0 && abs(remCol - established) <= 8
            let complete = established >= 0 && !continuesInValueColumn(after: lineNumber, valueColumn: restCol)
            if aligned || complete {
                t.codes.append(firstTok)
                t.descriptions.append(remainder)
                lastRow = Row(table: number, index: t.codes.count - 1, codeCol: restCol, descCol: remCol)
                if report { notes.append("\(number): single-column row accepted as \(firstTok) | \(remainder)") }
            } else {
                lastRow = nil
                if report { notes.append("\(number): SKIPPED prose-bleed row (remainder col \(remCol) vs description col \(established)): \(only)") }
            }
            continue
        }

        // Caption line (starts at column 0 in every observed Appendix A).
        if let f = raw.first, f == "H" || f == "U" || f == "u" {
            if let g = reCaptionNumbered.groups(raw) {
                let number = padNumber(g[2])
                let name = splitColumns(g[3]).first ?? g[3]
                let k = kindOfToken(g[1])
                _ = table(number, kind: index[number]?.kind ?? k.kind,
                          name: index[number]?.name ?? name,
                          external: index[number]?.external ?? k.external)
                pendingCaption = nil
                lastRow = nil
                continue
            }
            if let g = reCaptionPlain.groups(raw) {
                let name = splitColumns(g[2]).first ?? g[2]
                let k = kindOfToken(g[1])
                pendingCaption = (k.kind, name, k.external)
                lastRow = nil
                continue
            }
        }

        // Anything else inside the values section is a wrapped code or a
        // wrapped description belonging to the row above it.
        guard let row = lastRow, let t = tables[row.table] else { continue }
        for cell in splitCells(raw) {
            if row.descCol >= 0 && cell.offset >= row.descCol - 4 {
                t.descriptions[row.index] += (t.descriptions[row.index].isEmpty ? "" : " ") + cell.text
            } else if abs(cell.offset - row.codeCol) <= 6 {
                t.codes[row.index] += cell.text
            } else if row.descCol >= 0 {
                t.descriptions[row.index] += (t.descriptions[row.index].isEmpty ? "" : " ") + cell.text
            } else if report {
                notes.append("\(row.table): unattached continuation at col \(cell.offset): \(cell.text)")
            }
        }
    }

    // Tables named by the index but never enumerated: emit them empty.
    for (number, meta) in index where tables[number] == nil {
        _ = table(number, kind: meta.kind, name: meta.name, external: meta.external)
    }
    for (number, meta) in index {
        if let t = tables[number], t.name.isEmpty {
            t.name = meta.name
            t.kind = meta.kind
            t.externallyDefined = meta.external
        }
    }
    return (tables, notes)
}

// MARK: - layout B: Chapter 2C (v2.8.2)

let reHeading282 = RE("^\\s*2\\.C\\.2\\.[0-9]+\\s+([0-9]{4})\\s*[–-]\\s*(\\S.*)$")
let reCaption282 = RE("^\\s*(HL7|HL7-defined|User-defined|User Defined|User -defined|Externally-defined|Externally Defined|External|Imported)\\s+Table\\s+([0-9]{4})\\s*[–-]\\s*(\\S.*)$")
let reValueHeader282 = RE("^\\s*(Value|Values|Code|Message|Coding System)\\s\\s+Description")
let reMetaHeader282 = RE("^\\s*Table\\s\\s+Steward")

func extract282(_ text: String, report: Bool) -> ([String: Table], [String]) {
    var tables: [String: Table] = [:]
    var order: [String] = []
    var notes: [String] = []

    var current: Table? = nil
    var inRows = false
    var descCol = -1
    var commentCol = -1
    // Set by a table caption, cleared by the first line after it. Chapter 2C does not
    // always head its columns "Value / Description": 0354 prints "Value / Events", 0440
    // "Data type / Data Type Name", 0209 "Relational operator / Value", 0227 and 0292
    // "Code / ...". The line directly under a caption IS the column header whatever it
    // says, provided it has at least two cells; those tables used to extract empty.
    var awaitingHeader = false
    // The non-standard header of the current table, whitespace-collapsed. Chapter 2C
    // reprints it at the top of every page the table runs onto; a footer ends the rows, so
    // the reprint is what resumes them. Without this a long table (0354, 240 rows) stopped
    // at its first page break and would have shipped as a PARTIAL closed set.
    var customHeader: String? = nil
    func collapsed(_ line: String) -> String {
        line.split(whereSeparator: { $0 == " " }).joined(separator: " ")
    }

    func table(_ number: String, name: String, kind: String, external: Bool) -> Table {
        if let t = tables[number] { return t }
        let t = Table(number: number, name: name, kind: kind, externallyDefined: external)
        tables[number] = t
        order.append(number)
        return t
    }

    for raw in text.split(separator: "\n", omittingEmptySubsequences: false).map({ clean(String($0)) }) {
        let s = raw.trimmingCharacters(in: .whitespaces)
        if s.isEmpty { continue }
        if s.contains("..") { continue }        // table of contents

        if let g = reHeading282.groups(raw) {
            let number = g[1]
            let name = g[2].trimmingCharacters(in: .whitespaces)
            current = table(number, name: name, kind: "User", external: false)
            inRows = false
            customHeader = nil
            awaitingHeader = false
            descCol = -1
            commentCol = -1
            continue
        }
        if let g = reCaption282.groups(raw) {
            // The caption, not the heading, is the reliable identifier: 0399's
            // heading prints the code system's name (`2.C.2.565 ISO-3166-1`)
            // instead of a table number, so the caption has to be able to
            // create the table as well as label it.
            let number = g[2]
            let k = kindOfToken(g[1])
            let t = table(number, name: g[3].trimmingCharacters(in: .whitespaces),
                          kind: k.kind, external: k.external)
            t.kind = k.kind
            t.externallyDefined = k.external
            if t.name.isEmpty { t.name = g[3].trimmingCharacters(in: .whitespaces) }
            current = t
            inRows = false
            descCol = -1
            commentCol = -1
            awaitingHeader = true
            customHeader = nil
            continue
        }
        if reMetaHeader282.matches(raw) { inRows = false; awaitingHeader = false; continue }
        if awaitingHeader && !reValueHeader282.matches(raw) {
            awaitingHeader = false
            let headerCells = splitCells(raw)
            if headerCells.count >= 2 && !isFurniture(s) && !noValuesPhrase.matches(s) {
                descCol = headerCells[1].offset
                commentCol = column(of: "Comment", in: raw)
                customHeader = collapsed(s)
                inRows = true
                continue
            }
        }
        if !inRows, current != nil, let header = customHeader, collapsed(s) == header {
            let headerCells = splitCells(raw)
            if headerCells.count >= 2 { descCol = headerCells[1].offset }
            commentCol = column(of: "Comment", in: raw)
            inRows = true
            continue
        }
        if reValueHeader282.matches(raw) {
            awaitingHeader = false
            descCol = column(of: "Description", in: raw)
            commentCol = column(of: "Comment", in: raw)
            if commentCol < 0 { commentCol = column(of: "Chapter", in: raw) }
            inRows = true
            continue
        }
        // A page footer ends the rows. Chapter 2C reprints the column header on
        // the next page, so nothing is lost — and a footnote printed below the
        // footer (0200 / 0301 `Note: The content of Legal Name ...`) no longer
        // lands in the table that happened to precede it.
        if isFurniture(s) { inRows = false; continue }
        guard inRows, let t = current else { continue }

        // Chapter 2C prints the column header once per page and does not always
        // align it with the rows beneath it (0868, 0937), so the header only
        // seeds the columns; the rows themselves correct them as they are read.
        let cells = splitCells(raw)
        guard let first = cells.first else { continue }

        if descCol >= 0 && abs(first.offset - descCol) <= 4 {
            // Wrapped description (any further cell is a wrapped Comment).
            guard !t.descriptions.isEmpty else { continue }
            let i = t.descriptions.count - 1
            t.descriptions[i] += (t.descriptions[i].isEmpty ? "" : " ") + first.text
            continue
        }
        if commentCol >= 0 && first.offset >= commentCol - 4 {
            continue                            // wrapped Comment column — dropped
        }
        if descCol >= 0 && first.offset > descCol + 4 { continue }

        // A code too wide for the Value column wraps onto the next line, which
        // then looks exactly like a new row. The break is only visible in the
        // code the spec left dangling: 0356 prints `ISO 2022-` / `1994`, and a
        // printed code never ends in a separator. Join it back on.
        if let last = t.codes.last, last.hasSuffix("-") || last.hasSuffix("_") {
            let i = t.codes.count - 1
            t.codes[i] += first.text
            for cell in cells.dropFirst() {
                if commentCol >= 0 && cell.offset >= commentCol - 4 { continue }
                t.descriptions[i] += (t.descriptions[i].isEmpty ? "" : " ") + cell.text
            }
            if report { notes.append("\(t.number): wrapped code rejoined as \(t.codes[i])") }
            continue
        }

        if cells.count >= 2 {
            if noValuesPhrase.matches(first.text) {
                if report { notes.append("\(t.number): SKIPPED no-values marker: \(first.text)") }
                continue
            }
            if isNoteLead(first.text) {
                if report { notes.append("\(t.number): SKIPPED note row: \(first.text) \(cells[1].text)") }
                continue
            }
            t.codes.append(first.text)
            t.descriptions.append(cells[1].text)
            descCol = cells[1].offset
            if cells.count >= 3 { commentCol = cells[2].offset }
            continue
        }
        // One cell: a bare code, or a note the spec prints across the table.
        if noValuesPhrase.matches(first.text) || isNoteLead(first.text) {
            if report { notes.append("\(t.number): SKIPPED note row: \(first.text)") }
            continue
        }
        if first.text.contains(" ") {
            if report { notes.append("\(t.number): SKIPPED note row: \(first.text)") }
            continue
        }
        t.codes.append(first.text)
        t.descriptions.append("")
    }
    return (tables, notes)
}

// MARK: - JSON emission

func jsonString(_ s: String) -> String {
    var out = "\""
    for c in s.unicodeScalars {
        switch c {
        case "\"": out += "\\\""
        case "\\": out += "\\\\"
        case "\n": out += "\\n"
        case "\r": out += "\\r"
        case "\t": out += "\\t"
        default:
            if c.value < 0x20 {
                out += String(format: "\\u%04x", c.value)
            } else {
                out.unicodeScalars.append(c)
            }
        }
    }
    return out + "\""
}

/// A code with spaces and underscores removed. The printed tables sometimes
/// carry the same value twice with different separators — v2.6 0391 prints
/// `ENCODED` / `ORDER` (wrapped at the space) two rows above `ENCODED_ORD` /
/// `ER` (wrapped mid-word), and both name the same segment group.
func separatorKey(_ code: String) -> String {
    code.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "_", with: "")
}

/// Drop the codes the overlay removes, exact reprints, and separator-variant
/// twins. Returns the surviving (code, description) pairs plus the notes the
/// `--report` flag prints: nothing is removed silently.
func survivingRows(_ t: Table, drop: Set<String>, rename: [String: String]) -> ([(String, String)], [String]) {
    var notes: [String] = []
    var codes = t.codes
    for (i, code) in codes.enumerated() {
        if let corrected = rename[code] {
            notes.append("\(t.number): renamed by overrides.json: \(code) -> \(corrected)")
            codes[i] = corrected
        }
    }

    // Which spelling of each separator-variant group to keep: the one that uses
    // an underscore (every wrapped-at-a-space twin observed has an underscored
    // sibling), and among those the one with no space left in it.
    var preferred: [String: String] = [:]
    for code in codes {
        let key = separatorKey(code)
        guard let held = preferred[key] else { preferred[key] = code; continue }
        func rank(_ c: String) -> Int {
            (c.contains("_") ? 2 : 0) + (c.contains(" ") ? 0 : 1)
        }
        if rank(code) > rank(held) { preferred[key] = code }
    }

    var rows: [(String, String)] = []
    var seen = Set<String>()
    for (i, code) in codes.enumerated() {
        if drop.contains(code) {
            notes.append("\(t.number): dropped by overrides.json: \(code)")
            continue
        }
        if seen.contains(code) {
            notes.append("\(t.number): dropped reprint of \(code)")
            continue
        }
        if let keep = preferred[separatorKey(code)], keep != code {
            notes.append("\(t.number): dropped separator variant \(code) (keeping \(keep))")
            continue
        }
        seen.insert(code)
        rows.append((code, t.descriptions[i]))
    }
    return (rows, notes)
}

func render(_ t: Table, version: String, appendix: Bool, override: Override?) -> (json: String, notes: [String]) {
    let kind = override?.kind ?? t.kind
    let kindLabel = kind == "HL7" ? "HL7 Table" : "User-defined Table"
    let source = appendix ? "Appendix A" : "Chapter 2C"
    let citation = override?.citation
        ?? "HL7 v\(version) \(source), \(kindLabel) \(t.number) - \(t.name)"
    // A bare "..." row is never a code. The specs print it for "no suggested values" (an
    // otherwise empty table), for an external or open-ended list that continues (v2.6 0153
    // "See NUBC codes", 0359 / 0418 ranks), and for a null row (v2.6 0365 "(null) No state
    // change"). It is dropped structurally. Fail-safe (req #4): when other rows remain, the
    // printed rows are NOT taken as a closed set unless overrides.json says so explicitly.
    let hasEllipsis = t.codes.contains("...")
    let (allPairs, allNotes) = survivingRows(t, drop: Set(override?.dropCodes ?? []),
                                             rename: override?.renameCodes ?? [:])
    var rowPairs = allPairs.filter { $0.0 != "..." }
    var addedNotes: [String] = []
    let fixDescriptions = override?.fixDescriptions ?? [:]
    for (i, pair) in rowPairs.enumerated() {
        if let fixed = fixDescriptions[pair.0] {
            rowPairs[i].1 = fixed
            addedNotes.append("\(t.number): description of \(pair.0) corrected by overrides.json")
        }
    }
    for code in fixDescriptions.keys.sorted() where !rowPairs.contains(where: { $0.0 == code }) {
        addedNotes.append("\(t.number): fixDescriptions \(code) declared in overrides.json but not printed")
    }
    for pair in override?.addEntries ?? [] where pair.count == 2 && !rowPairs.contains(where: { $0.0 == pair[0] }) {
        rowPairs.append((pair[0], pair[1]))
        addedNotes.append("\(t.number): added by overrides.json: \(pair[0])")
    }
    var patternRows: [(code: String, description: String, regex: String)] = []
    for p in override?.patterns ?? [] {
        guard let code = p["code"], let regex = p["regex"],
              let i = rowPairs.firstIndex(where: { $0.0 == code }) else {
            addedNotes.append("\(t.number): pattern \(p["code"] ?? "?") declared in overrides.json but not printed")
            continue
        }
        patternRows.append((code, rowPairs[i].1, regex))
        rowPairs.remove(at: i)
        addedNotes.append("\(t.number): \(code) is a pattern row (\(regex))")
    }
    let notes = allNotes + addedNotes + (hasEllipsis ? ["\(t.number): dropped the bare \"...\" row"
        + (rowPairs.isEmpty ? "" : "; table left open unless overridden")] : [])
    let permits = override?.permitsLocalExtensions
        ?? (t.externallyDefined || (hasEllipsis && !rowPairs.isEmpty))
    var lines: [String] = []
    lines.append("{")
    lines.append("  \"table\": \(jsonString(t.number)),")
    lines.append("  \"version\": \(jsonString(version)),")
    lines.append("  \"name\": \(jsonString(t.name)),")
    lines.append("  \"kind\": \(jsonString(kind)),")
    lines.append("  \"permitsLocalExtensions\": \(permits),")
    lines.append("  \"citation\": \(jsonString(citation)),")
    let rows = rowPairs.map {
        "    {\n      \"code\": \(jsonString($0.0)),\n      \"description\": \(jsonString($0.1))\n    }"
    }
    if rows.isEmpty {
        lines.append("  \"entries\": []")
    } else {
        lines.append("  \"entries\": [")
        lines.append(rows.joined(separator: ",\n"))
        lines.append("  ]")
    }
    if !patternRows.isEmpty {
        lines[lines.count - 1] += ","
        let items = patternRows.map {
            "    {\n      \"code\": \(jsonString($0.code)),\n      \"description\": \(jsonString($0.description)),\n      \"regex\": \(jsonString($0.regex))\n    }"
        }
        lines.append("  \"patterns\": [")
        lines.append(items.joined(separator: ",\n"))
        lines.append("  ]")
    }
    lines.append("}")
    return (lines.joined(separator: "\n") + "\n", notes)
}

/// Load `Resources/tables/overrides.json` for one version.
///
/// Every entry is scoped to the version it was verified against: the file is
/// `{"<version>": {"<table>": {kind?, permitsLocalExtensions?, citation?,
/// dropCodes?, note?}}}`. `note` is documentation for the reader and is
/// ignored here.
func loadOverrides(_ path: String, version: String) -> [String: Override] {
    guard let data = FileManager.default.contents(atPath: path),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let scoped = obj[version] as? [String: Any] else { return [:] }
    var out: [String: Override] = [:]
    for (number, value) in scoped {
        guard let d = value as? [String: Any] else { continue }
        out[number] = Override(
            kind: d["kind"] as? String,
            permitsLocalExtensions: d["permitsLocalExtensions"] as? Bool,
            citation: d["citation"] as? String,
            dropCodes: (d["dropCodes"] as? [String]) ?? [],
            renameCodes: (d["renameCodes"] as? [String: String]) ?? [:],
            fixDescriptions: (d["fixDescriptions"] as? [String: String]) ?? [:],
            addEntries: (d["addEntries"] as? [[String]]) ?? [],
            createName: d["createName"] as? String,
            patterns: (d["patterns"] as? [[String: String]]) ?? []
        )
    }
    return out
}

// MARK: - main

var args = Array(CommandLine.arguments.dropFirst())
let report = args.contains("--report")
args.removeAll { $0.hasPrefix("--") }
guard args.count == 3 else {
    FileHandle.standardError.write("usage: extract-code-tables <pdf> <version> <outDir> [--report]\n".data(using: .utf8)!)
    exit(2)
}
let pdfPath = args[0], version = args[1], outDir = args[2]
let appendix = version != "2.8.2"

// The v2.5.1 Appendix A text layer carries mis-decoded curly quotes: an opening quote
// arrives as U+00E2, a space, U+0153 and a closing quote as a bare U+00E2 (nine
// descriptions, e.g. 0003 A21 "leave of absence"; never a code). No HL7 table text
// contains a genuine U+00E2, so both forms are restored to the quotes the page prints.
let text = runPdftotext(pdfPath)
    .replacingOccurrences(of: "\u{00E2} \u{0153}", with: "\u{201C}")
    .replacingOccurrences(of: "\u{00E2}", with: "\u{201D}")
    // v2.6 Appendix A Table 0550 carries a mis-decoded no-break space after three codes
    // ("CHEST", "KIDN" and a lone one): it arrives as U+00C2. No table text uses it.
    .replacingOccurrences(of: "\u{00C2}", with: "")
guard !text.isEmpty else {
    FileHandle.standardError.write("error: pdftotext produced no text for \(pdfPath)\n".data(using: .utf8)!)
    exit(2)
}

var (tables, extractionNotes) = appendix ? extractAppendixA(text, report: report) : extract282(text, report: report)
var notes = extractionNotes

let overridesPath = (outDir as NSString).deletingLastPathComponent + "/overrides.json"
let overrides = loadOverrides(overridesPath, version: version)
for (number, o) in overrides where tables[number] == nil {
    guard let name = o.createName, let kind = o.kind, !o.addEntries.isEmpty else { continue }
    tables[number] = Table(number: number, name: name, kind: kind)   // rows come from addEntries in render()
    notes.append("\(number): created from overrides.json (printed in a chapter, absent from the appendix)")
}

let fm = FileManager.default
try? fm.createDirectory(atPath: outDir, withIntermediateDirectories: true)
for existing in (try? fm.contentsOfDirectory(atPath: outDir)) ?? [] where existing.hasSuffix(".json") {
    try? fm.removeItem(atPath: outDir + "/" + existing)
}

var entryTotal = 0, empties = 0
for number in tables.keys.sorted() {
    let t = tables[number]!
    let (json, rowNotes) = render(t, version: version, appendix: appendix, override: overrides[number])
    notes.append(contentsOf: rowNotes)
    try! json.write(toFile: outDir + "/" + number + ".json", atomically: true, encoding: .utf8)
    let rows = json.components(separatedBy: "\"code\":").count - 1
    entryTotal += rows
    if rows == 0 { empties += 1 }
}

if report {
    for n in notes { print("   " + n) }
}
print("tables: \(tables.count), entries: \(entryTotal), empty: \(empties)")
