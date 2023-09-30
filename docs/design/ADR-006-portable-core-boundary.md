# ADR-006: Portable kernel boundary

| | |
|---|---|
| Status | Accepted |
| Date | 2026-05-27 |
| Supersedes | -- |
| Superseded by | -- |
| Related | ADR-001 (AST model), ADR-002 (error strategy) |

## Context

HL7v2Kit is written in Swift and is the foundational parsing layer for AU Core Workbench (a macOS application). Swift is the correct choice for a library consumed by a SwiftUI app: zero binding friction, native types, best App Store outcomes.

However, the parent project's roadmap names several consumers that are not macOS apps:

- a hosted FHIR validator service (a separate process; portability and single-binary deployment matter there);
- CLI tools for CI integration (cross-platform single binaries wanted);
- a possible Windows port of the workbench (SwiftUI does not port; a shared core could);
- a possible open-source community library (reach beyond Apple developers).

None of these is certain. Building the core in a maximally portable language now (Rust, Go) would pay a real upfront cost -- learning curve, a Swift-to-core FFI seam, more build complexity -- to buy optionality that may never be exercised. For a solo, part-time founder shipping a Mac MVP, that trade is not currently worth it.

But the *shape* of the Swift code determines how expensive a future port would be. A port is cheap when the parsing logic is pure, mechanical, and dependency-free -- close to a line-by-line translation. A port is expensive when platform conveniences (Foundation APIs, Swift-only language features) are woven through the parse path, because each one is a decision the next language must re-litigate.

## Decision

We keep HL7v2Kit in Swift and ship the Mac MVP. We do **not** adopt Rust or Go now.

We **do** structure the code as two explicit strata, and we hold the boundary as an architecture invariant:

### Stratum 1 -- the portable kernel

Pure parsing/serialisation logic. This is the code that a future Rust or Go port would translate. It must obey these rules:

1. **No Foundation-specific APIs.** No 'NSRegularExpression', 'NSString', 'DateFormatter', 'Scanner' (Foundation's), 'CharacterSet', 'NumberFormatter', locale-aware operations, or NS-bridged behaviour. 'Data' is permitted **only** at the very edges, for converting to and from '[UInt8]'. Everything internal works on '[UInt8]', '[Character]', 'String' (used as a plain value type), and the standard numeric and collection types.

2. **Byte-level or character-level, explicit.** Parsing operates on explicit indices into '[Character]' or '[UInt8]', or on simple delimiter splits whose semantics are identical across languages. Avoid Swift-only 'String' cleverness (grapheme-cluster-dependent behaviour, 'Substring' slicing tricks) where a manual scan would translate more directly.

3. **No protocols, generics, or property wrappers in the parse path.** Plain structs and enums only. Protocol-based polymorphism and type erasure belong in Stratum 2.

4. **Errors are plain enums with associated values.** They port directly to Rust enums and with modest work to Go error types. (Already mandated by ADR-002.)

5. **No concurrency annotations as logic.** 'Sendable' and friends are harmless Swift-build metadata; a porter ignores them. They must never carry semantic weight in the kernel.

The kernel currently comprises:

- 'Sources/HL7v2Kit/Parser/Parser.swift'
- 'Sources/HL7v2Kit/Parser/ParseError.swift'
- 'Sources/HL7v2Kit/Builder/Serializer.swift'
- 'Sources/HL7v2Kit/Segment/Field.swift' (the 'Field'/'Repetition'/'Component'/'Subcomponent' AST nodes)
- 'Sources/HL7v2Kit/Path/Path.swift'
- 'Sources/HL7v2Kit/Encoding/EncodingCharacters.swift'
- 'Sources/HL7v2Kit/Version.swift'
- the forthcoming escape-sequence codec ('Sources/HL7v2Kit/Encoding/EscapeSequences.swift')

Each kernel file carries a header comment naming it as kernel and pointing here.

### Stratum 2 -- the Swift-idiomatic skin

Everything that makes the library pleasant to use *from Swift specifically*, and which a port would deliberately rewrite in its own idiom rather than translate:

- 'Sources/HL7v2Kit/Segment/Segment.swift' -- the 'TypedSegment' protocol and 'AnyTypedSegment' type erasure.
- 'Sources/HL7v2Kit/Message.swift' -- the typed-segment accessors and ergonomic subscripts (the underlying resolution logic is kernel-ish, but the Swift-facing surface is skin).
- The code-generated typed segment structs ('Sources/HL7v2Kit/Segment/Generated/').
- Any future 'Codable', 'CustomStringConvertible', or SwiftUI-friendly conformances.

Stratum 2 may use the full expressive range of Swift. It is explicitly **not** required to be portable. Its only obligation is to not contaminate Stratum 1 -- i.e. kernel files must not import or depend on skin types.

## Consequences

**Positive**

- The Mac MVP ships at full Swift velocity now.
- If a second consumer becomes real, the port is "translate the kernel (~1,500-2,500 lines of mechanical code) and write a thin per-language skin," not "rewrite the library." Estimated kernel port to Rust: on the order of a week, not a quarter.
- The boundary doubles as a clarity aid: the kernel is the part with the interesting correctness properties (round-trip, escape handling), so isolating it makes it easier to test and reason about regardless of portability.

**Negative**

- A small ongoing tax: occasionally we write a few lines of manual code where a Foundation one-liner existed. Accept it in the kernel; ignore the rule in the skin.
- The boundary must be actively maintained. Foundation creep into kernel files is the failure mode. Mitigated by the per-file header comments and by reviewing kernel diffs for new 'import Foundation'-specific usage.

**Explicitly not promised**

- This ADR does **not** commit to ever porting. It keeps the door unlocked; it does not build the hallway. The trigger for an actual port is "a second consumer is real," not "a second consumer is imaginable."

## Notes for a future porter

If you are reading this because you are porting the kernel to Rust or Go:

- Start with 'Field.swift' and 'Path.swift' -- they are the most mechanical and have the cleanest semantics.
- 'Parser.swift' uses 'String.split(separator:)' in a few places. Every target language has an equivalent; check empty-subsequence behaviour matches (we rely on *not* omitting empty subsequences, to preserve empty fields for round-trip).
- The round-trip invariant (ADR-001, spec ?5) is the acceptance test for your port: 'parse(bytes).serialize() == bytes' for every fixture the Swift kernel accepts.
- Do not port Stratum 2. Design an idiomatic skin for your target language instead.
