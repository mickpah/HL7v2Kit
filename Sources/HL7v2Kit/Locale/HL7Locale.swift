// PORTABLE KERNEL — keep this file Foundation-free and byte/character-level.
// A future Rust/Go port translates this file directly. No NSRegularExpression,
// NSString, DateFormatter, CharacterSet, locale-aware ops, protocols, or
// generics in the parse path. `Data` only at the edges (to/from [UInt8]).
// See docs/design/ADR-006-portable-core-boundary.md

// HL7Locale.swift
// The locale of a parsed message or a running validator. Locale is a
// first-class API mode that selects which (if any) localisation profile
// layers on top of the base HL7 v2 spec. See ADR-007.
//
// Default is `.international` (base spec only). Consumers opt in to a
// localisation by constructing a Parser / Validator with the
// corresponding locale value. Locale propagates onto Message.locale and
// ValidationReport.locale so downstream consumers (e.g. a FHIR mapping
// layer) can read it without re-parsing.

/// Selects the localisation profile applied on top of the base HL7 v2 spec.
///
/// Locale is the public API surface for HL7v2Kit's localisation work.
/// The internal `Profile` overlay mechanism (under `Sources/HL7v2Kit/Locale/`)
/// is the implementation detail.
///
/// - `.international`: base HL7 v2 spec only. No localisation profile loaded.
///   This is the default everywhere and preserves the v0.3.x behaviour.
/// - `.auLocalisation`: HL7 Australia's *Australian Diagnostics and Referral
///   Messaging — Localisation of HL7 Version 2.4* (`HL7AUSD-STD-OO-ADRM-2021.1`)
///   layered over the base v2.4 spec. v0.4-S5-A ships the API surface; the
///   AU constraints themselves land in subsequent stages.
public enum HL7Locale: String, Sendable, CaseIterable, Equatable, Hashable {
    /// Base HL7 v2 spec. No localisation profile loaded. Default.
    case international = "international"

    /// HL7 Australia ADRM-2021 profile, layered over base HL7 v2.4. See ADR-007.
    case auLocalisation = "au-adrm-2021"
}
