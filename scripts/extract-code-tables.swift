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
//    `Value  Description [ Comment ]` column header and the rows. Columns are
//    read at the offsets the header prints, so the Comment column is dropped
//    without truncating a description that contains wide gaps.
//
// Tables the index names but the values section never enumerates are emitted
// with `entries: []` — the registry stays honest about "known but unenumerated"
// rather than silently omitting the table.
//
// Resources/tables/overrides.json is a hand-kept overlay merged into every
// version's emission for that table number (permitsLocalExtensions / citation /
// dropCodes). It lives at the root of Resources/tables, which the codegen's
// tables pass ignores because that pass only enumerates `v*` directories.

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
    var codes: [String] = []
    var descriptions: [String] = []
    init(number: String, name: String, kind: String) {
        self.number = number
        self.name = name
        self.kind = kind
    }
}

struct Override {
    var permitsLocalExtensions: Bool?
    var citation: String?
    var dropCodes: [String] = []
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

/// The v2.6 index prints a third ownership token, `undefined`, for tables whose
/// values an external body owns (0227 MVX, 0291 MIME subtypes, 0292 CVX, 0399
/// ISO 3166, 0834 MIME types). HL7Table.Kind models two owners, and an
/// externally-owned value set is not an HL7-closed one, so `undefined` maps to
/// `User` — the kind that never validates as a closed set.
func normaliseKind(_ token: String) -> String {
    token.hasPrefix("HL7") ? "HL7" : "User"
}

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
    var index: [String: (kind: String, name: String)] = [:]
    var order: [String] = []
    var tables: [String: Table] = [:]
    var notes: [String] = []

    var inIndex = false
    var inValues = false
    var pendingCaption: (kind: String, name: String)? = nil
    var lastRow: Row? = nil

    func table(_ number: String, kind: String, name: String) -> Table {
        if let t = tables[number] { return t }
        let t = Table(number: number, name: name, kind: kind)
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
            if index[number] == nil { index[number] = (normaliseKind(g[1]), name) }
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
                t = table(number, kind: idx.kind, name: idx.name)
            } else if let cap = pendingCaption {
                t = table(number, kind: cap.kind, name: cap.name)
            } else {
                t = table(number, kind: "User", name: "")
                notes.append("\(number): no caption and no index entry — kind defaulted to User")
            }
            pendingCaption = nil

            let cells = splitCells(rest)
            let chunks = cells.map(\.text)
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
                if report && !noValuesPhrase.matches(only) {
                    notes.append("\(number): SKIPPED note row (empty Value column): \(only)")
                }
                continue
            }
            if noValuesPhrase.matches(only) { lastRow = nil; continue }
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
                _ = table(number, kind: index[number]?.kind ?? normaliseKind(g[1]), name: index[number]?.name ?? name)
                pendingCaption = nil
                lastRow = nil
                continue
            }
            if let g = reCaptionPlain.groups(raw) {
                let name = splitColumns(g[2]).first ?? g[2]
                pendingCaption = (normaliseKind(g[1]), name)
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
        _ = table(number, kind: meta.kind, name: meta.name)
    }
    for (number, meta) in index {
        if let t = tables[number], t.name.isEmpty { t.name = meta.name; t.kind = meta.kind }
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

    for raw in text.split(separator: "\n", omittingEmptySubsequences: false).map({ clean(String($0)) }) {
        let s = raw.trimmingCharacters(in: .whitespaces)
        if s.isEmpty { continue }
        if s.contains("..") { continue }        // table of contents

        if let g = reHeading282.groups(raw) {
            let number = g[1]
            let name = g[2].trimmingCharacters(in: .whitespaces)
            if let existing = tables[number] {
                current = existing
            } else {
                let t = Table(number: number, name: name, kind: "User")
                tables[number] = t
                order.append(number)
                current = t
            }
            inRows = false
            descCol = -1
            commentCol = -1
            continue
        }
        if let g = reCaption282.groups(raw) {
            let number = g[2]
            let kind = g[1].lowercased().hasPrefix("hl7") ? "HL7" : "User"
            if let t = tables[number] {
                t.kind = kind
                if t.name.isEmpty { t.name = g[3].trimmingCharacters(in: .whitespaces) }
                current = t
            }
            inRows = false
            continue
        }
        if reMetaHeader282.matches(raw) { inRows = false; continue }
        if reValueHeader282.matches(raw) {
            descCol = column(of: "Description", in: raw)
            commentCol = column(of: "Comment", in: raw)
            if commentCol < 0 { commentCol = column(of: "Chapter", in: raw) }
            inRows = true
            continue
        }
        if isFurniture(s) { continue }
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

        if cells.count >= 2 {
            if noValuesPhrase.matches(first.text) { continue }
            t.codes.append(first.text)
            t.descriptions.append(cells[1].text)
            descCol = cells[1].offset
            if cells.count >= 3 { commentCol = cells[2].offset }
            continue
        }
        // One cell: a bare code, or a note the spec prints across the table.
        if noValuesPhrase.matches(first.text) { continue }
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

func render(_ t: Table, version: String, appendix: Bool, override: Override?) -> String {
    let kindLabel = t.kind == "HL7" ? "HL7 Table" : "User-defined Table"
    let source = appendix ? "Appendix A" : "Chapter 2C"
    let citation = override?.citation
        ?? "HL7 v\(version) \(source), \(kindLabel) \(t.number) - \(t.name)"
    let permits = override?.permitsLocalExtensions ?? false
    let drop = Set(override?.dropCodes ?? [])
    var lines: [String] = []
    lines.append("{")
    lines.append("  \"table\": \(jsonString(t.number)),")
    lines.append("  \"version\": \(jsonString(version)),")
    lines.append("  \"name\": \(jsonString(t.name)),")
    lines.append("  \"kind\": \(jsonString(t.kind)),")
    lines.append("  \"permitsLocalExtensions\": \(permits),")
    lines.append("  \"citation\": \(jsonString(citation)),")
    var rows: [String] = []
    var seen = Set<String>()
    for (i, code) in t.codes.enumerated() {
        if drop.contains(code) { continue }
        if seen.contains(code) { continue }     // the spec reprints a row across a page break
        seen.insert(code)
        rows.append("    {\n      \"code\": \(jsonString(code)),\n      \"description\": \(jsonString(t.descriptions[i]))\n    }")
    }
    if rows.isEmpty {
        lines.append("  \"entries\": []")
    } else {
        lines.append("  \"entries\": [")
        lines.append(rows.joined(separator: ",\n"))
        lines.append("  ]")
    }
    lines.append("}")
    return lines.joined(separator: "\n") + "\n"
}

func loadOverrides(_ path: String) -> [String: Override] {
    guard let data = FileManager.default.contents(atPath: path),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
    var out: [String: Override] = [:]
    for (number, value) in obj {
        guard let d = value as? [String: Any] else { continue }
        out[number] = Override(
            permitsLocalExtensions: d["permitsLocalExtensions"] as? Bool,
            citation: d["citation"] as? String,
            dropCodes: (d["dropCodes"] as? [String]) ?? []
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

let text = runPdftotext(pdfPath)
guard !text.isEmpty else {
    FileHandle.standardError.write("error: pdftotext produced no text for \(pdfPath)\n".data(using: .utf8)!)
    exit(2)
}

let (tables, notes) = appendix ? extractAppendixA(text, report: report) : extract282(text, report: report)

let overridesPath = (outDir as NSString).deletingLastPathComponent + "/overrides.json"
let overrides = loadOverrides(overridesPath)

let fm = FileManager.default
try? fm.createDirectory(atPath: outDir, withIntermediateDirectories: true)
for existing in (try? fm.contentsOfDirectory(atPath: outDir)) ?? [] where existing.hasSuffix(".json") {
    try? fm.removeItem(atPath: outDir + "/" + existing)
}

var entryTotal = 0, empties = 0
for number in tables.keys.sorted() {
    let t = tables[number]!
    let json = render(t, version: version, appendix: appendix, override: overrides[number])
    try! json.write(toFile: outDir + "/" + number + ".json", atomically: true, encoding: .utf8)
    let rows = json.components(separatedBy: "\"code\":").count - 1
    entryTotal += rows
    if rows == 0 { empties += 1 }
}

if report {
    for n in notes { print("   " + n) }
}
print("tables: \(tables.count), entries: \(entryTotal), empty: \(empties)")
