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

- **Segment terminators.** `\r` is preserved exactly, including its absence after the last segment (``Message/trailingSegmentTerminator``). Under `LineTerminatorPolicy.strict` only `\r` ends a segment. A segment that starts with `\n` (a `\r\n` line ending) is rejected with ``ParseError/lineFeedAfterSegmentTerminator(position:)``; an `\n` anywhere else is data and stays in the value it falls in.
- **Empty trailing fields.** `PID|1|||\r` retains its trailing pipes after a round trip — the parser does not omit empty subsequences.
- **Segment IDs.** Outside MSH, BHS and FHS a segment ID is the text before the first field separator (the whole line when there is none), so `ZABC|1` comes back as written rather than as `ZAB|C|1`, and `A|B|c` has ID `A`. The site chooses the delimiters (v2.5.1 section 2.5.4), and a letter or digit can stand inside an ID, so with one as the field separator the ID is the first three characters when the line is three characters long or its fourth is the separator: under `X`, `TXA` and `TXAX1X2` both have ID `TXA`. The validator reports an ID that is not three characters (``IssueCode/segmentIDMalformed``).
- **Lines with no field.** A line with no field separator, such as `ZZZ`, `ZABC` or a bare `BHS` or `FHS`, keeps no field and is written back as its ID alone; `ZZZ|` keeps its one empty field. MSH is the exception: it is always written with MSH-1 and MSH-2, so a bare `MSH` line later in a message comes back as `MSH|^~\&`.
- **Envelope-like lines.** A later line starting `MSH` is read as a message header only when its fourth character is the message's field separator, so `MSHX|1|2` is a segment with ID `MSHX` (reported as 1014) and comes back as written. In ``BatchParser`` and ``StreamingBatchParser`` a line starting `BTS` or `FTS` is a trailer only when it is that ID alone or its fourth character is the field separator of the last MSH, the last BHS or the last FHS read (`|` before any), so an envelope may use a separator other than its messages'; otherwise, as with `BTSX|1`, it stays in the open message. ``StreamingBatchParser`` compares one byte, so a multi-byte UTF-8 separator matches on its lead byte.
- **Repetitions, components, and subcomponents.** Every layer of nesting that exists on the wire is preserved as a distinct AST node. See ``Field``, ``Repetition``, ``Component``, ``Subcomponent``.
- **Edits.** After ``Message/set(_:at:)``, ``Message/clear(at:)`` or ``Message/insertRepetition(_:at:)``, every segment and field the edit did not touch serialises as it was read; in the edited field, only the named node and any empty nodes created to reach it change; an edit to MSH-18 re-encodes every segment in the new character set.
- **Escape sequences.** A parsed value is written back exactly as it was read, escapes and all: `\F\`, `\S\`, `\T\`, `\R\`, `\E\`, `\X..\` (non-canonical and invalid forms such as `\X0D\\X0A\`, `\X41\` and `\XZZ\` included), `\Z..\` and any other body. A value set by an edit or built in code is encoded instead. See <doc:EscapeSequences>. Equality compares decoded values, so a message parsed from `\X41\` equals one parsed from `A`, though each serialises as read.
- **Character set.** MSH-18 is detected on parse; the same charset is used on serialise. UTF-8, ASCII, and ISO-8859-1 are supported. See <doc:CharacterEncodingGuide>.
- **MSH-2 encoding characters.** Custom delimiter characters (non-default field separator, component separator, etc.) round-trip exactly via ``EncodingCharacters``. A fifth MSH-2 character (the v2.7+ truncation character) is kept in MSH-2's literal value and written back unchanged; the validator reports it, as a field length, on versions that print MSH-2 as four characters.
- **Delimiter spelling.** A delimiter matches only its own spelling. With `é` as U+00E9 for the field separator, `e` U+0301 in a value stays in the value and comes back as written; the same goes for U+212A under a `K` separator and U+037E under `;`. Two spellings of one character still do not count as distinct delimiters: ``Parser`` refuses an MSH-2 that holds both.

## What round-trip does not promise

- **Inputs the parser rejected.** A malformed message that fails ``Parser/parse(_:)-(Data)`` is not in the round-trip set. The serialiser is only run on successful parses. Two byte-level rejections worth knowing about (both added post-v0.1.0 — see <doc:Migration>):
  - **Embedded NUL bytes** (`0x00`) are rejected with ``ParseError/truncatedMessage(atByte:)``. Real v2 wire never carries NUL; an embedded one is almost always transport truncation. This rejection makes the invariant honest without a NUL carve-out — every *accepted* message is NUL-free, so the serialiser never has to worry about preserving a control byte the wire shouldn't carry.
  - **Leading UTF-8 BOM** (`EF BB BF`) is silently stripped on the byte-input path. A BOM-prefixed input parses successfully but the serialised output is BOM-free — the serialiser never re-emits a BOM. So a BOM round trip is `BOM + body in → body only out` (canonicalisation, not byte-equality). The String-input path is unaffected.
- **Bytes synthesised by ``MessageBuilder``.** Builder-produced messages round-trip if you parse-then-serialise them, but the builder API does not enforce that *every* combination of typed accessor writes produces a byte-equal stream of the user's original bytes (because there were no original bytes to compare to).
- **Character-set conversion loss.** If a sender declares MSH-18 = `ASCII` but populates a body byte outside ASCII range, `Parser.parse(_ data:)` throws ``ParseError/unsupportedCharacterEncoding(declared:)``; text given to `Parser.parse(_:)` as a `String` throws the same way when the declared character set cannot encode it. There is no "best-effort" lossy decode. A message built in code that holds such a character is written entirely as UTF-8 and is reported by the validator (``IssueCode/characterNotEncodable(declared:)``).
- **Line endings under `.lenient`.** `LineTerminatorPolicy.lenient` (the parser's default) reads `\r\n` and `\n` as segment terminators and serialises `\r`. Under `.strict` a `\r\n` line ending is rejected, so `.strict` suits input that ends its segments with `\r` alone.
- **Blank lines.** An empty line between segments (`\r\r`) is skipped on parse and not re-emitted.
- **Batch headers inside one message.** ``Parser`` reads a BHS or FHS line inside a message with the message's delimiters, so one that declares others (`BHS#^~\&#APP`, or `BHSX|1`, in a message whose field separator is `|`) comes back with the message's field separator. ``BatchParser`` keeps each envelope line as written.
- **Raw control characters.** A control character inside a value, such as an `\n` read under `.strict`, is written back as a hex escape (`\X0A\`); a raw one cannot stand inside a field on the wire. The decoded value is unchanged. This holds inside a locally defined escape too: `\Za<TAB>b\` comes back as `\E\Za\X09\b\E\`, the same text written escaped.

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
