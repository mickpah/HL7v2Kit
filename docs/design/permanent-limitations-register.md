# Permanent-limitations register — v0.17 (ROADMAP M2 close-out)

**Compiled:** 2026-07-09 (v0.17 cycle, ROADMAP M2 close-out).
**Purpose:** the single authoritative list of conformance rules HL7v2Kit **cannot** machine-check from the wire, with the reason and the v1.0 freeze decision for each. This closes ROADMAP **M2** — the conformance surface is now, in full, either *shipped* (validated) or *documented here as a permanent limitation with a spec-cited rationale* (req #2 / #3 / #4).

**Scope note:** these are **not defects**. Every entry falls into the fail-safe path (v0.2-V1: an absent/unresolvable predicate evaluates `false`, so the field is treated as optional and never wrongly flagged). A permanent limitation means "the spec states a constraint that no on-the-wire signal lets us decide" — not "we skipped it".

## A. Base-spec conditional-without-condition set

Fully audited in v0.16 — see **`docs/design/conditional-completeness-audit.md`** for the per-field rationale and the guard test. 17 positions: 2 shipped (PD1-15, ORC-26), 15 permanent limitations (OBR-1/8/9/10/11/20/21/22/26/32, OBR-48, OBX-4/5/22, DG1-22). Not repeated here.

**Freeze decision:** acceptable to freeze. Each is discourse-level, data-nature-dependent, peer-comparison, or descriptive-without-cited-MUST; none is wire-decidable. A guard test keeps the set honest across future edits.

## B. AU-localisation (ADRM 2021) narrowings

The machine-checkable HL7au:00044.* CE/CNE/CWE narrowings shipped in v0.13 (ADR-011). The following AU rules are **not** machine-checkable from the wire:

| Rule | What it requires | Why it can't ship | Freeze decision |
|------|------------------|-------------------|-----------------|
| ~~**HL7au:00044.4.3** (CE `<text>`)~~ **SHIPPED caller-asserted (M30, 2026-09-23):** `ValidationOptions.auDisplayIntended = true` applies it; the blank-allowed locations are still not wire-signalled, so the default stays silent. | CE-2 text must be valued | The spec carries an explicit "*in some locations user display is not intended and the text may be blank*" carve-out. An unconditional required-CE-2 rule would over-fire on the blank-allowed locations, and those locations are not wire-signalled. Shipping it would violate req #4 ("no predicate ships if known-incorrect"). | **Permanent** unless a future spec revision adds a wire signal for the blank-allowed locations. |
| **HL7au:00044.4.7** (CE concept-match) | CE identifier and alternate identifier must reflect the *same concept* | Requires a terminology service to compare concepts across code systems; not derivable from the wire. Out of the portable-core boundary (ADR-006). | **Permanent** (a terminology-service hook would be a post-1.0, out-of-core module). |
| **HL7au:00044.5.7 / 00044.6.7** (CNE/CWE concept-match) | as .4.7, for CNE/CWE | Marked **"Removed"** in ADRM r2 — not applicable. | **N/A** (withdrawn by the profile). |
| **HL7au:00044.2** (HD / NASH) — **PARTLY SHIPPED (M32, 2026-09-23)** | The family's sub-points on MSH-4 / MSH-6 | **.2.2 and .2.3 now ship caller-asserted** (`ValidationOptions.auNASHTransport = true`): the Universal ID must be `1.2.36.1.2001.1003.0.` + a 16-digit HPI-O (width from HL7au:000043.1), and the Universal ID Type must be `ISO`. All 8 OID values the ADRM prints honour it. **Still out:** `.2.1` and `00044.3.2` name the organisation "as registered in the Medicare Australia HPOS/HI service" (needs the HI directory); `.2.4` and the ADRM's second `00044.3.4` compare against a vendor X.509 certificate; `00043.2` is an anti-spoofing check the ADRM marks *"applies only to SMD Agent implementers … before handing off a the message to the receiving system"*. **The EI twins `00044.3.3` / `.3.4` ship too (M33, 2026-09-23)**, datatype-wide as the ADRM's "EI datatype conformance points" grouper states: the sentence constrains the *shape* of the universal ID, not whose HPI-O it is, so an identifier echoed from another organisation satisfies it unchanged. They allow an empty universal ID, because HL7au:000006 / 000007 already require all four EI components on the five AU EI fields. | **Permanent for the directory and certificate halves.** |
| **HL7au:00044.1.2 / .1.3** (NASH sub-points / value-set membership) | NASH-specific formats / value-set membership | Runtime/PKI-dependent or require value-set dispatch against externally-maintained tables. | **Deferred**; re-audit if a value-set-dispatch mechanism lands. |
| **HL7au:000001** (Order addressing / MSH-6 Receiving Facility) | 4 sub-rules on order addressing | Each sub-rule is either **receiver-runtime semantics** (what the receiver must *do*, not what the message must *contain*), **soft "should" guidance** (not a MUST), or points to the PKI-deferred 00044.2. None is a wire-checkable MUST. | **Permanent** (runtime/soft-guidance, not a schema constraint). |
| ~~**HL7au:00050.1.5** (OBX-6.3 = "UCUM")~~ **SHIPPED caller-asserted (M29, 2026-09-23):** `ValidationOptions.auPathologySender = true` applies it; the wire still carries no discriminator, so the default stays silent. | OBX-6 name-of-coding-system must be "UCUM" — scoped **"Senders (Pathology only)", Results** (Appendix 5 p. 465) | "Pathology sender" has no message-decidable discriminator: ADRM-2021 defines no pathology subset of HL7 table 0074 (OBR-24 mixes pathology and imaging disciplines), and no other wire signal identifies the sender's discipline. A bare `messageCode = ORU` gate would over-fire on spec-compliant imaging results (req #4); inventing an OBR-24 subset would not be defensible against spec text (req #2). M6-A stage 3, 2026-09-15. | **Permanent** unless a future ADRM revision adds a wire-decidable pathology discriminator. |

## C. Terminology / external-state limitations (cross-cutting)

- **Code-system-aware value checks** — any rule of the form "value X must belong to code system Y" or "concept A ≡ concept B" needs a terminology service; the validator checks structure and (where the profile enumerates them) literal value sets, not semantic equivalence. This bounds the AU 00044.4.4 LOINC-placement rule (shipped v0.13 as a **partial** necessary condition) and 00044.4.7 above.
- **PKI / certificate validation** — NASH and similar require live certificate infrastructure; out of the portable-core boundary (ADR-006). M32 shipped the *format* half of the NASH addressing points on the caller's assertion; the certificate comparison itself stays out.
- **Cross-message / patient-history state** — rules like OBR-48 "duplicate procedure" need history beyond the current message.
- **Composite-component table links** — shipped on all six versions (ADR-017): from the printed component tables of v2.5.1 / v2.6 / v2.8.2 (`v3.4.0`), with nested composites and OBX-5 (M11), and from the numbered prose subsections of v2.3 / v2.3.1 / v2.4 under a three-test evidence rule (M13). **Closed since:** the 39 rejected prose mentions were read one by one and found unbindable (M24, `v3.7.3`); printed `R` components are enforced (M14 to M16), `C` components where the prose states a sibling-presence or repetition condition (M26, M28), and the 32 "as of v2.7" conditions are opt-in (M27). **Still registered:** component length (recorded, never enforced, M25); CWE.7 and kin (a value-pattern term plus table-type lookup, and the spec's own examples violate it); CNE.20 (self-contradictory sentence). See `Resources/datatypes/conditions.json`.

**Freeze decision (B + C):** all acceptable to freeze for v1.0. They are honest, spec-cited gaps, not defects; each would require an out-of-core runtime integration (terminology service, PKI) that is explicitly **post-1.0** (see ROADMAP "Post-1.0 sketch"). Shipping any as an unconditional rule would misfire, violating req #4.

## D. M6-B — ADRM-2021 points awaiting model capabilities (deferred, blocks spec-completeness)

Added at M6 close (2026-09-16) as the EXTEND remainder of the ADRM-2021 Appendix 5
register; **drained by M6-B-4 through M6-B-9** (same date). Each row below records its
outcome: shipped, shipped-PARTIAL with the unenforced half stated in the conformance
register, or registered with the citation-backed reason no faithful rule can exist (see
`m6-adrm-2021-conformance-register.md` for per-point text).

| Capability | Points (HL7au:) | What it needs |
|------------|-----------------|---------------|
| **HL7 code-table registry (M6-O6)** — shipped 2026-09-20 (ADR-016): per-version registry with descriptions, generated Swift, `valueNotInTable` on ID fields over closed tables, locale axis. Seeded M6-B-4/5, 2026-09-16. | ~~`000032`, `000032.2`, `00104.7.2.1`, `00104.7.3.1`, `00044.7.3`, `00044.7.4`~~ all shipped: the `HL7CodeTables` seed (tables 0074/0200/0203/0363, hand-verified against the ADRM's printed renderings) plus the M6-B-5 composite value-set track (populated-only allow lists on `CompositeOverride`) | **Remaining:** the general per-version registry only — the seed holds just the tables shipped points consume, values-only, with no descriptions and no codegen. Grow it when a new point needs a new table. |
| **OBX-2-driven datatype resolution (M6-O7)** — ✅ shipped (M6-B-7, 2026-09-16) | ~~`00044.10.1.1`–`.1.4` (ED), `00044.11.1.1`–`.1.4` (RP)~~ all shipped: the composite-override dispatch resolves OBX-5's effective datatype from the sibling OBX-2 value | Nothing remaining for these points. The general capability stays OBX-5-specific by design — no other field's type varies at runtime. |
| **Value-correspondence maps** — ✅ shipped (M6-B-8, 2026-09-16) | ~~`00044.10.1.5`/`.6`, `00044.11.1.5`/`.6`, `000008.1.3`, `00104.7.1.4`~~ all shipped (PARTIAL where the ADRM leaves the pair set open) via `ComponentCorrespondence` on both override tracks | **Remaining:** only the open ends noted per row in the register — unstated IANA subtypes and open-ended vendor authorities skip, fail-safe (req #4). |
| **Within-message uniqueness** — ✅ shipped (M6-B-9, 2026-09-16) | ~~`000028`, `000028.2`~~ shipped via `FieldUniquenessRule` (message-wide OBR-3.1 duplicate detection, ORU- and REF-gated legs) | Nothing remaining. |
| **Intra-message ordering** — registered (M6-B-9, 2026-09-16) | `00100.1` (REF-4 referral-priority ordering "according to the SNOMED CT hierarchy"), `000008.1.5` (display-segment signature ordering per **HB 308-2011**) | `00100.1` needs SNOMED CT subsumption — a terminology server, §C territory, not a DSL gap. `000008.1.5`'s normative content (which identifiers mark a signature block) lives in HB 308-2011, an external Standards Australia handbook the ADRM does not reproduce; a rule would not be defensible against the ADRM text alone (req #2). **Permanent** unless a future revision inlines the handbook's identifier list. |
| **Coding-system precedence** — ✅ shipped for named public systems (M6-B-9, 2026-09-16) | ~~`000034.1`, `000034.2`~~ shipped PARTIAL: a public system the ADRM names (LN, SCT, UCUM — `HL7CodeTables.publicCodingSystems`) appearing in the CE/CWE alternate triplet behind a non-public primary fires; unnamed systems skip, fail-safe. `000034.3` registered | `000034.3` ("the alternate must be a translation of the same concept") is a terminology-equivalence judgement, §C territory — same reasoning as the registered `00044.4.7`/`.5.7` and their CWE twin `00044.6.7` (also registered at M6-B-9). |
| **Relational group cardinality** — ✅ shipped, structural half (M6-B-9, 2026-09-16) | ~~`000008.3.2`~~ shipped PARTIAL via `SegmentCardinalityRule.activationPredicate`: RTF display present in an OBR group without an HTML/PDF/TXT sibling fires (L2 Referrals gate) | **Remaining:** the "same content" equality half — comparing rendered RTF against rendered HTML/PDF/TXT is not machine-checkable; permanent, same class as `000008.2`. |
| **TS timezone offset** — ✅ shipped, presence half (M6-B-9, 2026-09-16) | ~~`00044.8.1`~~ shipped PARTIAL via `CompositeOverride.timezoneRequiredCitation`: a TS with hour-or-greater precision and no `+`/`-ZZZZ` suffix fires on Orders/Results/Referrals | **Remaining:** verifying the offset is *correct* for the stated local time needs a timezone database and the sender's location — out of scope by nature. |
| **Batch-scope rules** — ✅ shipped via `BatchValidator` (M8-C, 2026-09-17) | ~~`000022.1`, `000022.3`~~ — `BatchValidator` over `BatchParser` output landed: `000022.3` SHIPPED (a REF alongside any other message in one batch group fires); `000022.1` PARTIAL (the individual-acknowledgement mode lives in each contained message's MSH-15/16, which the per-message AU rules enforce on every batched message; the "no information from batch segments used" half is receiver behaviour). Also shipped there: the single-batch-per-file prose rule (`ADRM-prose:P-7`, p. 19). | Nothing remaining for these points. |

**Freeze decision (M6-B-9 close, 2026-09-16): §D is drained.** Every capability row is
now shipped, shipped-PARTIAL with the unenforced half stated, or registered with a
citation-backed reason no faithful rule can exist. The EXTEND class of the ADRM register
is empty; nothing awaits a model extension. *(Historical note, M6-B-6: the "MSH-21
profile-ID addressing" root cause named here earlier was a misidentification — the ADRM
declares the adhered profile in MSH-12.3, which the DSL addresses.)*

## What is NOT a limitation (recorded to prevent re-litigation)

- **NUL / BOM handling** — embedded NUL is *rejected* at parse (v0.2-P2); BOM is stripped. These are design decisions with no carve-out, not limitations.
- **`.v2_8` grammar-less case** — a deliberate scope decision (ADR-013), not an undocumented gap: `2.8` is rare and distinct from the fully-modelled `2.8.2`.
- **Curated NK1 / PV1 / IN1 depth** — a req-#1 feature-completeness *backlog* item (extend the field sets), not a conformance limitation of the modelled fields.

## Outcome — M2 closed

With A (v0.16) and B/C (this register) documented and freeze-decided, **ROADMAP M2 (conformance-surface finalisation) is closed**: every conformance rule is either validated or listed here with a spec-cited reason and an explicit v1.0 freeze decision. The remaining v1.0 gate is **M3** (API stabilisation).
