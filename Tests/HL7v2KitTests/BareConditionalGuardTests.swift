// BareConditionalGuardTests.swift
// P4-15 (V23-C10, V24-C09, and the P7 intake guard row for v2.3.1/v2.5.1/
// v2.6): the conditionals that remain bare (C with no condition and no
// prohibitedWhen) on each pre-v2.8.2 version are pinned, so a schema edit
// cannot add or drop one without docs/design/conditional-completeness-audit.md
// following. `bareConditionals(_:)` (TestSupport.swift) is the same set
// construction v282M2PermanentLimitationsGuard uses in MultiVersionTests, so
// the two guards cannot drift apart.
//
// The literal sets below are the live output of `bareConditionals`, not the
// pre-P4 predictions in the task brief: P1's OBR optionality changes moved
// OBR-1/8/9/10/11/20/21/26/32 (v2.3) and OBR-1/8/9/10/11/20/21/26/32 (v2.4)
// to `O`; P4-12 shipped conditions for AIG-3/9, AIL-3/7 and AIP-3/7 (its
// AIS-2/AIL-2/AIP-2/RGS-2 "Segment Action Code" reading stayed bare, outcome
// B); P4-17 shipped PRC-5 and, on v2.4, RXO-1/2/4; P4-26 shipped OBX-5's
// `OBX-11 = O` rule on every version from v2.3.1 (v2.3's table has no `O`
// status, so OBX-5 stays bare there alone). OBR-14 is already registered
// (P1-1: "not wire-decidable", conditional-completeness-audit.md's inventory
// table) rather than newly found here.

import Testing
@testable import HL7v2Kit

@Suite("Bare-C guards (P4-15)")
struct BareConditionalGuardTests {

    @Test("v2.3 bare-C set matches the conditional-completeness register")
    func v23BareC() {
        let expected: Set<String> = [
            "AIL-2", "AIP-2", "AIS-2", "AIS-5", "ARQ-2", "ARQ-3", "AUT-6", "CSP-4",
            "OBR-1", "OBR-14", "OBR-22", "OBX-4", "OBX-5", "PTH-6", "PV2-1", "QAK-1", "RGS-2",
            "RXA-7", "RXA-11", "RXA-12", "RXD-5", "RXD-8", "RXD-13",
            "RXE-8", "RXE-10", "RXE-11", "RXE-13", "RXE-15", "RXE-16", "RXE-17", "RXE-18", "RXE-19", "RXE-22",
            "RXG-14", "RXO-14", "RXO-15", "RXO-17", "SCH-2", "SCH-3", "TXA-11", "TXA-21",
        ]
        let actual = bareConditionals(SegmentGrammarTable.v2_3)
        #expect(actual == expected, "v2.3 bare-C set drifted from the register; got \(actual.sorted())")
    }

    @Test("v2.3.1 bare-C set matches the conditional-completeness register")
    func v231BareC() {
        let expected: Set<String> = [
            "AIG-2", "AIL-2", "AIP-2", "AIS-2", "AIS-5", "ARQ-2", "ARQ-3", "AUT-6", "CSP-4",
            "OBR-14", "OBR-22", "OBX-4", "PTH-6", "PV2-1", "QAK-1", "RGS-2",
            "RXA-7", "RXA-11", "RXA-12", "RXD-5", "RXD-8", "RXD-13",
            "RXE-8", "RXE-10", "RXE-11", "RXE-13", "RXE-15", "RXE-16", "RXE-17", "RXE-18", "RXE-19", "RXE-22",
            "RXG-14", "RXO-14", "RXO-15", "RXO-17", "SCH-3", "SCH-24", "TXA-11", "TXA-21",
        ]
        let actual = bareConditionals(SegmentGrammarTable.v2_3_1)
        #expect(actual == expected, "v2.3.1 bare-C set drifted from the register; got \(actual.sorted())")
    }

    @Test("v2.4 bare-C set matches the conditional-completeness register")
    func v24BareC() {
        let expected: Set<String> = [
            "AIG-2", "AIL-2", "AIP-2", "AIS-2", "AIS-5",
            "ARQ-2", "ARQ-3", "ARQ-24", "AUT-6", "CSP-4", "EQU-3",
            "OBR-14", "OBR-22", "OBX-4", "PTH-6", "QAK-1", "QPD-2", "RCP-4", "RGS-2", "ROL-1",
            "RXA-7", "RXA-11", "RXA-12", "RXD-5", "RXD-8", "RXD-13",
            "RXE-8", "RXE-10", "RXE-11", "RXE-13", "RXE-15", "RXE-16", "RXE-17", "RXE-18", "RXE-19", "RXE-22",
            "RXG-14", "RXO-5", "RXO-14", "RXO-15", "RXO-17",
            "SAC-3", "SAC-4", "SCH-3", "SCH-24", "SCH-26", "SID-1", "SID-2", "SID-3", "SID-4", "TXA-11", "TXA-21",
        ]
        let actual = bareConditionals(SegmentGrammarTable.v2_4)
        #expect(actual == expected, "v2.4 bare-C set drifted from the register; got \(actual.sorted())")
    }

    @Test("v2.5.1 bare-C set matches the conditional-completeness register")
    func v251BareC() {
        let expected: Set<String> = [
            "AIG-2", "AIL-2", "AIP-2", "AIS-2", "AIS-5",
            "ARQ-2", "ARQ-3", "ARQ-24", "AUT-6", "CER-12", "CSP-4", "EQU-3", "IAM-7",
            "OBR-22", "OBR-48", "OBX-4", "PTH-6", "QAK-1", "QPD-2", "RCP-4", "RGS-2", "ROL-1",
            "RXA-7", "RXA-11", "RXA-12", "RXD-5", "RXD-8", "RXD-13",
            "RXE-10", "RXE-11", "RXE-13", "RXE-15", "RXE-16", "RXE-17", "RXE-18", "RXE-19", "RXE-22",
            "RXG-14", "RXO-5", "RXO-14", "RXO-15", "RXO-17",
            "SAC-3", "SAC-4", "SAC-6", "SCH-3", "SCH-24", "SCH-26",
            "SID-1", "SID-2", "SID-3", "SID-4", "TXA-11", "TXA-21",
        ]
        let actual = bareConditionals(SegmentGrammarTable.v2_5_1)
        #expect(actual == expected, "v2.5.1 bare-C set drifted from the register; got \(actual.sorted())")
    }

    @Test("v2.6 bare-C set matches the conditional-completeness register")
    func v26BareC() {
        let expected: Set<String> = [
            "ADJ-7", "AIG-2", "AIL-2", "AIP-2", "AIS-2", "AIS-5",
            "ARQ-2", "ARQ-3", "ARQ-24", "AUT-6", "CER-12", "CSP-4", "DG1-22",
            "DMI-2", "DMI-3", "DMI-4", "DMI-5", "EQU-3", "GOL-22", "IAM-7", "IVC-23",
            "OBR-22", "OBR-48", "OBX-4", "OBX-22", "PRB-28",
            "PSL-10", "PSL-12", "PSL-13", "PSL-14", "PSL-15", "PSL-16", "PTH-6", "PTH-7",
            "QAK-1", "QPD-2", "RCP-4", "REL-1", "RGS-2", "ROL-1",
            "RXA-7", "RXA-12", "RXD-5", "RXD-8",
            "RXE-10", "RXE-11", "RXE-13", "RXE-15", "RXE-16", "RXE-17", "RXE-18", "RXE-19", "RXE-22",
            "RXG-14", "RXO-5", "RXO-14", "RXO-15", "RXO-17", "RXO-31",
            "SAC-3", "SAC-4", "SAC-6", "SCH-3", "SCH-24", "SCH-26",
            "SID-1", "SID-2", "SID-3", "SID-4", "TXA-11", "TXA-21", "TXA-22",
        ]
        let actual = bareConditionals(SegmentGrammarTable.v2_6)
        #expect(actual == expected, "v2.6 bare-C set drifted from the register; got \(actual.sorted())")
    }
}
