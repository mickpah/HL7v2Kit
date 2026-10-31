// Path+Description.swift
// The string form of a Path (P00 S2-1). A conformance, so it lives outside the kernel
// file (ADR-006).

extension Path: CustomStringConvertible {
    /// The path in the native syntax (`OBX[2]-5~1.3`), with `[*]` for a wildcard. A
    /// repetition wildcard has no native spelling, so it is written as the alternative
    /// syntax writes it (`PID-3[*].1`). For every path the string parser produces,
    /// `Path(path.description) == path`. A path the string parser cannot produce, a
    /// subcomponent without a component, prints as `PID-3..2`, which does not parse back.
    public var description: String {
        var text = segmentID
        if segmentWildcard {
            text += "[*]"
        } else if let segmentIndex {
            text += "[\(segmentIndex)]"
        }
        text += "-\(field)"
        if repetitionWildcard {
            text += "[*]"
        } else if let repetition {
            text += "~\(repetition)"
        }
        if let component {
            text += ".\(component)"
        } else if subcomponent != nil {
            // Only the memberwise initialiser builds a subcomponent without a component;
            // show it rather than drop it.
            text += "."
        }
        if let subcomponent { text += ".\(subcomponent)" }
        return text
    }
}
