// PrimitiveFormat.swift
// Lexical rules for the HL7 primitive types whose format the spec prints
// (P6-7, V251-C10). Values arrive decoded (escape sequences resolved). Every
// rule admits all a section allows: a value the spec permits is never rejected.

import Foundation

enum PrimitiveFormat {
    /// The types with a rule here. Every other type (ST, TX, FT, ID, IS, ...)
    /// has no lexical rule beyond its character set and is never checked.
    static let checkedTypes: Set<String> = ["NM", "SI", "DT", "TM", "DTM", "TS"]

    /// Whether `value` is lexically valid for `dataType` on `version`, or nil
    /// when the type has no rule here.
    static func isValid(_ value: String, dataType: String, version: Version) -> Bool? {
        switch dataType {
        case "NM": return isNumeric(value)
        case "SI": return isSequenceID(value, bounded: version.boundsSequenceID)
        case "DT": return isDate(Substring(value))
        case "TM": return isTime(value)
        case "DTM", "TS": return isTimestamp(value)
        default: return nil
        }
    }

    /// NM (v2.5.1 §2.A.47, v2.8.2 §2.A.47; v2.3 §2.8.25, v2.3.1 §2.8.27, v2.4
    /// §2.9.28): "an optional leading sign (+ or -), the digits and an optional
    /// decimal point"; leading zeros, and trailing zeros after the point, are
    /// not significant. At least one digit, on either side of the point.
    static func isNumeric(_ value: String) -> Bool {
        numericParts(value) != nil
    }

    /// SI (v2.5.1 §2.A.69, v2.8.2 §2.A.70; v2.3 §2.8.36, v2.3.1 §2.8.38, v2.4
    /// §2.9.40): "a non-negative integer in the form of a NM field". The NM form
    /// is read for its value, so `+5`, `1.0` and `-0` are integers that are not
    /// negative. With `bounded` (v2.5.1+), the value lies in 0 to 9999.
    static func isSequenceID(_ value: String, bounded: Bool) -> Bool {
        guard let (negative, whole, fraction) = numericParts(value),
              fraction.allSatisfy({ $0 == "0" }) else { return false }
        let significant = whole.drop { $0 == "0" }
        if negative, !significant.isEmpty { return false }
        return !bounded || significant.count <= 4
    }

    /// DT (v2.5.1 and v2.8.2 §2.A.21; v2.3 §2.8.13, v2.3.1 §2.8.15, v2.4
    /// §2.9.15): `YYYY[MM[DD]]`, precision by the number of digits; the month
    /// and day, where present, name a calendar date.
    static func isDate(_ value: Substring) -> Bool {
        let c = Array(value)
        guard [4, 6, 8].contains(c.count), c.allSatisfy(isDigit) else { return false }
        if c.count >= 6, !(1...12).contains(number(c[4..<6])) { return false }
        if c.count == 8 {
            let year = number(c[0..<4]), month = number(c[4..<6])
            let leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
            let days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][month - 1]
            if !(1...days).contains(number(c[6..<8])) { return false }
        }
        return true
    }

    /// TM (v2.5.1 §2.A.75, v2.8.2 §2.A.77; v2.3 §2.8.39, v2.3.1 §2.8.41, v2.4
    /// §2.9.44): `HH[MM[SS[.S[S[S[S]]]]]][+/-ZZZZ]`.
    static func isTime(_ value: String) -> Bool {
        let (clock, zoneOK) = splitZone(value)
        return zoneOK && isClock(clock)
    }

    /// DTM (v2.5.1 and v2.8.2 §2.A.22): `YYYY[MM[DD[HH[MM[SS[.S[S[S[S]]]]]]]]][+/-ZZZZ]`.
    /// TS before v2.5 (v2.3 §2.8.42, v2.3.1 §2.8.44, v2.4 §2.9.47) prints
    /// `YYYY[MM[DD[HHMM[SS...]]]]` but its prose says "YYYYMMDDHH is used to
    /// specify a precision of 'hour'" and "the time portion follows the rules of
    /// a time field", so the hour may stand alone on every version.
    static func isTimestamp(_ value: String) -> Bool {
        let (body, zoneOK) = splitZone(value)
        let date = body.prefix(8)
        guard zoneOK, isDate(date) else { return false }
        let rest = body.dropFirst(8)
        return rest.isEmpty || (date.count == 8 && isClock(rest))
    }

    /// The sign, the digits before the point and the digits after it, or nil
    /// when `value` is not an NM.
    private static func numericParts(_ value: String) -> (Bool, Substring, Substring)? {
        var body = Substring(value)
        let negative = body.first == "-"
        if let first = body.first, first == "+" || first == "-" { body = body.dropFirst() }
        let parts = body.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.allSatisfy({ $0.allSatisfy(isDigit) }), parts.contains(where: { !$0.isEmpty }) else { return nil }
        return (negative, parts[0], parts.count == 2 ? parts[1] : "")
    }

    /// Splits a trailing `+/-ZZZZ`, the offset "represented in HHMM format"
    /// (v2.5.1 §2.A.22 and 2.A.75). `zoneOK` is false when a sign is present but
    /// not followed by exactly four digits.
    private static func splitZone(_ value: String) -> (Substring, Bool) {
        guard let sign = value.lastIndex(where: { $0 == "+" || $0 == "-" }) else { return (Substring(value), true) }
        let zone = value[value.index(after: sign)...]
        return (value[..<sign], zone.count == 4 && zone.allSatisfy(isDigit))
    }

    /// `HH[MM[SS[.S[S[S[S]]]]]]` on a "24-hour clock": hour 00-23 (midnight is
    /// `0000`, v2.5.1 §2.A.75 example), minute 00-59, second 00-60 (60 admits a
    /// leap second; the sections print no range), 1 to 4 fractional digits only
    /// after seconds ("Fractional representations of minutes, hours or other
    /// higher-order units of time are not permitted", §2.A.75).
    private static func isClock(_ clock: Substring) -> Bool {
        let parts = clock.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        let whole = Array(parts[0])
        guard [2, 4, 6].contains(whole.count), whole.allSatisfy(isDigit) else { return false }
        if parts.count == 2 {
            let fraction = parts[1]
            guard whole.count == 6, (1...4).contains(fraction.count), fraction.allSatisfy(isDigit) else { return false }
        }
        if number(whole[0..<2]) > 23 { return false }
        if whole.count >= 4, number(whole[2..<4]) > 59 { return false }
        if whole.count >= 6, number(whole[4..<6]) > 60 { return false }
        return true
    }

    /// An ASCII digit only: a fullwidth or combined digit is not "ASCII numeric".
    private static func isDigit(_ c: Character) -> Bool {
        guard let ascii = c.asciiValue else { return false }
        return (48...57).contains(ascii)
    }

    private static func number(_ digits: ArraySlice<Character>) -> Int { Int(String(digits)) ?? -1 }
}
