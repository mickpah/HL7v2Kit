# Escape Sequences

How HL7v2Kit handles `\F\`, `\S\`, `\T\`, `\R\`, `\E\`, `\X..\` and `\Z..\` — the v2 escape grammar.

## Overview

HL7 v2 uses backslash-delimited escape sequences to embed delimiter characters inside scalar field values. A patient name containing a literal `^` is encoded `\S\` (because `^` is the component separator); a CR byte inside an observation value is encoded `\X0D\`.

HL7v2Kit decodes these on parse and re-encodes them on serialise. ``Subcomponent/value`` stores the **decoded** text — callers never see `\F\` in a typed accessor result. The serialiser canonicalises the re-emission, so round-trip yields the canonical wire form (not necessarily byte-for-byte the input form for non-canonical encodings — see <doc:RoundTripGuarantee>).

## The escape grammar

HL7v2Kit recognises the following escape bodies (delimited by the configured escape character, default `\`):

| Sequence | Meaning | Direction |
|---|---|---|
| `\F\` | Field separator literal (default `|`) | Atomic |
| `\S\` | Component separator literal (default `^`) | Atomic |
| `\T\` | Subcomponent separator literal (default `&`) | Atomic |
| `\R\` | Repetition separator literal (default `~`) | Atomic |
| `\E\` | Escape character literal (default `\`) | Atomic |
| `\Xdd..\` | Hex-encoded UTF-8 bytes (pairs of hex digits) | Hex |
| `\Z…\` | Locally-defined; passes through verbatim | Passthrough |
| Anything else | Unrecognised; passes through verbatim | Passthrough |

## Example

```swift
// On the wire (note: in Swift literals the backslash itself doubles up):
let wire = "MSH|^~\\&|...\rOBX|1|TX|MSG^TEXT||Hello \\S\\ World\r"

let message = try Parser().parse(wire)

// Subcomponent.value is decoded:
let obx5 = message["OBX-5"]
print(obx5)                                                 // "Hello ^ World"

// Round-trip preserves the encoded form:
let rebuilt = String(data: message.serialize(), encoding: .utf8)!
assert(rebuilt == wire)
```

## Hex coalescing

Multi-byte hex content coalesces into a single `\X..\` block on encode:

```swift
let raw = "\r\n"                                            // CR LF
let encoded = EscapeSequences.encode(raw, encoding: .default)
print(encoded)                                              // "\\X0D0A\\" not "\\X0D\\\\X0A\\"
```

Two property tests pin this:
- `decode(encode(x)) == x` for any decoded value (canonical round-trip).
- `encode(decode(y)) == y` for any canonical encoded wire form (canonical wire stays canonical).

A sender that wrote non-canonical hex (separate `\X0D\` and `\X0A\` blocks) will see them coalesced on round-trip. The decoded content is identical; the wire bytes differ.

## `\Z..\` and unknown bodies

Locally-defined escape sequences (sender-specific extensions like `\Z123\`) and any unrecognised body (such as `\H\` or `\.br\` used in some legacy systems) pass through verbatim. The decoder does not invent semantics, and the encoder does not double-escape the backslashes it encountered.

## Customising the escape character

The escape character is itself a sender-configured delimiter (the third character of MSH-2). Most senders use the default `\`, but if your traffic uses (say) `#` instead, HL7v2Kit picks that up from MSH-2 automatically — the escape grammar adapts. See ``EncodingCharacters``.

## See Also

- <doc:RoundTripGuarantee>
- <doc:CharacterEncodingGuide>
- ``EncodingCharacters``
