// FieldUsage.swift
// The usage a localisation gives a field, and the public read of it (ADR-007). Not a kernel
// file: the read in a message uses the Validator's condition evaluator.

/// The usage code a localisation prints for a field: the six codes of a conformance profile
/// (ADR-007) and `B`, which a localisation's attribute table may carry over from the base
/// standard. The raw value is the printed letter.
///
/// The AU ADRM 2021.1 defines all six profile codes (section 1) but prints its segment
/// attribute tables with the base standard's OPT column: its fields carry `R`, `O`, `C`, `B`
/// and `X`, and none carries `RE` or `CE`.
///
/// - Note: **Open** enum per ADR-014; switch with `@unknown default`.
public enum FieldUsage: String, Sendable, Equatable, Hashable, CaseIterable {
    /// R: required. A sender must value the field.
    case required = "R"
    /// RE: required, but may be empty when the sender does not hold the data.
    case requiredOrEmpty = "RE"
    /// O: optional.
    case optional = "O"
    /// C: conditional. The localisation states when the field is required.
    case conditional = "C"
    /// CE: conditional, but may be empty.
    case conditionalOrEmpty = "CE"
    /// X: not used in this localisation.
    case notUsed = "X"
    /// B: kept for backward compatibility with earlier versions of the base standard.
    case backwardCompatible = "B"
}

/// The usage a localisation gives a field, with where it is stated.
public struct LocaleFieldUsage: Sendable, Equatable, Hashable {
    /// Where a usage is stated.
    ///
    /// - Note: **Open** enum per ADR-014; switch with `@unknown default`.
    public enum Source: Sendable, Equatable, Hashable {
        /// The OPT cell of the localisation's own segment attribute table.
        case attributeTable
        /// A conformance statement of the localisation that applies to the message asked about.
        case conformanceStatement
    }

    /// The usage code.
    public let usage: FieldUsage
    /// Whether the attribute table or a conformance statement gives it.
    public let source: Source
    /// Where the localisation states it: the document, table and page, or the statement.
    public let citation: String
}

extension HL7Locale {
    /// The usage this localisation's own segment attribute table prints for `field` (1-based)
    /// of `segment`, whether or not it differs from the base standard's optionality
    /// (``FieldGrammar/optionality``).
    ///
    /// `nil` under ``international``, for a segment the localisation prints no attribute table
    /// for, for a field past its table, and where the table prints no code (in the ADRM, the
    /// reserved MSH-22 to MSH-26 and PV2-39). This is what the document prints, not what the
    /// ``Validator`` enforces: see the Australian localisation article for the cells it does
    /// not yet check. A conformance statement may give a field another usage in particular
    /// messages: ``fieldUsage(at:in:)`` applies those.
    public func fieldUsage(segment: String, field: Int) -> LocaleFieldUsage? {
        guard self == .auLocalisation,
              let row = AttributeUsageTable.row(segment: segment, field: field, in: AttributeUsageTable.au_adrm_2021),
              let usage = FieldUsage(rawValue: row.code) else { return nil }
        return LocaleFieldUsage(usage: usage, source: .attributeTable,
                                citation: "HL7AUSD-STD-OO-ADRM-2021.1, \(segment) attribute table, p \(row.page)")
    }

    /// The usage of the field `path` names in `message`: the usage a conformance statement of
    /// this localisation gives it when the statement applies to this message and segment, and
    /// otherwise the attribute table's (``fieldUsage(segment:field:)``).
    ///
    /// The statements are the ones the ``Validator`` enforces under this locale, read with
    /// its own condition evaluator, so a field it reports as profile-required reads as
    /// ``FieldUsage/required`` here with ``LocaleFieldUsage/Source/conformanceStatement``. In
    /// the ADRM, MSH-6 is `O` in the attribute table and required in an ORM. `nil` when the
    /// path names no field or a segment the message does not hold, and where the table read
    /// gives `nil` and no statement applies.
    public func fieldUsage(at path: Path, in message: Message) -> LocaleFieldUsage? {
        guard !path.isSegmentOnly, let index = message.indexOfSegment(at: path) else { return nil }
        let segment = message.segments[index]
        // The Validator reads the first override of a field, so this does too.
        if let profile = Profile.load(for: self),
           let override = profile.fieldOverrides.first(where: { $0.segmentID == path.segmentID && $0.fieldIndex == path.field }),
           let usage = override.profileUsage {
            let gate = override.condition ?? ""
            let applies = gate.isEmpty || Validator(locale: self).conditionTriggers(
                gate, in: segment, segmentIndex: index, message: message, currentSegmentID: path.segmentID)
            if applies {
                return LocaleFieldUsage(usage: usage, source: .conformanceStatement,
                                        citation: override.specCitation ?? "\(rawValue):\(path.segmentID)-\(path.field)")
            }
        }
        return fieldUsage(segment: path.segmentID, field: path.field)
    }
}
