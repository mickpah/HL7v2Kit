# Source Positions

Where in the input each parsed value sits, so an issue can be shown in the text it came from.

## Overview

``Parser/sourceMap(of:)`` returns a ``SourceMap``: the byte range in the input of every segment, field, repetition, component and subcomponent ``Parser/parse(_:)-(Data)`` produces from it, and it throws what `parse(_:)` throws. A ``WireLocation`` names a place. ``SourceMap/range(of:)`` gives its bytes, or nil for a place the parse did not produce. An empty field between two separators has an empty range at its offset; a field numbered beyond the line's last field has none, so an issue on a required field the line stops short of selects the segment instead. ``Parser/parseWithSourceMap(_:)`` returns the message and its map from one parse.

```swift
let parser = Parser()
let data = Parser.wire(fromCarried: pasted)             // text a person pasted, as bytes
let (message, map) = try parser.parseWithSourceMap(data)
if let issue = Validator().validate(message).issues.first {
    let place = WireLocation(issue.location)
    // A field the line stops short of has no bytes: select its segment.
    let segment = WireLocation(segmentID: place.segmentID, segmentIndex: place.segmentIndex)
    if let bytes = map.range(of: place) ?? map.range(of: segment) {
        let selection = NSRange(map.utf16Range(bytes))  // in map.text, for a text view
    }
}
```

A range covers the bytes of the input as written: an escape sequence as its wire text, and an empty value as an empty range at its offset. Offsets count from the first byte of the `Data` as given, a byte-order mark included; for a `Data` whose `startIndex` is not zero, add `data.startIndex` before subscripting. They count one byte per character in ASCII and ISO 8859-1, and a character's UTF-8 length under UTF-8. ``SourceMap/text`` is the decoded text without a byte-order mark, and ``SourceMap/utf16Range(_:)`` converts a byte range to UTF-16 offsets in it, moving a bound inside a Unicode scalar back to its first byte.

## What a map is not

- **Kept in step with edits.** It describes the bytes it was built from. After an edit, map ``Message/serialize()``'s output again.
- **A map of a batch.** It maps one message, as ``Parser`` reads it; ``BatchParser`` and ``StreamingBatchParser`` input is not mapped.
- **A map of text.** Its offsets are bytes of a `Data`. Text a person pasted goes through ``Parser/wire(fromCarried:)-(Data)`` first, and the offsets are into its output, not the pasted text: a view shows ``SourceMap/text``, which the UTF-16 offsets index.

## Delimiters

The separator between two values is in neither's range, only in the range of the value that holds both. ``SourceMap/location(at:)`` gives the deepest value whose range holds a byte, so a separator answers the value that encloses it: a subcomponent separator its component, a component separator its repetition, a repetition separator its field, and a field separator its segment. A byte of the segment ID answers the segment. A segment's range is its line without the terminator, and a terminator, a byte-order mark or an offset outside the input answers nil.

## MSH-1 and MSH-2

MSH-1 is the line's fourth character, the field separator, and MSH-2 the encoding characters as one value, not split at the separators it holds. Each has one repetition, component and subcomponent, all with the value's range, so a byte in either answers repetition 1, component 1, subcomponent 1. BHS and FHS follow the same rule. A BHS or FHS line may spell its own separator: its field 1 covers that character, though the parse gives the field the message's separator.

## Cost

``Parser/sourceMap(of:)`` runs the parse itself, then decodes and tokenises the data again to build the map, and keeps nothing between calls. A caller that wants the message as well calls ``Parser/parseWithSourceMap(_:)``, which parses once; `parse(_:)` followed by `sourceMap(of:)` parses twice. A caller that never asks for positions pays nothing.
