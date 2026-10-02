// CompositeView.swift
// Shared mechanics for the typed composite value views (CX / XPN / CWE / …).
//
// Each composite is a value-type view over a Field: the segment still owns
// the data, so round-trip byte-identity is preserved. The mechanics that were
// previously duplicated verbatim across all 16 views — first-repetition
// component access, single-repetition wrapping, and the empty metadata
// defaults — live here. Per-spec accessors, docs, and non-empty metadata
// stay on each conforming type: component names are spec surface. R3.
// Accessors beyond the hand-written set are generated (P9-3, ADR-020).

/// Shared surface of the typed composite views (``CX``, ``XPN``, ``CWE``, …).
///
/// A composite view wraps a ``Field`` without owning the data. Named
/// accessors read from the **first repetition** of the underlying field;
/// use ``field`` to walk further repetitions, or wrap an individual
/// ``Repetition`` via ``init(repetition:)``.
///
/// Every component index that any supported HL7 version defines has a named
/// `String?` accessor (ADR-020). Accessors added after v3.13.0 are generated
/// from the datatype component tables into `Composite/Generated/`; their DocC
/// lists the versions that define each component. A component withdrawn
/// (`W`) in a later version keeps its accessor, because earlier versions
/// define it and a wire can carry it. A component a version prints without a
/// data type takes the type from the newest version that prints one. Open
/// arrays such as `MA` and `NA` have no fixed component indices, so they are
/// not composite views.
public protocol CompositeView: Sendable, Equatable, Hashable {
    /// The underlying ``Field``. Use this when you need access to
    /// repetitions beyond the first. Every component has a named accessor;
    /// use ``component(_:as:)`` for a sub-composite's subcomponents.
    var field: Field { get }

    /// Wrap an entire ``Field``. Accessors read from the first repetition.
    init(field: Field)

    /// Required components for this composite per the HL7 spec.
    /// ``Validator`` consults this when the `checkComponentGrammar` toggle
    /// is on: if the composite is populated but one of these components is
    /// empty, the validator emits ``IssueCode/requiredComponentMissing``.
    /// Empty when the composite has no per-component requirements.
    static var requiredComponents: [RequiredComponent] { get }

    /// Cross-component requirement set (e.g. "identifier + coding system,
    /// or text") for composites whose spec requirements exceed a flat
    /// per-component list. `nil` when the composite has none.
    static var requiredComponentSet: RequiredComponentSet? { get }
}

extension CompositeView {
    /// No per-component requirements unless the conforming type declares them.
    public static var requiredComponents: [RequiredComponent] { [] }

    /// No cross-component requirement set unless the conforming type declares one.
    public static var requiredComponentSet: RequiredComponentSet? { nil }

    /// Wrap a single ``Repetition``. Convenient when iterating
    /// `field.repetitions` and you want typed access to each repetition
    /// in turn.
    public init(repetition: Repetition) {
        self.init(field: Field(repetitions: [repetition]))
    }

    /// The 1-based component `index` of the first repetition, viewed as the
    /// composite `type`: the component's subcomponents become the view's
    /// components. Use it for sub-composites such as ``CX`` component 4 (an
    /// ``HD``): `cx.component(4, as: HD.self)?.universalID`. `nil` when the
    /// component is absent.
    public func component<V: CompositeView>(_ index: Int, as type: V.Type) -> V? {
        guard let rep = field.repetitions.first,
              rep.components.indices.contains(index - 1) else {
            return nil
        }
        let parts = rep.components[index - 1].subcomponents.map { Component(subcomponents: [$0]) }
        return V(field: Field(repetitions: [Repetition(components: parts)]))
    }

    /// The same ``field`` viewed as another composite. Use it where a later
    /// HL7 version retypes a field. For example, OBX-3 is `CE` in v2.5.1 and
    /// `CWE` from v2.6: `obx.observationIdentifier?.viewed(as: CWE.self)`.
    public func viewed<V: CompositeView>(as type: V.Type) -> V {
        V(field: field)
    }

    /// The first-subcomponent value of the 1-based component `index` in the
    /// first repetition, or `nil` when the component is absent.
    func componentValue(_ index: Int) -> String? {
        guard let rep = field.repetitions.first,
              rep.components.indices.contains(index - 1) else {
            return nil
        }
        return rep.components[index - 1].subcomponents.first?.value
    }
}
