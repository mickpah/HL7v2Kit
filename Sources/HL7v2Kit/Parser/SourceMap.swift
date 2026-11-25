// SourceMap.swift
// Parser.sourceMap(of:): the byte range in the input of everything a parse produced (P01 R4, #37).

import Foundation

/// The position in the input of everything a parse produced.
///
/// Build one with ``Parser/sourceMap(of:)``, look a place up with ``range(of:)`` and a byte with
/// ``location(at:)``. A range is a byte offset into the data as given, so a byte-order mark's
/// three bytes come before offset 3. A value is covered as written: an escape sequence by its
/// wire text, MSH-1 by the line's fourth character.
public struct SourceMap: Sendable {
    /// The decoded text of the input, without a byte-order mark.
    ///
    /// The offsets ``range(of:)`` gives count bytes of the input `Data` as given, not characters
    /// of this text: after a byte-order mark, the text's first character is at offset 3.
    /// ``utf16Range(_:)`` converts them to offsets in this text.
    public let text: String

    // A value's byte range and the values it splits into: a segment's fields, a field's
    // repetitions, a repetition's components, a component's subcomponents.
    struct Node: Sendable {
        let range: Range<Int>
        let children: [Node]
    }

    let segments: [Node]
    // Each segment ID's occurrences, as positions in `segments`, in order.
    let segmentsByID: [String: [Int]]
    // The ID and occurrence of each segment, by its position in `segments`.
    let segmentLocations: [WireLocation]
    // The bytes of the input that `text` decodes (after any byte-order mark), and how.
    let textBytes: Range<Int>
    let characterEncoding: CharacterEncoding

    /// Byte range in the input of the value at `location`, or nil when the parse produced no
    /// such value. An empty value has an empty range at its offset.
    ///
    /// Offsets are into the input `Data` as given, from its first byte, a byte-order mark
    /// included. For a `Data` whose `startIndex` is not zero, add `data.startIndex` before
    /// subscripting. A nil index answers the level above it: no field is the segment, no
    /// repetition the field, and so on; a component without a repetition is read in the first
    /// repetition.
    public func range(of location: WireLocation) -> Range<Int>? {
        guard let occurrences = segmentsByID[location.segmentID],
              location.segmentIndex >= 1, location.segmentIndex <= occurrences.count else { return nil }
        var node = segments[occurrences[location.segmentIndex - 1]]
        // A component without a repetition is in the first repetition, as `WireLocation(_:)` places it.
        let repetition = location.repetitionIndex ?? (location.componentIndex == nil ? nil : 1)
        for index in [location.fieldIndex, repetition, location.componentIndex, location.subcomponentIndex] {
            guard let index else { break }
            guard index >= 1, index <= node.children.count else { return nil }
            node = node.children[index - 1]
        }
        return node.range
    }

    /// The deepest value whose range holds the byte at `offset`, or nil when the byte is a
    /// segment terminator, a byte-order mark or outside the input. A delimiter belongs to no
    /// value at its own level, so it answers the value that encloses it: a component separator
    /// its repetition, a field separator its segment.
    ///
    /// `offset` counts as ``range(of:)`` counts. A byte in MSH-1 or MSH-2 (BHS, FHS) answers
    /// repetition 1, component 1, subcomponent 1, as a byte of any other value does; a byte of a
    /// segment ID answers the segment.
    public func location(at offset: Int) -> WireLocation? {
        guard let s = Self.position(in: segments, holding: offset) else { return nil }
        var indices: [Int] = []
        var node = segments[s]
        while let i = Self.position(in: node.children, holding: offset) {
            indices.append(i + 1)
            node = node.children[i]
        }
        func at(_ k: Int) -> Int? { k < indices.count ? indices[k] : nil }
        let segment = segmentLocations[s]
        return WireLocation(segmentID: segment.segmentID, segmentIndex: segment.segmentIndex, fieldIndex: at(0),
                            repetitionIndex: at(1), componentIndex: at(2), subcomponentIndex: at(3))
    }

    /// `byteRange` as UTF-16 offsets in ``text``, for a text view. A bound inside a character
    /// is moved back to the character's first byte.
    ///
    /// A character here is a Unicode scalar: a bound inside one's UTF-8 bytes moves back, so a
    /// range never splits a surrogate pair; a bound between a letter and its combining mark
    /// stays. A bound in a byte-order mark or before the input moves to the text's start; a bound
    /// past the input's end moves to the text's end.
    public func utf16Range(_ byteRange: Range<Int>) -> Range<Int> {
        let bytes = byteRange.clamped(to: textBytes)
        return utf16Offset(bytes.lowerBound)..<utf16Offset(bytes.upperBound)
    }

    // A byte offset in `textBytes` as a UTF-16 offset in `text`. In ASCII and ISO 8859-1 a byte
    // is one character, which is one UTF-16 unit. Under UTF-8 `text`'s own bytes are the input's,
    // and the standard library converts: a native string's UTF-8 offset is direct and its UTF-16
    // offset comes from a table it builds once, on first use, safely across threads.
    private func utf16Offset(_ byte: Int) -> Int {
        let offset = byte - textBytes.lowerBound
        guard characterEncoding == .utf8 else { return offset }
        var index = text.utf8.index(text.utf8.startIndex, offsetBy: offset)
        while index.samePosition(in: text.unicodeScalars) == nil { index = text.utf8.index(before: index) }
        return index.utf16Offset(in: text)
    }

    /// The position in `nodes` (in order, none overlapping) of the one whose range holds
    /// `offset`; an empty range holds nothing.
    static func position(in nodes: [Node], holding offset: Int) -> Int? {
        var low = 0
        var high = nodes.count
        while low < high {   // the first node starting after `offset`
            let mid = (low + high) / 2
            if nodes[mid].range.lowerBound <= offset { low = mid + 1 } else { high = mid }
        }
        return low > 0 && nodes[low - 1].range.contains(offset) ? low - 1 : nil
    }

    /// The byte ranges of `pieces`, slices of `parent` in order, with `parent` starting at byte
    /// `start`. Each gap and piece is measured once, so the cost is the parent's length.
    static func ranges(of pieces: [Substring], in parent: Substring, at start: Int,
                       width: (Substring) -> Int) -> [Range<Int>] {
        var offset = start
        var cursor = parent.startIndex
        return pieces.map { piece in
            offset += width(parent[cursor..<piece.startIndex])
            let lower = offset
            offset += width(piece)
            cursor = piece.endIndex
            return lower..<offset
        }
    }

    /// The values the first of `splits` cuts `parent` into, each with the rest of `splits` below it.
    static func nodes(in parent: Substring, at start: Int, splits: ArraySlice<(Substring) -> [Substring]>,
                      width: (Substring) -> Int) -> [Node] {
        guard let split = splits.first else { return [] }
        let pieces = split(parent)
        return zip(pieces, ranges(of: pieces, in: parent, at: start, width: width)).map { piece, range in
            Node(range: range, children: nodes(in: piece, at: range.lowerBound, splits: splits.dropFirst(), width: width))
        }
    }

    /// A value the parse keeps whole (MSH-1, MSH-2): one repetition, component and subcomponent,
    /// each with the value's range.
    static func literal(_ range: Range<Int>, depth: Int = 3) -> Node {
        Node(range: range, children: depth == 0 ? [] : [literal(range, depth: depth - 1)])
    }
}

extension Parser {
    /// The byte range in `data` of every segment, field, repetition, component and subcomponent
    /// ``parse(_:)-(Data)`` produces from it.
    ///
    /// It parses `data` first, so it throws what `parse(_:)` throws for the same input and options.
    /// Offsets count the bytes of `data` as given: one per character in ASCII and ISO 8859-1, a
    /// character's UTF-8 length under UTF-8. A segment's range is its line without the terminator.
    public func sourceMap(of data: Data) throws(ParseError) -> SourceMap {
        try SourceMap(mapping: data, encoding: parse(data).encodingCharacters, policy: options.lineTerminator)
    }
}

extension SourceMap {
    /// The map of `data`, which `parse` has accepted with `encoding` under `policy`.
    init(mapping data: Data, encoding: EncodingCharacters, policy: LineTerminatorPolicy) throws(ParseError) {
        var (text, characterEncoding) = try Parser.decodeWirePayload(data)
        // A string Foundation bridged would make each `utf16Range` call walk the text.
        text.makeContiguousUTF8()
        let width: (Substring) -> Int = characterEncoding == .utf8 ? { $0.utf8.count } : { $0.unicodeScalars.count }
        let below: [(Substring) -> [Substring]] = [
            { Parser.repetitionSlices(of: $0, encoding: encoding) },
            { Parser.componentSlices(of: $0, encoding: encoding) },
            { Parser.subcomponentSlices(of: $0, encoding: encoding) },
        ]
        let whole = text[...]
        let lines = Parser.lineSlices(of: text, policy: policy)
        // The bytes decoding dropped in front: a byte-order mark, or two (Foundation's UTF-8 decode drops one).
        let textBytes = (data.count - width(whole))..<data.count
        let lineRanges = SourceMap.ranges(of: lines, in: whole, at: textBytes.lowerBound, width: width)
        var segments: [SourceMap.Node] = []
        var segmentsByID: [String: [Int]] = [:]
        var segmentLocations: [WireLocation] = []
        for (i, (line, range)) in zip(lines, lineRanges).enumerated() {
            if line.isEmpty { continue }   // a blank line is no segment, as in `parse`
            let separatorSegment = Parser.isSeparatorLine(line, at: i, fieldSeparator: encoding.fieldSeparator)
            // The parse has already rejected a line too short to have an ID.
            guard let slices = Parser.fieldSlices(of: line, encoding: encoding, separatorSegment: separatorSegment) else {
                continue
            }
            let fieldRanges = SourceMap.ranges(of: slices.fields, in: line, at: range.lowerBound, width: width)
            let fields = zip(slices.fields, fieldRanges).enumerated().map { f, pair in
                separatorSegment && f < 2
                    ? SourceMap.literal(pair.1)
                    : SourceMap.Node(range: pair.1, children: SourceMap.nodes(in: pair.0, at: pair.1.lowerBound,
                                                                               splits: below[...], width: width))
            }
            let id = String(slices.id)
            segmentsByID[id, default: []].append(segments.count)
            segmentLocations.append(WireLocation(segmentID: id, segmentIndex: segmentsByID[id]?.count ?? 1))
            segments.append(SourceMap.Node(range: range, children: fields))
        }
        self.init(text: text, segments: segments, segmentsByID: segmentsByID, segmentLocations: segmentLocations,
                  textBytes: textBytes, characterEncoding: characterEncoding)
    }
}
