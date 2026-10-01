// Version+Eras.swift
// Spec-era switches the validator keys on. Exhaustive on purpose: a new Version case
// must decide which side of each boundary it falls on (P6-6).

import Foundation

extension Version {
    /// True where the attribute tables print LEN as a maximum length (v2.3 to v2.6:
    /// v2.3.1 §2.6.2, v2.5.1 §2.5.3.2); false from v2.7, where LEN is a normative
    /// length and C.LEN a conformance length (v2.8.2 §2.5.5).
    var printsMaximumLength: Bool {
        switch self {
        case .v2_3, .v2_3_1, .v2_4, .v2_5_1, .v2_6: return true
        case .v2_8_2, .v2_8: return false
        }
    }

    /// True where a pre-v2.7 LEN cell may print the symbols 65536 ("the notion of
    /// a Very Large Number", replacing the earlier `64K`) and 99999 (a length that
    /// "cannot be definitively expressed because the data type for the field is
    /// variable"): v2.4 section 2.7.2, v2.5.1 and v2.6 section 2.5.3.2 b) and c).
    /// v2.3 and v2.3.1 abbreviate as `64K` instead; v2.7+ prints no maximum.
    var printsLengthSymbols: Bool {
        switch self {
        case .v2_4, .v2_5_1, .v2_6: return true
        case .v2_3, .v2_3_1, .v2_8_2, .v2_8: return false
        }
    }
}
