import AppKit
import HL7v2Kit
import SwiftUI

/// A window with a message editor above and the message as a grid below: one row per segment,
/// one cell per field, the cell white when the field draws nothing, yellow for a warning and red
/// for an error. Hover a cell for its name and the issues on it. Run with `swift run MessageViewer`.
@main
struct MessageViewerApp: App {
    init() {
        // `swift run` has no app bundle; without this the window opens behind the terminal.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup("HL7v2Kit MessageViewer") {
            ContentView().frame(minWidth: 900, minHeight: 500)
        }
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
    @State private var text = sample
    @State private var strictAU = false
    @State private var hovered: Cell?
    // One grid per preset, kept until the message changes, so switching presets is instant and
    // a hover (also a state change) never re-validates. The work runs off the main thread.
    @State private var cache: [Bool: Outcome] = [:]
    @State private var work: Task<Void, Never>?

    enum Outcome: Sendable {
        case grid(CellGrid)
        case failure(String)
    }

    var body: some View {
        VSplitView {
            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 120)
            VStack(alignment: .leading, spacing: 8) {
                Picker("Validation", selection: $strictAU) {
                    Text("Default").tag(false)
                    Text("Strict, AU").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 320)
                // The hovered cell's name and issues. Fixed height: if this panel grew with its
                // text the grid would shift under the pointer, the hover would change, and the
                // two would chase each other until the window hung. (A `.help` tooltip on every
                // cell hung it too.)
                ScrollView {
                    Text(hovered?.tooltip ?? "Hover a cell for its name and any issues.")
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(6)
                }
                .frame(height: 96)
                .background(Color.gray.opacity(0.15))
                grid
            }
            .padding(8)
        }
        .onAppear(perform: ensure)
        .onChange(of: text) { _ in cache = [:]; ensure() }
        .onChange(of: strictAU) { _ in ensure() }
    }

    /// Computes the grid for the current preset unless it is cached. Edits are debounced.
    private func ensure() {
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

    @ViewBuilder private var grid: some View {
        switch cache[strictAU] {
        case nil:
            Text("Validating...")
            Spacer()
        case .failure(let error):
            Text(error).foregroundColor(.red)
            Spacer()
        case .grid(let grid):
            ScrollView([.horizontal, .vertical]) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(grid.rows.indices, id: \.self) { r in
                        HStack(spacing: 2) {
                            ForEach(grid.rows[r].cells.indices, id: \.self) { c in
                                cell(grid.rows[r].cells[c])
                            }
                        }
                    }
                    ForEach(grid.unplaced, id: \.self) { Text($0).foregroundColor(.red) }
                }
                .padding(2)
            }
        }
    }

    private func cell(_ cell: Cell) -> some View {
        Text(cell.text.isEmpty ? " " : cell.text)
            .font(.system(.body, design: .monospaced))
            .foregroundColor(.black)   // the cell backgrounds are light in dark mode too
            .padding(4)
            .background(colour(cell.state))
            .border(Color.gray.opacity(0.4))
            .onHover { inside in hovered = inside ? cell : (hovered == cell ? nil : hovered) }
    }

    private func colour(_ state: CellState) -> Color {
        switch state {
        case .clean: return .white
        case .warning: return .yellow
        case .error: return .red
        }
    }
}
