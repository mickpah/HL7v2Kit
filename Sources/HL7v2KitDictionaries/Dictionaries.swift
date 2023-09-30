// Dictionaries.swift
// Public accessor for the bundled v2 segment grammar JSON.
//
// v0.1.0: stub. Sprint 4 will replace this with real dictionary loading
// from JSON resources covering v2.3.1, v2.4, v2.5.1, v2.8.

import Foundation

/// Namespace for accessing bundled HL7 v2 grammar dictionaries.
public enum Dictionaries {
    /// Returns the URL to the dictionary resource for the given version,
    /// or nil if not yet bundled.
    public static func resourceURL(for version: String) -> URL? {
        Bundle.module.url(forResource: version, withExtension: "json")
    }

    /// Sentinel string for version readiness checks. Tests assert this exists.
    public static let scaffoldMarker = "HL7v2KitDictionaries scaffold v0.1.0"
}
