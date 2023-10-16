// PORTABLE KERNEL — keep this file Foundation-free in the inner loop.
// MLLP framing is purely byte-level — VT (0x0B) prefix, message body,
// FS (0x1C) + CR (0x0D) suffix. `Data` is used at the API edges only;
// the buffer and inner loop work on `[UInt8]`. A future Rust/Go port
// translates this file directly. See
// docs/design/ADR-006-portable-core-boundary.md

// MLLPCodec.swift
// Minimum Lower Layer Protocol (MLLP) framing — the standard TCP
// transport framing for HL7 v2 over the wire. Each frame is:
//   0x0B <body bytes> 0x1C 0x0D
// v0.3-T1.

import Foundation

/// MLLP frame markers and the framing function. The MLLP envelope is
/// the standard transport framing for HL7 v2 over TCP — every sender
/// wraps a message body in `0x0B …body… 0x1C 0x0D`. ``MLLP/frame(_:)``
/// applies this envelope; ``MLLPUnframer`` consumes incremental TCP
/// byte chunks and yields complete frame bodies.
public enum MLLP {
    /// Vertical-Tab — frame start byte (precedes the message body).
    public static let startByte: UInt8 = 0x0B
    /// File-Separator — body end marker (precedes the carriage return).
    public static let endBodyByte: UInt8 = 0x1C
    /// Carriage-Return — frame end byte (after the FS).
    public static let endFrameByte: UInt8 = 0x0D

    /// Frame a single HL7 message body into an MLLP envelope.
    ///
    /// Returns the original `body` bytes preceded by `0x0B` and
    /// followed by `0x1C 0x0D`. Callers stream the result directly to
    /// a TCP socket. The body is treated as opaque — no escape
    /// processing happens at the MLLP layer.
    public static func frame(_ body: Data) -> Data {
        var framed = Data(capacity: body.count + 3)
        framed.append(startByte)
        framed.append(body)
        framed.append(endBodyByte)
        framed.append(endFrameByte)
        return framed
    }
}

/// Stateful unframer that consumes incremental TCP byte chunks and
/// emits complete MLLP-framed message bodies as they arrive.
///
/// TCP doesn't preserve message boundaries — a single `recv()` may
/// return a half frame, two and a half frames, or one frame across
/// three receives. The unframer buffers partial frames between
/// ``feed(_:)`` calls so each completed frame surfaces as soon as
/// its trailing `0x1C 0x0D` arrives.
///
/// Garbage bytes before the first `0x0B` are silently dropped — a
/// common real-world resilience pattern for HL7 receivers that may
/// be attached mid-stream or recovering from a previous corrupted
/// frame. Inside a frame, a second `0x0B` re-syncs the unframer
/// (drops the partial body and restarts) — handles the case of a
/// sender restarting mid-frame.
public struct MLLPUnframer: Sendable {
    private var buffer: [UInt8]
    private var insideFrame: Bool

    public init() {
        self.buffer = []
        self.insideFrame = false
    }

    /// Feed incremental bytes; returns 0 or more complete frame
    /// bodies in arrival order.
    public mutating func feed(_ bytes: Data) -> [Data] {
        var frames: [Data] = []
        for byte in bytes {
            if !insideFrame {
                // Looking for start byte; drop everything else as
                // pre-frame garbage.
                if byte == MLLP.startByte {
                    insideFrame = true
                    buffer.removeAll(keepingCapacity: true)
                }
                continue
            }
            // Inside a frame.
            //
            // End-of-frame: FS (0x1C) immediately followed by CR
            // (0x0D). Detect by checking for CR when the previously
            // buffered byte is the FS.
            if byte == MLLP.endFrameByte && buffer.last == MLLP.endBodyByte {
                buffer.removeLast()              // drop the FS
                frames.append(Data(buffer))      // emit the body bytes
                buffer.removeAll(keepingCapacity: true)
                insideFrame = false
                continue
            }
            // Mid-frame restart: a fresh start byte while we're
            // already inside a frame means the sender hit a problem
            // and restarted. Drop the partial body and re-arm.
            if byte == MLLP.startByte {
                buffer.removeAll(keepingCapacity: true)
                continue
            }
            buffer.append(byte)
        }
        return frames
    }

    /// True when the unframer is currently mid-frame — has seen a
    /// start byte and is waiting for the trailing `0x1C 0x0D`. Useful
    /// for detecting timed-out half-frames at the application layer.
    public var isMidFrame: Bool { insideFrame }
}
