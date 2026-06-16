# COA Faker Generator — Claude Code Prompt

You are building a Python tool that takes authentic Certificate of Analysis (COA) PDF reports and generates realistic tampered/fake versions for training a document authenticity detection model.

## Project Structure

```
coa-faker/
├── input/              # Place real COA PDFs here
├── output/             # Generated fakes go here
├── faker_engine.py     # Main generation logic
├── perturbations.py    # All tampering functions
├── config.yaml         # Controls what/how much to fake
└── requirements.txt
```

## Requirements

- Python 3.10+
- Libraries: pymupdf (fitz), Pillow, reportlab, faker, pyyaml, numpy

## What the Tool Must Do

### Step 1 — Parse Real COAs
- Extract text, layout coordinates, fonts, font sizes, and colors from each page using PyMuPDF
- Extract embedded images (logos, stamps, signatures)
- Extract PDF metadata (author, producer, creation date, mod date)
- Store everything in a structured dict per document

### Step 2 — Apply Perturbations
Generate multiple fake variants per real COA. Each fake should have 1-3 perturbations randomly selected from these categories:

**Data Tampering (text-level)**
- Alter numeric test results (shift values ±5-20%, or push out of spec range)
- Change batch/lot numbers (swap digits, increment, randomize)
- Modify dates (shift by days/months, use inconsistent formats)
- Swap lab name or analyst name with a plausible fake (use Faker library)
- Change product name or description subtly

**Visual Tampering (image-level)**
- Render page to image, then paste edited text over original (slightly mismatched font)
- Shift or resize the logo slightly
- Add or remove a watermark
- Alter the quality/DPI (e.g., re-save at lower JPEG quality to simulate scan-of-a-copy)
- Introduce subtle alignment issues (shift a text block by 1-3 pixels)

**Metadata Tampering**
- Change PDF author, producer, or creator fields
- Alter creation/modification timestamps (make them inconsistent)
- Strip or fake digital signatures if present
- Change the PDF producer string to a different software

**Structural Tampering**
- Remove or duplicate a page
- Reorder sections
- Insert an extra blank or near-blank page
- Change page dimensions slightly

### Step 3 — Label & Export
- Save each fake as a PDF in `output/`
- Generate a `manifest.csv` with columns:
  - `filename` — output filename
  - `source_file` — which real COA it was based on
  - `perturbation_types` — comma-separated list of what was changed (e.g., "test_values,date,metadata_author")
  - `difficulty` — easy / medium / hard
  - `is_fake` — always True for generated, False for originals copied to output
- Also copy the original (unmodified) COAs into `output/` and include them in the manifest as `is_fake=False`

### Step 4 — Config file (config.yaml)

```yaml
fakes_per_original: 5         # how many fakes to generate per real COA
difficulty_distribution:
  easy: 0.3
  medium: 0.5
  hard: 0.2
perturbation_weights:
  test_values: 0.8
  batch_number: 0.6
  dates: 0.7
  names: 0.4
  logo_shift: 0.3
  font_mismatch: 0.5
  metadata: 0.6
  dpi_quality: 0.4
  alignment: 0.3
  page_structure: 0.2
image_render_dpi: 300
output_format: pdf             # pdf or png
seed: 42                       # for reproducibility
```

## Difficulty Levels

- **Easy**: Obvious changes — wrong font, clearly altered values, missing logo, broken layout
- **Medium**: Plausible changes — correct-looking font but wrong values, slightly shifted elements, altered metadata only
- **Hard**: Subtle changes — values within plausible range but inconsistent with other fields, metadata-only tampering, micro-alignment shifts, slight DPI difference

## Important Constraints

- Never modify the original input files
- Every generated fake must be visually openable as a valid PDF
- Use deterministic seeding so results are reproducible
- Print progress to stdout: `[3/50] Generating medium fake from report_042.pdf → fake_042_003.pdf`
- Handle errors gracefully — if a COA can't be parsed, skip it and log a warning

## Run Command

```bash
python faker_engine.py --input ./input --output ./output --config config.yaml
```

Build the complete tool now. Start by reading the SKILL.md files for any relevant skills, then implement all files.
