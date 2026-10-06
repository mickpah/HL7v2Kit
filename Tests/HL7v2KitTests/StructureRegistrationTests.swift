// StructureRegistrationTests.swift
// S1-3 (owner decision 8, 2026-10-06): a consumer can tell a structure a
// version registers as not modelled (register section E) from an ID the
// version does not print, and read the registration's triggers and reason.

import Foundation
import Testing
@testable import HL7v2Kit

@Suite("Structure registration lookup")
struct StructureRegistrationTests {

    @Test("A registered structure returns its triggers and reason")
    func registeredStructure() throws {
        // v2.8.2 QRY_PC4: a Table 0354 row marked Deprecated with no printed syntax (UDM_Q05,
        // the example before S2-2, is modelled since).
        let registration = try #require(MessageStructureTable.registration("QRY_PC4", version: .v2_8_2))
        #expect(registration.id == "QRY_PC4")
        #expect(registration.version == .v2_8_2)
        #expect(registration.triggers == ["QRY^PC4", "QRY^PC9", "QRY^PCE", "QRY^PCK"])
        #expect(registration.reason.hasPrefix("Table 0354 v2.8.2 (CH02C section 2.C.2.279"))
        #expect(registration.reason == MessageStructureTable.notModelled(for: .v2_8_2)["QRY_PC4"]?.reason)
    }

    @Test("A modelled structure and an unknown ID return nil")
    func modelledAndUnknown() {
        #expect(MessageStructureTable.structure("ADT_A01", version: .v2_5_1) != nil)
        #expect(MessageStructureTable.registration("ADT_A01", version: .v2_5_1) == nil)
        #expect(MessageStructureTable.registration("ZZZ_Z01", version: .v2_5_1) == nil)
        #expect(MessageStructureTable.structure("ZZZ_Z01", version: .v2_5_1) == nil)
    }

    @Test("MSH-12 2.8 reads the v2.8.2 register and reports the grammar version")
    func grammarVersionResolution() throws {
        let registration = try #require(MessageStructureTable.registration("QRY_PC4", version: .v2_8))
        #expect(registration.version == .v2_8_2)
        #expect(MessageStructureTable.registrations(for: .v2_8) == MessageStructureTable.registrations(for: .v2_8_2))
    }

    @Test("registrations(for:) lists the whole register of each version, sorted by ID")
    func registrationsPerVersion() {
        // The counts move with the register (Resources/structures/completeness.json,
        // register section E); they are pinned so a change is seen.
        let expected: [(Version, Int)] = [
            (.v2_3, 16), (.v2_3_1, 30), (.v2_4, 29), (.v2_5_1, 24),
            (.v2_6, 12), (.v2_7_1, 45), (.v2_8_2, 57),
        ]
        for (version, count) in expected {
            let list = MessageStructureTable.registrations(for: version)
            #expect(list.count == count, "\(version)")
            #expect(list.count == MessageStructureTable.notModelled(for: version).count, "\(version)")
            #expect(list.map(\.id) == list.map(\.id).sorted(), "\(version)")
            #expect(list.allSatisfy { MessageStructureTable.structure($0.id, version: version) == nil }, "\(version)")
            #expect(list.allSatisfy { MessageStructureTable.registration($0.id, version: version) == $0 }, "\(version)")
        }
    }
}
