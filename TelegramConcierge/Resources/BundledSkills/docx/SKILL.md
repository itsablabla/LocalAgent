---
name: docx
description: Create and edit Microsoft Word .docx documents with real Word structure, template-aware styling, tables/forms/comments, and rendered QA. Use for editable reports, memos, proposals, letters, contracts, forms, CVs, and Google Docs-ready documents.
---

# DOCX Skill

Use this skill when the user needs an editable Word document, not a fixed-layout PDF. A good DOCX is built from real Word structures: styles, paragraphs, lists, tables, sections, headers, footers, images, and comments. It should survive editing in Word or Google Docs.

This skill is not a house style. Preserve supplied templates and choose formatting that fits the document's purpose.

## Reliable Workflow

1. Decide the task mode: create, edit, template-follow, redline/comment, or Google Docs-ready.
2. Separate source content from reference/style material.
3. Choose the authoring path: `python-docx`, Pandoc, or template editing.
4. Build real Word structure, not visual fakes.
5. Run structural checks on the package.
6. Render to PDF if possible and inspect pages visually.
7. Fix objective defects and repeat up to 3 times.

Do not overwrite the user's original file. Create a new output file unless explicitly asked otherwise.

## Tool Choice

Use `python-docx` for most precise DOCX work:

```python
from docx import Document
from docx.shared import Inches, Pt

doc = Document()
section = doc.sections[0]
section.top_margin = Inches(1)
section.bottom_margin = Inches(1)
section.left_margin = Inches(1)
section.right_margin = Inches(1)

style = doc.styles["Normal"]
style.font.name = "Aptos"
style.font.size = Pt(11)

doc.add_heading("Decision Memo", level=1)
doc.add_paragraph("Recommendation: proceed with the focused pilot.")
doc.save("output.docx")
```

Use Pandoc for straightforward prose drafts, especially Markdown to DOCX:

```bash
pandoc input.md -o output.docx
pandoc input.md --reference-doc=template.docx -o output.docx
```

Use an existing DOCX as the starting point when the user supplies a template or wants targeted edits. Inspect and reuse its styles instead of rebuilding the look from scratch.

Avoid GUI automation. LibreOffice is useful for conversion/render QA, not as the main authoring engine.

## Task Modes

| Mode | Use when | Default behavior |
| --- | --- | --- |
| Create | New document from prompt/source | Choose an archetype, build structure, render QA |
| Targeted edit | User wants limited changes | Preserve layout and make surgical edits |
| Major rewrite | User wants stronger structure or tone | Preserve facts, redesign organization carefully |
| Template-follow | User supplied a branded/source DOCX | Start from it and preserve style/furniture |
| Redline/comment | User wants review feedback | Put comments/markers near relevant text |
| Google Docs-ready | Output will be imported to Google Docs | Prefer simple native styles and avoid Word-only tricks |

## Structure Rules

- Use real Heading styles for headings. Do not fake headings with bold body text.
- Use real list/numbering behavior. Do not type manual numbers or repeated spaces for alignment.
- Use tables for repeated comparable records, forms, schedules, budgets, and matrices. Do not use tables to hold ordinary prose unless making a form.
- Set page size, orientation, margins, header/footer distance, and section breaks intentionally.
- Preserve image aspect ratios. Do not stretch logos, signatures, screenshots, or diagrams.
- Preserve existing styles, numbering, headers, footers, and table geometry during targeted edits.
- Do not invent legal clauses, signatures, citations, metrics, logos, tax IDs, or organizational claims.

## Planning The Document

Before generating or editing, decide:

- Document type: memo, report, proposal, SOP, contract, form, letter, CV, handbook, questionnaire, brief, appendix pack.
- Audience and editing destination: Word, Google Docs, internal review, client-ready, legal review.
- Page setup: A4/Letter, portrait/landscape, margins, headers/footers.
- Content forms: prose, bullets, numbered steps, checklist, table, form field, figure, appendix, comment.
- Risk areas: long tables, nested lists, page breaks, comments, headers/footers, images, template preservation.

Choose the simplest structure that lets collaborators edit comfortably.

## Tables And Forms

Tables are a common source of broken DOCX output. Treat them as structure:

- Give columns deliberate widths. Short fields like date, owner, amount, status, score, or checkbox should be compact; narrative fields get space.
- Let rows expand. Avoid fixed row heights that clip wrapped text.
- Use enough padding and line spacing that text is not pinned to borders.
- Repeat header rows on long tables when possible.
- Align by data type: right-align numbers/currency, center compact statuses/dates/checkmarks, left-align narrative text.
- Keep captions/source notes close to the table.
- Forms should feel fillable: clear labels, visible response areas, generous row height, and restrained borders.

## Existing Documents

When editing an existing DOCX:

- Preserve the original and save a new file.
- Inspect styles, headings, tables, sections, headers, and footers first.
- Make the smallest change that satisfies the request.
- Do not restyle unrelated sections.
- For comments/reviews, attach feedback near the relevant passage, not only in a final summary.
- If true tracked changes are not available, use comments, visible markers, or a companion change summary.

Useful inspection:

```python
from docx import Document

doc = Document("input.docx")
print("Paragraphs:", len(doc.paragraphs))
print("Tables:", len(doc.tables))
for p in doc.paragraphs:
    if p.style and p.style.name.startswith("Heading"):
        print(p.style.name, p.text[:100])
for i, section in enumerate(doc.sections, 1):
    print(i, section.page_width, section.page_height, section.left_margin, section.right_margin)
```

## Render And Verify

Open-package checks are not enough because DOCX layout depends on the renderer. Convert to PDF when possible:

```bash
libreoffice --headless --convert-to pdf output.docx
```

Then inspect the rendered PDF/pages visually.

Structural checks:

```python
from docx import Document

doc = Document("output.docx")
print(f"Paragraphs: {len(doc.paragraphs)}")
print(f"Tables: {len(doc.tables)}")
for i, table in enumerate(doc.tables, 1):
    print(f"Table {i}: {len(table.rows)} rows x {len(table.columns)} cols")
```

Visual QA checklist:

- Opens without repair prompts.
- Expected page count and no accidental blank pages.
- Title, headings, body, captions, callouts, and footnotes have clear hierarchy.
- No clipped text, overlapping objects, broken images, or missing glyphs.
- Tables fit the page, rows expand, and columns are deliberate.
- Lists wrap with correct indentation.
- Headers, footers, page numbers, dates, confidentiality labels, and source notes are aligned.
- Existing-document edits did not accidentally restyle unrelated content.
- Google Docs-ready files avoid complex floating objects and Word-only decoration.

## Common Failures

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Navigation pane is empty | Fake heading formatting | Apply real Heading styles |
| Bullets wrap badly | Manual bullets or bad indents | Use real list/numbering styles |
| Table text clips | Fixed row height or tight padding | Allow row growth and add padding |
| Table runs off page | Default widths/autofit | Set explicit widths and compact short columns |
| Footer overlaps body | Bad section margins/footer distance | Adjust section properties and re-render |
| Image/logo distorted | Forced width and height | Preserve aspect ratio or crop deliberately |
| Template branding lost | Rebuilt from scratch | Start from template and reuse styles |
| Google Docs import looks odd | Word-only layout tricks | Simplify to native styles/tables |
| Render differs from XML inspection | Word layout engine behavior | Trust visual render and fix the DOCX |

## When To Redirect

- Pixel-perfect final layout belongs in PDF.
- Slide-native storytelling belongs in PPTX.
- Interactive formulas and grids belong in XLSX.
- "Editable PDF" needs clarification: DOCX, PDF form, or annotated PDF.
- Legal/contracts need provided or user-approved language; do not invent clauses.

## Stopping Criterion

Ship when the DOCX opens cleanly, uses real Word structure, preserves any requested template, renders cleanly page by page, and has no clipped content, broken tables, accidental restyling, or unresolved placeholders.
