// Anonymiser.swift
// De-identifies a parsed message (spec section 10): the identifying fields of the patient,
// next of kin, insured, guarantor and providers, their gender and sex segments, the visit,
// order and specimen numbers, and the participations, roles and devices of an order or result,
// become synthetic values. The HL7v2KitAnonymise tool calls it with its per-file salt.

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
/// Covered, each field by the rule its type takes:
///
/// - MSH-3 to MSH-6, and the network addresses MSH-24 and MSH-25, as facilities.
/// - The patient, next of kin, insured and guarantor (PID, PD1, NK1, IN1, IN2, GT1) and a merge's
///   prior patient (MRG): their identifiers, held as CX or as text (a social security, Medicare,
///   Medicaid or military number), names, dates of birth and death, addresses, phone numbers,
///   birth places and employers, and PID's last update facility. The patient's county and place of
///   worship, an employer that is an organisation (XON), a military unit and station, and IN1's
///   pre-admission certification become `[REDACTED]` whole. Under a key the same value maps alike
///   in every field that holds it, so MRG-1 still matches PID-3; under the tool's rule, only at the
///   same repetition.
/// - The visit's pre-admit, visit, alternate visit and service episode numbers (PV1), and the
///   insurer's ID, address, contact and phone and the authorisation number (IN1).
/// - The order numbers and order group numbers (ORC, OBR, and TXA-14 and TXA-15, which hold ORC-2
///   and ORC-3), their parents (ORC-8, OBR-29, OBR-54), the observation group and instance
///   identifiers (OBR, OBX), the equipment (OBX-18), the specimen identifiers (OBX-33, SPM), and
///   the call-back, ordering and performing phones and addresses (ORC-14, ORC-22 to ORC-24,
///   OBR-17, OBX-24). A parent or specimen reference names what the same number becomes elsewhere,
///   at every repetition and under both rules, so OBR-29 still matches its parent's OBR-2, and each
///   repetition of OBX-33 the SPM-2 it names.
/// - The providers and other staff in PD1, PV1, PV2, IN1, ORC, OBR, OBX, NTE, EVN, DG1, PR1, TXA
///   and RF1; RF1's source name and phone; and PRD's provider, with its addresses, phones and
///   identifiers.
/// - Free-text OBX-5 and NTE-3.
/// - Every field of GSP, GSR and GSC (gender and sex) but the set ID, the action code, GSR-8 (the
///   acquisition date) and GSC's context and evidence, which point into the message; a coded value
///   there becomes `[REDACTED]` whole, its coding system included.
///
/// PRT, ROL and DEV, the participations, roles and devices (on v2.9 and v2.9.1, where ORC-12 and
/// OBR-16 are withdrawn, the ordering provider travels only in PRT), have every field replaced but
/// the action code, the coded fields and the dates: the person as a provider, the address and
/// phone as elsewhere, and the instance, device, donation and contact identifiers as an EI's
/// identifier, its other components kept, so DEV-2 still matches PRT-10. Their organisation and
/// location, and a device's lot and serial number, brand, model, catalogue and software version,
/// become `[REDACTED]` whole. Every repetition of a covered field is replaced.
///
/// Passed through unchanged:
///
/// - Every other segment, Z-segments included. Some carry identifiers, among them ACC, CTD, FT1,
///   IN3, RXA, RXO, SCH and STF.
/// - Every field of EVN, DG1, PR1, PV2, TXA, RF1 and PRD but those above. Among them are the
///   facilities EVN-7 and TXA-27; identifiers no covered field holds: the diagnosis, procedure,
///   document and referral identifiers and their parents (DG1-20, DG1-22, PR1-19, PR1-25, TXA-12,
///   TXA-13, TXA-31, RF1-6, RF1-11) and the document's file name (TXA-16); and RF1-24, a comment.
/// - Every other field of a covered segment. Among them are the event dates (MSH-7, EVN-2, ORC-9,
///   OBR-7, OBX-14, SPM-17, GSR-8, PRT-11, PRT-12, ROL-5 and ROL-6, and the device dates PRT-17,
///   PRT-18, DEV-12 and DEV-13): the tool moves every date of a file by one shift, so a moved
///   event date beside the same instant in clear would give that shift away, and with it every
///   date of birth. Others are MSH-21, the message profile; OBR-18 to OBR-21, which the placer and
///   filler define; and a device type (PRT-22, DEV-3), whose UDI can hold a lot number.
/// - Organisations and locations outside PRT, ROL and DEV, but for the employers and place of
///   worship above: XON in MSH-22, PD1-3, IN1-4, IN1-9, GT1-21, IN2-69, ORC-21 and OBX-23, for
///   example, and PL in PV1-3, PV1-6, PV1-11, PV1-42, PV1-43 and ORC-13, its facility (PL-4)
///   included.
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
    ///     form cannot, such as an IHI's check digit. It is asked for each CX and each identifier
    ///     held as text (PID-19, IN2-2). An EI, such as an order number or GSP-3, an EIP, a PLN
    ///     and an AUI are replaced without asking it, as providers are.
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
                let type = grammar[id]?.field(index)?.dataType
                // A field the version types EIP (ORC-4 on v2.8.2) holds two EIs.
                apply(rule == .entityIdentifier && type == "EIP" ? .entityIdentifierPair : rule,
                      to: &fields, at: index, ts: type == "TS")
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
