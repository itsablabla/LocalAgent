---
name: pptx
description: Generate high-quality PowerPoint (.pptx) decks with editable slides, claim/proof structure, rendered visual QA, and template-aware workflows. Use when the user asks for PowerPoint, pptx, slide deck, presentation, or editable Keynote/Google Slides-ready output.
---

# PPTX Skill

PowerPoint decks are editable visual arguments. A good deck is not a list of bullets in slide containers; it has a story, a design system, proof objects, and slide-by-slide visual quality.

Use this skill when the user needs an editable `.pptx`. Use the `pdf` skill when they only need a final non-editable slide-style PDF.

## Quality contract

Every serious deck must pass three tests:

- **Claim/proof test**: every non-divider slide has a conclusion title and a proof object: chart, table, timeline, diagram, screenshot, image, quote, or comparison.
- **Contact-sheet test**: thumbnails show a coherent system, varied rhythm, and no generic repeated template.
- **Render test**: every slide renders cleanly; no clipped text, missing images, broken charts, overlapping shapes, or unreadable labels.

Do not deliver a PPTX until it has been rendered or converted to PDF/PNGs and visually inspected. If rendering tooling is unavailable, run structural checks and say visual QA could not be completed.

## Tool choice

**Primary: `python-pptx`.** Use for editable decks with precise control over slides, shapes, text boxes, images, tables, and speaker notes.

```python
from pptx import Presentation
from pptx.util import Inches, Pt

prs = Presentation()
prs.slide_width = Inches(13.333)
prs.slide_height = Inches(7.5)
slide = prs.slides.add_slide(prs.slide_layouts[6])  # blank
title = slide.shapes.add_textbox(Inches(0.6), Inches(0.45), Inches(8.8), Inches(0.8))
title.text_frame.text = "Retention, not acquisition, is now carrying growth."
prs.save("deck.pptx")
```

**Template mode: `python-pptx` from template.** If the user supplies a branded/template deck, start from `Presentation("template.pptx")`, inspect layouts/placeholders, and preserve the source visual system unless the user asks to restyle.

**Pandoc markdown to PPTX: only for simple content drafts.** It is acceptable for quick internal outlines but usually too generic for polished decks.

## Workflow

1. **Classify task mode**:
   - `template-following`: user supplied a template/source deck and wants the output in that style.
   - `targeted-edit`: user wants changes to an existing deck.
   - `create`: build a new deck from prompt/source material.
2. **Extract source and reference**:
   - Source material determines facts and required sections.
   - Reference/template determines visual grammar.
   - Never invent metrics, logos, customer marks, partner marks, or product UI.
3. **Write the claim spine** before making slides:
   - thesis
   - audience
   - one-line arc
   - slide list with kicker, claim title, proof object, source, and omission notes
4. **Lock the design system**:
   - slide size, margins/grid, typography, palette, chart grammar, diagram grammar, footer/source grammar, brand asset policy
5. **Plan the contact sheet**:
   - pick macro-layout families before building
   - for a 10-slide deck, use at least 5 distinct layout families unless a template or operating-review format intentionally repeats
6. **Build editable slides**:
   - prefer native shapes/text/tables/images over flattened screenshots
   - use charts/diagrams as proof, not decoration
7. **Programmatic sanity check**:
   - slide count, titles, empty slides, shape counts, missing images
8. **Render and inspect**:
   - convert to PDF or PNGs, inspect every slide and the contact sheet
9. **Fix and re-render**:
   - cap at 3 QA loops; fix objective defects first

## Claim spine rules

Every non-appendix, non-divider slide needs:

- **Kicker**: 1-3 words naming slide role, e.g. `MARKET SHIFT`, `MARGIN BRIDGE`, `PRODUCT LOOP`.
- **Claim title**: a conclusion, not a topic label.
- **Proof object**: the visual/evidence that proves the claim.
- **Support note**: concise factual context, source-backed when data is external.

Bad title: `Revenue and margin trends`

Good title: `Growth slowed, but the margin engine kept expanding.`

If a title can be reused after swapping the company/topic name, sharpen it.

## Design system

Define and reuse these tokens:

- **Slide geometry**: default 16:9 widescreen (`13.333 x 7.5 in`) unless user/template says otherwise.
- **Safe margins**: usually 0.45-0.65 in; do not place important content at the edge.
- **Typography**: title 28-40 pt, section/cover claims 44-64 pt, body 16-24 pt, chart labels 9-14 pt, footers 7-9 pt.
- **Palette**: neutral/base, main accent, secondary/support; avoid one-note navy/teal/beige/gray unless brand-driven.
- **Chart grammar**: direct labels, unit labels, restrained gridlines, source notes.
- **Container grammar**: boxes only for real grouping, stages, comparisons, or metrics.
- **Footer grammar**: quiet source line/page marker, consistent placement.
- **Brand policy**: use provided/verified logos/assets only. Do not approximate identity marks.

Use fewer objects with stronger hierarchy. Hairline rules and whitespace often beat boxes and shadows.

## Macro-layout families

Choose layouts by proof object:

| Family | Use when | Structure |
| --- | --- | --- |
| Claim + evidence | Argument needs explanation | Large claim, dominant proof, compact side note |
| Chart hero | Data carries the slide | Chart dominates, direct labels, 1-2 callouts |
| Metric bridge | Metrics need comparison | KPI row plus bridge/waterfall/variance explanation |
| Product proof | Workflow/UI matters | Screenshot or product diagram with attached labels |
| System map | Architecture/process/loop | Nodes/connectors with clear direction and grouping |
| Timeline/roadmap | Sequence matters | Stages/dates/milestones plus implication |
| Editorial image | Real-world subject matters | Strong image with claim and concise caption |
| Quote/evidence | Source/customer voice is proof | Quote, attribution, implication |
| Comparison matrix | Options need evaluation | Deliberate columns, compact criteria, clear winner/tradeoffs |
| Appendix/table | Detail must survive | Dense but aligned table/source page |

Hard gates:

- No repeated `title + subtitle + three equal cards` default.
- No more than 2 card-grid slides in a 10-slide deck.
- No 3 consecutive slides with the same macro layout unless intentionally template-driven.
- No icons as proof; icons may label navigation, not carry the argument.
- No decorative arrows; arrows must encode causality, flow, or direction.

## Structured visual rules

Charts, tables, diagrams, and connectors are high-risk. Treat them as geometry systems:

- Define what the visual proves before drawing.
- Use one dominant proof object per slide.
- Directly label marks/series where possible.
- Keep chart scales honest; do not invent missing values.
- Use tabular figures for numbers.
- Diagram connectors must visibly attach to intended nodes, avoid ambiguous crossings, and terminate cleanly.
- Equal-role boxes/nodes must share dimensions, padding, border logic, and text hierarchy.
- Text inside boxes needs breathing room; if it only fits with tiny type or edge-hugging text, shorten copy or enlarge the box.
- Tables need deliberate column widths, header treatment, and cell padding. Do not use tables to package normal prose.
- Screenshots/images must be sharp and relevant. Avoid blurred atmospheric filler.

## Template-following mode

If a template/source deck is provided:

- Inspect slide layouts and placeholder names before editing.
- Preserve typography, palette, page furniture, logo placement, and spacing unless explicitly restyling.
- Map each output slide to an existing layout or source slide type.
- Do not rebuild the source style from scratch if copying/editing template slides is possible.
- Record deviations: what changed, why, and whether the user asked for it.

Useful inspection snippet:

```python
from pptx import Presentation
prs = Presentation("template.pptx")
for i, layout in enumerate(prs.slide_layouts):
    print(i, layout.name)
    for ph in layout.placeholders:
        print(" ", ph.placeholder_format.idx, ph.name, ph.placeholder_format.type)
```

## Render and verification

PPTX is not safe until rendered. Convert to PDF and inspect:

```bash
libreoffice --headless --convert-to pdf output.pptx
```

Then `read_file output.pdf` and inspect every slide. If possible, render PDF pages to PNGs and review a contact sheet.

Programmatic sanity check:

```python
from pptx import Presentation
prs = Presentation("output.pptx")
print(f"Slides: {len(prs.slides)}")
for i, slide in enumerate(prs.slides, 1):
    title = slide.shapes.title.text if slide.shapes.title else ""
    shape_count = len(slide.shapes)
    print(f"{i}: {title[:80]!r} ({shape_count} shapes)")
```

Visual QA checklist:

- Expected slide count.
- Every non-divider slide has a claim title and proof object.
- No text clipped, overlapping, or too small.
- Contact sheet shows coherent system and varied rhythm.
- Charts/tables/diagrams are readable and correctly labeled.
- Images/logos render sharply and are not stretched.
- Footers/source lines/page markers are consistent.
- Template-following decks preserve source grammar.

## Common bugs

| Symptom | Cause | Fix |
| --- | --- | --- |
| Text disappears off bottom | Text frame overflow | Shorten copy, split slide, enlarge box, or reduce type within legibility bounds |
| Deck feels generic | Repeated title + cards template | Rebuild around claim spine and proof objects |
| Slide has no evidence | Topic title plus decorative bullets | Add chart/table/diagram/image/quote or merge/delete slide |
| Chart labels unreadable | Chart too small or labels too dense | Make chart hero, direct-label fewer values, move detail to appendix |
| Connectors float | Lines not attached/aligned to nodes | Recompute node geometry; attach connectors visually and avoid crossings |
| Images distorted | Forced width/height ratio | Preserve aspect ratio and crop deliberately |
| Template looks broken | Wrong placeholder/layout assumptions | Inspect layout placeholders before assigning |
| Fonts change on another machine | Non-system fonts without embedding | Use common fonts or user-provided template fonts |

## Stopping criterion

The PPTX opens without repair prompts, renders cleanly, has the expected slide count, passes contact-sheet review, and every meaningful slide has a claim, proof object, readable layout, and coherent style. Ship only the final `.pptx` unless the user asks for QA artifacts.
