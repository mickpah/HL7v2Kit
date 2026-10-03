// Version+Eras.swift
// Spec-era switches the validator keys on. Exhaustive on purpose: a new Version case
// must decide which side of each boundary it falls on (P6-6).

import Foundation

extension Version {
    /// True where the attribute tables print LEN as a maximum length (v2.3 to v2.6:
    /// v2.3.1 §2.6.2, v2.5.1 §2.5.3.2); false from v2.7, where LEN is a normative
    /// length and C.LEN a conformance length (v2.8.2 §2.5.5; v2.7.1 CH02 §2.5.3.2
    /// and §2.5.3.3 p8, §2.5.5.0 p10 "Normative Length", §2.5.5.3 p12).
    var printsMaximumLength: Bool {
        switch self {
        case .v2_3, .v2_3_1, .v2_4, .v2_5_1, .v2_6: return true
        case .v2_7_1, .v2_7, .v2_8_2, .v2_8: return false
        }
    }

    /// True where a pre-v2.7 LEN cell may print the symbols 65536 ("the notion of
    /// a Very Large Number", replacing the earlier `64K`) and 99999 (a length that
    /// "cannot be definitively expressed because the data type for the field is
    /// variable"): v2.4 section 2.7.2, v2.5.1 and v2.6 section 2.5.3.2 b) and c).
    /// v2.3 and v2.3.1 abbreviate as `64K` instead; v2.7+ prints no maximum
    /// (v2.7.1 CH02 §2.5.5 pp10-12 defines neither symbol).
    var printsLengthSymbols: Bool {
        switch self {
        case .v2_4, .v2_5_1, .v2_6: return true
        case .v2_3, .v2_3_1, .v2_7_1, .v2_7, .v2_8_2, .v2_8: return false
        }
    }

    /// True where the SI section bounds a sequence ID to 0 to 9999: "Maximum
    /// Length: 4. This allows for a number between 0 and 9999 to be specified"
    /// (v2.5.1 §2.A.69, v2.6 §2.A.69, v2.7.1 §2.A.69 p80, v2.8.2 §2.A.70). v2.3 §2.8.36, v2.3.1
    /// §2.8.38 and v2.4 §2.9.40 print only "a non-negative integer in the form
    /// of a NM field" (P6-7). This property gates only the *value* bound (0 to
    /// 9999) in `PrimitiveFormat.isSequenceID`; the same sentence's printed
    /// maximum length of 4 is a separate, field-length concern: `09999` is
    /// within the value bound but is 5 characters, so the length check
    /// reports it where the field's LEN is 4 (`fieldLengthOutOfRange`), not
    /// by this format check. A component-level SI is not length-checked.
    var boundsSequenceID: Bool {
        switch self {
        case .v2_5_1, .v2_6, .v2_7_1, .v2_7, .v2_8_2, .v2_8: return true
        case .v2_3, .v2_3_1, .v2_4: return false
        }
    }
}
