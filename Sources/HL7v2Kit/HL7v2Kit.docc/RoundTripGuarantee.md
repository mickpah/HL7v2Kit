# Round-Trip Guarantee

What "byte equality after parse and serialise" means, what's covered, and what isn't.

## Overview

HL7v2Kit's primary correctness invariant is: for any input the parser accepts, serialising the result yields **exactly** the input bytes back.

```swift
let message = try Parser().parse(originalBytes)
let rebuilt = message.serialize()
assert(rebuilt == originalBytes)                          // always true
```

This is non-negotiable. Failed round-trip is treated as a bug in HL7v2Kit, not in the test. The property has its own test suite (`Tests/HL7v2KitTests/RoundTripTests.swift`) and forms the acceptance criterion for any future Rust/Go port of the parser kernel (see `ADR-006`).

## What round-trip covers

The library guarantees byte equality across:

- **Segment terminators.** `\r` is preserved exactly, including its absence after the last segment (``Message/trailingSegmentTerminator``). Under `LineTerminatorPolicy.strict` only `\r` ends a segment: an `\n` is data and stays in the value it falls in.
- **Empty trailing fields.** `PID|1|||\r` retains its trailing pipes after a round trip — the parser does not omit empty subsequences.
- **Repetitions, components, and subcomponents.** Every layer of nesting that exists on the wire is preserved as a distinct AST node. See ``Field``, ``Repetition``, ``Component``, ``Subcomponent``.
- **Escape sequences.** `\F\`, `\S\`, `\T\`, `\R\`, `\E\`, and `\X..\` round-trip exactly. Hex escapes are coalesced canonically (`\X0D0A\`, not `\X0D\\X0A\`). `\Z..\` and unknown escape bodies pass through verbatim. See <doc:EscapeSequences>.
- **Character set.** MSH-18 is detected on parse; the same charset is used on serialise. UTF-8, ASCII, and ISO-8859-1 are supported. See <doc:CharacterEncodingGuide>.
- **MSH-2 encoding characters.** Custom delimiter characters (non-default field separator, component separator, etc.) round-trip exactly via ``EncodingCharacters``. A fifth MSH-2 character (the v2.7+ truncation character) is kept in MSH-2's literal value and written back unchanged; the validator reports it, as a field length, on versions that print MSH-2 as four characters.

## What round-trip does not promise

- **Inputs the parser rejected.** A malformed message that fails ``Parser/parse(_:)-(Data)`` is not in the round-trip set. The serialiser is only run on successful parses. Two byte-level rejections worth knowing about (both added post-v0.1.0 — see <doc:Migration>):
  - **Embedded NUL bytes** (`0x00`) are rejected with ``ParseError/truncatedMessage(atByte:)``. Real v2 wire never carries NUL; an embedded one is almost always transport truncation. This rejection makes the invariant honest without a NUL carve-out — every *accepted* message is NUL-free, so the serialiser never has to worry about preserving a control byte the wire shouldn't carry.
  - **Leading UTF-8 BOM** (`EF BB BF`) is silently stripped on the byte-input path. A BOM-prefixed input parses successfully but the serialised output is BOM-free — the serialiser never re-emits a BOM. So a BOM round trip is `BOM + body in → body only out` (canonicalisation, not byte-equality). The String-input path is unaffected.
- **Bytes synthesised by ``MessageBuilder``.** Builder-produced messages round-trip if you parse-then-serialise them, but the builder API does not enforce that *every* combination of typed accessor writes produces a byte-equal stream of the user's original bytes (because there were no original bytes to compare to).
- **Non-canonical escape forms.** A sender that writes `\X0D\\X0A\` (two separate hex-byte escapes for CR LF) round-trips as the canonical coalesced form `\X0D0A\`. The decoded content is identical; the wire bytes are not. Two property tests cover this: `decode(encode(x)) == x` for decoded inputs (canonical round trip), and `encode(decode(y)) == y` for canonical wire inputs (canonical wire stays canonical).
- **Character-set conversion loss.** If a sender declares MSH-18 = `ASCII` but populates a body byte outside ASCII range, `Parser.parse(_ data:)` throws ``ParseError/unsupportedCharacterEncoding(declared:)`` — there is no "best-effort" lossy decode.
- **Line endings under `.lenient`.** `LineTerminatorPolicy.lenient` (the parser's default) reads `\r\n` and `\n` as segment terminators and serialises `\r`. Use `.strict` when the bytes must come back unchanged.
- **Blank lines.** An empty line between segments (`\r\r`) is skipped on parse and not re-emitted.
- **Raw control characters.** A control character inside a value, such as an `\n` read under `.strict`, is written back as a hex escape (`\X0A\`); a raw one cannot stand inside a field on the wire. The decoded value is unchanged.

## How to debug a failed round trip

If you find a real-world fixture where `parse(bytes).serialize() != bytes`:

1. Diff `bytes` against the rebuilt output. Most often the discrepancy is in MSH (the field-separator / encoding-character handling is the fiddliest path).
2. Confirm the parser accepted the message at all (vs. silently failing — it should always throw on rejection).
3. File an issue with the fixture (PHI-scrubbed). The library should accept any v2-conformant byte stream byte-for-byte.

## See Also

- <doc:EscapeSequences>
- <doc:CharacterEncodingGuide>
- ``Parser``
- ``Message``
