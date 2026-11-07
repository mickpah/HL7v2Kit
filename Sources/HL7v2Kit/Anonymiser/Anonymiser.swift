// Anonymiser.swift
// De-identifies a parsed message (spec section 10): the identifying fields of the patient,
// next of kin, insured and providers, their gender and sex segments, and the participations,
// roles and devices of an order or result, become synthetic values. The HL7v2KitAnonymise tool
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
/// in PD1, PV1, ORC, OBR and OBX; free-text OBX-5 and NTE-3; and every field of GSP, GSR and GSC
/// (gender and sex) but the set ID, the action code, GSR-8 (the acquisition date) and GSC's
/// context and evidence, which point into the message; a coded value there becomes `[REDACTED]`
/// whole, its coding system included.
///
/// PRT, ROL and DEV, the participations, roles and devices (on v2.9 and v2.9.1, where ORC-12 and
/// OBR-16 are withdrawn, the ordering provider travels only in PRT), have every field replaced but
/// the action code, the coded fields and the dates: the person as a provider, the address and
/// phone as elsewhere, and the instance, device, donation and contact identifiers as an EI's
/// identifier, its other components kept, so DEV-2 still matches PRT-10. Their organisation and
/// location, and a device's lot and serial number, brand, model, catalogue and software version,
/// become `[REDACTED]` whole. Every repetition of a covered field is replaced.
///
/// Passed through unchanged: every other segment, Z-segments included, and every other field of
/// a covered segment. Among them are the event dates (MSH-7, EVN-2, ORC-9, OBR-7, OBX-14, GSR-8,
/// PRT-11, PRT-12, ROL-5 and ROL-6, and the device dates PRT-17, PRT-18, DEV-12 and DEV-13): the
/// tool moves every date of a file by one shift, so a moved event date beside the same instant in
/// clear would give that shift away, and with it every date of birth. Organisations and locations
/// outside PRT, ROL and DEV pass through too (XON in PD1-3, NK1-13, IN1-4, GT1-51 and OBX-23, for
/// example; PL in PV1-3, PV1-6, PV1-11, PV1-42 and PV1-43), and so does a device type (PRT-22,
/// DEV-3), whose UDI can hold a lot number.
///
/// A covered date, of birth or death, moves by one to four whole weeks, or as many whole months
/// when given only to the month; one given only to the year is kept, and so is the HL7 null `""`.
/// A date moves only in the shape its type defines: its first component a date and, where the
/// version types the field TS (v2.3 to v2.5.1), a degree of precision that is empty or one of its
/// codes, which is kept.
/// Any other repetition becomes `[REDACTED]` whole: a value of any length that is not a date, and
/// one with a subcomponent or a further component. A range moves both ends at its coarser end's
/// precision, so it keeps its order: beside a year, the finer end is cut to its year. A range
/// with an end that is not a date, or more than its two components, becomes `[REDACTED]` whole.
/// Under a key, a range's end moves by its start's shift, so it may not map as the same date
/// elsewhere does.
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
    ///     form cannot, such as an IHI's check digit. GSP-3, GSR-3 and GSC-3, which are EI, are
    ///     replaced without asking it, as providers are, and so are the identifiers of PRT, ROL
    ///     and DEV.
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
        let grammar = Validator.grammarTable(for: message.version)
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
            for (index, rule) in Self.coverage[id] ?? [] {
                apply(rule, to: &fields, at: index, ts: grammar[id]?.field(index)?.dataType == "TS")
            }
            // Re-hydrated as the path editor does, so a typed segment stays typed (#12).
            return SegmentRegistry.hydrate(UnknownSegment(segmentID: id, fields: fields))
        }
        var result = Message(version: message.version, encodingCharacters: message.encodingCharacters,
                             segments: segments, characterEncoding: message.characterEncoding,
                             locale: message.locale)
        result.trailingSegmentTerminator = message.trailingSegmentTerminator
        return result
    }
}
