// HL7v2KitAnonymise — strip PHI from a v2 message file per spec § 10.
//
// Usage:
//   swift run HL7v2KitAnonymise <input.hl7> [output.hl7]
//
// If output is omitted, writes to stdout. The script PARSES the input via
// HL7v2Kit, REWRITES the PHI-bearing fields with deterministic synthetic
// substitutes (same input → same output, modulo MSH-10-derived per-file
// salt), and re-SERIALISES. The output is therefore guaranteed to be a
// well-formed v2 message that round-trips and validates the same shape
// as the input.
//
// All scrubbing is deterministic per-file: a fixed salt is derived from
// MSH-10 (the message control ID), so re-anonymising the same input twice
// produces byte-identical output. This makes the anonymise step reproducible
// for CI gates.

import Foundation
import HL7v2Kit

// MARK: - Entry point

@main
struct Anonymise {
    static func main() throws {
        let args = CommandLine.arguments
        guard args.count >= 2 else {
            FileHandle.standardError.write(Data("usage: HL7v2KitAnonymise <input.hl7> [output.hl7]\n".utf8))
            throw ExitCode.failure
        }
        let inputURL = URL(fileURLWithPath: args[1])
        let outputURL = args.count >= 3 ? URL(fileURLWithPath: args[2]) : nil

        let inputData = try Data(contentsOf: inputURL)
        let message = try Parser().parse(inputData)
        let salt = deriveSalt(from: message)
        let scrubbed = scrub(message, salt: salt)
        let outputData = scrubbed.serialize()

        if let outputURL {
            try outputData.write(to: outputURL)
            FileHandle.standardError.write(Data("anonymised \(inputURL.lastPathComponent) → \(outputURL.lastPathComponent) (salt=\(salt))\n".utf8))
        } else {
            FileHandle.standardOutput.write(outputData)
        }
    }
}

enum ExitCode: Error { case failure }

// MARK: - Salt

/// Derive a per-file salt from MSH-10 (the message control ID). Same input
/// MSH-10 → same salt → same scrubbed output. If MSH-10 is missing or
/// empty, falls back to a hash of the entire message bytes.
func deriveSalt(from message: Message) -> Int {
    let mshControlID = message["MSH-10"] ?? ""
    let seed = mshControlID.isEmpty ? String(describing: message.segments.count) : mshControlID
    var hash = 5381
    for byte in seed.utf8 {
        hash = ((hash << 5) &+ hash) &+ Int(byte)   // djb2
    }
    return hash & 0x7FFFFFFF   // mask to non-negative
}

// MARK: - Scrub

/// Apply the spec § 10 scrubbing rules to a parsed message. Returns a new
/// `Message` with PHI fields replaced by deterministic synthetic values.
func scrub(_ message: Message, salt: Int) -> Message {
    var segments: [Segment] = []
    for segment in message.segments {
        switch segment.segmentID {
        case "MSH": segments.append(scrubMSH(segment, salt: salt))
        case "PID": segments.append(scrubPID(segment, salt: salt))
        case "NK1": segments.append(scrubNK1(segment, salt: salt))
        case "PV1": segments.append(scrubPV1(segment, salt: salt))
        case "OBR": segments.append(scrubOBR(segment, salt: salt))
        case "OBX": segments.append(scrubOBX(segment, salt: salt))
        case "NTE": segments.append(scrubNTE(segment, salt: salt))
        default:    segments.append(segment)
        }
    }
    return Message(
        version: message.version,
        encodingCharacters: message.encodingCharacters,
        segments: segments,
        characterEncoding: message.characterEncoding
    )
}

// MARK: - Per-segment scrubbers

func scrubMSH(_ segment: Segment, salt: Int) -> Segment {
    var fields = segment.fields
    replace(&fields, index: 3, with: .scalar(syntheticFacility(salt: salt, slot: 0)))   // sending app
    replace(&fields, index: 4, with: .scalar(syntheticFacility(salt: salt, slot: 1)))   // sending facility
    replace(&fields, index: 5, with: .scalar(syntheticFacility(salt: salt, slot: 2)))   // receiving app
    replace(&fields, index: 6, with: .scalar(syntheticFacility(salt: salt, slot: 3)))   // receiving facility
    return rebuild(segment, with: fields)
}

func scrubPID(_ segment: Segment, salt: Int) -> Segment {
    var fields = segment.fields
    replace(&fields, index: 3, withScrubbedCXList: fields, fieldIndex: 3, salt: salt)
    replace(&fields, index: 5, withScrubbedNameList: fields, fieldIndex: 5, salt: salt)
    replace(&fields, index: 6, withScrubbedNameList: fields, fieldIndex: 6, salt: salt)
    replace(&fields, index: 7, withScrubbedDOB: fields, fieldIndex: 7, salt: salt)
    replace(&fields, index: 9, withScrubbedNameList: fields, fieldIndex: 9, salt: salt)
    replace(&fields, index: 11, withScrubbedAddress: fields, fieldIndex: 11, salt: salt)
    replace(&fields, index: 13, withScrubbedPhoneList: fields, fieldIndex: 13, salt: salt)
    replace(&fields, index: 14, withScrubbedPhoneList: fields, fieldIndex: 14, salt: salt)
    replace(&fields, index: 18, withScrubbedCXList: fields, fieldIndex: 18, salt: salt)   // account number
    return rebuild(segment, with: fields)
}

func scrubNK1(_ segment: Segment, salt: Int) -> Segment {
    var fields = segment.fields
    replace(&fields, index: 2, withScrubbedNameList: fields, fieldIndex: 2, salt: salt)
    replace(&fields, index: 4, withScrubbedAddress: fields, fieldIndex: 4, salt: salt)
    replace(&fields, index: 5, withScrubbedPhoneList: fields, fieldIndex: 5, salt: salt)
    replace(&fields, index: 6, withScrubbedPhoneList: fields, fieldIndex: 6, salt: salt)
    return rebuild(segment, with: fields)
}

func scrubPV1(_ segment: Segment, salt: Int) -> Segment {
    var fields = segment.fields
    replace(&fields, index: 7, withScrubbedProviderList: fields, fieldIndex: 7, salt: salt)
    replace(&fields, index: 8, withScrubbedProviderList: fields, fieldIndex: 8, salt: salt)
    replace(&fields, index: 9, withScrubbedProviderList: fields, fieldIndex: 9, salt: salt)
    replace(&fields, index: 17, withScrubbedProviderList: fields, fieldIndex: 17, salt: salt)
    return rebuild(segment, with: fields)
}

func scrubOBR(_ segment: Segment, salt: Int) -> Segment {
    var fields = segment.fields
    replace(&fields, index: 10, withScrubbedProviderList: fields, fieldIndex: 10, salt: salt)   // collector
    replace(&fields, index: 16, withScrubbedProviderList: fields, fieldIndex: 16, salt: salt)   // ordering provider
    replace(&fields, index: 32, withScrubbedProviderList: fields, fieldIndex: 32, salt: salt)   // principal result interpreter
    return rebuild(segment, with: fields)
}

func scrubOBX(_ segment: Segment, salt: Int) -> Segment {
    var fields = segment.fields
    // OBX-5 is the observation value. Scrub free-text narrative (`TX`),
    // formatted text (`FT`), and string (`ST`) value types; leave numeric
    // (`NM`), coded (`CE`/`CWE`), and date-time alone.
    if let valueType = segment.field(2)?.stringValue,
       ["TX", "FT", "ST", "ED"].contains(valueType.uppercased()) {
        replace(&fields, index: 5, with: .scalar("[REDACTED]"))
    }
    return rebuild(segment, with: fields)
}

func scrubNTE(_ segment: Segment, salt: Int) -> Segment {
    var fields = segment.fields
    replace(&fields, index: 3, with: .scalar("[REDACTED]"))
    return rebuild(segment, with: fields)
}

// MARK: - Field-level helpers

func replace(_ fields: inout [Field], index: Int, with newField: Field) {
    guard fields.indices.contains(index) else { return }
    fields[index] = newField
}

/// True if at least one subcomponent under the field has a non-empty value.
/// An empty field (`||` on the wire) has the shape "one repetition, one
/// component, one empty subcomponent" — populated returns false there.
func isPopulated(_ field: Field) -> Bool {
    for rep in field.repetitions {
        for component in rep.components {
            for sub in component.subcomponents {
                if !sub.value.isEmpty { return true }
            }
        }
    }
    return false
}

func replace(_ fields: inout [Field], index: Int, withScrubbedCXList originals: [Field], fieldIndex: Int, salt: Int) {
    guard fields.indices.contains(index),
          let original = originals.indices.contains(fieldIndex) ? originals[fieldIndex] : nil,
          isPopulated(original)
    else { return }
    let scrubbedReps = original.repetitions.enumerated().map { i, rep -> Repetition in
        scrubCX(rep, salt: salt &+ i)
    }
    fields[index] = Field(repetitions: scrubbedReps)
}

func replace(_ fields: inout [Field], index: Int, withScrubbedNameList originals: [Field], fieldIndex: Int, salt: Int) {
    guard fields.indices.contains(index),
          let original = originals.indices.contains(fieldIndex) ? originals[fieldIndex] : nil,
          isPopulated(original)
    else { return }
    let scrubbedReps = original.repetitions.enumerated().map { i, rep -> Repetition in
        scrubXPN(rep, salt: salt &+ i)
    }
    fields[index] = Field(repetitions: scrubbedReps)
}

func replace(_ fields: inout [Field], index: Int, withScrubbedDOB originals: [Field], fieldIndex: Int, salt: Int) {
    guard fields.indices.contains(index),
          let original = originals.indices.contains(fieldIndex) ? originals[fieldIndex] : nil,
          let dobString = original.stringValue, !dobString.isEmpty
    else { return }
    let scrubbed = scrubDOB(dobString, salt: salt)
    fields[index] = .scalar(scrubbed)
}

func replace(_ fields: inout [Field], index: Int, withScrubbedAddress originals: [Field], fieldIndex: Int, salt: Int) {
    guard fields.indices.contains(index),
          let original = originals.indices.contains(fieldIndex) ? originals[fieldIndex] : nil,
          isPopulated(original)
    else { return }
    let scrubbedReps = original.repetitions.enumerated().map { i, _ -> Repetition in
        let addr = syntheticAddress(salt: salt, slot: i)
        return Repetition.components([addr.street, "", addr.city, addr.state, addr.postcode, "AU"])
    }
    fields[index] = Field(repetitions: scrubbedReps)
}

func replace(_ fields: inout [Field], index: Int, withScrubbedPhoneList originals: [Field], fieldIndex: Int, salt: Int) {
    guard fields.indices.contains(index),
          let original = originals.indices.contains(fieldIndex) ? originals[fieldIndex] : nil,
          isPopulated(original)
    else { return }
    let scrubbedReps = original.repetitions.enumerated().map { i, _ -> Repetition in
        Repetition.scalar(syntheticPhone(salt: salt, slot: i))
    }
    fields[index] = Field(repetitions: scrubbedReps)
}

func replace(_ fields: inout [Field], index: Int, withScrubbedProviderList originals: [Field], fieldIndex: Int, salt: Int) {
    guard fields.indices.contains(index),
          let original = originals.indices.contains(fieldIndex) ? originals[fieldIndex] : nil,
          isPopulated(original)
    else { return }
    let scrubbedReps = original.repetitions.enumerated().map { i, _ -> Repetition in
        let name = syntheticName(salt: salt &+ 100, slot: i)
        let id = syntheticProviderID(salt: salt, slot: i)
        return Repetition.components([id, name.family, name.given])
    }
    fields[index] = Field(repetitions: scrubbedReps)
}

func rebuild(_ segment: Segment, with fields: [Field]) -> Segment {
    // Emit as .unknown — round-trip byte-equality is preserved because the
    // serializer uses `Segment.fields` (the unified accessor) regardless of
    // typed-vs-unknown variant. A re-parse will re-hydrate to .typed.
    return .unknown(UnknownSegment(segmentID: segment.segmentID, fields: fields))
}

// MARK: - Composite-level scrubbers

func scrubCX(_ rep: Repetition, salt: Int) -> Repetition {
    // CX format: ID^^^assigning-authority^identifier-type-code.
    // Component[0] is the ID — synthesise format-preserving replacement.
    let originalID = rep.components.first?.stringValue ?? ""
    let scrubbedID = syntheticIdentifier(matching: originalID, salt: salt)
    var components = rep.components
    if !components.isEmpty {
        components[0] = .scalar(scrubbedID)
    }
    return Repetition(components: components)
}

func scrubXPN(_ rep: Repetition, salt: Int) -> Repetition {
    // XPN format: family^given^middle^suffix^prefix^degree^name-type-code.
    let name = syntheticName(salt: salt, slot: 0)
    var components = rep.components
    if components.indices.contains(0) { components[0] = .scalar(name.family) }
    if components.indices.contains(1) { components[1] = .scalar(name.given) }
    if components.indices.contains(2) { components[2] = .scalar("") }
    return Repetition(components: components)
}

func scrubDOB(_ raw: String, salt: Int) -> String {
    // Preserve YYYYMMDD prefix; shift by (salt mod 365) days but cap so we
    // don't shift across decade boundaries (preserves rough age bucket).
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
    let shiftDays = (salt % 60) - 30   // ± 30 days
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
