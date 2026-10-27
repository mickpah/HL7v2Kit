// Anonymiser.swift
// De-identifies a parsed message (spec section 10): the identifying fields of the patient,
// next of kin, insured and providers become synthetic values. The HL7v2KitAnonymise tool
// calls it with its per-file salt.

import Foundation

/// Replaces the identifying fields of a message with synthetic values chosen from a key.
///
/// Under one key, the same original value gives the same synthetic value in every message,
/// whatever its MSH-10, so linkage across messages survives: two messages about one patient
/// are still about one synthetic patient. A different key gives different values, and the
/// same key gives the same output on every run and platform.
///
/// The output keeps the input's shape. An identifying component is replaced in place; the
/// other components (type codes, assigning authorities, use codes) are kept; an empty or
/// absent field or component stays empty or absent. So the output validates as the input did.
///
/// ```swift
/// let anonymiser = Anonymiser(key: sessionKey)
/// let safe = anonymiser.anonymise(try Parser().parse(bytes)).serialize()
/// ```
///
/// Covered: MSH-3 to MSH-6; the identifiers, names, dates of birth and death, addresses, phone
/// numbers and birth places in PID, NK1, IN1 and GT1 (the guarantor), and PD1-10; the providers
/// in PD1, PV1, ORC, OBR and OBX; free-text OBX-5 and NTE-3. Every repetition of a covered field is replaced. Any other segment or field,
/// Z-segments included, is kept as it is.
public struct Anonymiser: Sendable {
    /// What a caller-supplied replacement sees for one identifier: a CX, or an identifier
    /// held as text (PID-19).
    public struct Identifier: Sendable, Equatable {
        /// The identifier being replaced: CX-1.
        public let value: String
        /// CX-5, the identifier type code (`NI` for an IHI), or `nil` when empty or absent.
        public let typeCode: String?
        /// CX-4.1, the assigning authority's namespace ID (`AUSHIC`), or `nil` when empty or absent.
        public let assigningAuthority: String?
        /// This value's seed under the anonymiser's key: the same for the same value and key
        /// on every call, run and platform. Generate a valid synthetic identifier from it.
        public let seed: UInt64
    }

    let source: SyntheticSource
    let replacingIdentifier: (@Sendable (Identifier) -> String)?

    /// An anonymiser whose synthetic values are chosen from `key`.
    ///
    /// - Parameters:
    ///   - key: The caller's key. Use one key for the messages whose linkage should survive.
    ///   - replacingIdentifier: Returns the replacement for one identifier. Without it, an
    ///     identifier is replaced by one of the same form: digits by as many digits, anything
    ///     else by `SYN-` and four digits. Supply it when identifiers must pass a check that
    ///     form cannot, such as an IHI's check digit.
    public init(key: UInt64, replacingIdentifier: (@Sendable (Identifier) -> String)? = nil) {
        source = .keyed(key)
        self.replacingIdentifier = replacingIdentifier
    }

    /// The command-line tool's rule: every value chosen from one salt per file.
    package init(legacySalt: Int) {
        source = .legacy(salt: legacySalt)
        replacingIdentifier = nil
    }

    /// `message` with its covered fields replaced; see the type's discussion.
    public func anonymise(_ message: Message) -> Message {
        let segments = message.segments.map { segment -> Segment in
            let id = segment.segmentID
            guard id == "MSH" || id == "NTE" || Self.coverage[id] != nil else { return segment }
            var fields = segment.fields
            switch id {
            case "MSH": replaceFacilities(&fields)
            case "NTE": redactComment(&fields)
            case "OBX": redactObservationValue(&fields, valueType: segment.field(2)?.stringValue)
            default: break
            }
            for (index, rule) in Self.coverage[id] ?? [] { apply(rule, to: &fields, at: index) }
            return .unknown(UnknownSegment(segmentID: id, fields: fields))
        }
        return Message(version: message.version, encodingCharacters: message.encodingCharacters,
                       segments: segments, characterEncoding: message.characterEncoding,
                       locale: message.locale)
    }
}
