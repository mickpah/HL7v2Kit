// AnonymiserParticipationTests.swift
// PRT (CH07 7.4.4, from v2.7.1), ROL (from v2.3) and DEV (CH17, v2.9 and 2.9.1) carry the people,
// organisations, places and devices taking part in an order, a result or a role; on v2.9 and 2.9.1
// the ordering provider travels only in PRT. Each identifying field takes the rule its type takes
// elsewhere, under the tool's rule and under a key; the action code, the coded fields and the event
// dates are kept.

import Foundation
import Testing
@testable import HL7v2Kit

@Suite("Anonymiser participation, role and device")
struct AnonymiserParticipationTests {
    static let header = "MSH|^~\\&|SYNTH_APP|TESTFAC|SYNTH_RCV|TESTFAC|20240301120000||ORU^R01^ORU_R01|CTRLPR01|P|2.9.1"

    /// PRT (2.9.1 CH07 7.4.4, pp 89 to 99), ROL (2.9.1 CH15 15.4.7, p 38) and DEV (2.9.1 CH17 17.7.1,
    /// pp 66 to 70) with every field populated.
    /// A repeating field holds two repetitions; each identifying component holds an `ORIG...X` marker.
    static let message: String = {
        let lines: [String] = [
            header,
            "PID|1||SYN-0291^^^TESTFAC^MR||Testpatient^Sample||19000101|U",
            ["PRT|ORIGPRT1X^TESTFAC|UC|SYN-AR^Synthetic reason^L|OP^Ordering Provider^HL70912",
             "|ORIGPRT5X^ORIGPRT5FX^ORIGPRT5GX~ORIGPRT5RX^ORIGPRT5RFX^ORIGPRT5RGX",
             "|SYN-PT^Synthetic provider type^L|SYN-OU^Synthetic unit type^L",
             "|ORIGPRT8X^L^^^^TESTFAC^XX^^^ORIGPRT8IX~ORIGPRT8RX",
             "|ORIGPRT9X^ORIGPRT9RMX^ORIGPRT9BX^TESTFAC~ORIGPRT9RX",
             "|ORIGPRT10X^^2.16.840.1.113883.3.3719^ISO~ORIGPRT10RX",
             "|20240301101500|20240301113000|SYN-QD^Synthetic duration^L",
             "|ORIGPRT14X^^ORIGPRT14CX^NSW^2000^AU^B~ORIGPRT14RX^^ORIGPRT14RCX^NSW^2000^AU^O",
             "|ORIGPRT15X^WPN^PH~^NET^Internet^ORIGPRT15EX@example.invalid",
             "|ORIGPRT16X^^2.51.1.1^ISO|20200101|20300101|ORIGPRT19X|ORIGPRT20X",
             "|ORIGPRT21X^^2.16.840.1.113883.6.18.2.1^ISO|SYN-DT^Synthetic device type^L|E^Email^HL70185",
             "|ORIGPRT24X^SYN^NSW^20301231~ORIGPRT24RX^SYN"].joined(),
            ["ROL|ORIGROL1X^TESTFAC|UC|PP^Primary Care Provider^HL70443",
             "|ORIGROL4X^ORIGROL4FX^ORIGROL4GX~ORIGROL4RX^ORIGROL4RFX^ORIGROL4RGX",
             "|20240101|20240301|SYN-RD^Synthetic duration^L|SYN-RR^Synthetic reason^L",
             "|SYN-PT^Synthetic provider type^L~SYN-PT2^Synthetic provider type^L|SYN-OU^Synthetic unit type^L",
             "|ORIGROL11X^^ORIGROL11CX^NSW^2000^AU^O~ORIGROL11RX^^ORIGROL11RCX^NSW^2000^AU^H",
             "|ORIGROL12X^WPN^PH~ORIGROL12RX^PRN^PH",
             "|ORIGROL13X^ORIGROL13RMX^ORIGROL13BX^TESTFAC|ORIGROL14X^L^^^^TESTFAC^XX^^^ORIGROL14IX"].joined(),
            ["DEV|UC|ORIGDEV2X^^2.16.840.1.113883.3.3719^ISO|SYN-DT^Synthetic device type^L~SYN-DT2^Synthetic device type^L",
             "|SYN-ST^Synthetic status^L|ORIGDEV5X^L^^^^TESTFAC^XX^^^ORIGDEV5IX|ORIGDEV6X|ORIGDEV7X|ORIGDEV8X",
             "|ORIGDEV9X^^2.51.1.1^ISO|ORIGDEV10X|ORIGDEV11X|20200101|20300101",
             "|SYN-SC^Synthetic safety^L~SYN-SC2^Synthetic safety^L|ORIGDEV15X^^2.16.840.1.113883.6.18.2.1^ISO",
             "|ORIGDEV16X|SYN-IS^Synthetic implantation status^L"].joined(),
        ]
        return lines.joined(separator: "\r") + "\r"
    }()

    /// The fields kept: the action code, the coded fields and the event dates (CH07 7.4.4; CH15 15.4.7;
    /// CH17 17.7.1). PRT-22 and DEV-3 name a device type: a UDI there has no serial number (7.4.4.10, p 95).
    /// The dates are kept as other event dates are: one shift per file under the tool, a moved date beside
    /// the same instant in clear (the device dates must match the UDI, p 95) would give the shift away.
    static let kept = ["PRT": [2, 3, 4, 6, 7, 11, 12, 13, 17, 18, 22, 23], "ROL": [2, 3, 5, 6, 7, 8, 9, 10],
                       "DEV": [1, 3, 4, 12, 13, 14, 17]]

    /// `wire` anonymised under key 7, or under the tool's rule with salt 41.
    static func anonymised(_ wire: String, keyed: Bool) throws -> String {
        let anonymiser = keyed ? Anonymiser(key: 7) : Anonymiser(legacySalt: 41)
        return String(decoding: anonymiser.anonymise(try Parser().parse(wire)).serialize(), as: UTF8.self)
    }

    /// Each segment's fields as written, by segment ID (the last of an ID wins).
    static func fields(_ wire: String) -> [String: [String]] {
        var out: [String: [String]] = [:]
        for line in wire.split(separator: "\r") {
            let fields = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            out[fields[0]] = fields
        }
        return out
    }

    @Test("PRT, ROL and DEV keep the action code, coded fields and dates; every repetition of the rest is replaced",
          arguments: [true, false])
    func participationCovered(keyed: Bool) throws {
        let text = try Self.anonymised(Self.message, keyed: keyed)
        let input = Self.fields(Self.message), output = Self.fields(text)
        for (id, kept) in Self.kept {
            let before = try #require(input[id]), after = try #require(output[id])
            #expect(after.count == before.count, "\(id) field count")
            for n in 1..<min(before.count, after.count) {
                let label = "\(id)-\(n), keyed \(keyed)"
                if kept.contains(n) { #expect(after[n] == before[n], "\(label)"); continue }
                let was = before[n].split(separator: "~"), now = after[n].split(separator: "~")
                #expect(now.count == was.count, "\(label) repetitions")
                for (a, b) in zip(was, now) { #expect(!b.isEmpty && b != a, "\(label): \(b)") }
            }
        }
        #expect(!text.contains("ORIG"), "keyed \(keyed)")
    }

    /// One segment: `values` at their field numbers, every other field empty.
    static func segment(_ id: String, _ values: [Int: String]) -> String {
        ([id] + (1...(values.keys.max() ?? 1)).map { values[$0] ?? "" }).joined(separator: "|")
    }

    /// One value of each type, in PRT, ROL and DEV and in a field elsewhere that takes the same rule.
    static let sameValues: String = {
        let (xcn, xad, xtn) = ("ORIGPROVX^ORIGPROVFX^ORIGPROVGX", "ORIGADDRX^^ORIGCITYX^NSW^2000^AU^H", "ORIGPHONEX^PRN^PH")
        let (ei, dtm) = ("ORIGEIX^TESTFAC", "20240301101500")
        return [
            header,
            segment("PID", [1: "1", 3: "SYN-0291^^^TESTFAC^MR", 5: "Testpatient^Sample", 7: dtm, 8: "U", 11: xad, 13: xtn]),
            segment("ORC", [1: "NW", 12: xcn]),
            segment("GSP", [1: "1", 2: "U", 3: ei]),
            segment("PRT", [1: ei, 2: "UC", 4: "OP^Ordering Provider^HL70912", 5: xcn, 10: ei, 11: dtm, 12: dtm,
                            14: xad, 15: xtn, 16: ei, 17: dtm, 18: dtm, 21: ei, 24: "ORIGEIX^SYN^NSW"]),
            segment("ROL", [1: ei, 2: "UC", 3: "PP^Primary Care Provider^HL70443", 4: xcn, 5: dtm, 6: dtm, 11: xad, 12: xtn]),
            segment("DEV", [1: "UC", 2: ei, 5: "ORIGORGX", 9: ei, 10: "ORIGLOTX", 11: "ORIGSERIALX", 12: dtm, 15: ei]),
        ].joined(separator: "\r") + "\r"
    }()

    @Test("A value in PRT, ROL or DEV is written as the same value of its type is elsewhere", arguments: [true, false])
    func sameValueSameOutput(keyed: Bool) throws {
        let out = Self.fields(try Self.anonymised(Self.sameValues, keyed: keyed))
        let pid = try #require(out["PID"]), orc = try #require(out["ORC"]), gsp = try #require(out["GSP"])
        let prt = try #require(out["PRT"]), rol = try #require(out["ROL"]), dev = try #require(out["DEV"])
        #expect(orc[12] != "ORIGPROVX^ORIGPROVFX^ORIGPROVGX" && gsp[3] != "ORIGEIX^TESTFAC" && pid[7] != "20240301101500")
        for (label, value, elsewhere) in [
            ("PRT-5", prt[5], orc[12]), ("ROL-4", rol[4], orc[12]),            // XCN, as ORC-12
            ("PRT-14", prt[14], pid[11]), ("ROL-11", rol[11], pid[11]),        // XAD, as PID-11
            ("PRT-15", prt[15], pid[13]), ("ROL-12", rol[12], pid[13]),        // XTN, as PID-13
            ("PRT-1", prt[1], gsp[3]), ("PRT-10", prt[10], gsp[3]), ("PRT-16", prt[16], gsp[3]),
            ("PRT-21", prt[21], gsp[3]), ("ROL-1", rol[1], gsp[3]),            // EI, as GSP-3
            ("DEV-2", dev[2], prt[10]), ("DEV-9", dev[9], prt[16]), ("DEV-15", dev[15], prt[21]),  // so DEV-2 = PRT-10
            ("DEV-5", dev[5], "[REDACTED]"), ("DEV-10", dev[10], "[REDACTED]"), ("DEV-11", dev[11], "[REDACTED]"),
            ("PRT-11", prt[11], "20240301101500"), ("ROL-5", rol[5], "20240301101500"),  // event dates kept
            ("DEV-12", dev[12], "20240301101500"),
        ] {
            #expect(value == elsewhere, "\(label), keyed \(keyed)")
        }
        // PLN: its ID number replaced as an EI's identifier is; its type, qualifier and expiry date kept.
        #expect(prt[24] == gsp[3].split(separator: "^")[0] + "^SYN^NSW", "PRT-24, keyed \(keyed)")
    }

    @Test("Under a key, the identifier closure is not asked for PRT, ROL or DEV, and assigning authorities are kept")
    func closureNotAsked() throws {
        final class Seen: @unchecked Sendable { var values: [String] = [] }
        let seen = Seen()
        let anonymiser = Anonymiser(key: 7) { identifier in
            seen.values.append(identifier.value)
            return "REPLACED"
        }
        let out = try Parser().parse(anonymiser.anonymise(try Parser().parse(Self.message)).serialize())
        #expect(seen.values == ["SYN-0291"])   // PID-3, a CX
        #expect(out["PRT-1.2"] == "TESTFAC" && out["ROL-1.2"] == "TESTFAC")
        #expect(out["PRT-10.3"] == "2.16.840.1.113883.3.3719" && out["PRT-10.4"] == "ISO")
        #expect(out["PRT-24.2"] == "SYN" && out["PRT-24.3"] == "NSW" && out["PRT-24.4"] == "20301231")
        #expect(out["PRT-14.6"] == "AU" && out["PRT-14.7"] == "B" && out["ROL-12.2"] == "WPN")
        #expect(out["DEV-2.3"] == "2.16.840.1.113883.3.3719" && out["DEV-9.3"] == "2.51.1.1" && out["DEV-15.4"] == "ISO")
    }

    @Test("A second pass under the tool's rule writes PRT, ROL and DEV byte for byte alike")
    func secondPassUnderTheTool() throws {
        let first = try Self.anonymised(Self.message, keyed: false)
        let once = Self.fields(first), twice = Self.fields(try Self.anonymised(first, keyed: false))
        for id in ["PRT", "ROL", "DEV"] { #expect(twice[id] == once[id] && once[id] != nil, "\(id)") }
    }

    @Test("A second pass under a key keeps the kept fields, [REDACTED] and every repetition count")
    func secondPassUnderAKey() throws {
        let first = try Self.anonymised(Self.message, keyed: true)
        let once = Self.fields(first), twice = Self.fields(try Self.anonymised(first, keyed: true))
        for (id, kept) in Self.kept {
            let a = try #require(once[id]), b = try #require(twice[id])
            #expect(a.count == b.count, "\(id)")
            for n in 1..<min(a.count, b.count) {
                if kept.contains(n) || a[n].contains("[REDACTED]") { #expect(b[n] == a[n], "\(id)-\(n)") }
                #expect(b[n].split(separator: "~").count == a[n].split(separator: "~").count, "\(id)-\(n)")
            }
        }
    }
}
