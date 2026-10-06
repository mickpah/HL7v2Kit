// StructureErrorResponse.swift
// S4-3 (ADR-019 amendment "S4-3 error responses"): the query error response. CH05 5.6.5 on
// v2.4 to v2.8.2 returns an error as AE or AR in MSA-1 "of the applicable query response
// message"; the response "contains the MSH, MSA, ERR, QAK and the query defining segment if
// available" and "The rest of the message is absent" (v2.5.1 p 5-61); the DSC "is not sent or,
// if it is, its continuation pointer field ... is null". A query response whose MSA-1 is one of
// those codes is therefore matched against that head instead of its full structure. v2.3 and
// v2.3.1 (CH02 2.22) print no such sentence, so their structures carry no rule.

/// The 5.6.5 rule of one query response structure, from `overrides.json` errorResponses.
struct StructureErrorResponse: Sendable, Equatable, Hashable {
    /// The MSA-1 values that make the message an error response (`["AE", "AR"]`).
    let acknowledgmentCodes: [String]
    /// The query defining segments the structure prints (`["QRD", "QRF"]`, `["QPD"]`,
    /// `["ERQ"]`), empty when it prints none (TBR, EDR).
    let querySegments: [String]
    /// Where the version prints the rule.
    let citation: String
}

extension MessageStructure {
    /// The segments 5.6.5 names besides the query defining ones; SFT and UAC sit in the
    /// message header that the structures print after MSH (v2.5 on, v2.6 on).
    private static let errorResponseSegments: Set<String> = ["MSH", "SFT", "UAC", "MSA", "ERR", "QAK", "DSC"]

    /// The error-response head of this structure when `acknowledgmentCode` (MSA-1) is one of
    /// its rule's codes, or nil: the segments 5.6.5 names, each taken once at its first place in
    /// the print (so ORF_R04 keeps ERR and QAK after QRD), MSH and MSA required and the rest
    /// optional; ERR and SFT keep their printed repetition. An ERR the structure does not print
    /// goes after MSA, a QAK after ERR, as 5.6.5 lists them. Slots are not entered.
    func errorResponseHead(acknowledgmentCode: String?) -> MessageStructure? {
        guard let rule = errorResponse, let code = acknowledgmentCode,
              rule.acknowledgmentCodes.contains(code) else { return nil }
        let named = Self.errorResponseSegments.union(rule.querySegments)
        var head: [StructureElement] = []
        var seen: Set<String> = []
        func walk(_ elements: [StructureElement]) {
            for element in elements {
                switch element {
                case .segment(let id, _, let max) where named.contains(id) && !seen.contains(id):
                    seen.insert(id)
                    let required = id == "MSH" || id == "MSA"
                    let repeats = id == "SFT" || id == "ERR"
                    head.append(.segment(id, min: required ? 1 : 0, max: repeats ? max : 1))
                case .slot:
                    continue
                default:
                    walk(element.children)
                }
            }
        }
        walk(elements)
        func insert(_ id: String, after previous: String) {
            guard !seen.contains(id), let at = head.firstIndex(where: { $0.label == previous }) else { return }
            head.insert(.segment(id, min: 0, max: 1), at: at + 1)
            seen.insert(id)
        }
        insert("ERR", after: "MSA")
        insert("QAK", after: "ERR")
        let shape = head.map { element -> String in
            guard case .segment(let id, let min, let max) = element else { return element.label }
            let item = max == 1 ? id : "{\(id)}"
            return min == 0 ? "[\(item)]" : item
        }.joined(separator: " ")
        return MessageStructure(
            id: id, version: version, triggers: triggers,
            citation: "MSA-1 is \(code), so \(id) is matched as its query error response, \(shape), "
                + "the rest of the message absent (\(rule.citation)); the full structure: \(citation)",
            profile: profile, baseVersion: baseVersion, rule: self.rule, aliasOf: aliasOf,
            keySelection: "MSA-1=\(code)", elements: head)
    }

    /// ``errorResponseHead(acknowledgmentCode:)`` with MSA-1 (the first MSA's field 1,
    /// component 1) read from `message`.
    func errorResponseHead(in message: Message) -> MessageStructure? {
        guard errorResponse != nil else { return nil }
        let msa1 = StructureChoiceKey(segmentID: "MSA", field: 1, component: 1, alternatives: [:], citation: "")
        return errorResponseHead(acknowledgmentCode: msa1.value(in: message))
    }
}
