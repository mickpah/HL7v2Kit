// StructureVariant.swift
// S6-1 (ADR-019 amendment 2026-10-06): per-trigger prints of one structure ID. Where two
// normative prints of one ID differ by trigger, each governs the triggers it is printed for;
// the Validator selects the print for MSH-9.1^9.2 before matching. P12 S1-1 (ADR-019 amendment
// "P12 S1", owner ruling G-AU3): a profile structure's variant may instead be selected by the
// profile the message declares (the ADRM-2021 Appendix 8 simplified REF profile, MSH-12.3.1).

/// One print of a structure ID that governs some of the structure's
/// triggers with a syntax of its own (S6-1).
///
/// v2.6 prints ADT_A30 twice: CH03 3.3.30 (ADT^A30, also A35, A48 and A49,
/// p 3-30) has no ARV, 3.3.34 (ADT^A34, also A36, A46 and A47, p 3-33)
/// prints `[{ARV}]` after PD1. The structure's ``MessageStructure/elements``
/// are the 3.3.34 print; one variant carries the 3.3.30 print for A30, A35,
/// A48 and A49, so an ADT^A30 with ARV is reported and an ADT^A34 with ARV
/// is not.
///
/// A profile structure's variant may be selected by the profile the message
/// declares rather than by its trigger alone (P12 S1-1): the ADRM-2021
/// Appendix 8 simplified REF profile (A8.5, pp 484 to 485) replaces the AU
/// REF_I12 for a REF^I12 whose MSH-12.3.1 declares it (A8.3, p 483). Such a
/// variant lists the declarations in ``profileIdentifiers``.
public struct StructureVariant: Sendable, Equatable, Hashable {
    /// The triggers this print governs, each `"CODE^EVENT"` as printed
    /// (never `"CODE^*"`).
    public let triggers: [String]
    /// Where the print is, and the `overrides.json` variantPrints entry
    /// that makes it a variant.
    public let citation: String
    /// The ordered top-level elements of this print, starting with MSH.
    public let elements: [StructureElement]
    /// The profile identifiers that select this print, as the profile prints
    /// them for MSH-12.3.1 (the internal version ID's identifier), matched
    /// exactly (P12 S1-1). Empty for a print selected by its triggers alone,
    /// which is every variant of a base structure. A variant with identifiers
    /// governs its ``triggers`` only for a message that declares one of them.
    public let profileIdentifiers: [String]
    /// Whether this print fails the ADR-019 determinism lint (P8b-12), as
    /// for ``MessageStructure``; set by the codegen for each print.
    let requiresExactMatch: Bool

    // Internal, as MessageStructure's: the generated tables and the tests use it.
    init(triggers: [String], citation: String, profileIdentifiers: [String] = [], requiresExactMatch: Bool? = nil,
         elements: [StructureElement]) {
        self.triggers = triggers
        self.citation = citation
        self.profileIdentifiers = profileIdentifiers
        self.elements = elements
        self.requiresExactMatch = requiresExactMatch ?? !StructureMatcher.lint(elements).isDeterministic
    }
}

extension MessageStructure {
    /// The variant whose print governs `messageCode^triggerEvent`, or nil
    /// when ``elements`` (the default print) governs it. A variant is
    /// selected by an exact trigger; any other trigger the structure
    /// accepts, a `"CODE^*"` one included, takes the default print. A
    /// variant selected by a declared profile (``StructureVariant/profileIdentifiers``
    /// not empty) is never returned here: the trigger alone does not select it.
    public func variant(messageCode: String, triggerEvent: String) -> StructureVariant? {
        variantIndex(messageCode: messageCode, triggerEvent: triggerEvent).map { variants[$0] }
    }

    func variantIndex(messageCode: String, triggerEvent: String, declaredProfile: String? = nil) -> Int? {
        let trigger = "\(messageCode)^\(triggerEvent)"
        return variants.firstIndex { variant in
            guard variant.triggers.contains(trigger) else { return false }
            guard !variant.profileIdentifiers.isEmpty else { return true }
            return declaredProfile.map(variant.profileIdentifiers.contains) ?? false
        }
    }

    /// This structure with the elements of the print that governs
    /// `messageCode^triggerEvent`: itself when the default print governs,
    /// else a copy carrying the variant's elements and lint result, with
    /// no variants of its own and ``variantIndex`` set. `declaredProfile`, the
    /// message's MSH-12.3.1, also selects a variant that a declared profile
    /// governs (P12 S1-1).
    func selectingVariant(messageCode: String, triggerEvent: String, declaredProfile: String? = nil) -> MessageStructure {
        guard let index = variantIndex(messageCode: messageCode, triggerEvent: triggerEvent,
                                       declaredProfile: declaredProfile) else { return self }
        let chosen = variants[index]
        return MessageStructure(id: id, version: version, triggers: triggers, citation: chosen.citation,
                                profile: profile, baseVersion: baseVersion, rule: rule,
                                requiresExactMatch: chosen.requiresExactMatch, aliasOf: aliasOf,
                                keySelection: keySelection, errorResponse: errorResponse,
                                variants: [], variantIndex: index, elements: chosen.elements)
    }
}
