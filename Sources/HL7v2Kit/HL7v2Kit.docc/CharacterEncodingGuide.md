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

Common aliases are accepted case-insensitively. If MSH-18 is absent, empty or the HL7 null `""` (or its first repetition is empty or `""`), the parser defaults to ``CharacterEncoding/utf8``, and so does an edit that sets it so. This departs from v2.5.1 section 2.15.9.18, which reads an unvalued MSH-18 as 7-bit ASCII; UTF-8 contains ASCII, so a conformant message decodes the same, and a message with no MSH-18 that holds non-ASCII text is accepted.

## Repeated MSH-18

MSH-18 repeats. The first repetition names the character set of the whole message; later repetitions name alternate character sets, used only in FT, ST and TX values through the `\C..\` and `\M..\` escapes (v2.5.1 section 2.15.9.18). HL7v2Kit decodes and writes the message in the first repetition's character set, keeps the later repetitions as data, and keeps those escapes verbatim, so `8859/1~ISO IR87` reads as ``CharacterEncoding/iso8859_1``. An empty first repetition (`~ISO IR87`) takes the empty-field default. An unrecognised first repetition throws, naming it. ``CharacterEncoding/from(mshField18:)`` maps one value; a repeated one maps to `nil`.

## How detection works

``CharacterEncoding/detect(in:)`` is the entry point:

```swift
let probe = String(data: bytes, encoding: .isoLatin1) ?? ""
let charset = try CharacterEncoding.detect(in: probe)       // throws on unrecognised MSH-18
```

The probe uses ISO-8859-1 because it's a 1:1 byte-to-codepoint mapping — every byte yields a valid String, and the structural ASCII characters (`MSH`, `|`, the encoding chars) survive untouched. Any non-ASCII body bytes show up as arbitrary Latin-1 codepoints but are past MSH-18 so they don't affect the lookup.

The snippet shows the steps; the parser itself converts ISO-8859-1 without `String.Encoding.isoLatin1`, because swift-corelibs-foundation 6.0 on Linux returns `nil` for any ISO Latin 1 text holding a CR.

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

``Parser/parse(_:)-(String)`` still consults MSH-18 even though the input is already decoded text, so ``Message/characterEncoding`` reflects what the wire declared. An unrecognised value throws the same way. So does text the declared character set cannot encode (an `é` under `ASCII`, a `€` under `8859/1`): it throws ``ParseError/unsupportedCharacterEncoding(declared:)`` with the declared set, as the same message given as bytes would. ``BatchParser`` parses each message through it.

## Text the character set cannot encode

Every way into a message refuses a character its character set cannot encode, except building one in code: both parse paths throw, and ``Message/set(_:at:)`` throws ``MessageEditError/characterNotEncodable(_:)``. A message built with ``MessageBuilder`` or ``Message/init(version:encodingCharacters:segments:characterEncoding:locale:)`` can still hold one. ``Validator`` reports each such field as ``IssueCode/characterNotEncodable(declared:)``, an error in every preset (field values only: the delimiters and segment IDs are not checked), and ``Message/serialize()`` writes that message entirely as UTF-8, so one `€` under `8859/1` turns an `é` from `E9` into `C3 A9`. Validate a built message before sending it.

## See Also

- <doc:RoundTripGuarantee>
- <doc:EscapeSequences>
- ``CharacterEncoding``
- ``Message``
