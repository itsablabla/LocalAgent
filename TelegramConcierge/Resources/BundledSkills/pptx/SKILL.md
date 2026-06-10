---
name: pptx
description: Create and edit editable PowerPoint .pptx decks with native slides, template-aware structure, visual proof objects, and rendered QA. Use for slide decks, presentations, pitch decks, board decks, and Google Slides/Keynote-ready editable slides.
---

# PPTX Skill

Use this skill when the user needs editable slides. A good PPTX is made of native slide objects: layouts, placeholders, text boxes, shapes, tables, charts, images, speaker notes, and theme-aware styling where possible.

This skill is not a single deck style. Follow the user's template, reference, audience, and content. Use presentation craft to make the deck clear, not to force every deck into the same consulting format.

`${CLAUDE_SKILL_DIR}/reference.md` holds the detail: planning checklist, slide craft defaults, geometry rules, template handling, full QA checklist, and the symptom→fix table. Read it before building a deck of any substance.

## Reliable Workflow

1. Decide the mode: create, targeted edit, template-follow, or content-to-deck.
2. Separate source facts from visual/style references.
3. Author with `python-pptx`. When the user supplied a template or source deck, inspect it first: `python3 ${CLAUDE_SKILL_DIR}/inspect_pptx.py template.pptx --layouts` lists layouts and placeholders; without the flag it summarizes slides, titles, and shapes. Reuse the template's layouts and styles instead of rebuilding the look. Pandoc is only for quick outline drafts.
4. Plan the slide sequence and what each slide needs to prove or communicate. Not every deck needs aggressive "claim/proof" titles, but every important slide needs a reason to exist — a slide that is only a topic label plus generic bullets should be improved, merged, or made an intentional agenda/divider.
5. Build editable native slides. Do not invent metrics, logos, customer marks, product UI, citations, or financial data.
6. Verify structure (`inspect_pptx.py output.pptx` — slide count, titles, shapes), then render and look: `python3 ${CLAUDE_SKILL_DIR}/render_doc_pages.py output.pptx --out-dir deck_qa` converts via LibreOffice and rasterizes every slide. Inspect each one — PPTX is not safe until rendered. Check both full-size readability and thumbnail rhythm.
7. Fix objective defects and repeat up to 3 times.

Do not overwrite source decks. Save a new output file unless the user explicitly asks otherwise.

## Hard Rules

- One main idea per slide is the default; split or move detail to appendix rather than overcrowding.
- Text boxes need enough internal margin and height — text overflow is the most common defect.
- Preserve template conventions (theme fonts, colors, logo placement, footers, page numbers) and do not restyle unrelated slides during targeted edits.
- Preserve image aspect ratios; crop deliberately instead of stretching.
- Charts need honest scales, units, source notes, and legible labels.

## When To Redirect

Final non-editable handout → PDF. Text-heavy reports → DOCX or PDF. Data-heavy workbooks → XLSX. Complex animation/video → the video skill or a real editor.

## Stopping Criterion

Ship when the PPTX opens without repair prompts, uses editable native slides, preserves any requested template, renders cleanly, has the expected slide count, and contains no clipped text, distorted images, broken charts, accidental blank slides, or unresolved placeholders.
