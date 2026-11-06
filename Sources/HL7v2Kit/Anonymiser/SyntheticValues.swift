// SyntheticValues.swift
// The synthetic values the anonymiser writes. Each is chosen from a salt and a slot, and
// SyntheticSource says where those come from. The generators moved unchanged from the
// HL7v2KitAnonymise tool, so the tool's output is unchanged.

import Foundation

/// Where a synthetic value's salt and slot come from.
enum SyntheticSource: Sendable {
    /// The command-line tool's rule: one salt per file (from MSH-10), offset by the
    /// repetition or slot the tool has always used.
    case legacy(salt: Int)

    /// The library's rule: every value chosen from a seed of the caller's key, its kind and the
    /// original value alone, so the same value gives the same output in every message.
    case keyed(UInt64)

    /// The salt and slot a generator takes for `original`, a value of `kind`. `offset` and
    /// `slot` are the tool's per-repetition and per-field adjustments.
    func pick(_ kind: String, _ original: String, offset: Int = 0, slot: Int = 0) -> (salt: Int, slot: Int) {
        switch self {
        case .legacy(let salt): (salt &+ offset, slot)
        case .keyed(let key): (Int(truncatingIfNeeded: anonymiserSeed(key: key, kind: kind, original: original) & 0x7FFF_FFFF), 0)
        }
    }
}

/// FNV-1a 64 over the key's eight little-endian bytes, then `kind`'s UTF-8 bytes, a 0x00 byte
/// and `original`'s UTF-8 bytes. Fixed arithmetic, so the same on every run and platform; the
/// FHIR counterpart uses the same function, so one key maps an identifier to the same value.
func anonymiserSeed(key: UInt64, kind: String, original: String) -> UInt64 {
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    func mix(_ byte: UInt8) { hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01b3 }
    for shift in stride(from: 0, to: 64, by: 8) { mix(UInt8(truncatingIfNeeded: key >> UInt64(shift))) }
    kind.utf8.forEach(mix)
    mix(0)
    original.utf8.forEach(mix)
    return hash
}

/// How finely a date is given: a DTM's digits before any `+/-ZZZZ` offset (CH02A 2A.2.22 p39).
package enum DatePrecision: Comparable {
    case year, month
    /// A day or finer.
    case day
}

/// `raw`'s precision, or nil for a value that is not a DTM, whatever its length.
func datePrecision(_ raw: String) -> DatePrecision? {
    guard PrimitiveFormat.isTimestamp(raw) else { return nil }
    switch raw.prefix(while: \.isNumber).count {
    case 4: return .year
    case 6: return .month
    default: return .day
    }
}

/// `raw` moved at its own precision or `coarsest`, whichever is coarser. A month or day keeps the
/// tail past its date (a time, an offset); a year is kept whole, and a finer value cut to its year
/// loses its tail. Empty and the HL7 null `""` are kept, and any other value that is not a DTM is
/// replaced whole by `[REDACTED]`, which a second pass therefore keeps.
package func scrubDOB(_ raw: String, salt: Int, at coarsest: DatePrecision = .day) -> String {
    guard let own = datePrecision(raw) else { return raw.isEmpty || raw == "\"\"" ? raw : "[REDACTED]" }
    let precision = min(own, coarsest)
    let yyyy = Int(raw.prefix(4)) ?? 1980
    // A year alone says no more than an age, so it is kept; a finer value beside it is cut to its year.
    if precision == .year { return own == .year ? raw : String(format: "%04d", yyyy) }
    let mm = Int(raw.dropFirst(4).prefix(2)) ?? 1
    let dd = own == .month ? 1 : Int(raw.dropFirst(6).prefix(2)) ?? 1
    let tail = String(raw.dropFirst(own == .month ? 6 : 8))   // time / timezone if present

    var components = DateComponents()
    components.year = yyyy
    components.month = mm
    components.day = dd
    let calendar = Calendar(identifier: .gregorian)
    guard let date = calendar.date(from: components) else { return "[REDACTED]" }
    // Shift by one to four whole weeks, or as many whole months, either way: the age stays about
    // right and the shift is never zero. By weeks the day of the week holds; by months the day of
    // the month is kept where the month has it, so the 31st becomes a shorter month's last day.
    let weeks = salt % 4 + 1
    let shift = salt & 4 == 0 ? weeks : -weeks
    guard let shifted = precision == .month ? calendar.date(byAdding: .month, value: shift, to: date)
                                            : calendar.date(byAdding: .day, value: 7 * shift, to: date)
    else { return "[REDACTED]" }
    let shiftedComponents = calendar.dateComponents([.year, .month, .day], from: shifted)
    if own == .month {
        return String(format: "%04d%02d%@", shiftedComponents.year ?? yyyy, shiftedComponents.month ?? mm, tail)
    }
    return String(format: "%04d%02d%02d%@",
                  shiftedComponents.year ?? yyyy,
                  shiftedComponents.month ?? mm,
                  shiftedComponents.day ?? dd,
                  tail)
}

// MARK: - Synthetic value generators

struct SyntheticName: Sendable {
    let family: String
    let given: String
}

func syntheticName(salt: Int, slot: Int) -> SyntheticName {
    let families = ["Anderson", "Bennett", "Carter", "Davies", "Edwards", "Foster", "Greene", "Harris", "Irving", "Jensen"]
    let givens = ["Alex", "Sam", "Jordan", "Casey", "Morgan", "Riley", "Taylor", "Robin", "Drew", "Quinn"]
    let f = families[((salt &+ slot) & 0x7FFFFFFF) % families.count]
    let g = givens[((salt &+ slot &+ 7) & 0x7FFFFFFF) % givens.count]
    return SyntheticName(family: f, given: g)
}

func syntheticIdentifier(matching original: String, salt: Int) -> String {
    // Format-preserving: if the original is all digits, emit an all-digit
    // replacement of the same length. Otherwise emit a "SYN-" prefix +
    // last-4 of the salt-derived hash.
    if original.allSatisfy(\.isNumber), !original.isEmpty {
        var generator = SeededRNG(seed: UInt64(salt) &+ UInt64(original.count))
        var s = ""
        for _ in original {
            s.append(String(generator.next() % 10))
        }
        return s
    }
    let suffix = String(format: "%04d", abs(salt) % 10000)
    return "SYN-\(suffix)"
}

func syntheticFacility(salt: Int, slot: Int) -> String {
    let facilities = ["SYNTH_HIS", "SYNTH_FAC", "SYNTH_LAB", "SYNTH_HOSP", "SYNTH_PMS", "SYNTH_LIS", "SYNTH_RIS", "SYNTH_EMR"]
    return facilities[((salt &+ slot) & 0x7FFFFFFF) % facilities.count]
}

func syntheticProviderID(salt: Int, slot: Int) -> String {
    // AHPRA-shaped: 10 alphanumerics. Emit DR + 8 digits for determinism.
    var generator = SeededRNG(seed: UInt64(salt) &+ UInt64(slot &* 31))
    var s = "DR"
    for _ in 0..<8 {
        s.append(String(generator.next() % 10))
    }
    return s
}

struct SyntheticAddress: Sendable {
    let street: String
    let city: String
    let state: String
    let postcode: String
}

func syntheticAddress(salt: Int, slot: Int) -> SyntheticAddress {
    let auSuburbs: [(city: String, state: String, postcode: String)] = [
        ("Surry Hills", "NSW", "2010"),
        ("Carlton", "VIC", "3053"),
        ("Fortitude Valley", "QLD", "4006"),
        ("Norwood", "SA", "5067"),
        ("Subiaco", "WA", "6008"),
        ("Battery Point", "TAS", "7004"),
        ("Braddon", "ACT", "2612"),
        ("Parap", "NT", "0820"),
    ]
    let pick = auSuburbs[((salt &+ slot) & 0x7FFFFFFF) % auSuburbs.count]
    let streetNumber = ((salt &* 17) & 0xFF) % 200 + 1
    let streetNames = ["Banksia St", "Wattle Rd", "Eucalyptus Ave", "Coolabah Cres", "Karri Pl"]
    let street = "\(streetNumber) \(streetNames[((salt &+ slot &* 3) & 0x7FFFFFFF) % streetNames.count])"
    return SyntheticAddress(street: street, city: pick.city, state: pick.state, postcode: pick.postcode)
}

func syntheticPhone(salt: Int, slot: Int) -> String {
    // 61-2-XXXX-XXXX shape (AU landline + Sydney area code).
    var generator = SeededRNG(seed: UInt64(salt) &+ UInt64(slot &* 7919))
    var s = "61-2-"
    for i in 0..<8 {
        if i == 4 { s.append("-") }
        s.append(String(generator.next() % 10))
    }
    return s
}

// MARK: - Seeded PRNG

/// A deterministic, seedable RNG (xorshift64). Same seed → same sequence.
/// Used to make every synthetic value reproducible from the per-file salt.
struct SeededRNG {
    var state: UInt64

    init(seed: UInt64) {
        self.state = seed == 0 ? 0xDEADBEEFCAFEBABE : seed
    }

    mutating func next() -> Int {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return Int(state & 0x7FFFFFFF)
    }
}
