// StructureRegistration.swift
// The public view of the not-modelled register (permanent-limitations
// register section E): owner decision 8, ADR-019 amendment 2026-10-06.

/// A message structure that a version prints (or its Table 0354 lists) and
/// that is registered as not modelled, with the reason (ADR-019,
/// permanent-limitations register section E).
///
/// A registration is not a ``MessageStructure``: there is no grammar to
/// match against. The ``Validator`` reports a message naming it as
/// ``IssueCode/messageStructureNotModelled(structure:)`` with this reason,
/// never as a mismatch. Read one through
/// ``MessageStructureTable/registration(_:version:)``.
public struct StructureRegistration: Sendable, Equatable {
    /// The structure ID, as MSH-9.3 or Table 0354 names it (for example
    /// `UDM_Q05`).
    public let id: String
    /// The grammar version whose register holds the entry
    /// (``Version/grammarVersion`` of the version asked for, so
    /// ``Version/v2_8`` reports ``Version/v2_8_2``).
    public let version: Version
    /// The `messageCode^triggerEvent` pairs the print's captions (or Table
    /// 0354) give the structure; `CODE^*` accepts every trigger of the code.
    /// Empty when the source lists no event.
    public let triggers: [String]
    /// Why the structure is not modelled, cited to the print.
    public let reason: String
}

extension MessageStructureTable {
    /// The registration of `id` on `version`'s grammar version, or nil when
    /// `id` is not registered as not modelled.
    ///
    /// Together with ``structure(_:version:)`` this tells the three cases
    /// apart: a modelled structure (``structure(_:version:)`` returns it and
    /// this returns nil), a structure the version prints but does not model
    /// (this returns its triggers and reason), and an ID the version does not
    /// print at all (both return nil). No supported version registers an ID
    /// it also models.
    ///
    /// A (trigger, structure) pair the print gives to a modelled structure
    /// but whose grammar is not modelled for that trigger (a query profile's
    /// response row) is not a structure registration, since the structure is
    /// modelled; the ``Validator`` reports such a message as
    /// ``IssueCode/messageStructureNotModelled(structure:)`` with the pair's
    /// reason.
    public static func registration(_ id: String, version: Version) -> StructureRegistration? {
        let grammar = version.grammarVersion
        guard let entry = notModelled(for: grammar)[id] else { return nil }
        return StructureRegistration(id: id, version: grammar, triggers: entry.triggers, reason: entry.reason)
    }

    /// Every structure registered as not modelled on `version`'s grammar
    /// version, sorted by ID. Empty for a version with no register.
    public static func registrations(for version: Version) -> [StructureRegistration] {
        let grammar = version.grammarVersion
        return notModelled(for: grammar)
            .map { StructureRegistration(id: $0.key, version: grammar, triggers: $0.value.triggers, reason: $0.value.reason) }
            .sorted { $0.id < $1.id }
    }
}
