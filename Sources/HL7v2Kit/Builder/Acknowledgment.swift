// Acknowledgment.swift
// The general acknowledgment (ACK) of a received message, ADR-019 decision 9:
// build and validate the general ACK, no protocol logic. Structure
// MSH [{SFT}] [UAC] MSA [{ERR}] (v2.5.1 CH02 §2.14.1; v2.6 and v2.8.2 §2.13.1;
// MSH MSA [ERR] in v2.3 and v2.3.1 §2.13.1 and v2.4 §2.14.1), with the
// original-mode response rules of v2.5.1 CH02 §2.9.2.2 (v2.3 and v2.3.1
// §2.12.1.2.1, v2.4 §2.13.1.2.1, v2.6 and v2.8.2 §2.9.2.2).

/// HL7 Table 0008, Acknowledgment Code: the value of MSA-1.
///
/// The six codes are the whole of Table 0008 on every supported version
/// (v2.3, v2.3.1, v2.4, v2.5.1, v2.6 and v2.8.2; `Resources/tables/v*/0008.json`,
/// an HL7 table that permits no local extension). The A codes are the
/// original-mode responses and, in enhanced mode, the application
/// acknowledgment; the C codes are the enhanced-mode accept (commit)
/// acknowledgment (v2.5.1 CH02 §2.9.3).
///
/// - Note: **Open** enum per ADR-014: HL7 owns Table 0008 and a later version
///   could add a code, which would then ship as an additive case in a minor
///   release. Switch with `@unknown default`.
public enum AcknowledgmentCode: String, Sendable, CaseIterable, Equatable, Hashable {
    /// `AA`: original mode application accept; enhanced mode application
    /// acknowledgment, accept.
    case applicationAccept = "AA"
    /// `AE`: original mode application error; enhanced mode application
    /// acknowledgment, error.
    case applicationError = "AE"
    /// `AR`: original mode application reject; enhanced mode application
    /// acknowledgment, reject.
    case applicationReject = "AR"
    /// `CA`: enhanced mode accept acknowledgment, commit accept.
    case commitAccept = "CA"
    /// `CE`: enhanced mode accept acknowledgment, commit error.
    case commitError = "CE"
    /// `CR`: enhanced mode accept acknowledgment, commit reject.
    case commitReject = "CR"
}

public extension MessageBuilder {
    /// Build the general acknowledgment (`ACK`) of `original`.
    ///
    /// The ACK is built in the original's version, encoding characters and
    /// character set, through ``MessageBuilder``. It holds MSH and MSA only.
    ///
    /// What the builder sets, and from where:
    ///
    /// - MSH-1 and MSH-2: the original's encoding characters.
    /// - MSH-3 and MSH-4: the original's MSH-5 and MSH-6, copied as fields.
    ///   The response header is "constructed anew following the rules used to
    ///   create the initial message" (v2.5.1 CH02 §2.9.2.2), so its sender is
    ///   the application and facility that received the original.
    /// - MSH-5 and MSH-6: the original's MSH-3 and MSH-4, and MSH-11: the
    ///   original's MSH-11, all copied as fields ("contain codes that are
    ///   copied from MSH-3, MSH-4 and MSH-11 in the initiating message",
    ///   v2.5.1 CH02 §2.9.2.2; the same text in every supported version).
    /// - MSH-7: `dateTime`, and MSH-10: `messageControlID`. Both "refer to
    ///   the response message; they are not echoes" (§2.9.2.2).
    /// - MSH-9: `ACK^<original MSH-9.2>^ACK`. The trigger event equals the
    ///   acknowledged message's and the structure "is always ACK" (v2.5.1
    ///   CH02 §2.14.1 note; v2.4 §2.14.1, v2.6 and v2.8.2 §2.13.1). On v2.3,
    ///   whose MSH-9 has two components (v2.3 CH02 §2.24.1.9), it is
    ///   `ACK^<event>`; v2.3.1 adds the third component (§2.24.1.9). On v2.3
    ///   and v2.3.1, §2.24.1.9 says "The second component is not required on
    ///   response or acknowledgment messages" and prints no note that the
    ///   event equals the original's, so echoing it there is permitted, not
    ///   mandated; the builder echoes it on every version. The version is
    ///   the original's parsed `version`. An empty original MSH-9.2 (an MSH-9
    ///   of `ADT`, or a bare `ACK`) leaves the event empty rather than
    ///   guessing one, so MSH-9 is `ACK^^ACK` (`ACK` on v2.3). On v2.5.1,
    ///   v2.6 and v2.8.2, which print MSG.2 as required, that ACK fails the
    ///   required-component check at MSH-9.2, as the original itself does;
    ///   v2.3.1 and v2.4 print no component optionality and accept it.
    /// - MSH-12: the original's MSH-12, copied as a field, so the ACK
    ///   declares the version it was built in. An unrecognised or empty
    ///   MSH-12 is echoed as received (the parser reads such a message as
    ///   v2.5.1, ADR-018), and the Validator reports it on the ACK as on the
    ///   original.
    /// - MSH-18: the original's MSH-18, copied as a field, because the ACK is
    ///   serialised in the original's character set and must declare it.
    ///   This is a builder rule, not a spec echo: §2.9.2.2 lists MSH-3, MSH-4
    ///   and MSH-11 as the copied fields, and MSH-18 is not among them (nor
    ///   in ADR-019 decision 9's original list; amended in P8-8).
    /// - MSA-1: `code`. MSA-2: the original's MSH-10 field, copied so that an
    ///   escape sequence round-trips ("MSH-10 from MSH segment of incoming
    ///   message", v2.5.1 CH02 §2.9.2.2 table).
    ///
    /// Left to the caller: every other MSH field (MSH-8, MSH-13 to MSH-17,
    /// MSH-19 onward), MSA-3 (Text Message, backward compatible from v2.5.1
    /// in favour of ERR), MSA-4 (sequence number protocol), MSA-5 and MSA-6,
    /// and the optional SFT, UAC and ERR segments. To add them, build a new
    /// ``Message`` from the returned message's `segments`.
    ///
    /// The builder has no protocol logic (ADR-019 decision 9): it does not
    /// decide whether, when or with which code to acknowledge, does not read
    /// MSH-15 or MSH-16, does not apply the enhanced-mode rules and does not
    /// run the sequence number protocol. That is receiving-application
    /// behaviour (v2.5.1 CH02 §2.9.2 to §2.9.3); the caller chooses `code`.
    ///
    /// - Parameters:
    ///   - original: The message being acknowledged.
    ///   - code: MSA-1, from HL7 Table 0008.
    ///   - messageControlID: MSH-10 of the acknowledgment itself.
    ///   - dateTime: MSH-7, already formatted for the version (TS to v2.5.1,
    ///     DTM from v2.6).
    /// - Throws: ``BuilderError/acknowledgedMessageControlIDMissing`` when
    ///   `original` has no MSH segment or an empty MSH-10.
    static func acknowledgment(
        to original: Message,
        code: AcknowledgmentCode,
        messageControlID: String,
        dateTime: String
    ) throws -> Message {
        guard let msh = original.segments.first, msh.segmentID == "MSH",
              let controlID = msh.field(10), controlID.isPopulated else {
            throw BuilderError.acknowledgedMessageControlIDMissing
        }
        func echo(_ index: Int) -> Field { msh.field(index) ?? .scalar("") }
        let event = msh.field(9)?.first?.components.dropFirst().first ?? Component.scalar("")
        var messageType = [Component.scalar("ACK"), event]
        if original.version != .v2_3 { messageType.append(.scalar("ACK")) }
        while messageType.count > 1, messageType.last?.isEmpty == true { messageType.removeLast() }
        let separators = original.encodingCharacters
        var builder = MessageBuilder(
            version: original.version,
            encodingCharacters: separators,
            characterEncoding: original.characterEncoding
        )
        var fields: [Field] = [
            .scalar(String(separators.fieldSeparator)),  // MSH-1
            .scalar(separators.msh2String),              // MSH-2
            echo(5), echo(6),                            // MSH-3/4: the original receiver
            echo(3), echo(4),                            // MSH-5/6: the original sender
            .scalar(dateTime),                           // MSH-7
            .scalar(""),                                 // MSH-8
            Field(repetitions: [Repetition(components: messageType)]),  // MSH-9
            .scalar(messageControlID),                   // MSH-10
            echo(11),                                    // MSH-11
            echo(12),                                    // MSH-12
        ]
        if let charset = msh.field(18), charset.isPopulated {
            fields += Array(repeating: .scalar(""), count: 5) + [charset]  // MSH-13 to 17, MSH-18
        }
        builder.appendSegment(id: "MSH", fields: fields)
        builder.appendSegment(id: "MSA", fields: [.scalar(code.rawValue), controlID])
        return try builder.build()
    }
}

private extension Field {
    // True when any subcomponent of any repetition carries a value.
    var isPopulated: Bool {
        repetitions.contains { $0.components.contains { !$0.isEmpty } }
    }
}

private extension Component {
    var isEmpty: Bool { subcomponents.allSatisfy { $0.value.isEmpty } }
}
