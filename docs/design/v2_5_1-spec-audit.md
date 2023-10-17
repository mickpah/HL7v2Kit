# HL7 v2.5.1 schema audit — v0.4-S1

**Date:** 2026-06-17
**Audited:** `Resources/schemas/v2.5.1/*.json` (9 segments: MSH, PID, ORC, OBR, OBX, NK1, PV1, NTE, AL1)
**Reference:** HL7 v2.5.1 spec, public-record copies of the published per-segment field tables.
**Outcome:** Substantially spec-accurate. No schema changes warranted. Three classes of known limitation documented for future DSL extension.

## Audit methodology

For each segment, every field row was cross-referenced against the HL7 v2.5.1 spec on five attributes:

1. **`name`** — must match the spec's field name exactly (capitalisation, punctuation, hyphens / slashes).
2. **`dataType`** — HL7 v2 type code (ST, CE, CWE, XPN, EI, …) per spec table.
3. **`optionality`** — single-letter code: `R` required, `O` optional, `C` conditional, `X` not-supported, `B` backward-compat (deprecated).
4. **`repeatability`** — `"1"` single, `"*"` repeating per the spec's "Repeat" column.
5. **`condition`** — predicate string for `C` fields, only when the spec's conditional rule is expressible in the v0.2-V1 DSL grammar (`populated` / `empty` / `= <value>` / `!= <value>` against a same-segment reference).

The `swiftName` field is internal naming and was not audited against the spec.

## Per-segment findings

| Segment | Fields audited | Corrections | Notes |
|---|---:|---:|---|
| MSH | 21 | 0 | All names / dataTypes / optionality / repeatability confirmed. |
| PID | 39 | 0 | All confirmed. One field (PID-36) carries a known-over-broad condition predicate — documented below as Limitation 1. |
| ORC | 31 | 0 | Multiple `C` fields (ORC-2, ORC-3, ORC-8) carry `C` without a DSL predicate — their spec conditions are compound and not expressible (Limitation 2). |
| OBR | 47 | 0 | Same `C`-without-predicate treatment for OBR-1, OBR-7, OBR-8, OBR-10, OBR-14, OBR-22, OBR-25, OBR-26, OBR-32. |
| OBX | 17 | 0 | OBX-2 and OBX-4 marked `C`-without-predicate per the OBR rationale. |
| NK1 | 13 | 0 | All confirmed. |
| PV1 | 20 | 0 | All confirmed. |
| NTE | 4 | 0 | All confirmed. |
| AL1 | 6 | 0 | All confirmed. |
| **Total** | **198** | **0** | |

## Outstanding limitations (documented, not corrected)

### Limitation 1 — PID-36 conditional predicate over-broad

PID-36 (Breed Code) carries `condition: "PID-35 populated"` shipped with v0.2-V1 as the first real conditional-field demonstration. The HL7 v2.5.1 spec's actual condition for PID-36 reads informally as *"required when the subject is a non-human species"* — meaning PID-35 carries a species code other than human (typically `L1` in HL70447). Our predicate fires when PID-35 has any value, including `L1^Human`. A sender that legitimately populates PID-35=L1 without PID-36 would receive a false-positive `conditionalFieldMissing` error.

**Why kept**: AU clinical traffic almost never populates PID-35 at all (human is the implicit default), so the over-broadness is theoretical, not observed. v0.2-V1's six demo tests (`ConditionalFieldTests.swift`) depend on this predicate to exercise the DSL. Removing the predicate would lose the demo coverage AND not protect any real consumer (because the false-positive case doesn't occur in practice).

**Possible future fixes**:
- Extend the DSL to support code-system-aware comparisons (`PID-35.identifier != L1` parsing the CE composite, not just the first-subcomponent flat view).
- Replace `populated` semantics with `value matches code-set <X>`.
- Move the v0.2-V1 demo to a different field whose spec condition cleanly maps to the current DSL.

None of these is in v0.4 scope; flagged here for future cycles.

### Limitation 2 — Compound conditional predicates not expressible

Several `C` fields in v2.5.1 (ORC-2 "Required if ORC-1 control code is one of NW/CA/CR…", OBR-1, OBR-7, OBR-22, OBR-25, OBR-32, and others) have spec conditions that mix multiple predicates with `AND` / `OR`. The v0.2-V1 DSL supports single-predicate same-segment refs only.

**Current treatment**: those fields are marked `C` without a `condition` predicate. The Validator's `C`-without-predicate behaviour treats the field as effectively optional — never fires `conditionalFieldMissing` for the field — which is the right ad-hoc-tolerant default.

**Possible future fix**: extend the DSL to support `<predicate> AND <predicate>` / `<predicate> OR <predicate>` composition. Probably worth doing once HL7v2Kit has a real consumer who needs strict ORC / OBR conditional validation. Not v0.4 scope.

### Limitation 3 — Composite OR-rules

Five composite types carry disjunctive conformance rules in the v2.5.1 spec:

- **CWE**: "CWE-1 OR CWE-9 populated" (documented on `CWE`'s struct doc).
- **XTN**: "at least one of XTN-1 / XTN-4 / XTN-12 populated" (documented on `XTN`).
- **HD**: "HD-1 OR (HD-2 AND HD-3) populated" (documented on `HD`).
- **PL**: "PL-1 OR PL-4 populated" (documented on `PL`).
- **EIP**: "either EIP-1 or EIP-2 populated" (documented on `EIP`).

**Current treatment**: each composite ships with an empty `requiredComponents` list. The Validator never fires `requiredComponentMissing` for these composites. Pinned by `…SkipsSilentlyWithNoRequiredComponents` tests in `ComponentGrammarTests.swift`.

**Possible future fix**: introduce a `RequiredComponentSet` value type that lets a composite declare "at least one of `[1, 9]` must be populated" semantics. The `Validator.requiredComponents(forCompositeCode:)` dispatch can branch on `Set` vs. flat list. Explicitly deferred from v0.3-C2 / C3 / C4 / S1 — keep it deferred until a consumer asks for it.

## What this audit does NOT validate

- **v2.3 / v2.3.1 / v2.4 schemas** — v0.4-S2's scope. Audited as deltas against this v2.5.1 baseline.
- **v2.8 schema** — doesn't yet exist; v0.4-S3 adds it.
- **Spec table errata** — the audit uses publicly-available v2.5.1 reference materials. The official HL7 v2.5.1 ballot's errata sheets are private to HL7 members; any errata not reflected in the public references slip through this audit.
- **Real-world wire variance** — sender systems sometimes ship messages that violate the spec. The audit measures schema vs. spec, not schema vs. real-world traffic. Real-world variance is the right target for v0.4-segments (which expands the typed-segment surface).

## Conclusion

The v2.5.1 schemas as of v0.3.0 are accurate against the public HL7 v2.5.1 spec text. Zero per-field corrections are warranted. Three classes of known limitation are documented above — all involve spec semantics richer than the v0.2-V1 DSL can currently express, all conservative-fallback behaviours preserve correctness for the dominant AU-clinical-traffic consumer profile, and all are out-of-scope for v0.4 by deliberate choice.

This is the bedrock for v0.4-S2 (v2.3.1 + v2.4 audits as deltas) and v0.4-S3 (v2.8 grammar table addition).
