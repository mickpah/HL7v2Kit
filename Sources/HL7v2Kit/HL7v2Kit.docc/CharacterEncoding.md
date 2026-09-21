# Character Encoding

How HL7v2Kit detects the message charset from MSH-18 and uses it for both parse and serialise.

## Overview

HL7 v2 messages carry their character set declaration in **MSH-18**. A sender writing `MSH|^~\&|...|2.5.1|||||||8859/1` is telling the receiver "the body of this message is encoded as ISO-8859-1, even though my header bytes are ASCII-safe".

HL7v2Kit detects the declared charset on parse, decodes the bytes accordingly, and re-emits them in the same charset on serialise. The detected charset is exposed on the parsed ``Message`` via ``Message/characterEncoding``.

## Supported charsets

For v0.1.0:

| MSH-18 wire string | ``CharacterEncoding`` case | `String.Encoding` |
|---|---|---|
| `UNICODE UTF-8` (default) | ``CharacterEncoding/utf8`` | `.utf8` |
| `ASCII` / `US-ASCII` | ``CharacterEncoding/ascii`` | `.ascii` |
| `8859/1` / `ISO-8859-1` / `Latin-1` | ``CharacterEncoding/iso8859_1`` | `.isoLatin1` |

Common aliases are accepted case-insensitively. If MSH-18 is empty or absent, the parser defaults to ``CharacterEncoding/utf8``.

## How detection works

``CharacterEncoding/detect(in:)`` is the entry point:

```swift
let probe = String(data: bytes, encoding: .isoLatin1) ?? ""
let charset = try CharacterEncoding.detect(in: probe)       // throws on unrecognised MSH-18
```

The probe uses ISO-8859-1 because it's a 1:1 byte-to-codepoint mapping — every byte yields a valid String, and the structural ASCII characters (`MSH`, `|`, the encoding chars) survive untouched. Any non-ASCII body bytes show up as arbitrary Latin-1 codepoints but are past MSH-18 so they don't affect the lookup.

``Parser/parse(_:)-(Data)`` uses this internally:

1. ISO-8859-1 probe-decode the bytes.
2. Look up MSH-18 via ``CharacterEncoding/detect(in:)``.
3. Re-decode the original bytes with the chosen charset.
4. Parse the resulting String.

## Strict on unrecognised

An MSH-18 value HL7v2Kit doesn't recognise (e.g. `EBCDIC`, `GB18030`) throws ``ParseError/unsupportedCharacterEncoding(declared:)``. There is no "best-effort" lossy decode; the policy is strict to avoid silently mojibake-ing message content. Add the charset to ``CharacterEncoding`` (and `Resources/schemas/` if the codegen needs to know) if your traffic uses it.

## Round-trip with Latin-1

```swift
// A real sender writes "Café au lait" as a Latin-1-encoded byte stream:
var bytes = Data("MSH|^~\\&|LAB|FAC|HOSPITAL|FAC|||ORU^R01^ORU_R01|MSG00001|P|2.5.1||||||8859/1\r".utf8)
bytes.append(Data("OBX|1|TX|MSG^TEXT||Caf".utf8))
bytes.append(0xE9)                                          // 'é' in Latin-1
bytes.append(Data(" au lait\r".utf8))

let message = try Parser().parse(bytes)
print(message.characterEncoding)                            // .iso8859_1
print(message["OBX-5"])                                     // "Café au lait"

let rebuilt = message.serialize()
assert(rebuilt == bytes)                                    // byte-perfect, Latin-1 preserved
```

## String input

``Parser/parse(_:)-(String)`` still consults MSH-18 even though the input is already decoded text — so ``Message/characterEncoding`` reflects what the wire declared. An unrecognised value throws the same way. If you need to parse a string without MSH-18 validation, the documented v0.1.0 limitation is to decode the bytes yourself and use the byte-input overload (no `Parser.parse(structural:)` exists yet).

## See Also

- <doc:RoundTripGuarantee>
- <doc:EscapeSequences>
- ``CharacterEncoding``
- ``Message``
