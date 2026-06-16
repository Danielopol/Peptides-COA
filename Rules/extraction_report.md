# COA Forensic Ruleset — Extraction Report

**Generated:** 2026-05-17  
**Source articles:** 8 reference documents (9 files; one article existed as both .md and .pdf)  
**Total rules extracted:** 81  
**Output files:** `coa_rules.json`, `scoring_rubric.json`, `llm_prompt_template.txt`

---

## 1. Rules Per Category

| Category | Rules | Critical | Major | Minor | Total Weight (raw) |
|---|---|---|---|---|---|
| structure | 12 | 5 | 4 | 3 | 83 |
| numerical | 11 | 5 | 4 | 2 | 80 |
| analytical_methods | 12 | 2 | 3 | 7 | 64 |
| lab_credentials | 10 | 3 | 6 | 1 | 71 |
| formatting | 8 | 2 | 5 | 1 | 52 |
| metadata | 5 | 2 | 3 | 0 | 39 |
| cross_reference | 8 | 4 | 3 | 1 | 62 |
| forgery_indicators | 15 | 7 | 6 | 2 | 105 |
| **TOTAL** | **81** | **30** | **34** | **17** | **556** |

*Note: forgery_indicators rules have high raw weight because failing them subtracts from score; they do not add to the maximum possible score in the same way as pass/fail rules.*

---

## 2. Article Contributions

### SubQProtocol_COA_Verification_2026
`SubQProtocol_Peptide-COA-Verification-Guide.pdf`  
**Unique contributions:**
- "Nearly 40% of vendors fail independent purity testing" — motivating statistic
- Testing date ideally within **90 days** of purchase (most aggressive freshness standard of any source)
- Future-dated COAs explicitly flagged: "yes, this happens" (META-003)
- Explicit purity band table: ≥99% = Premium/Pharmaceutical; 98–99% = Research Grade; 95–98% = Lower Research Grade; <95% = Substandard
- Endotoxin standard explicitly stated as <0.5 EU/mg (NUM-009)
- RP-HPLC with C18 column specified (METH-003)
- Janoshik online verification URL explicitly named: `janoshik.com/verify` (LAB-008)
- MZ Biolabs and Freedom Analytics Labs added to known-labs list (LAB-009)
- Template COA problem described in depth (META-005)

### TruPeptide_Fake-COA-Red-Flags.pdf
**Unique contributions:**
- Community testing found products claiming "99% pure" tested below 90% (FORG-012)
- Community testing found products containing wrong compound entirely (XREF-002)
- 7 explicit red flags: no lab name, no batch, round numbers, missing chromatogram, no MS, identical COAs across batches, lab doesn't know vendor
- MS tolerance framed as "typically ±1 Da" in plain language (NUM-004 general threshold)
- Janoshik Analytical, Colmaric Analyticals, Novascreen Biosciences named as known legitimate labs (LAB-009)
- 4-tier vendor trust hierarchy: Tier 1 (consistent third-party + confirmable lab), Tier 2 (occasional third-party), Tier 3 (in-house only), Tier 4 (no COAs)

### PeptideRecon_Verify_COAs_Guide
`PeptideRecon_Verify-COAs_Guide.pdf` + `.md`  
**Primary source — most comprehensive single contribution:**
- 8 required COA field types with full detail (STRUCT-001 through STRUCT-012)
- Full HPLC chromatogram reading methodology: retention time, peak shape, baseline, impurity peaks, integration lines (METH-007, METH-008)
- MALDI-TOF vs ESI-MS tolerance breakdown: MALDI ±0.1–0.3 Da (<2000 Da), ESI ±0.05 Da (NUM-004)
- Charge state analysis: [M+H]+, [M+2H]2+, formula mass = (m/z × z) − (z × 1.00728) (XREF-005)
- Adduct peaks: Na+22, K+38, TFA+114 (XREF-006)
- Photoshop detection methodology: resolution inconsistencies, clone stamps, alignment issues, blurry stamps with sharp text (FMT-002 through FMT-006, FORG-006, FORG-007)
- PDF metadata analysis methodology: creation date, authoring software, modification history (META-001, META-002, META-004)
- ISO 17025 accreditation verification: ANAB, A2LA, UKAS, CNAS as accreditation bodies; ILAC as verifying body (LAB-002, LAB-004, LAB-005)
- Correct terminology: labs are "accredited" not "certified" (LAB-003)
- NPC vs HPLC purity distinction: NPC 60–90% typical, ≥70% ideal; counter-ions explained (NUM-005)

### HonestPeptide_How_to_Read_COA
`How_to_Read_a_Peptide_COA.pdf`  
**Unique contributions:**
- Janoshik COA format shown in real example: task number, client, verification key field
- Digital verification key requirement: static PDF alone insufficient (LAB-008)
- NPC components named explicitly: TFA, acetate, HCl counter-ions; residual moisture especially in Lys/Arg-rich sequences; atmospheric water during freeze-drying (NUM-005)
- Heavy metals: ICP-MS method, Pb/Cd/As screening (METH-011)
- Endotoxins: LAL test, EU/ml units (METH-012)
- Purity interpretation: ≥99% excellent, 95–98% standard RUO, <95% problematic (NUM-001)
- Vanguard Laboratory example COA with A2LA Certificate #6377.01.01 (LAB-009)

### HonestPeptide_Vendor_Selection
`How_to_Select_a_Peptide_Vendor.pdf`  
**Unique contributions:**
- "Premium Grade with no specifics" = red flag concept
- Vendor must disclose salt form (TFA vs acetate) as transparency indicator
- Storage requirements: –20°C or –80°C, crimp-sealed vials under nitrogen
- COA analysis dates <2 years as vendor standard
- RUO marketing red flags: therapeutic claims, dosing protocols, selling syringes/bacteriostatic water, lifestyle social media marketing, customer reviews describing physiological effects (FORG-014)
- Pricing dramatically below market rate as red flag (FORG-015)
- Vendor evaluation scorecard as structural concept used in scoring_rubric.json

### HonestPeptide_Complete_Guide_RUO
`The Complete Guide to Research Peptides (RUO).md`  
**Unique contributions:**
- RUO regulatory framework: compliant vs red-flag phrasing defined
- SPPS manufacturing quality levels: Crude <70%, Research Grade 95–98%, Premium >98%, GMP (framing for NUM-001)
- "Custom synthesis of novel sequences may not require MS" — source of false_positive_notes in STRUCT-009
- HPLC and MS from same batch requirement (XREF-008)

### bestpepprices_COA_Guide
`What Is a Certificate of Analysis (COA) and Why It Matters for Research Peptides.md`  
**Unique contributions:**
- COA age threshold stated as 12–18 months (more specific than other sources) (NUM-006)
- Standard purity ≥98% stated as market baseline (NUM-001)
- "COA not downloadable or verifiable" as explicit red flag (FMT-008)
- In-house vs third-party COA distinction explained most clearly
- "COA only as embedded low-resolution image" as red flag (FMT-008)
- Supplier comparison table with 15 confirmed third-party verified vendors
- Purity conveniently round across entire catalog as catalog-level red flag (FORG-009)

### Reddit_r_PeptideProgress_COA_Beginners
`How to Read a Peptide COA (Certificate of Analysis) for Beginners.md`  
**Unique contributions:**
- BPC-157 reference molecular weight: ~1419 Da (NUM-010)
- TB-500 reference molecular weight: ~4963 Da (NUM-010)
- Legit vendor response time as behavioral indicator (FORG-010)
- "Grading your own exam" framing for in-house testing — useful for llm_prompt_template
- Community-level practical verification approach

---

## 3. Rule Deduplication Log

The following topics appeared in multiple articles and were merged into single rules:

| Topic | Sources | Merged Into |
|---|---|---|
| Third-party lab requirement | bestpepprices, Reddit, HonestPeptide-Complete, TruPeptide | LAB-001 |
| Batch number matching vial | bestpepprices, PeptideRecon, Reddit, HonestPeptide-Complete, SubQProtocol | XREF-001 |
| Round purity numbers as suspicious | bestpepprices, TruPeptide, PeptideRecon, SubQProtocol | FORG-001 + NUM-002 |
| Missing MS data | TruPeptide, HonestPeptide-Complete, PeptideRecon | STRUCT-009 + METH-002 |
| COA age / freshness | bestpepprices (12–18 mo), HonestPeptide-Complete (<24 mo), SubQProtocol (90 days) | NUM-006 (graduated thresholds) |
| Janoshik as known lab | Reddit, SubQProtocol, HonestPeptide-How-to-Read | LAB-009 |
| Endotoxin standard | PeptideRecon, SubQProtocol, HonestPeptide-How-to-Read | NUM-009 |
| Lab doesn't recognize vendor/batch | TruPeptide, PeptideRecon, Reddit | FORG-013 + LAB-007 |

---

## 4. Ambiguities and Resolution Notes

### 4a. Chromatogram Absence: Major or Critical?
**Ambiguity:** Some articles treat missing chromatogram as critical (TruPeptide), while Janoshik Analytical — the most commonly cited legitimate lab — is known to provide numerical results without embedded chromatogram images.

**Resolution:** METH-006 is rated **major** (not critical), with false_positive_notes specifically calling out that Janoshik's format is legitimate when digital verification key is provided. Absence of chromatogram alone does not disqualify if the lab is independently verifiable.

### 4b. COA Age Thresholds Vary Across Sources
**Ambiguity:** Sources cite 90 days (SubQProtocol), 12–18 months (bestpepprices), and <24 months (HonestPeptide-Complete) as acceptable COA age.

**Resolution:** NUM-006 uses **18 months as primary threshold** (major concern flag) and **24 months as critical concern**, with a note that 90 days is the ideal for pre-purchase evaluation. All three thresholds are preserved in the rule.

### 4c. ISO 17025 Accreditation: Required or Best Practice?
**Ambiguity:** bestpepprices states ISO 17025 is "the gold standard" while PeptideRecon treats it as a requirement. But Janoshik — the most-cited lab — is community-trusted without always explicitly displaying accreditation.

**Resolution:** LAB-002 is rated **major** (not critical), with false_positive_notes acknowledging that community-trusted labs may not always display accreditation prominently. Combined with LAB-006 (web presence) and LAB-007 (direct verification), the set provides a complete credential picture.

### 4d. NPC vs HPLC Purity Confusion
**Ambiguity:** Several articles discuss NPC without clearly distinguishing it from HPLC purity, which could lead to evaluating the wrong metric.

**Resolution:** NUM-005 and METH-010 explicitly distinguish NPC (60–90%, accounts for counter-ions and moisture) from HPLC purity (peptide-related impurities only). A red flag in METH-010 flags NPC = HPLC purity as a confusion indicator.

### 4e. MS Tolerance "±1 Da" (TruPeptide) vs ±0.1–0.3 Da (PeptideRecon)
**Ambiguity:** TruPeptide states ±1 Da as the general tolerance; PeptideRecon specifies tighter tolerances by instrument type.

**Resolution:** NUM-004 uses **±1 Da as the general threshold** (accessible to non-specialist evaluators) while including the instrument-specific tighter tolerances (MALDI ±0.1–0.3 Da, ESI ±0.05 Da) for specialist evaluation.

---

## 5. Rules Not Extractable From Articles (Suggested Additions)

The following rules are commonly discussed in pharmaceutical analytical chemistry but were not explicitly stated in the 8 source articles. They are listed here for potential future expansion:

| Suggested Rule | Rationale | Category |
|---|---|---|
| HPLC column lot number verification | Column lot affects retention time reproducibility — batch-to-batch variation detectable | analytical_methods |
| Instrument calibration date | HPLC and MS instruments require periodic calibration; calibration date on COA is pharmaceutical-grade practice | analytical_methods |
| Reference standard identity | Purity is relative to a standard; undisclosed or generic reference standards reduce comparability | analytical_methods |
| Protein/peptide-specific impurity profiling | Deletion sequences, oxidized forms, deamidated forms are expected impurities — their presence confirms real SPPS output | numerical |
| Water content by Karl Fischer titration | Separate from NPC; gives more precise moisture content for pharmaceutical-grade material | analytical_methods |
| Counterion content by ion chromatography | TFA vs acetate salt form affects safety and solubility — explicitly stated by HonestPeptide-Vendor but no specific rule recommended | structure |
| Residual solvent testing (ICH Q3C) | Relevant for pharmaceutical-grade claims; absent in RUO context but worth flagging for GMP-aspirant products | analytical_methods |
| Optical rotation or chiral purity | Amino acid chirality (D vs L) can affect biological activity — rare but premium-grade differentiator | analytical_methods |

---

## 6. Source Coverage Map

The table below shows which article contributed to each rule category:

| Article | STRUCT | NUM | METH | LAB | FMT | META | XREF | FORG |
|---|---|---|---|---|---|---|---|---|
| SubQProtocol | ✓ | ✓✓ | ✓ | ✓ | — | ✓✓ | ✓ | ✓✓ |
| TruPeptide | ✓✓ | ✓ | ✓✓ | ✓✓ | — | — | ✓ | ✓✓✓ |
| PeptideRecon | ✓✓✓ | ✓✓✓ | ✓✓✓ | ✓✓✓ | ✓✓✓ | ✓✓✓ | ✓✓✓ | ✓✓✓ |
| HonestPeptide-COA | ✓ | ✓✓ | ✓✓ | ✓✓ | — | — | — | — |
| HonestPeptide-Vendor | — | — | — | ✓ | — | — | — | ✓✓ |
| HonestPeptide-RUO | ✓ | ✓ | ✓ | — | — | — | ✓ | — |
| bestpepprices | ✓✓ | ✓✓ | — | ✓✓ | ✓✓ | — | ✓ | ✓✓ |
| Reddit | ✓ | ✓✓ | — | ✓ | ✓ | — | — | ✓ |

Legend: ✓ = minor contribution; ✓✓ = significant contribution; ✓✓✓ = primary source

---

## 7. Weight Distribution Summary

| Weight Value | Rules Count | Categories Present |
|---|---|---|
| 10 | 10 | structure(2), numerical(2), analytical_methods(1), cross_reference(2), forgery_indicators(3) |
| 9 | 13 | structure(2), numerical(2), lab_credentials(2), metadata(1), cross_reference(2), forgery_indicators(4) |
| 8 | 9 | structure(1), numerical(2), lab_credentials(1), formatting(2), forgery_indicators(3) |
| 7 | 12 | structure(1), numerical(2), analytical_methods(2), lab_credentials(3), cross_reference(2), forgery_indicators(2) |
| 6 | 11 | structure(2), numerical(1), lab_credentials(2), formatting(2), metadata(1), forgery_indicators(3) |
| 5 | 9 | structure(1), analytical_methods(3), lab_credentials(1), metadata(1), cross_reference(1), forgery_indicators(2) |
| 4 | 10 | structure(2), analytical_methods(4), formatting(1), cross_reference(1), forgery_indicators(2) |
| 3 | 4 | numerical(1), lab_credentials(1), forgery_indicators(1), formatting(1) |

---

*End of extraction report.*
