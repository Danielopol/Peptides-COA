# Peptide COA Authenticity Scanner — Full Project Plan

## Project Overview

A web-based + Android app that scans peptide Certificates of Analysis (COA) and provides an authenticity/legitimacy score. Users upload a COA as an image, PDF, or document, and the app returns a 0–100 score with a detailed breakdown of which checks passed, failed, or flagged suspicious.

**Stack:** Flutter (web + Android), Gemini Flash API (MVP), Gemma (future local LLM), Claude Design (UI/UX), Claude Code (prototyping)

**Data assets:** Benchmark articles on reading/spotting fake COAs, hundreds of valid COA examples, 1000+ AI-generated forged COAs.

---

## Phase 0: Knowledge Extraction & Rule Engineering

> This is the foundation. The quality of the ruleset determines the quality of the entire app.

### Step 1: Extract Rules from Benchmark Articles

Place all reference articles in `D:\DIRECTORY\Peptides\Articles`.

Use the following Claude Code prompt to extract a machine-readable ruleset:

---

```
You are an expert document forensics analyst specializing in pharmaceutical and peptide quality documentation. Your task is to extract machine-readable verification rules from reference articles about how to read, evaluate, and spot forged peptide Certificates of Analysis (COAs).

## CONTEXT

I am building an app that scans peptide COAs (image, PDF, or document) and scores their authenticity. I need you to extract every verifiable signal from the reference articles I provide and structure them as a ruleset that a scoring engine can evaluate programmatically.

## INPUT

Read all files in `D:\DIRECTORY\Peptides\Articles` — these are guides on how to properly read a COA and how to identify forged or fraudulent ones.

## YOUR TASK

For each article, extract every checkable signal, red flag, and authenticity indicator. Then consolidate all findings into a single deduplicated ruleset.

## OUTPUT FORMAT

Create a file at `D:\DIRECTORY\Peptides\Rules\coa_rules.json` with this exact structure:

{
  "version": "1.0",
  "last_updated": "YYYY-MM-DD",
  "rule_categories": [
    {
      "category_id": "structure",
      "category_name": "Document Structure & Required Sections",
      "description": "Rules about what sections and fields a legitimate COA must contain",
      "rules": [
        {
          "rule_id": "structure_001",
          "name": "Short human-readable name",
          "description": "What this rule checks and why it matters",
          "check_type": "presence | range | format | consistency | cross_reference | visual",
          "severity": "critical | major | minor",
          "weight": 1-10,
          "expected_value": "What a legitimate COA should show",
          "red_flags": ["List of specific suspicious patterns"],
          "source_article": "Which article this rule was extracted from",
          "evaluation_method": "How an LLM or rule engine should evaluate this — be specific",
          "false_positive_notes": "Cases where a legitimate COA might fail this check"
        }
      ]
    }
  ]
}

## REQUIRED CATEGORIES (create others if the articles warrant it)

1. **structure** — Required sections, fields, headers (e.g., must contain purity %, batch number, peptide sequence, molecular weight, test date, lab info)
2. **numerical** — Value ranges and consistency (e.g., HPLC purity typically 95-99.9%, molecular weight must match peptide, retention times plausible)
3. **analytical_methods** — Expected testing methods and their results (e.g., HPLC, mass spectrometry, endotoxin testing, sterility, amino acid analysis)
4. **lab_credentials** — Lab identification and accreditation signals (e.g., lab name, address, accreditation marks, analyst signatures)
5. **formatting** — Visual and layout indicators (e.g., consistent fonts, professional layout, logo quality, alignment, resolution)
6. **metadata** — Document metadata signals (e.g., PDF creation date vs claimed test date, authoring software, embedded fonts)
7. **cross_reference** — Cross-checkable claims (e.g., batch format matches known lab patterns, peptide sequence matches claimed compound)
8. **forgery_indicators** — Explicit red flags from the articles about common forgery patterns

## RULES FOR EXTRACTION

- Be exhaustive. Extract EVERY signal mentioned in the articles, even if it seems minor.
- If an article gives a specific number or threshold, capture it exactly.
- If an article describes a pattern qualitatively ("the font looks off"), translate it into a checkable rule ("font_consistency: all text in the document should use no more than 2-3 font families").
- For each rule, write the `evaluation_method` as if instructing an LLM that is reading the COA — what specifically should it look for and how should it decide pass/fail/suspicious.
- Add `false_positive_notes` to prevent legitimate COAs from being wrongly flagged.
- Set weights based on how diagnostic each rule is: a rule that only fakes fail gets weight 8-10, a rule that many legitimate COAs also fail gets weight 1-3.

## ALSO CREATE

1. `D:\DIRECTORY\Peptides\Rules\scoring_rubric.json` — A scoring specification:
   - How to compute the final 0-100 score from individual rule results
   - Score bands with labels (e.g., 90-100 = "Highly Likely Authentic", 50-70 = "Suspicious — Review Manually", 0-30 = "Likely Forged")
   - How to handle rules that return "not_applicable" (some COAs legitimately skip certain tests)

2. `D:\DIRECTORY\Peptides\Rules\llm_prompt_template.txt` — A ready-to-use prompt for Gemini Flash that:
   - Receives extracted COA text/image
   - Evaluates it against the full ruleset
   - Returns structured JSON with per-rule pass/fail/suspicious + confidence + reasoning
   - Includes 2 few-shot examples (one valid COA summary, one forged COA summary) based on common patterns from the articles

3. `D:\DIRECTORY\Peptides\Rules\extraction_report.md` — A human-readable report showing:
   - How many rules were extracted per category
   - Which articles contributed which rules
   - Any ambiguities or conflicts between articles
   - Suggested additional rules not in the articles but obvious from domain knowledge (clearly marked as "suggested, not sourced")

After creating all files, print a summary of total rules extracted per category and the overall weight distribution.
```

---

### Step 2: Validate Rules Against Your Dataset

After extraction, manually test the rules against a sample:

- Pick ~50 valid COAs and ~50 forged COAs from your dataset.
- For each, check which rules correctly discriminate fakes from real ones.
- Drop rules with zero signal (both valid and forged pass or fail equally).
- Increase weight on rules that reliably catch fakes.
- Document edge cases in `false_positive_notes`.

---

## Phase 1: Data Pipeline & Labeling

### Step 3: Organize Your Dataset

Structure your data into a clean directory:

```
D:\DIRECTORY\Peptides\
├── Articles\          → Benchmark articles (source material)
├── Rules\             → Extracted ruleset, scoring rubric, LLM prompt
├── Data\
│   ├── valid\         → Real COAs, each with a JSON sidecar
│   │   ├── coa_001.pdf
│   │   ├── coa_001.json   (peptide name, lab, purity, format)
│   │   └── ...
│   ├── forged\        → AI-generated fakes, same sidecar structure
│   │   ├── fake_001.pdf
│   │   ├── fake_001.json
│   │   └── ...
│   └── evaluation\    → Gold-standard annotated set
│       ├── eval_001.pdf
│       ├── eval_001_annotations.json  (per-rule pass/fail)
│       └── ...
```

### Step 4: Create Gold-Standard Annotations

For 100–200 COAs (mix of valid and forged), manually annotate which rules each one passes or fails. This becomes your evaluation set for measuring pipeline accuracy. Without this, you cannot objectively measure improvement.

JSON sidecar format per COA:

```json
{
  "file": "eval_001.pdf",
  "label": "valid",
  "source_lab": "Peptide Sciences",
  "peptide": "BPC-157",
  "rule_results": {
    "structure_001": "pass",
    "structure_002": "pass",
    "numerical_001": "pass",
    "formatting_003": "suspicious",
    ...
  },
  "notes": "Slightly low resolution scan but all data checks out"
}
```

---

## Phase 2: LLM Integration Architecture

### Step 5: Design the Two-Layer Analysis Pipeline

Do not rely solely on the LLM or solely on rules. Combine them:

```
Input (image / PDF / photo)
    │
    ├──→ [ OCR / Document Parsing Layer ]
    │         Extracts text, structure, metadata
    │         Tools: Tesseract, pdf-parse, Google Vision API
    │
    ├──→ [ Rule Engine ] (deterministic)
    │         Applies your weighted ruleset from coa_rules.json
    │         Outputs: per-rule pass/fail + partial score
    │
    ├──→ [ Gemini Flash API ] (probabilistic)
    │         Receives extracted text + original image
    │         Uses llm_prompt_template.txt
    │         Outputs: structured JSON assessment
    │
    └──→ [ Score Aggregator ]
              Combines rule engine + LLM outputs
              Applies scoring_rubric.json
              Produces final score (0-100) + breakdown
```

### Step 6: Craft the Gemini Flash Prompt

The `llm_prompt_template.txt` generated in Phase 0 is your starting point. Key principles:

- Include the full ruleset as context in the system prompt.
- Ask for structured JSON output only.
- Use 2–3 few-shot examples (one valid, one forged, one borderline).
- Do NOT fine-tune Gemini for MVP. Few-shot prompting is faster to iterate and sufficient.
- Save fine-tuning/training for the Gemma migration.

### Step 7: Build the Backend API

A lightweight backend that handles the pipeline:

**Recommended:** Python + FastAPI (best ecosystem for OCR, PDF parsing, LLM integration)

Endpoints:

```
POST /api/scan
  - Accepts: multipart file upload (image, PDF, document)
  - Returns: JSON with score, per-rule breakdown, LLM reasoning

GET /api/history
  - Returns: past scans for the authenticated user

GET /api/rules
  - Returns: current ruleset version and summary
```

Processing flow inside `/api/scan`:

1. Detect file type (image vs PDF vs document).
2. Normalize to text + image (OCR if image, extract if PDF).
3. Extract metadata (PDF creation date, author, fonts).
4. Run deterministic rule engine against extracted data.
5. Call Gemini Flash API with extracted text + image + ruleset prompt.
6. Aggregate scores using `scoring_rubric.json`.
7. Return combined result.

**Hosting:** Vercel (serverless functions) or Railway/Fly.io for the Python backend. Keep it stateless for MVP.

---

## Phase 3: Flutter App Development

### Step 8: Prompt Claude Design for UI/UX

Use this prompt template for Claude Design to generate high-quality screens:

```
Design a mobile-first Flutter app for verifying peptide Certificates of Analysis.

Core user flow:
1. Upload screen — camera capture, gallery pick, or PDF upload.
   Clean, minimal. Single prominent CTA. Drag-and-drop zone for web.
2. Processing screen — progress indicator with status steps
   ("Extracting text...", "Analyzing structure...", "Checking benchmarks...")
3. Results screen — large circular score gauge (0-100),
   color-coded (green/yellow/red). Below: expandable cards
   for each rule category showing pass/fail with brief reasoning.
4. History screen — past scans with scores, searchable.

Design language: clinical but approachable. Think "health-tech meets
fintech verification." White/light gray base, accent color for trust
(deep blue or teal). Typography: clean sans-serif, strong hierarchy.
No decoration — let the data breathe.

Target audience: fitness/biohacking community members buying peptides
online who want to verify supplier claims. They're semi-technical
but not scientists.

Please provide:
- Complete screen designs for all 4 flows
- Component library (buttons, cards, score gauge, status badges)
- Color palette with hex codes
- Typography scale
- Empty states and error states
- Light and dark mode variants
```

**Iterate specifically on:**

- The results screen (this is where users form trust — try gauge vs badge vs traffic light vs detailed breakdown).
- The processing screen (users need reassurance the scan is thorough, not just fast).
- Onboarding (brief explainer on what the app checks and why).

### Step 9: Build with Claude Code

Prototype build order — prioritize the core loop first:

```
1. Flutter project scaffold
   └── Configure for web + Android targets

2. Camera / file upload + format detection
   └── camera_capture, image_picker, file_picker packages
   └── Detect image vs PDF vs document

3. API integration layer
   └── HTTP client to your backend
   └── File upload with progress
   └── Response parsing into typed Dart models

4. Results display with score breakdown
   └── Circular score gauge widget
   └── Expandable rule category cards
   └── Color-coded pass/fail/suspicious badges

5. Processing screen with status steps
   └── Animated progress through pipeline stages
   └── Estimated time remaining

6. Scan history (local storage first)
   └── SQLite or Hive for local persistence
   └── List view with score, date, peptide name

7. Web version adjustments
   └── Responsive layout
   └── Drag-and-drop upload zone
   └── Keyboard navigation
```

---

## Phase 4: Validation & Calibration

### Step 10: Test Against Your Gold Set

Run your annotated evaluation set (from Step 4) through the full pipeline. Measure:

| Metric | What It Measures | Target |
|--------|-----------------|--------|
| Accuracy | % correct classification | > 85% |
| False Positive Rate | Real COAs flagged as fake | < 5% (critical for user trust) |
| False Negative Rate | Fake COAs passing as real | < 10% (critical for user safety) |
| Score Calibration | Do scores correlate with actual authenticity? | Linear correlation > 0.8 |

### Tuning Process

1. Run all 100–200 evaluation COAs through the pipeline.
2. Compare predicted scores to known labels.
3. Identify which rules are noisy (high false positive) and reduce their weights.
4. Identify which rules are discriminative (catch fakes reliably) and increase their weights.
5. Adjust score band thresholds in `scoring_rubric.json`.
6. Re-run and measure improvement. Iterate until targets are met.

---

## Phase 5: Future Roadmap (Post-MVP)

### Gemma Migration (Local LLM)
- Fine-tune Gemma on your labeled dataset (valid + forged with annotations).
- Run on-device or on your own infrastructure for privacy and cost elimination.
- Use your evaluation set to ensure Gemma matches or exceeds Gemini Flash accuracy.

### Community Features
- User-reported COAs from specific suppliers.
- Crowd-sourced database of known labs and their COA formats.
- Supplier reputation scores aggregated over time.

### Lab Database
- Cross-reference claimed labs against verified accredited lab registries.
- Auto-check lab contact information against public records.
- Flag labs that don't appear in any accreditation database.

### Monetization
- Freemium: X free scans/month, paid for unlimited.
- API access for vendors and supplement review sites.
- Premium features: batch scanning, supplier comparison reports.

---

## Summary: Execution Order

| Phase | Deliverable | Estimated Effort |
|-------|------------|-----------------|
| 0 | Extracted ruleset + scoring rubric + LLM prompt | 2–3 days |
| 1 | Organized dataset + gold-standard annotations | 3–5 days |
| 2 | Backend API with rule engine + Gemini integration | 5–7 days |
| 3 | Flutter app (upload, results, history) | 7–10 days |
| 4 | Validation, calibration, tuning | 3–5 days |
| **Total MVP** | **Working app with scored COA analysis** | **~3–4 weeks** |

---

## Key Architectural Decisions

1. **Two-layer scoring (rules + LLM):** Deterministic rules catch obvious fakes fast and cheap. The LLM catches subtle forgeries that rules miss. Combined scoring is more robust than either alone.

2. **No fine-tuning for MVP:** Few-shot prompting with Gemini Flash is faster to iterate and sufficient. Fine-tuning is reserved for the Gemma migration when you have validated labels.

3. **Flutter for both platforms:** Single codebase for web + Android. The upload-heavy workflow works well in Flutter. Consider a dedicated web frontend only if Flutter web performance becomes a bottleneck.

4. **Backend-first pipeline:** All analysis happens server-side. The Flutter app is a thin client. This keeps the scoring logic centralized and easy to update without app releases.

5. **False positives over false negatives:** A real COA flagged as fake destroys user trust immediately. A fake COA that passes is bad but less visible. Calibrate accordingly.
