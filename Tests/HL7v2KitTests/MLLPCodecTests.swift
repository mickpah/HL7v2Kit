// MLLPCodecTests.swift
// v0.3-T1: MLLP framing — exercise the framer + stateful unframer
// against single-frame, multi-frame, partial-frame, and resync paths.

import Testing
import Foundation
@testable import HL7v2Kit

@Suite("MLLP framing (v0.3-T1)")
struct MLLPCodecTests {

    private let body = Data("MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|||ADT^A01|MSG00001|P|2.5.1\rPID|1||123^^^HOSP^MR||Smith^John\r".utf8)

    // MARK: - Framing

    @Test("frame() wraps body with 0x0B prefix and 0x1C 0x0D suffix")
    func frameWrapsCorrectly() {
        let framed = MLLP.frame(body)
        #expect(framed.count == body.count + 3)
        #expect(framed.first == 0x0B)
        #expect(framed[framed.index(framed.endIndex, offsetBy: -2)] == 0x1C)
        #expect(framed.last == 0x0D)
        // Body bytes preserved untouched between the markers.
        let inner = framed.subdata(in: framed.index(after: framed.startIndex)..<framed.index(framed.endIndex, offsetBy: -2))
        #expect(inner == body)
    }

    @Test("frame() of empty body produces just the three marker bytes")
    func frameEmpty() {
        let framed = MLLP.frame(Data())
        #expect(framed == Data([0x0B, 0x1C, 0x0D]))
    }

    // MARK: - Unframing — happy path

    @Test("Single complete frame in one feed yields one body")
    func unframeSingleFrame() {
        var unframer = MLLPUnframer()
        let frames = unframer.feed(MLLP.frame(body))
        #expect(frames.count == 1)
        #expect(frames.first == body)
        #expect(!unframer.isMidFrame)
    }

    @Test("Two concatenated frames in one feed yield both bodies in order")
    func unframeTwoConcatenated() {
        var unframer = MLLPUnframer()
        let body2 = Data("MSH|^~\\&|LAB|FAC|HIS|FAC|||ORU^R01|MSG00002|P|2.5.1\r".utf8)
        var stream = MLLP.frame(body)
        stream.append(MLLP.frame(body2))
        let frames = unframer.feed(stream)
        #expect(frames.count == 2)
        #expect(frames[0] == body)
        #expect(frames[1] == body2)
    }

    @Test("Empty-body frame (0x0B 0x1C 0x0D) yields a zero-length Data")
    func unframeEmptyBody() {
        var unframer = MLLPUnframer()
        let frames = unframer.feed(Data([0x0B, 0x1C, 0x0D]))
        #expect(frames.count == 1)
        #expect(frames.first == Data())
    }

    // MARK: - Unframing — partial / streaming

    @Test("Half a frame returns nothing; the second half completes it")
    func unframeSplitAcrossFeeds() {
        var unframer = MLLPUnframer()
        let framed = MLLP.frame(body)
        let split = framed.count / 2
        let firstHalf = framed.prefix(split)
        let secondHalf = framed.suffix(from: split)

        let firstFrames = unframer.feed(firstHalf)
        #expect(firstFrames.isEmpty)
        #expect(unframer.isMidFrame)

        let secondFrames = unframer.feed(secondHalf)
        #expect(secondFrames.count == 1)
        #expect(secondFrames.first == body)
        #expect(!unframer.isMidFrame)
    }

    @Test("Three-way split across feeds still reassembles correctly")
    func unframeSplitThreeWays() {
        var unframer = MLLPUnframer()
        let framed = MLLP.frame(body)
        let t1 = framed.count / 3
        let t2 = 2 * framed.count / 3
        let chunks = [
            framed.prefix(t1),
            framed.subdata(in: t1..<t2),
            framed.suffix(from: t2),
        ]
        var collected: [Data] = []
        for chunk in chunks {
            collected.append(contentsOf: unframer.feed(chunk))
        }
        #expect(collected.count == 1)
        #expect(collected.first == body)
        #expect(!unframer.isMidFrame)
    }

    @Test("Single byte at a time still produces the frame")
    func unframeOneByteAtATime() {
        var unframer = MLLPUnframer()
        let framed = MLLP.frame(body)
        var collected: [Data] = []
        for byte in framed {
            collected.append(contentsOf: unframer.feed(Data([byte])))
        }
        #expect(collected.count == 1)
        #expect(collected.first == body)
    }

    // MARK: - Unframing — resync / garbage

    @Test("Garbage bytes before the first 0x0B are silently dropped")
    func unframeGarbagePrefixDropped() {
        var unframer = MLLPUnframer()
        var stream = Data("garbage from previous half-frame\r\n".utf8)
        stream.append(MLLP.frame(body))
        let frames = unframer.feed(stream)
        #expect(frames.count == 1)
        #expect(frames.first == body)
    }

    @Test("A fresh 0x0B mid-frame re-syncs: prior partial is dropped")
    func unframeMidFrameRestart() {
        var unframer = MLLPUnframer()
        // First 0x0B + some partial body, then a fresh 0x0B starts
        // over with the full frame.
        var stream = Data([0x0B])
        stream.append(Data("partial body that the sender abandoned".utf8))
        stream.append(MLLP.frame(body))
        let frames = unframer.feed(stream)
        #expect(frames.count == 1)
        #expect(frames.first == body)
    }

    // MARK: - Round-trip

    @Test("Round-trip through the Parser: framed wire parses to the same Message")
    func unframeIntoParserParses() throws {
        var unframer = MLLPUnframer()
        let frames = unframer.feed(MLLP.frame(body))
        let unframedBody = try #require(frames.first)
        let message = try Parser().parse(unframedBody)
        #expect(message.firstSegment(MSH.self)?.messageType?.messageCode == "ADT")
        #expect(message.firstSegment(PID.self)?.setID == "1")
    }
}
