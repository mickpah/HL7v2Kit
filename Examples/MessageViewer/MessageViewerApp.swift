import AppKit
import HL7v2Kit
import SwiftUI

/// A window with a message editor above and the message as a grid below: one row per segment,
/// one cell per field, the cell tinted yellow for a warning and red for an error. The pane
/// under the grid names the cell under the pointer and lists its issues. Run with
/// `swift run MessageViewer`.
@main
struct MessageViewerApp: App {
    @StateObject private var document = Document()

    init() {
        // `swift run` has no app bundle; without this the window opens behind the terminal.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup("MessageViewer") {
            ContentView(document: document).frame(minWidth: 900, minHeight: 560)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open...") { document.open() }.keyboardShortcut("o")
            }
            CommandGroup(after: .pasteboard) {
                Button("Copy Issues") { document.copyIssues() }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                    .disabled(document.grid == nil)
            }
        }
    }
}

/// The message text, the chosen preset and the grids computed from them.
@MainActor
final class Document: ObservableObject {
    @Published var text = sample { didSet { cache = [:]; ensure() } }
    @Published var strictAU = false { didSet { ensure() } }
    // One grid per preset, kept until the message changes, so switching presets is instant and
    // a hover (also a state change) never re-validates. The work runs off the main thread.
    @Published private(set) var cache: [Bool: Outcome] = [:]
    private var work: Task<Void, Never>?

    enum Outcome: Sendable {
        case grid(CellGrid)
        case failure(String)
    }

    var outcome: Outcome? { cache[strictAU] }
    var grid: CellGrid? {
        if case .grid(let grid)? = outcome { return grid }
        return nil
    }

    /// Computes the grid for the current preset unless it is cached. Edits are debounced.
    func ensure() {
        guard cache[strictAU] == nil else { return }
        work?.cancel()
        let text = text, strict = strictAU
        work = Task {
            guard (try? await Task.sleep(nanoseconds: 250_000_000)) != nil else { return }
            let outcome = await Task.detached(priority: .userInitiated) { Self.compute(text, strict: strict) }.value
            if !Task.isCancelled { cache[strict] = outcome }
        }
    }

    nonisolated private static func compute(_ text: String, strict: Bool) -> Outcome {
        do {
            let message = try Parser().parse(CellGrid.wire(from: text))
            let validator = strict
                ? Validator(options: .strict, locale: .auLocalisation)
                : Validator(options: .default)
            return .grid(CellGrid(message: message, report: validator.validate(message)))
        } catch {
            return .failure(String(describing: error))
        }
    }

    /// File > Open: reads the file as UTF-8, or Latin-1 when it is not UTF-8.
    func open() {
        let panel = NSOpenPanel()
        panel.message = "Choose an HL7 v2 message file"
        guard panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) else { return }
        guard let read = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return }
        text = read
    }

    /// Edit > Copy Issues: every issue of the current grid, one per line.
    func copyIssues() {
        guard let grid else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(grid.issuesText, forType: .string)
    }
}

/// The same synthetic v2.4 ORU^R01 as the QuickStart example: no real identifiers.
private let sample = [
    #"MSH|^~\&|SYNTH_LAB|SYNTH_PATH|SYNTH_EMR|SYNTH_CLINIC|20260101120000+1000||ORU^R01^ORU_R01|SYN-MSG-0001|P|2.4"#,
    #"PID|1||SYN-000123^^^SYNTH_PATH^MR||Synthetic^Alex^^^^^L||1980-01-01|F|||1 Example Street^^Sydney^NSW^2000^AUS||(02) 5550 1234^PRN^PH"#,
    #"PV1|1|O"#,
    #"OBR|1|SYN-ORD-0001|SYN-FIL-0001|2951-2^Sodium^LN|||20260101100000+1000|||||||||||||||20260101115000+1000||CH|F"#,
    #"OBX|1|NM|2951-2^Sodium^LN||140|mmol/L^mmol/L^UCUM|135-145|N|||F"#,
].joined(separator: "\n")

struct ContentView: View {
    @ObservedObject var document: Document
    @State private var hovered: Cell?

    private let mono = Font.system(.body, design: .monospaced)

    var body: some View {
        VSplitView {
            editor
            VStack(spacing: 0) {
                grid
                Divider()
                detail
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Validation", selection: $document.strictAU) {
                    Text("Default").tag(false)
                    Text("Strict, AU").tag(true)
                }
                .pickerStyle(.segmented)
                .help("The validation preset applied to the message")
            }
            ToolbarItem {
                Button("Copy Issues") { document.copyIssues() }
                    .disabled(document.grid == nil)
                    .help("Copy every issue, one per line")
            }
        }
        .navigationTitle("MessageViewer")
        .navigationSubtitle(subtitle)
        .onAppear(perform: document.ensure)
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Message")
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.top, 8)
            TextEditor(text: $document.text)
                .font(mono)
                .padding(.horizontal, 8)
        }
        .frame(minHeight: 140)
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var subtitle: String {
        guard let grid = document.grid else { return "" }
        let s = grid.rows.count, e = grid.errorCount, w = grid.warningCount
        return "\(s) segment\(s == 1 ? "" : "s"), \(e) error\(e == 1 ? "" : "s"), \(w) warning\(w == 1 ? "" : "s")"
    }

    @ViewBuilder private var grid: some View {
        switch document.outcome {
        case nil where document.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty:
            placeholder("Paste an HL7 v2 message above.")
        case nil:
            placeholder("Validating")
        case .failure(let error):
            placeholder(error)
        case .grid(let grid):
            ScrollView([.horizontal, .vertical]) {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(grid.rows.indices, id: \.self) { r in
                        HStack(spacing: 3) {
                            ForEach(grid.rows[r].cells.indices, id: \.self) { c in
                                cell(grid.rows[r].cells[c], isHeader: c == 0)
                            }
                        }
                    }
                    ForEach(grid.unplaced, id: \.self) {
                        Text($0).font(mono).foregroundColor(.secondary).padding(.top, 6)
                    }
                }
                .padding(12)
            }
            .background(Color(nsColor: .controlBackgroundColor))
        }
    }

    private func placeholder(_ message: String) -> some View {
        VStack {
            Spacer()
            Text(message).foregroundColor(.secondary).multilineTextAlignment(.center).padding()
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func cell(_ cell: Cell, isHeader: Bool) -> some View {
        let isHovered = hovered == cell
        return Text(cell.text.isEmpty ? " " : cell.text)
            .font(isHeader ? mono.weight(.semibold) : mono)
            .foregroundColor(.primary)
            .textSelection(.enabled)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 4).fill(fill(cell.state, isHeader: isHeader)))
            .overlay(RoundedRectangle(cornerRadius: 4)
                .stroke(isHovered ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: isHovered ? 2 : 1))
            .onHover { inside in hovered = inside ? cell : (hovered == cell ? nil : hovered) }
    }

    private func fill(_ state: CellState, isHeader: Bool) -> Color {
        switch state {
        case .clean: return isHeader ? Color(nsColor: .windowBackgroundColor) : Color(nsColor: .textBackgroundColor)
        case .warning: return Color(nsColor: .systemYellow).opacity(0.45)
        case .error: return Color(nsColor: .systemRed).opacity(0.4)
        }
    }

    // The pane has a fixed height on purpose: if it grew with its text the grid would shift under
    // the pointer, the hover would change, and the two would chase each other until the window
    // hung. (A `.help` tooltip on every cell hung it the same way.)
    private var detail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                if let cell = hovered {
                    Text(cell.title).font(.headline)
                    if cell.notes.isEmpty {
                        Text("No issues.").foregroundColor(.secondary)
                    }
                    ForEach(cell.notes, id: \.self) { note in
                        let parts = note.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(parts[0].capitalized)
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(parts[0] == "error" ? .red : parts[0] == "warning" ? .orange : .secondary)
                                .frame(width: 64, alignment: .leading)
                            Text(parts.count > 1 ? parts[1] : note).textSelection(.enabled)
                        }
                    }
                } else {
                    Text("Move the pointer over a cell to see its name and any issues.")
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(12)
        }
        .frame(height: 120)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
