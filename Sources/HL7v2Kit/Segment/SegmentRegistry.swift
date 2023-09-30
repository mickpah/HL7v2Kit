// SegmentRegistry.swift
// Entry point for typed-segment hydration. The actual switch over registered
// IDs lives in `Generated/SegmentRegistry+Generated.swift`, emitted by
// `HL7v2KitCodegen`. To register a new segment, add its JSON schema under
// `Resources/schemas/` and run `bash scripts/regenerate-typed-segments.sh`.

import Foundation

enum SegmentRegistry {
    static func hydrate(_ unknown: UnknownSegment) -> Segment {
        hydrateGenerated(unknown) ?? .unknown(unknown)
    }
}
