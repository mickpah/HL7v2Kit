// StructureErrorResponse.swift
// S4-3 (ADR-019 amendment "S4-3 error responses"): the short query responses of CH05 5.6.5
// "Query error response" on v2.4 to v2.9 (5.5.5 on 2.9.1). Situations 1 and 2: an error is AE or AR in MSA-1
// "of the applicable query response message"; the response "contains the MSH, MSA, ERR, QAK and
// the query defining segment if available" and "The rest of the message is absent" (v2.5.1
// p 5-61). Situation 3 (no data found): MSA-1 AA and QAK-2 NF; "The Response message contains
// MSH, MSA, QAK, and query defining segment" and the rest is absent (v2.5.1 p 5-61). The DSC
// "is not sent or, if it is", its pointer is null. Such a response is matched against that head
// instead of its full structure. The no-data head also allows an optional ERR after MSA (ruling
// 6, owner, 2026-10-07: an AA reply may carry an informational or warning ERR). v2.3 and v2.3.1 (CH02 2.22) print no rest-absent sentence, so
// their structures carry no rule.

/// The 5.6.5 rule of one query response structure, from `overrides.json` errorResponses.
struct StructureErrorResponse: Sendable, Equatable, Hashable {
    /// The MSA-1 values that make the message an error response (`["AE", "AR"]`).
    let acknowledgmentCodes: [String]
    /// The query defining segments the structure prints (`["QRD", "QRF"]`, `["QPD"]`,
    /// `["ERQ"]`), empty when it prints none (TBR, EDR).
    let querySegments: [String]
    /// The QAK-2 values that, with MSA-1 AA, make the message a no-data response (`["NF"]`,
    /// 5.6.5 Situation 3).
    let noDataQueryStatus: [String]
    /// Where the version prints the rule.
    let citation: String

    init(acknowledgmentCodes: [String], querySegments: [String], noDataQueryStatus: [String] = [], citation: String) {
        self.acknowledgmentCodes = acknowledgmentCodes
        self.querySegments = querySegments
        self.noDataQueryStatus = noDataQueryStatus
        self.citation = citation
    }
}

extension MessageStructure {
    /// The segments 5.6.5 names besides the query defining ones; SFT and UAC sit in the
    /// message header that the structures print after MSH (v2.5 on, v2.6 on). ARV is taken only
    /// from the structure's top level: the HL7 CTO's letter of 29 March 2021 places it "at the
    /// top of the messages" in "any message definition containing" PID, while a body ARV (v2.6 to
    /// v2.8.2) belongs to the rest of the message 5.6.5 says is absent.
    private static let errorResponseSegments: Set<String> = ["MSH", "SFT", "UAC", "MSA", "ARV", "ERR", "QAK", "DSC"]

    /// The MSA-1 value of a no-data response: "returns an Application Accept (AA)" (5.6.5
    /// Situation 3 note).
    private static let noDataAcknowledgmentCode = "AA"

    /// The short-response head of this structure, or nil to match the full structure.
    /// `acknowledgmentCode` (MSA-1) among the rule's codes gives the error response head
    /// (Situations 1 and 2); MSA-1 AA with `queryResponseStatus` (QAK-2) among the rule's
    /// no-data values gives the no-data head (Situation 3), which requires the QAK that carries
    /// the key. Situation 3 names no ERR, but the no-data head allows an optional one (ruling 6,
    /// owner, 2026-10-07): an AA reply may carry a warning or informational ERR (ERR-4 severity
    /// W or I). The segments named are each taken once at their first place in the print (so
    /// ORF_R04 keeps ERR and QAK after QRD), MSH and MSA required and the rest optional; ERR, SFT
    /// and ARV keep their printed repetition. An ERR the structure does not print goes after MSA,
    /// or after an ARV directly following MSA, and a QAK after ERR, as 5.6.5 Situation 2 lists them.
    /// Slots are not entered.
    func errorResponseHead(acknowledgmentCode: String?, queryResponseStatus: String? = nil) -> MessageStructure? {
        guard let rule = errorResponse, let code = acknowledgmentCode else { return nil }
        let noData: Bool
        if rule.acknowledgmentCodes.contains(code) {
            noData = false
        } else if code == Self.noDataAcknowledgmentCode, let status = queryResponseStatus,
                  rule.noDataQueryStatus.contains(status) {
            noData = true
        } else {
            return nil
        }
        let named = Self.errorResponseSegments.union(rule.querySegments)
        var head: [StructureElement] = []
        var seen: Set<String> = []
        func walk(_ elements: [StructureElement], topLevel: Bool) {
            for element in elements {
                switch element {
                case .segment(let id, _, let max) where named.contains(id) && !seen.contains(id) && (topLevel || id != "ARV"):
                    seen.insert(id)
                    let required = id == "MSH" || id == "MSA" || (noData && id == "QAK")
                    let repeats = id == "SFT" || id == "ERR" || id == "ARV"
                    head.append(.segment(id, min: required ? 1 : 0, max: repeats ? max : 1))
                case .slot:
                    continue
                default:
                    walk(element.children, topLevel: false)
                }
            }
        }
        walk(elements, topLevel: true)
        func insert(_ id: String, after previous: String, min: Int = 0) {
            guard !seen.contains(id), let at = head.firstIndex(where: { $0.label == previous }) else { return }
            head.insert(.segment(id, min: min, max: 1), at: at + 1)
            seen.insert(id)
        }
        let arvFollowsMSA = zip(head, head.dropFirst()).contains { $0.label == "MSA" && $1.label == "ARV" }
        insert("ERR", after: arvFollowsMSA ? "ARV" : "MSA")
        insert("QAK", after: "ERR", min: noData ? 1 : 0)
        let shape = head.map { element -> String in
            guard case .segment(let id, let min, let max) = element else { return element.label }
            let item = max == 1 ? id : "{\(id)}"
            return min == 0 ? "[\(item)]" : item
        }.joined(separator: " ")
        let why = noData
            ? "MSA-1 is AA and QAK-2 is \(queryResponseStatus ?? ""), so \(id) is matched as its no-data query response"
            : "MSA-1 is \(code), so \(id) is matched as its query error response"
        return MessageStructure(
            id: id, version: version, triggers: triggers,
            citation: "\(why), \(shape), the rest of the message absent (\(rule.citation)); the full structure: \(citation)",
            profile: profile, baseVersion: baseVersion, rule: self.rule, aliasOf: aliasOf,
            keySelection: noData ? "MSA-1=AA,QAK-2=\(queryResponseStatus ?? "")" : "MSA-1=\(code)",
            elements: head)
    }

    /// ``errorResponseHead(acknowledgmentCode:queryResponseStatus:)`` with MSA-1 (the first
    /// MSA's field 1, component 1) and QAK-2 (the first QAK's field 2, component 1) read from
    /// `message`.
    func errorResponseHead(in message: Message) -> MessageStructure? {
        guard errorResponse != nil else { return nil }
        func read(_ segment: String, _ field: Int) -> String? {
            StructureChoiceKey(segmentID: segment, field: field, component: 1, alternatives: [:], citation: "")
                .value(in: message)
        }
        return errorResponseHead(acknowledgmentCode: read("MSA", 1), queryResponseStatus: read("QAK", 2))
    }
}
