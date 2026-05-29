---
name: pptx
description: Create and edit editable PowerPoint .pptx decks with native slides, template-aware structure, visual proof objects, and rendered QA. Use for slide decks, presentations, pitch decks, board decks, and Google Slides/Keynote-ready editable slides.
---

# PPTX Skill

Use this skill when the user needs editable slides. A good PPTX is made of native slide objects: layouts, placeholders, text boxes, shapes, tables, charts, images, speaker notes, and theme-aware styling where possible.

This skill is not a single deck style. Follow the user's template, reference, audience, and content. Use presentation craft to make the deck clear, not to force every deck into the same consulting format.

## Reliable Workflow

1. Decide the mode: create, targeted edit, template-follow, or content-to-deck.
2. Separate source facts from visual/style references.
3. Choose the authoring path: `python-pptx`, template editing, or simple Pandoc draft.
4. Plan the slide sequence and what each slide needs to prove or communicate.
5. Build editable native slides.
6. Run structural checks.
7. Render to PDF/images and inspect every slide.
8. Fix objective defects and repeat up to 3 times.

Do not overwrite source decks. Save a new output file unless the user explicitly asks otherwise.

## Tool Choice

Use `python-pptx` for precise editable decks:

```python
from pptx import Presentation
from pptx.util import Inches, Pt

prs = Presentation()
prs.slide_width = Inches(13.333)
prs.slide_height = Inches(7.5)
slide = prs.slides.add_slide(prs.slide_layouts[6])
box = slide.shapes.add_textbox(Inches(0.6), Inches(0.5), Inches(8.8), Inches(0.8))
box.text_frame.text = "Growth slowed, but retention improved."
prs.save("deck.pptx")
```

Use a supplied template/source deck when style matters:

```python
from pptx import Presentation
prs = Presentation("template.pptx")
for i, layout in enumerate(prs.slide_layouts):
    print(i, layout.name)
    for ph in layout.placeholders:
        print(" ", ph.placeholder_format.idx, ph.name, ph.placeholder_format.type)
```

Use Pandoc only for quick draft decks or simple outlines. It is usually not enough for polished visual slides.

## Modes

| Mode | Use when | Default behavior |
| --- | --- | --- |
| Create | New deck from prompt/source | Build story, design system, native slides, render QA |
| Targeted edit | User wants specific changes | Preserve deck style and make surgical edits |
| Template-follow | User supplied template/source | Reuse layouts, placeholders, typography, page furniture |
| Content-to-deck | User supplied notes/docs | Extract structure, turn into slide sequence, avoid inventing facts |

## Planning The Deck

Before building slides, decide:

- Audience and decision/use case.
- Slide count or expected length.
- Source facts and what must not be invented.
- Visual grammar from any template/reference.
- Slide size, margins, typography, palette, footer/source treatment.
- What each slide should communicate: claim, explanation, walkthrough, reference, appendix, divider, or visual.
- Risk areas: crowded text, tiny labels, bad image quality, charts without sources, placeholder misuse, template drift.

Not every deck needs aggressive "claim/proof" titles, but every important slide needs a reason to exist. If a slide is only a topic label plus generic bullets, improve it, merge it, or make it an intentional agenda/divider.

## Slide Craft Defaults

Use these as defaults, not laws:

- Prefer one main idea per slide.
- Use native editable objects when practical.
- Use screenshots/images only when they are real, provided, verified, or clearly illustrative.
- Use charts, tables, diagrams, timelines, screenshots, quotes, or comparisons as evidence when the slide makes an argument.
- Keep labels and source notes readable.
- Avoid overcrowding. Split a slide or move detail to appendix when needed.
- Preserve template conventions for logos, footers, typography, and spacing.
- Do not invent metrics, logos, customer marks, partner marks, product UI, citations, or financial data.

## Geometry And Objects

- Text boxes need enough internal margin and height; avoid text overflow.
- Equal-role boxes/nodes should use consistent dimensions, padding, and hierarchy.
- Connectors should visibly attach to intended objects and avoid ambiguous crossings.
- Tables need deliberate column widths and readable padding.
- Charts need honest scales, units, source notes, and legible labels.
- Images should preserve aspect ratio. Crop deliberately instead of stretching.
- Footers/source lines/page numbers should be quiet and consistent.

## Template And Existing Decks

When editing or following a deck:

- Inspect layouts and placeholders before writing.
- Reuse existing layouts where possible.
- Preserve theme fonts, colors, logo placement, page numbers, and footer conventions unless the user asks for restyling.
- Copy/edit existing slide types when that is safer than recreating them.
- Do not restyle unrelated slides during targeted edits.
- Keep a short note of meaningful deviations from the template.

## Render And Verify

PPTX is not safe until rendered. Convert to PDF when possible:

```bash
libreoffice --headless --convert-to pdf output.pptx
```

Then inspect every rendered slide. If page-image rendering is available, review full-size slides and a contact sheet.

Structural check:

```python
from pptx import Presentation

prs = Presentation("output.pptx")
print(f"Slides: {len(prs.slides)}")
for i, slide in enumerate(prs.slides, 1):
    title = slide.shapes.title.text if slide.shapes.title else ""
    print(f"{i}: {title[:80]!r}, shapes={len(slide.shapes)}")
```

Visual QA checklist:

- Expected slide count and no accidental blank slides.
- Text is not clipped, overlapping, or too small.
- Images/logos render sharply and are not stretched.
- Charts, tables, and diagrams are readable.
- Footer/source/page markers are consistent.
- Template-following decks preserve the source grammar.
- Thumbnail/contact-sheet view makes the sequence understandable.
- Any slide making an argument has evidence or a concrete visual, not just decoration.

## Common Failures

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Text cut off | Text frame overflow | Shorten copy, split slide, enlarge box, or reduce type within readability |
| Deck feels generic | Repeated default card layout | Choose slide forms based on content and evidence |
| Slide says nothing | Topic title plus filler bullets | Rewrite around a point, proof, or concrete walkthrough |
| Chart unreadable | Too small or too many labels | Make it dominant, simplify labels, move detail to appendix |
| Connectors float | Lines not aligned to nodes | Recompute geometry and inspect render |
| Image distorted | Forced width/height | Preserve aspect ratio and crop deliberately |
| Template breaks | Wrong layout/placeholder assumptions | Inspect and reuse placeholders/layouts |
| Fonts change elsewhere | Unavailable fonts | Use template fonts or common system fonts |
| Render differs from object model | PowerPoint/LibreOffice layout behavior | Trust rendered output and adjust |

## When To Redirect

- A final non-editable slide handout can be PDF.
- Text-heavy reports belong in DOCX or PDF.
- Data-heavy workbooks belong in XLSX.
- Complex animation/video editing belongs in a video editor or the video skill.

## Stopping Criterion

Ship when the PPTX opens without repair prompts, uses editable native slides, preserves any requested template, renders cleanly, has the expected slide count, and contains no clipped text, distorted images, broken charts, accidental blank slides, or unresolved placeholders.
