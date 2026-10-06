// StructureVariant.swift
// S6-1 (ADR-019 amendment 2026-10-06): per-trigger prints of one structure ID. Where two
// normative prints of one ID differ by trigger, each governs the triggers it is printed for;
// the Validator selects the print for MSH-9.1^9.2 before matching.

/// One print of a structure ID that governs some of the structure's
/// triggers with a syntax of its own (S6-1).
///
/// v2.6 prints ADT_A30 twice: CH03 3.3.30 (ADT^A30, also A35, A48 and A49,
/// p 3-30) has no ARV, 3.3.34 (ADT^A34, also A36, A46 and A47, p 3-33)
/// prints `[{ARV}]` after PD1. The structure's ``MessageStructure/elements``
/// are the 3.3.34 print; one variant carries the 3.3.30 print for A30, A35,
/// A48 and A49, so an ADT^A30 with ARV is reported and an ADT^A34 with ARV
/// is not.
public struct StructureVariant: Sendable, Equatable, Hashable {
    /// The triggers this print governs, each `"CODE^EVENT"` as printed
    /// (never `"CODE^*"`).
    public let triggers: [String]
    /// Where the print is, and the `overrides.json` variantPrints entry
    /// that makes it a variant.
    public let citation: String
    /// The ordered top-level elements of this print, starting with MSH.
    public let elements: [StructureElement]
    /// Whether this print fails the ADR-019 determinism lint (P8b-12), as
    /// for ``MessageStructure``; set by the codegen for each print.
    let requiresExactMatch: Bool

    // Internal, as MessageStructure's: the generated tables and the tests use it.
    init(triggers: [String], citation: String, requiresExactMatch: Bool? = nil, elements: [StructureElement]) {
        self.triggers = triggers
        self.citation = citation
        self.elements = elements
        self.requiresExactMatch = requiresExactMatch ?? !StructureMatcher.lint(elements).isDeterministic
    }
}

extension MessageStructure {
    /// The variant whose print governs `messageCode^triggerEvent`, or nil
    /// when ``elements`` (the default print) governs it. A variant is
    /// selected by an exact trigger; any other trigger the structure
    /// accepts, a `"CODE^*"` one included, takes the default print.
    public func variant(messageCode: String, triggerEvent: String) -> StructureVariant? {
        variantIndex(messageCode: messageCode, triggerEvent: triggerEvent).map { variants[$0] }
    }

    func variantIndex(messageCode: String, triggerEvent: String) -> Int? {
        let trigger = "\(messageCode)^\(triggerEvent)"
        return variants.firstIndex { $0.triggers.contains(trigger) }
    }

    /// This structure with the elements of the print that governs
    /// `messageCode^triggerEvent`: itself when the default print governs,
    /// else a copy carrying the variant's elements and lint result, with
    /// no variants of its own and ``variantIndex`` set.
    func selectingVariant(messageCode: String, triggerEvent: String) -> MessageStructure {
        guard let index = variantIndex(messageCode: messageCode, triggerEvent: triggerEvent) else { return self }
        let chosen = variants[index]
        return MessageStructure(id: id, version: version, triggers: triggers, citation: chosen.citation,
                                profile: profile, baseVersion: baseVersion, rule: rule,
                                requiresExactMatch: chosen.requiresExactMatch, aliasOf: aliasOf,
                                keySelection: keySelection, errorResponse: errorResponse,
                                variants: [], variantIndex: index, elements: chosen.elements)
    }
}
