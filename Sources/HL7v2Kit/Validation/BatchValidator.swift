// BatchValidator.swift
// Batch-scope validation over a parsed `BatchFile` (M8-C). Runs the
// per-message `Validator` on every contained message and adds the
// batch-envelope rules no single message can carry. This is the
// documented home for the AU batch-scope conformance points that the
// message-scoped `Validator` registered as limitations (M6-B-9):
// HL7au:000022.1 and 000022.3.

import Foundation

/// The result of validating a batch file: per-message reports in
/// document order plus the batch-scope issues no single message can
/// carry (envelope cardinality, batch-level localisation rules).
public struct BatchValidationReport: Sendable, Equatable, Hashable {
    /// Batch-scope issues (file / batch envelope).
    public let batchIssues: [ValidationIssue]

    /// One report per contained message, in document order across all
    /// batch groups.
    public let messageReports: [ValidationReport]

    /// The locale the validation ran under.
    public let locale: HL7Locale

    public init(
        batchIssues: [ValidationIssue],
        messageReports: [ValidationReport],
        locale: HL7Locale = .international
    ) {
        self.batchIssues = batchIssues
        self.messageReports = messageReports
        self.locale = locale
    }

    /// True when there are no batch-scope errors and every contained
    /// message's report is valid.
    public var isValid: Bool {
        !batchIssues.contains { $0.severity == .error }
            && messageReports.allSatisfy(\.isValid)
    }
}

/// Validates a `BatchFile` produced by `BatchParser`: every contained
/// message through the standard `Validator`, plus batch-scope rules.
///
/// Batch-scope rules under `.auLocalisation`:
/// - **Single batch per file** (ADRM-prose:P-7): "In Australia only one
///   Batch is supported" (AU ADRM-2021 §1, p. 19). More than one
///   BHS-headed batch group fires.
/// - **HL7au:000022.3** — "Senders must generate batches containing no
///   more than 1 message", scoped Referrals: a batch group holding a
///   REF message alongside any other message fires.
/// - **HL7au:000022.1** — "If the batch header is used it must specify
///   individual message acknowledgement." BHS carries no
///   acknowledgement field; the individual-acknowledgement mode is
///   carried by each contained message's MSH-15/16, which the
///   per-message AU rules (HL7au:00047.1/.2, MSH-15/16 = AL) enforce
///   on every batched message this validator runs. The point's second
///   half ("no information from the file header/footer or batch
///   segments must be used") is receiver processing behaviour and is
///   not decidable from the file.
/// - **HL7au:000024.1 to .5** — "FHS, BHS, and MSH segments must
///   specify" the AU delimiters `|^~\&` (Appendix 5, pp. 440 to 441).
///   The FHS and BHS legs are checked here on the raw header, scoped by
///   the messages the header carries: the field separator and the
///   component separator on Orders, Results and Referrals, all four
///   encoding characters on Orders and Results.
public struct BatchValidator: Sendable {
    public let locale: HL7Locale
    public let options: ValidationOptions

    public init(options: ValidationOptions = .default, locale: HL7Locale = .international) {
        self.options = options
        self.locale = locale
    }

    /// Validate every message in the file and apply the batch-scope
    /// rules. Never throws — like `Validator`, all findings are
    /// collected into the report.
    public func validate(_ file: BatchFile) -> BatchValidationReport {
        let validator = Validator(options: options, locale: locale)
        let messageReports = file.batches.flatMap { group in
            group.messages.map { validator.validate($0) }
        }

        var batchIssues: [ValidationIssue] = []
        if locale == .auLocalisation {
            checkSingleBatchPerFile(file, issues: &batchIssues)
            checkReferralBatchSize(file, issues: &batchIssues)
            if let header = file.fileHeader {
                checkDelimiters(header, segmentIndex: 1, messages: file.allMessages, issues: &batchIssues)
            }
            for (index, group) in file.batches.enumerated() {
                guard let header = group.header else { continue }
                checkDelimiters(header, segmentIndex: index + 1, messages: group.messages, issues: &batchIssues)
            }
        }

        return BatchValidationReport(
            batchIssues: batchIssues,
            messageReports: messageReports,
            locale: locale
        )
    }

    /// ADRM-prose:P-7 — "In Australia only one Batch is supported"
    /// (p. 19). Counts BHS-HEADED groups only: a bare-MSH stream with
    /// no BHS parses as one header-less group and is not a "Batch".
    private func checkSingleBatchPerFile(
        _ file: BatchFile,
        issues: inout [ValidationIssue]
    ) {
        let headedGroups = file.batches.filter { $0.header != nil }
        guard headedGroups.count > 1 else { return }
        let citation = "ADRM-prose:P-7 — in Australia only one Batch is supported per file; AU ADRM-2021 §1 p. 19"
        issues.append(ValidationIssue(
            severity: .error,
            code: .profileConstraintViolation(localeRule: citation),
            location: IssueLocation(segmentID: "BHS", segmentIndex: 2),
            message: "AU batch rule violated: the file carries \(headedGroups.count) BHS-headed batches but only one Batch is supported (\(citation))"
        ))
    }

    /// HL7au:000022.3 — "Senders must generate batches containing no
    /// more than 1 message" (Senders, Referrals; Appendix 5 p. 440).
    /// Scoped by content: fires on a group that carries a REF message
    /// together with any other message. Non-referral batches "can
    /// contain any number of messages" (p. 19) and stay silent.
    private func checkReferralBatchSize(
        _ file: BatchFile,
        issues: inout [ValidationIssue]
    ) {
        for (index, group) in file.batches.enumerated() where group.messages.count > 1 {
            guard group.messages.contains(where: { $0.messageCode == "REF" }) else { continue }
            let citation = "HL7au:000022.3 — Senders must generate batches containing no more than 1 message on Referrals; AU ADRM-2021 Appendix 5 p. 440"
            issues.append(ValidationIssue(
                severity: .error,
                code: .profileConstraintViolation(localeRule: citation),
                location: IssueLocation(segmentID: "BHS", segmentIndex: index + 1),
                message: "AU batch rule violated: batch \(index + 1) carries a referral (REF) among \(group.messages.count) messages but referral batches must contain no more than 1 message (\(citation))"
            ))
        }
    }

    /// HL7au:000024.1 to .5 on FHS and BHS (P12 S2-2). Each point reads
    /// "FHS, BHS, and MSH segments must specify the ..." (Appendix 5,
    /// .1 p. 440, .2 to .5 p. 441); the MSH legs are profile rules. The
    /// header is the raw segment string, so the field separator is the
    /// character after the segment ID and the encoding characters run to
    /// the next field separator. Scoped by the messages the header
    /// carries, as the points are: .1 and .2 on Orders, Results and
    /// Referrals; .3, .4 and .5 on Orders and Results. As on MSH, the
    /// four encoding characters are one literal on ORM/ORU and only the
    /// component separator is checked when the scope is Referrals alone.
    private func checkDelimiters(
        _ header: String,
        segmentIndex: Int,
        messages: [Message],
        issues: inout [ValidationIssue]
    ) {
        let segmentID = String(header.prefix(3))
        let codes = Set(messages.compactMap(\.messageCode))
        guard !codes.isDisjoint(with: ["ORM", "ORU", "REF"]),
              let separator = header.dropFirst(3).first else { return }
        func report(_ field: Int, _ citation: String, _ detail: String) {
            issues.append(ValidationIssue(
                severity: .error,
                code: .profileConstraintViolation(localeRule: citation),
                location: IssueLocation(segmentID: segmentID, segmentIndex: segmentIndex, fieldIndex: field),
                message: "AU batch rule violated at \(segmentID)-\(field): \(detail) (\(citation))"
            ))
        }
        if separator != "|" {
            report(1, "HL7au:000024.1 — \(segmentID)-1 field separator must be \"|\"; AU ADRM-2021 Appendix 5 p. 440",
                   "field separator is \"\(separator)\"")
        }
        let encoding = String(header.dropFirst(4).prefix { $0 != separator })
        if !codes.isDisjoint(with: ["ORM", "ORU"]) {
            if encoding != "^~\\&" {
                report(2, "HL7au:000024.2/.3/.4/.5 — \(segmentID)-2 encoding characters must be \"^~\\&\" (component, repeat, escape, sub-component); AU ADRM-2021 Appendix 5 p. 441",
                       "encoding characters are \"\(encoding)\"")
            }
        } else if !encoding.hasPrefix("^") {
            report(2, "HL7au:000024.2 — \(segmentID)-2 must specify the component separator as \"^\" on Referrals; AU ADRM-2021 Appendix 5 p. 441",
                   "encoding characters are \"\(encoding)\"")
        }
    }
}
