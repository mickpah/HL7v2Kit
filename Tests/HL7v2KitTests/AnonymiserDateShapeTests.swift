// AnonymiserDateShapeTests.swift
// A date repetition moves only in the shape its type defines: component 1 a DTM, and on a TS
// (v2.3 to v2.5.1) TS.2 empty or one of its codes. Anything else becomes [REDACTED] whole, so
// a date of birth cannot pass in clear beside a subcomponent or an extra component.

import Testing
@testable import HL7v2Kit

@Suite("Anonymiser date shapes")
struct AnonymiserDateShapeTests {
    /// The covered date fields that are no range, and the ranges (DR); GSP, GSR and GSC on 2.9.1 only.
    static let dates = [("PID", 7), ("PID", 29), ("NK1", 16), ("IN1", 18), ("GT1", 8), ("GT1", 24)]
    static let ranges = [("GSP", 6), ("GSR", 9), ("GSC", 5)]

    /// What a rule writes for `raw` alone: key 7, or the tool's rule with salt 41.
    static func moved(_ raw: String, keyed: Bool) -> String {
        let source: SyntheticSource = keyed ? .keyed(7) : .legacy(salt: 41)
        return scrubDOB(raw, salt: source.pick("date", raw).salt)
    }

    /// Field `index` of segment `id` as written, for every date field holding `value`.
    static func written(_ value: String, version: String, keyed: Bool) throws -> [String: String] {
        let anonymiser = keyed ? Anonymiser(key: 7) : Anonymiser(legacySalt: 41)
        let input = try Parser().parse(AnonymiserTests.everyDateField(value, version: version))
        let lines = String(decoding: anonymiser.anonymise(input).serialize(), as: UTF8.self).split(separator: "\r")
        var out: [String: String] = [:]
        for (id, index) in dates + ranges {
            guard let line = lines.first(where: { $0.hasPrefix(id + "|") }) else { continue }
            let fields = line.split(separator: "|", omittingEmptySubsequences: false)
            out["\(id)-\(index)"] = fields.indices.contains(index) ? String(fields[index]) : ""
        }
        return out
    }

    @Test("A repetition in a shape its type does not define becomes [REDACTED] whole, under a key and the tool",
          arguments: ["2.4", "2.9.1"])
    func shapeNotDefined(version: String) throws {
        let ts = version == "2.4"
        for keyed in [true, false] {
            let m = Self.moved("19800615", keyed: keyed)
            // (value, written in a date field, written in a range)
            for (value, date, range) in [
                ("19800615&1200", nil, nil),               // a subcomponent after the date
                ("19800615&", nil, nil),                   // an empty one: component 1 is no DTM
                ("^19800615", nil, "^" + m),                // TS.2, or no component DTM defines; a range with no start
                ("19800615^19800615", nil, m + "^" + m),    // the same date again: in TS.2, or a range's end
                ("20201218^20210115^20210115", nil, nil),   // beyond a range's two components
                ("1980-06-15^D", nil, nil),                // component 1 no DTM, beside a valid TS.2
                ("19800615^X", nil, nil),                  // no TS.2 code
                ("19800615^D", ts ? m + "^D" : nil, nil),  // a TS.2 code: kept on a TS, no DTM as a range's end
                ("19800615^", ts ? m + "^" : nil, m + "^"), // an empty TS.2 or range end; DTM defines no component 2
                ("19800615~19800615&1200", m + "~[REDACTED]", m + "~[REDACTED]"),  // every repetition alike
            ] {
                let out = try Self.written(value, version: version, keyed: keyed)
                for (id, index) in Self.dates {
                    #expect(out["\(id)-\(index)"] == (date ?? "[REDACTED]"),
                            "\(value) at \(id)-\(index), \(version), keyed \(keyed)")
                }
                for (id, index) in Self.ranges where version == "2.9.1" {
                    #expect(out["\(id)-\(index)"] == (range ?? "[REDACTED]"), "\(value) at \(id)-\(index), keyed \(keyed)")
                }
                #expect(!out.values.contains { $0.contains("0615&") || $0.hasSuffix("^19800615") }, "\(value), \(version)")
            }
        }
    }

    // v2.5.1 2.A.77.2 and Table 0529 (p 2-225); v2.3 2.8.42 (p 2-45), v2.3.1 2.8.44 (p 2-52), v2.4 2.9.47
    // (p 2-69): Y year, L month, D day, H hour, M minute, S second. TS.1's digits decide how the date moves,
    // as AnonymiseTests.precisionComponentKept pins.
    @Test("On a TS, an empty TS.2 or any of its codes is kept, and the date moves as it does alone",
          arguments: ["", "Y", "L", "D", "H", "M", "S"])
    func degreeOfPrecisionKept(code: String) throws {
        for keyed in [true, false] {
            let out = try Self.written("19800615^" + code, version: "2.4", keyed: keyed)
            for (id, index) in Self.dates {
                #expect(out["\(id)-\(index)"] == Self.moved("19800615", keyed: keyed) + "^" + code,
                        "\(code) at \(id)-\(index), keyed \(keyed)")
            }
        }
    }
}
