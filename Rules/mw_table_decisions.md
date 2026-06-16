# Peptide MW Table — Decisions (RESOLVED)

Three entries were originally flagged `needs_review` because they are **species/identity
ambiguities, not missing data** — each can resolve to more than one correct molecular weight
depending on what the physical product a COA describes actually is.

**Resolution:** rather than locking a single value (the scanner can't know in advance which
species a COA references), these entries now carry a `variants[]` array listing every plausible
form with its own formula and masses. The MW check (`backend/app/checks/mw_table.py`) accepts a
COA mass that matches the **primary OR any variant**, and reports which form matched.

All three are now `verified: true` with no remaining `needs_review`.

---

## Matcher contract (`variants[]`)

For any entry with a `variants[]` array:
1. Build candidate masses = primary (top-level `monoisotopic_mass`/`average_mass`) + each variant.
2. For each candidate, pick monoisotopic vs average per the detected MS technique, apply the
   technique's tolerance.
3. **Pass** if the claimed MW matches any candidate; the result reports `matched_variant` when the
   hit was a non-primary form.
4. **Fire** (XREF-009) only if it matches none; the result lists all `expected_masses`.

Blends (`is_blend: true`: GLOW, KLOW, Lipo-C, Thymalin) are skipped entirely — no single MW.

---

## 1. TB-500  → primary: full-length Thymosin β4

| Form | Formula | Avg | Monoisotopic | CID |
|---|---|---|---|---|
| **Full-length Thymosin β4 (43 aa)** — primary | C212H350N56O78S | 4963.44 | 4960.49 | 45382195 |
| Ac-LKKTETQ fragment (literal "TB-500") | C38H68N10O14 | 889.0 | 888.49 | 62707662 |

Primary follows research-market reality (vials sold as "TB-500" are full Tβ4). The pharmacology
fragment is accepted as a variant so a fragment COA still matches.

## 2. CJC-1295 no DAC  → Mod GRF 1-29 (single value, locked)

Resolved to a single value — not ambiguous, just lacked an authoritative reference.

| Form | Formula | Avg | Monoisotopic |
|---|---|---|---|
| Mod GRF 1-29 (DAC-less) | C152H252N44O42 | 3367.95 | 3365.89 |

Computed average (3367.95) matches literature ~3367.9. Distinct from Sermorelin (GRF 1-29,
~3357.9) and from CJC-1295 *with* DAC (~3647.2, separate entry).

## 3. AHK-Cu  → primary: neutral copper complex

Original seed (341) was wrong twice over — it looked copied from GHK, and bare AHK is actually
354.41.

| Form | Formula | Avg | Monoisotopic | CID |
|---|---|---|---|---|
| **Neutral 1:1 Cu complex** — primary | C15H26CuN6O4 | 417.96 | — | — |
| Bare AHK tripeptide (Ala-His-Lys) | C15H26N6O4 | 354.41 | — | — |
| Cu + chloride salt anion (PubChem) | C15H24ClCuN6O4- | 451.39 | — | 168431292 |

## Related: GHK-Cu also given variants

Same copper-complex ambiguity, so GHK-Cu carries variants too:
PubChem Cu anion **400.9** (primary) · neutral Cu complex **403.93** (common COA value) ·
bare GHK **340.38**.
