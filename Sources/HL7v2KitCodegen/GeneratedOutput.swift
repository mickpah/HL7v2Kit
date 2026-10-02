// GeneratedOutput.swift
// Writes one generated output directory all-or-nothing: every file is rendered
// before this is called, so a render failure leaves the directory untouched.
// Any entry in the directory that this run did not produce is stale (a segment
// or composite whose schema was removed or renamed) and is deleted, so the
// directory always equals the run's output and the codegen-drift check sees a
// stale committed file as a deletion.

import Foundation

/// Writes `rendered` into `directory`, then deletes every entry there that the run did not produce.
func writeGeneratedDirectory(_ rendered: [(file: URL, source: String)], into directory: URL) throws {
    let fm = FileManager.default
    try fm.createDirectory(at: directory, withIntermediateDirectories: true)
    for (outFile, source) in rendered {
        try Data(source.utf8).write(to: outFile)
        print("emitted \(outFile.path)")
    }
    let produced = Set(rendered.map { $0.file.lastPathComponent })
    for entry in try fm.contentsOfDirectory(atPath: directory.path).sorted() where !produced.contains(entry) {
        try fm.removeItem(at: directory.appendingPathComponent(entry))
        print("removed stale \(directory.appendingPathComponent(entry).path)")
    }
}
