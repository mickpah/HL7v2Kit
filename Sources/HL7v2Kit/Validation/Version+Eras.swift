// Version+Eras.swift
// Spec-era switches the validator keys on. Exhaustive on purpose: a new Version case
// must decide which side of each boundary it falls on (P6-6).

import Foundation

extension Version {
    /// True where the attribute tables print LEN as a maximum length (v2.3 to v2.6:
    /// v2.3.1 §2.6.2, v2.5.1 §2.5.3.2); false from v2.7, where LEN is a normative
    /// length and C.LEN a conformance length (v2.8.2 §2.5.5; v2.7.1 CH02 §2.5.3.2
    /// and §2.5.3.3 p8, §2.5.5.0 p10 "Normative Length", §2.5.5.3 p12; v2.9 CH02 §2.5.5 and §2.5.5.0
    /// "Normative Length", p12; v2.9.1 CH02 §2.4.5 and §2.4.5.0, p13).
    var printsMaximumLength: Bool {
        switch self {
        case .v2_3, .v2_3_1, .v2_4, .v2_5_1, .v2_6: return true
        case .v2_7_1, .v2_7, .v2_8_2, .v2_8, .v2_9, .v2_9_1: return false
        }
    }

    /// True where a pre-v2.7 LEN cell may print the symbols 65536 ("the notion of
    /// a Very Large Number", replacing the earlier `64K`) and 99999 (a length that
    /// "cannot be definitively expressed because the data type for the field is
    /// variable"): v2.4 section 2.7.2, v2.5.1 and v2.6 section 2.5.3.2 b) and c).
    /// v2.3 and v2.3.1 abbreviate as `64K` instead; v2.7+ prints no maximum
    /// (v2.7.1 CH02 §2.5.5 pp10-12, v2.9 CH02 §2.5.5, p12, and v2.9.1 CH02 §2.4.5, p13, define neither symbol).
    var printsLengthSymbols: Bool {
        switch self {
        case .v2_4, .v2_5_1, .v2_6: return true
        case .v2_3, .v2_3_1, .v2_7_1, .v2_7, .v2_8_2, .v2_8, .v2_9, .v2_9_1: return false
        }
    }

    /// True where the SI section bounds a sequence ID to 0 to 9999: "Maximum
    /// Length: 4. This allows for a number between 0 and 9999 to be specified"
    /// (v2.5.1 §2.A.69, v2.6 §2.A.69, v2.7.1 §2.A.69 p80, v2.8.2 §2.A.70, v2.9 §2A.3.70 p79, v2.9.1 §2A.2.70 p80). v2.3 §2.8.36, v2.3.1
    /// §2.8.38 and v2.4 §2.9.40 print only "a non-negative integer in the form
    /// of a NM field" (P6-7). This property gates only the *value* bound (0 to
    /// 9999) in `PrimitiveFormat.isSequenceID`; the same sentence's printed
    /// maximum length of 4 is a separate, field-length concern: `09999` is
    /// within the value bound but is 5 characters, so the length check
    /// reports it where the field's LEN is 4 (`fieldLengthOutOfRange`), not
    /// by this format check. A component-level SI is not length-checked.
    var boundsSequenceID: Bool {
        switch self {
        case .v2_5_1, .v2_6, .v2_7_1, .v2_7, .v2_8_2, .v2_8, .v2_9, .v2_9_1: return true
        case .v2_3, .v2_3_1, .v2_4: return false
        }
    }

    /// True where the validator reads the delete indicator on a data segment: a repetition holding
    /// only `""` has no components to require, and a segment with `""` first and nothing else real has
    /// no fields to read. v2.9 CH02 2.5.3.1 pp8-9 ("Populated with Delete Indicator") and 2.10.4.1 p42
    /// ("delete data" indicated "for the first field (or all fields)"). v2.9.1 prints the same words at
    /// CH02 2.4.3.1 pp9-10 and 2.9.4.1 p43.
    ///
    /// False on the earlier versions as a hold, not because their prints differ: v2.8.2 CH02 pp8, 38, 41
    /// and v2.7.1 pp7, 36, 40 say the same under the term "Null". Turning them on moves their reports.
    var appliesDeleteIndicator: Bool {
        switch self {
        case .v2_9, .v2_9_1: return true
        case .v2_3, .v2_3_1, .v2_4, .v2_5_1, .v2_6, .v2_7_1, .v2_7, .v2_8_2, .v2_8: return false
        }
    }

    /// True where a comparison ignores a value's trailing blanks. ST: "String data is left justified
    /// (i.e., no leading blank space) with trailing blanks optional, which may be trimmed, and SHOULD be
    /// ignored on string compare operations for 2 values of type ST" (v2.9 CH02A 2A.3.76 p82, v2.9.1
    /// 2A.2.76 p83), and ID "follows the formatting rules for an ST field" (p50 on each). v2.8.2's ST
    /// stops at "trailing blanks optional", so v2.3 to v2.8.2 keep counting them.
    var ignoresTrailingBlanksInComparisons: Bool {
        switch self {
        case .v2_9, .v2_9_1: return true
        case .v2_3, .v2_3_1, .v2_4, .v2_5_1, .v2_6, .v2_7_1, .v2_7, .v2_8_2, .v2_8: return false
        }
    }

    /// `value` as a comparison on this version reads it. Only U+0020 is a blank and only a trailing one
    /// goes. Length is not a comparison and still counts it, and a leading blank stays.
    func comparisonValue(_ value: String) -> String {
        guard ignoresTrailingBlanksInComparisons else { return value }
        var trimmed = Substring(value)
        while trimmed.last == " " { trimmed.removeLast() }
        return String(trimmed)
    }

    /// The OID the print gives table 0953, so a tuple carrying it in its OID component names the table:
    /// `Table OID 2.16.840.1.113883.12.953`, V291 CH02C p851. v2.9's entry prints none (CH02C pp 804 to 805).
    var table0953OID: String? {
        switch self {
        case .v2_9_1: return "2.16.840.1.113883.12.953"
        case .v2_3, .v2_3_1, .v2_4, .v2_5_1, .v2_6, .v2_7_1, .v2_7, .v2_8_2, .v2_8, .v2_9: return nil
        }
    }

    /// True where the truncation escape `\P\` is defined: v2.7.1 section 2.5.5.2 p12 (the
    /// truncation character "may be escaped but this is not required") and v2.8.2 sections
    /// 2.7.1 and 2.7.2, which list `\P\`, v2.9 sections 2.7.1 and 2.7.2 (p21), and v2.9.1 sections 2.6.1 (p22) and
    /// 2.6.2 (p23). v2.3 to v2.6 print no truncation character.
    var definesTruncationEscape: Bool {
        switch self {
        case .v2_7_1, .v2_7, .v2_8_2, .v2_8, .v2_9, .v2_9_1: return true
        case .v2_3, .v2_3_1, .v2_4, .v2_5_1, .v2_6: return false
        }
    }

    /// The Chapter 2 section that defines the escape sequences: "Use of escape sequences in
    /// text fields" is 2.9 in v2.3 and v2.3.1 and 2.10 in v2.4, and 2.7 from v2.5.1 (v2.8.2
    /// titles it "Use of escape sequences in fields"; v2.9 CH02 section 2.7, p21). v2.9.1 renumbers it 2.6
    /// (CH02 section 2.6, p22), as it does the whole chapter.
    var escapeSequenceSection: String {
        switch self {
        case .v2_3, .v2_3_1: return "2.9"
        case .v2_4: return "2.10"
        case .v2_5_1, .v2_6, .v2_7_1, .v2_7, .v2_8_2, .v2_8, .v2_9: return "2.7"
        case .v2_9_1: return "2.6"
        }
    }
}
