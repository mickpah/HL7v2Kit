// StructBase.swift
// P10-3 (ADR-020 amendment, ruling D2): the union base of a segment struct.
// A struct released with a base keeps that base for ever, so its accessor
// names and types cannot move when an earlier version that defines the
// segment is added. The pinned bases are data (Resources/struct-bases.json),
// not a comparison of version strings; StructBasePinTests guards the list and
// scripts/check-struct-base-pin.py proves the pin against an earlier definer.

import Foundation

/// The `bases` map of Resources/struct-bases.json: segment ID to base version.
struct StructBasePins: Decodable {
    let bases: [String: String]

    static func load(_ url: URL) throws -> [String: String] {
        try JSONDecoder().decode(StructBasePins.self, from: Data(contentsOf: url)).bases
    }
}

/// The base schema of `segmentID` among `schemas` (in `versionLess` order): the
/// pinned version where `pins` lists the segment, else the canonical v2.5.1,
/// else the earliest definer. A pin to a version that does not define the
/// segment fails the run rather than silently moving a released base.
func structBase(segmentID: String, schemas: [SegmentSchema], pins: [String: String]) throws -> SegmentSchema {
    if let pinned = pins[segmentID] {
        guard let base = schemas.first(where: { $0.version == pinned }) else {
            FileHandle.standardError.write(Data(
                "HL7v2KitCodegen: \(segmentID) is pinned to v\(pinned) in struct-bases.json but no v\(pinned) schema defines it\n".utf8))
            throw ExitCode.failure
        }
        return base
    }
    return schemas.first { $0.version == canonicalVersion } ?? schemas[0]
}
