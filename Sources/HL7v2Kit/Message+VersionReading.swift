// Message+VersionReading.swift
// How the message's own MSH-12 names its version, apart from the version it is read under.

extension Message {
    /// How MSH-12 of this message names its version: empty, a modelled version, or content
    /// from which no modelled version resolves.
    ///
    /// It reads MSH-12 itself, so it can differ from ``version``: a message whose MSH-12
    /// resolves to no version is parsed as v2.5.1, and `ParserOptions.versionOverride`
    /// replaces whatever MSH-12 says. The ``Validator`` reports an unresolved MSH-12 as
    /// ``IssueCode/versionNotRecognised(wireValue:)`` from this same reading; here it is known
    /// as soon as the message is parsed. For MSH-12 as written use ``wireText(at:)``.
    public var msh12Reading: Version.MSH12Reading {
        let msh12 = segments.first.flatMap { $0.segmentID == "MSH" ? $0.field(12) : nil }
        return Version.reading(msh12: msh12, subcomponentSeparator: encodingCharacters.subcomponentSeparator)
    }
}
