#!/usr/bin/env swift
// extract-segment-tables.swift — M5 segment-coverage extraction pipeline (ADR-015).
//
// Dev-time authoring aid: reads an HL7 Final-Standard chapter PDF, runs
// `pdftotext -layout` (poppler), locates each "HL7 Attribute Table" and parses
// its rows into structured fields (SEQ / LEN / DT / OPT / RP-# / TBL# / ITEM# /
// ELEMENT NAME). Emits JSON to stdout to *seed and cross-check* the hand-reviewed
// Resources/schemas/<version>/<SEG>.json. NOT part of the shipped package; poppler
// is a contributor prerequisite only (Package.swift.dependencies stays empty).
//
// Usage:
//   swift extract-segment-tables.swift <chapter.pdf> [SEGID]
//     SEGID (optional) filters to one segment's table (e.g. NK1).
//
// The RP/# column maps to repeatability: "Y" (or a max-count) -> "*", blank -> "1".

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

// MARK: - column model

// A detected header column: its label key and the character offset where its
// label begins on the header line.
struct Column { let key: String; let start: Int }

// Header keys we recognise, in canonical order. C.LEN is v2.7+ only.
let headerKeys: [(key: String, patterns: [String])] = [
    ("SEQ",  ["SEQ"]),
    ("LEN",  ["LEN"]),
    ("CLEN", ["C.LEN", "C.LEN."]),
    ("DT",   ["DT"]),
    ("OPT",  ["OPT", "R/O/C", "R/O"]),   // some legacy chapters (e.g. v2.3 CH10) label it "R/O/C"
    ("RP",   ["RP/#", "R P/#", "RP/ #", "RP/"]),   // v2.3 CH7 wraps the "#": header reads "RP/" — without it the RP column vanishes and its "Y" cells land in OPT (FAC-5..8)
    ("TBL",  ["TBL#", "TBL #", "TBL"]),
    ("ITEM", ["ITEM#", "ITEM #", "ITEM"]),
    ("NAME", ["ELEMENT NAME"]),
]

func charOffset(of needle: String, in line: String) -> Int? {
    guard let r = line.range(of: needle) else { return nil }
    return line.distance(from: line.startIndex, to: r.lowerBound)
}

// Detect an attribute-table header line -> ordered columns, or nil.
func detectHeader(_ line: String) -> [Column]? {
    let upper = line.uppercased()
    guard upper.contains("SEQ"), upper.contains("ELEMENT NAME"),
          upper.contains("OPT") || upper.contains("R/O/C") || upper.contains("R/O"),
          upper.contains("ITEM") else { return nil }
    var cols: [Column] = []
    for (key, pats) in headerKeys {
        var found: Int? = nil
        for pat in pats { if let o = charOffset(of: pat, in: upper) { found = o; break } }
        if let o = found { cols.append(Column(key: key, start: o)) }
    }
    cols.sort { $0.start < $1.start }
    // need at least SEQ, DT, OPT, ITEM, NAME to be a real attribute table
    let keys = Set(cols.map { $0.key })
    guard keys.isSuperset(of: ["SEQ", "DT", "OPT", "NAME"]) else { return nil }
    return cols
}

// MARK: - row parsing

struct FieldRow {
    var seq: Int
    var len: String = ""
    var dt: String = ""
    var opt: String = ""
    var rp: String = ""
    var tbl: String = ""
    var item: String = ""
    var name: String = ""
}

// A run of non-space text with its start offset.
struct Run { let text: String; let start: Int; let end: Int }

func runs(in line: String) -> [Run] {
    // Split on runs of 2+ spaces: a run is non-space chars optionally joined
    // by SINGLE spaces (element-name words stay together). Offsets are
    // Character distances, matching the old Array(line) indexing. Only
    // observable delta vs the hand-rolled scanner: a line ending in exactly
    // one trailing space no longer counts that space in the last run's
    // `end` — unreachable in both consumers (columnKey reads `start` only;
    // nameBoundary reads pre-NAME runs), and proven byte-identical against
    // full-chapter extractions + the all-PDF depth audit at the R6 swap.
    line.matches(of: #/[^ ](?: [^ ]|[^ ])*/#).map { m in
        Run(
            text: String(line[m.range]),
            start: line.distance(from: line.startIndex, to: m.range.lowerBound),
            end: line.distance(from: line.startIndex, to: m.range.upperBound)
        )
    }
}

// Assign a run to a pre-NAME column by the smallest distance between the run's START
// offset and each header label's START offset. Keying both on start (not the run's
// centre) is robust across the real layouts in the PDFs: a value can sit a few columns
// right of its label (v2.5.1 CH12 GOL — GOL-1 `ID`) or a hair left (v2.5.1 CH04 BPO —
// `CWE`); start-to-start nearest resolves both, where a centre-based or span-containment
// rule mis-bins one or the other. Ties favour the earlier column.
func columnKey(forStart start: Int, columns: [Column]) -> String {
    var best = columns.first!.key
    var bestDist = Int.max
    for c in columns where c.key != "NAME" {
        let d = abs(c.start - start)
        if d < bestDist { bestDist = d; best = c.key }
    }
    return best
}

func elementName(from line: String, nameStart: Int, slack: Int = 2) -> String {
    let chars = Array(line)
    guard nameStart < chars.count else { return "" }
    // start a couple of columns early to catch slightly left-shifted names, then trim
    let s = max(0, nameStart - slack)
    return String(chars[s...]).trimmingCharacters(in: .whitespaces)
}

// Where this row's element name begins.
//
// Long names are *centred* under the "ELEMENT NAME" label and can start well left of the
// label's own offset, so a fixed header-offset slice truncates them — v2.8.2 CH04A lost
// the head of RXA-29 ("ministered Tag Identifier"), RXE-45/RXO-36 ("armacy Phone Number")
// and RXR-6 ("inistration Site Modifier"). Anchor on the rightmost numeric metadata cell
// instead (ITEM #, or TBL # when the item number is blank): the name is whatever follows
// it. HL7 item/table numbers are 4-5 digit runs; `LEN`/`C.LEN` cells carry punctuation
// (`1..4`, `20=`, `5#`) or are shorter, so they don't collide. Falls back to the header
// offset when a row carries no numeric metadata at all (e.g. a withdrawn field whose LEN,
// DT, TBL and ITEM cells are all blank).
func nameBoundary(runs lineRuns: [Run], nameStart: Int) -> Int {
    var boundary = -1
    for r in lineRuns where r.start < nameStart {
        if (4...5).contains(r.text.count), r.text.allSatisfy({ $0.isNumber }) {
            boundary = max(boundary, r.end)
        }
    }
    return boundary >= 0 ? boundary : nameStart
}

// Parse a single body line into a field row using the current column model, or nil
// if the line's SEQ cell isn't a bare integer (blank, furniture, or continuation).
func parseRow(_ raw: String, columns: [Column]) -> FieldRow? {
    let line = raw.replacingOccurrences(of: "\t", with: "    ")
    let chars = Array(line)
    let nameStart = columns.first { $0.key == "NAME" }?.start ?? Int.max
    // SEQ = the first whitespace-delimited token on the line, if it is a bare
    // integer positioned before the DT column. Using the first token (not a fixed
    // header-offset slice) is robust to values that sit slightly left/right of the
    // "SEQ" label — a real v2.3-era layout where a fixed slice silently missed the
    // number, dropped every row, and skipped the whole table. The DT-column bound
    // rejects numeric continuation fragments (e.g. a lone "0328" under TBL#).
    let dtStart = columns.first { $0.key == "DT" }?.start ?? Int.max
    let lineRuns = runs(in: line)
    guard let firstRun = lineRuns.first,
          firstRun.start < dtStart,
          firstRun.text.allSatisfy({ $0.isNumber }),
          let n = Int(firstRun.text),
          n >= 1 else { return nil }   // reject seq 0 / non-field numeric lines (H2)
    var row = FieldRow(seq: n)
    // Bin metadata up to the row's own name boundary, not the header offset — otherwise a
    // left-shifted long name has its leading words binned as ITEM/TBL values.
    let boundary = nameBoundary(runs: lineRuns, nameStart: nameStart)
    let preNameLine = boundary < chars.count ? String(chars[0..<boundary]) : line
    for r in runs(in: preNameLine) {
        switch columnKey(forStart: r.start, columns: columns) {
        case "SEQ": break
        case "LEN": row.len = r.text
        case "CLEN": row.len = row.len.isEmpty ? r.text : row.len
        case "DT": row.dt = r.text
        case "OPT": row.opt = r.text
        case "RP": row.rp = r.text
        case "TBL": row.tbl = r.text
        case "ITEM": row.item = r.text
        default: break
        }
    }
    row.opt = normalizeOptionality(row.opt)
    // No slack when anchoring on a metadata run's end — 2 columns of slack would pull the
    // tail of the item number into the name.
    row.name = normalizeName(elementName(from: line, nameStart: boundary,
                                        slack: boundary == nameStart ? 2 : 0))
    // Reject footnote-number lines misread as rows: a real field always has an element
    // name. A "row" with no name AND no datatype is a stray table-footnote digit (e.g.
    // OBX's "2", MSA's "3", OM4's "0") that happened to sit before the DT column. (H2)
    //
    // The datatype test needs a *length* floor, not just non-emptiness: every real HL7
    // datatype token is 2+ characters, so a single-character "DT" is the tail of a wrapped
    // cell, not a type. v2.5.1 OBX-5's `varies` wraps as `varie` + `s`, and the orphan `s`
    // was parsed as a whole extra row (it also produced the bogus pre-v1.5 RDT field). (S2)
    if row.name.isEmpty && row.dt.count < 2 { return nil }
    return row
}

// Normalise cosmetic glyphs in element names for cross-version consistency with the
// canonical schemas: curly apostrophes/quotes → straight; non-breaking space → space.
func normalizeName(_ s: String) -> String {
    return s
        .replacingOccurrences(of: "\u{2019}", with: "'")   // ' right single quote
        .replacingOccurrences(of: "\u{2018}", with: "'")   // ' left single quote
        .replacingOccurrences(of: "\u{201C}", with: "\"")  // " left double quote
        .replacingOccurrences(of: "\u{201D}", with: "\"")  // " right double quote
        .replacingOccurrences(of: "\u{00A0}", with: " ")
        .trimmingCharacters(in: .whitespaces)
}

// Normalise the OPT cell. HL7 attribute tables sometimes render a backward-compat
// marker as "(B)" alone or compounded with the historical letter ("(B) R"); the
// effective single-letter optionality of such a field is B. Otherwise keep the letter.
func normalizeOptionality(_ raw: String) -> String {
    let t = raw.trimmingCharacters(in: .whitespaces)
    if t.contains("(B)") || t.uppercased() == "B" { return "B" }
    // strip any stray parentheses, keep the first R/O/C/X/W/B token
    let letters = t.uppercased().filter { "ROCXWB".contains($0) }
    return letters.isEmpty ? t : String(letters.first!)
}

// Append a no-SEQ continuation line to the last row: numeric fragments left of the
// NAME column continue the TBL# (e.g. 0327/ then 0328); text at/after NAME continues
// the wrapped element name.
func appendContinuation(_ raw: String, to rows: inout [FieldRow], columns: [Column]) {
    guard !rows.isEmpty else { return }
    let line = raw.replacingOccurrences(of: "\t", with: "    ")
    let chars = Array(line)
    let nameStart = columns.first { $0.key == "NAME" }?.start ?? Int.max
    let preName = nameStart < chars.count ? String(chars[0..<nameStart]) : ""
    for r in runs(in: preName) where r.text.allSatisfy({ $0.isNumber || $0 == "/" }) {
        rows[rows.count-1].tbl += r.text
    }
    let cont = elementName(from: line, nameStart: nameStart)
    if isNameContinuation(cont, currentName: rows[rows.count-1].name) {
        rows[rows.count-1].name += (rows[rows.count-1].name.isEmpty ? "" : " ") + cont
    }
}

// Page furniture between table rows (footers / running heads / form feeds) — skipped,
// not treated as table end.
func isPageFurniture(_ line: String) -> Bool {
    if line.contains("\u{0C}") { return true } // form feed
    let t = line.trimmingCharacters(in: .whitespaces)
    if t.isEmpty { return true }
    let markers = ["Health Level Seven", "All rights reserved", "Final Standard",
                   "Version 2.", "©", "\u{00A9}"]
    if markers.contains(where: { line.contains($0) }) { return true }
    if t.range(of: #"^Page\s"#, options: .regularExpression) != nil { return true }
    if t.range(of: #"^(January|February|March|April|May|June|July|August|September|October|November|December)\s"#, options: .regularExpression) != nil { return true }
    if t.range(of: #"^Chapter\s\d"#, options: .regularExpression) != nil { return true }
    return false
}

// The field-definitions section that immediately follows the attribute table
// (e.g. "3.4.2.0 PID field definitions" / "3.4.2.1 PID-1 ..."): the table's end.
//
// The leading token may carry an alphabetic chapter suffix — v2.8.2 splits the pharmacy
// chapter into 4 and 4A, numbering sections "4A.4.3.0 RXC field definitions". A
// digits-and-dots-only test missed those, so the scan ran past the table end and folded
// the whole field-definitions section into the last row's element name (v1.5-S2: the
// v2.8.2 RXA/RXC/RXD/RXE/RXG/RXO/RXR corruption).
func isFieldDefinitionsHeading(_ line: String) -> Bool {
    let t = line.trimmingCharacters(in: .whitespaces)
    guard let first = t.split(separator: " ").first, first.contains(".") else { return false }
    return first.range(of: #"^[0-9]+[A-Za-z]?(\.[0-9]+)+$"#, options: .regularExpression) != nil
}

// Is `cont` a plausible wrapped-element-name fragment, rather than body prose?
//
// A wrapped name is short and has no sentence structure. Prose paragraphs that sit
// between a table and its field-definitions heading (the "the business and/or application
// must assume responsibility for maintaining knowledge about data ownership…" note under
// PRB / GOL) would otherwise be appended to the last row's name (v1.5-S2).
func isNameContinuation(_ cont: String, currentName: String) -> Bool {
    let t = cont.trimmingCharacters(in: .whitespaces)
    if t.isEmpty { return false }
    if t.count > 60 { return false }                       // paragraphs aren't name wraps
    if t.contains(". ") || t.hasSuffix(".") { return false }   // sentence punctuation
    if t.contains("^") || t.contains("|") || t.contains("<") { return false } // component/example text
    if currentName.count + t.count > 120 { return false }  // no HL7 element name is this long
    return true
}

// Map RP/# cell to repeatability token.
func repeatability(_ rp: String) -> String {
    let t = rp.trimmingCharacters(in: .whitespaces).uppercased()
    if t.isEmpty || t == "N" { return "1" }        // blank or explicit "N" (no) -> single
    if t == "Y" { return "*" }                      // "Y" (yes) -> repeats
    if t.contains("Y") { return "*" }               // "Y/2" etc.
    if t.first(where: { $0.isNumber }) != nil { return "*" } // max-count (e.g. "2", "3") -> repeats
    return "1"
}

// MARK: - table extraction from full text

struct Table { let segHint: String; let rows: [FieldRow] }

// Segment hint from the caption line(s) just above a header (empty for a page-repeat
// header, whose "caption" is only page furniture).
func captionSegment(above index: Int, lines: [String]) -> String {
    for back in 1...3 where index - back >= 0 {
        let cap = lines[index - back]
        if let m = cap.range(of: #"Attribute Table[ ]*[-–][ ]*([A-Z][A-Z0-9]{1,3})"#, options: .regularExpression) {
            return String(cap[m]).components(separatedBy: CharacterSet(charactersIn: "-–")).last!
                .trimmingCharacters(in: .whitespaces).components(separatedBy: " ").first ?? ""
        }
        // "attributes" is the usual caption, but a few legacy figures use the singular —
        // v2.3 CH2's "Figure 2-10. ERR attribute" was silently skipped by the plural-only
        // pattern, which left ERR out of the v1.6 depth audit's coverage entirely.
        if let m = cap.range(of: #"([A-Z][A-Z0-9]{1,3}) attributes?"#, options: .regularExpression) {
            return String(cap[m]).components(separatedBy: " ").first ?? ""
        }
    }
    return ""
}

func extractTables(from text: String) -> [Table] {
    let lines = text.components(separatedBy: "\n")
    var tables: [Table] = []
    var i = 0
    while i < lines.count {
        guard var columns = detectHeader(lines[i]) else { i += 1; continue }
        let segHint = captionSegment(above: i, lines: lines)
        var rows: [FieldRow] = []
        var expected = 1
        var j = i + 1
        loop: while j < lines.count {
            let line = lines[j]
            // A header line mid-scan: a page-repeat (no attribute-table caption above it)
            // updates the column model and is skipped; a genuinely new segment's table
            // (has its own caption) ends this one.
            if let h = detectHeader(line) {
                let caption = captionSegment(above: j, lines: lines)
                if !rows.isEmpty && caption.isEmpty {
                    columns = h; j += 1; continue        // page-repeat header
                } else if !rows.isEmpty {
                    break loop                            // next segment's table
                } else if !caption.isEmpty && caption != segHint {
                    // No rows yet and the next header carries a DIFFERENT segment's caption:
                    // this table's only row was unparseable (the `1-n` class — ADD, RDT), so
                    // it must end EMPTY rather than bind the next segment's rows. Sprint 0 §3
                    // found v2.4 ADD reporting BHS's 12 fields and BHS missing entirely.
                    break loop
                } else {
                    columns = h; j += 1; continue         // stray duplicate before first row
                }
            }
            // End of the table: the field-definitions section right after it.
            if !rows.isEmpty && isFieldDefinitionsHeading(line) { break loop }
            // Page furniture between rows (footers, running heads, form feeds): skip.
            if isPageFurniture(line) { j += 1; continue }
            // A data row, or a continuation of the previous row.
            if let row = parseRow(line, columns: columns) {
                if row.seq == 1 && expected > 2 { break loop } // a new segment restarted at 1
                rows.append(row); expected = row.seq + 1
            } else {
                appendContinuation(line, to: &rows, columns: columns)
            }
            j += 1
        }
        if !rows.isEmpty { tables.append(Table(segHint: segHint, rows: rows)) }
        i = max(j, i + 1)
    }
    return tables
}

// MARK: - JSON output

func jsonEscape(_ s: String) -> String {
    var o = ""
    for c in s {
        switch c {
        case "\"": o += "\\\""
        case "\\": o += "\\\\"
        case "\n": o += "\\n"
        default: o.append(c)
        }
    }
    return o
}

func emit(_ tables: [Table], filter: String?) {
    var blocks: [String] = []
    for t in tables {
        if let f = filter, t.segHint.uppercased() != f.uppercased() { continue }
        var fieldLines: [String] = []
        for r in t.rows {
            let rep = repeatability(r.rp)
            fieldLines.append("    { \"index\": \(r.seq), \"name\": \"\(jsonEscape(r.name))\", \"dataType\": \"\(jsonEscape(r.dt))\", \"optionality\": \"\(jsonEscape(r.opt))\", \"repeatability\": \"\(rep)\", \"len\": \"\(jsonEscape(r.len))\", \"tbl\": \"\(jsonEscape(r.tbl))\", \"item\": \"\(jsonEscape(r.item))\" }")
        }
        let block = "{\n  \"segmentHint\": \"\(t.segHint)\",\n  \"fieldCount\": \(t.rows.count),\n  \"fields\": [\n\(fieldLines.joined(separator: ",\n"))\n  ]\n}"
        blocks.append(block)
    }
    print("[\n" + blocks.joined(separator: ",\n") + "\n]")
}

// MARK: - verify mode (golden check against a committed schema)

// Compare the extractor's schema-relevant columns (index -> dataType, optionality,
// repeatability + field count) against a canonical Resources/schemas JSON. Element
// names and TBL#/LEN are intentionally NOT compared (names carry cosmetic punctuation
// the human normalises; TBL#/LEN aren't in the schema model). Exit 0 = PASS, 1 = FAIL.
func verify(pdf: String, seg: String, schemaPath: String) -> Never {
    guard FileManager.default.fileExists(atPath: pdf) else {
        print("SKIP: PDF not present (\(pdf)) — author-local source absent; nothing to verify.")
        exit(0)
    }
    guard let data = FileManager.default.contents(atPath: schemaPath),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let fields = obj["fields"] as? [[String: Any]] else {
        print("FAIL: could not read schema \(schemaPath)"); exit(1)
    }
    var expected: [Int: (dt: String, opt: String, rep: String)] = [:]
    for f in fields {
        guard let idx = f["index"] as? Int else { continue }
        expected[idx] = (f["dataType"] as? String ?? "",
                         f["optionality"] as? String ?? "",
                         f["repeatability"] as? String ?? "")
    }
    let tables = extractTables(from: runPdftotext(pdf))
    guard let table = tables.first(where: { $0.segHint.uppercased() == seg.uppercased() }) else {
        print("FAIL: extractor found no \(seg) table in \(pdf)"); exit(1)
    }
    var mismatches: [String] = []
    if table.rows.count != expected.count {
        mismatches.append("field count: extracted \(table.rows.count), schema \(expected.count)")
    }
    for r in table.rows {
        guard let e = expected[r.seq] else { mismatches.append("\(seg)-\(r.seq): not in schema"); continue }
        if r.dt != e.dt { mismatches.append("\(seg)-\(r.seq) DT: extracted \(r.dt), schema \(e.dt)") }
        if r.opt != e.opt { mismatches.append("\(seg)-\(r.seq) OPT: extracted \(r.opt), schema \(e.opt)") }
        if repeatability(r.rp) != e.rep { mismatches.append("\(seg)-\(r.seq) RP: extracted \(repeatability(r.rp)), schema \(e.rep)") }
    }
    if mismatches.isEmpty {
        print("PASS: \(seg) — \(table.rows.count) fields, DT/OPT/RP all match \(schemaPath)")
        exit(0)
    } else {
        print("FAIL: \(seg) — \(mismatches.count) mismatch(es):")
        for m in mismatches { print("  - \(m)") }
        exit(1)
    }
}

// MARK: - emit-schema mode (seed a Resources/schemas JSON from a PDF)

// Derive a valid lowerCamelCase Swift identifier from an element name.
func deriveSwiftName(_ name: String, used: inout Set<String>) -> String {
    // split on non-alphanumerics, drop empties; drop lone "s" fragments left by a
    // possessive apostrophe (e.g. "Contact Person's Name" → contactPersonName, not
    // contactPersonSName).
    let words = name.split { !($0.isLetter || $0.isNumber) }.map(String.init)
        .filter { !($0.count == 1 && $0.lowercased() == "s") }
    var camel = ""
    for (i, w) in words.enumerated() {
        let lw = w.lowercased()
        if i == 0 { camel += lw }
        else { camel += lw.prefix(1).uppercased() + lw.dropFirst() }
    }
    if camel.isEmpty { camel = "field" }
    if let f = camel.first, f.isNumber { camel = "f" + camel }   // identifiers can't start with a digit
    var candidate = camel
    var n = 2
    while used.contains(candidate) { candidate = "\(camel)\(n)"; n += 1 }
    used.insert(candidate)
    return candidate
}

// --emit-schema <pdf> <SEGID> <version> <reference-schema.json>
// Emits a full Resources/schemas JSON to stdout: extractor DT/OPT/RP + swiftNames
// mapped by index from the reference (canonical v2.5.1) schema, deriving new names
// for version-specific trailing fields. A SEED for human spec-verification — not a
// substitute for it (req #2/#4).
func emitSchema(pdf: String, seg: String, version: String, refPath: String) -> Never {
    let refData = FileManager.default.contents(atPath: refPath)
    let refObj: [String: Any] = refData.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
    let refFields = (refObj["fields"] as? [[String: Any]]) ?? []
    var refSwift: [Int: String] = [:]
    for f in refFields { if let i = f["index"] as? Int, let s = f["swiftName"] as? String { refSwift[i] = s } }
    let description = (refObj["description"] as? String) ?? seg

    let tables = extractTables(from: runPdftotext(pdf))
    guard let table = tables.first(where: { $0.segHint.uppercased() == seg.uppercased() }) else {
        FileHandle.standardError.write("emit-schema: no \(seg) table in \(pdf)\n".data(using: .utf8)!); exit(1)
    }
    var used = Set<String>()
    // pre-seed used-set with the reference names we'll reuse, so derived names don't collide
    for r in table.rows { if let s = refSwift[r.seq] { used.insert(s) } }
    var lines: [String] = []
    for r in table.rows {
        let swiftName = refSwift[r.seq] ?? deriveSwiftName(r.name, used: &used)
        let rep = repeatability(r.rp)
        lines.append("    { \"index\": \(r.seq), \"swiftName\": \"\(jsonEscape(swiftName))\", \"name\": \"\(jsonEscape(r.name))\", \"dataType\": \"\(jsonEscape(r.dt))\", \"optionality\": \"\(jsonEscape(r.opt))\", \"repeatability\": \"\(rep)\" }")
    }
    let out = "{\n  \"segmentID\": \"\(seg)\",\n  \"version\": \"\(version)\",\n  \"description\": \"\(jsonEscape(description))\",\n  \"fields\": [\n\(lines.joined(separator: ",\n"))\n  ]\n}"
    print(out)
    exit(0)
}

// MARK: - main

let args = CommandLine.arguments
if args.count >= 5, args[1] == "--verify" {
    // --verify <pdf> <SEGID> <schema.json>
    verify(pdf: args[2], seg: args[3], schemaPath: args[4])
}
if args.count >= 6, args[1] == "--emit-schema" {
    // --emit-schema <pdf> <SEGID> <version> <reference-schema.json>
    emitSchema(pdf: args[2], seg: args[3], version: args[4], refPath: args[5])
}
guard args.count >= 2 else {
    FileHandle.standardError.write("""
    usage:
      extract-segment-tables.swift <chapter.pdf> [SEGID]
      extract-segment-tables.swift --verify <chapter.pdf> <SEGID> <canonical-schema.json>

    """.data(using: .utf8)!)
    exit(1)
}
let pdf = args[1]
let filter = args.count >= 3 ? args[2] : nil
let text = runPdftotext(pdf)
let tables = extractTables(from: text)
emit(tables, filter: filter)
