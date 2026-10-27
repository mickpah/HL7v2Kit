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

    /// The salt and slot a generator takes for `original`, a value of `kind`. `offset` and
    /// `slot` are the tool's per-repetition and per-field adjustments.
    func pick(_ kind: String, _ original: String, offset: Int = 0, slot: Int = 0) -> (salt: Int, slot: Int) {
        switch self {
        case .legacy(let salt): (salt &+ offset, slot)
        }
    }
}

package func scrubDOB(_ raw: String, salt: Int) -> String {
    // Shift by one to four whole weeks, either way: the day of the week holds,
    // the age stays about right, and the shift is never zero.
    guard raw.count >= 8 else { return raw }
    let yyyy = Int(raw.prefix(4)) ?? 1980
    let mm = Int(raw.dropFirst(4).prefix(2)) ?? 1
    let dd = Int(raw.dropFirst(6).prefix(2)) ?? 1
    let tail = String(raw.dropFirst(8))   // time / timezone if present

    var components = DateComponents()
    components.year = yyyy
    components.month = mm
    components.day = dd
    let calendar = Calendar(identifier: .gregorian)
    guard let date = calendar.date(from: components) else { return raw }
    let weeks = salt % 4 + 1
    let shiftDays = 7 * (salt & 4 == 0 ? weeks : -weeks)
    guard let shifted = calendar.date(byAdding: .day, value: shiftDays, to: date) else { return raw }
    let shiftedComponents = calendar.dateComponents([.year, .month, .day], from: shifted)
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
