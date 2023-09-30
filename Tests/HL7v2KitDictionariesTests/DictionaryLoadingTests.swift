// DictionaryLoadingTests.swift
// v0.1.0 stub coverage. Sprint 4 will add real dictionary load tests.

import Testing
@testable import HL7v2KitDictionaries

@Suite("HL7v2KitDictionaries scaffold")
struct DictionaryLoadingTests {
    @Test("Scaffold marker is present")
    func scaffoldMarker() {
        #expect(Dictionaries.scaffoldMarker.contains("v0.1.0"))
    }
}
