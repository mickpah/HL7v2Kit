# Escape Sequences

How HL7v2Kit handles `\F\`, `\S\`, `\T\`, `\R\`, `\E\`, `\X..\` and `\Z..\` — the v2 escape grammar.

## Overview

HL7 v2 uses backslash-delimited escape sequences to embed delimiter characters inside scalar field values. A patient name containing a literal `^` is encoded `\S\` (because `^` is the component separator); a CR byte inside an observation value is encoded `\X0D\`.

HL7v2Kit decodes these on parse and re-encodes them on serialise. ``Subcomponent/value`` stores the **decoded** text — callers never see `\F\` in a typed accessor result. A parsed value also keeps the text it was read from, and the serialiser writes that back, so a parsed message round-trips byte for byte, non-canonical escapes included. A value built in code or set by an edit is encoded, as described below.

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
| `\H\`, `\N\` | Start and end highlighting; pass through verbatim | Passthrough |
| `\P\` | Truncation character (v2.7 and later); passes through verbatim | Passthrough |
| `\Cxxyy\`, `\Mxxyy\`, `\Mxxyyzz\` | Character-set escapes; pass through verbatim | Passthrough |
| `\.br\`, `\.sp\`, `\.in+4\` and the other formatting commands | FT formatting; pass through verbatim | Passthrough |
| Anything else | Read: kept verbatim. Written from code: text, escaped as `\E\` | See below |

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

Coalescing applies to values built in code. A parsed value keeps its hex exactly as the sender wrote it, `\X0D\\X0A\` included.

## `\Z..\` and unknown bodies

The decoder keeps every escape it does not resolve verbatim in the value: locally defined sequences (`\Z123\`), highlighting (`\H\`, `\N\`), the formatting commands (`\.br\`), the character-set escapes (`\C2842\`, `\M2442\`), the truncation escape `\P\` (v2.7 and later, deliberately not decoded: a literal truncation character and its escape would become indistinguishable), and any body the standard does not define. A parsed value is written back from the text it was read from, so all of these round-trip exactly.

A value built in code, or set by an edit, has no such text, so the encoder decides. It copies a `\…\` run as an escape only when the standard defines it (v2.5.1 Chapter 2, sections 2.7.1 to 2.7.6): `\H\`, `\N\`, `\P\`, `\Z` followed by one or more characters, `\C` and four hex digits, `\M` and four or six hex digits, and the formatting commands `.br`, `.fi`, `.nf`, `.ce`, `.sp` (optional number), `.in` and `.ti` (signed number) and `.sk` (number). Any other run is text, so `C:\Users\me` is written `C:\E\Users\E\me`. A run that holds a delimiter or a control character is never copied: its characters are escaped one by one, so a value cannot split a field or start a segment.

One ambiguity remains, by design of the decoded-value model: text written in code that spells a defined escape (a literal `\H\` or `\.br\`) is written as the escape, and through ``Subcomponent/value`` a parsed escape `\H\` and parsed literal text `\E\H\E\` both read `\H\`. Round trip and validation read the wire text, so neither is affected.

## Customising the escape character

The escape character is itself a sender-configured delimiter (the third character of MSH-2). Most senders use the default `\`, but if your traffic uses (say) `#` instead, HL7v2Kit picks that up from MSH-2 automatically — the escape grammar adapts. See ``EncodingCharacters``.

## See Also

- <doc:RoundTripGuarantee>
- <doc:CharacterEncodingGuide>
- ``EncodingCharacters``
