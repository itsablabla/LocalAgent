---
name: docx
description: Generate high-quality Microsoft Word (.docx) documents for reports, memos, proposals, letters, contracts, forms, CVs, and editable Google Docs-ready files, with real Word structure and rendered visual QA. Use when the user asks for Word, DOCX, editable document, Google Docs-ready document, redline, comments, or a text-heavy file collaborators will edit.
---

# DOCX Skill

Word documents are editable structured artifacts, not PDFs with a different extension. A good `.docx` uses real Word styles, numbering, tables, headers, footers, comments, and section properties so it survives editing in Word or Google Docs.

Use this skill when the user needs an editable text-heavy deliverable. Use the PDF skill when the user needs final fixed layout. Use PPTX when the user needs slide-native editing.

## Quality contract

Every serious DOCX must pass three tests:

- **Structure test**: headings are real heading styles, lists use real numbering, tables use real table cells, references/comments are placed where they belong, and page setup is intentional.
- **Form-factor test**: prose, bullets, steps, tables, forms, callouts, and appendices are chosen because they fit the reading task, not because they are convenient.
- **Render test**: the file is converted to PDF/PNGs and every page is visually inspected for clipping, overflow, broken tables, orphan headings, bad page breaks, missing images, and header/footer issues.

Do not deliver a DOCX until it has been rendered and visually inspected. If rendering tooling is unavailable, run structural checks and say visual QA could not be completed.

## Task modes

Classify the request before touching the file:

| Mode | User intent | Default behavior |
| --- | --- | --- |
| `create` | Build a new document | Pick an archetype, choose a style preset, draft, render, revise |
| `major-rewrite` | Repackage or redesign supplied content | Preserve facts, redesign structure and hierarchy, render, revise |
| `targeted-edit` | Make limited edits to an existing DOCX | Preserve the source layout; make surgical edits only |
| `redline/comment` | Review with tracked-style changes or margin feedback | Use comments/markers at the relevant text, avoid end-only feedback |
| `template-following` | User supplied a branded/template DOCX | Start from the template and preserve its styles/furniture unless asked to restyle |
| `google-docs-ready` | Output will be imported to Google Docs | Keep styling native and simple; avoid Word-only visual tricks |

## Tool choice

**Primary for polished documents: `python-docx` plus small OOXML patches when needed.** Use it when you need exact styles, tables, headers/footers, page setup, comments placeholders, images, or template preservation.

```python
from docx import Document
from docx.shared import Inches, Pt

doc = Document()
section = doc.sections[0]
section.top_margin = Inches(1)
section.bottom_margin = Inches(1)
section.left_margin = Inches(1)
section.right_margin = Inches(1)

styles = doc.styles
styles["Normal"].font.name = "Calibri"
styles["Normal"].font.size = Pt(11)

doc.add_heading("Decision Memo", level=1)
doc.add_paragraph("Recommendation: proceed with the focused pilot.")
doc.save("output.docx")
```

**Pandoc markdown to DOCX: useful for clean prose drafts.** Use it for straightforward memos, articles, and briefs, especially with a reference document. Do not rely on it for complex tables, forms, comments, images, strict page furniture, or template-sensitive work.

```bash
pandoc input.md --reference-doc=template.docx -o output.docx
```

**Template mode:** if the user supplies a Word template or source document, open it as `Document("template.docx")`, inspect its styles, and reuse them. Do not invent a new visual system unless the user asks.

Avoid fragile GUI automation. Use LibreOffice only for headless conversion/render QA, not as the authoring engine.

## Workflow

1. **Separate source from reference**:
   - Source material determines facts and required content.
   - Reference/template determines visual grammar.
   - Never invent logos, signatures, legal terms, metrics, citations, or organizational claims.
2. **Choose the document archetype**:
   - memo, report, proposal, SOP, contract, form, letter, CV, handbook, questionnaire, brief, or appendix pack.
3. **Choose a style preset**:
   - template style, native Google Docs, formal business, compact reference, narrative proposal, or plain correspondence.
4. **Plan the form factors**:
   - decide where content should be prose, bullets, numbered steps, checklist, table, form field, callout, figure, or appendix.
5. **Build real Word structure**:
   - styles for headings/body/captions, real numbering for lists, explicit table widths, page setup, headers/footers, and images with alt text when practical.
6. **Run structural checks**:
   - paragraph/table counts, heading map, table widths, image count, empty paragraphs, expected comments/appendices.
7. **Render and inspect**:
   - convert DOCX to PDF, render pages to PNGs if possible, and inspect every page.
8. **Fix and re-render**:
   - cap at 3 QA loops; fix objective formatting/content defects first.

## Style presets

Pick one visual system and keep it stable. Do not mix heading colors, body spacing, list indents, table fills, or page furniture from multiple systems.

### Native Google Docs

Use for documents the user will import into Google Docs.

- Fonts: Arial or a Google Docs-native equivalent.
- Title: plain paragraph, 24-28 pt, black, no decorative underline or Word title border.
- Headings: black or dark gray, simple spacing, no cover-page furniture unless requested.
- Tables: minimal borders, no heavy fills, only for real tabular data.
- Avoid Word-specific title effects, section bands, ornate headers, and complex floating objects.

### Formal Business

Use for board memos, decision memos, RFI responses, executive briefs, formal reports.

- Fonts: Calibri/Aptos/Arial, 10.5-11.5 pt body.
- Page: Letter or A4, 0.8-1.0 in margins.
- Hierarchy: restrained blue/black headings, clear metadata block, quiet footer/page numbers.
- Tables: fixed widths, shaded header row, readable padding, repeated header rows when long.
- Good for dense but polished documents where authority matters more than expressiveness.

### Compact Reference

Use for SOPs, checklists, launch guides, playbooks, negotiation briefs, handbooks.

- Keep sections short and scannable.
- Use numbered procedures, checklists, key-value blocks, and compact tables deliberately.
- Use callouts only for warnings, decisions, or constraints.
- Avoid long unbroken prose runs.

### Narrative Proposal

Use for grants, project proposals, persuasive letters, partnership documents.

- More generous spacing and longer prose sections are acceptable.
- Use a strong opening summary, clear section transitions, and selective callouts for decisions or asks.
- Tables should support budgets, milestones, responsibilities, or evaluation criteria, not replace prose.

### Plain Correspondence

Use for letters, cover letters, notices, formal correspondence.

- Use block-letter conventions, restrained typography, and predictable spacing.
- Avoid decorative layouts unless the user supplied branding.
- Signature blocks, dates, recipient address, subject, and enclosure notes must be complete when applicable.

## Form-factor rules

Choose the representation that helps the reader act:

- **Prose section**: explanation, rationale, background, narrative.
- **Lead callout**: recommendation, decision, executive takeaway.
- **Numbered steps**: ordered workflow, procedure, legal sequence.
- **Grouped bullets**: unordered factors, requirements, pros/cons.
- **Checklist**: actions, acceptance criteria, review gates.
- **Definition list**: terms, metadata, responsibilities, key facts.
- **Table**: repeated comparable records with shared fields.
- **Form layout**: questionnaires, intake forms, approvals, sign-offs.
- **Source list**: evidence, citations, attachments, appendix material.

Tables are not a container for normal prose. If most cells contain paragraph-length text, convert the section to prose, bullets, steps, callouts, or an appendix.

## Word structure rules

- Use built-in heading styles or explicitly defined named styles. Do not fake headings with bold body paragraphs.
- Use real numbering definitions for bullets and ordered lists. Do not type bullet characters, hyphen bullets, or manual numbers.
- Use tabs/table cells/key-value styles for alignment. Do not align with repeated spaces.
- Set section page size, orientation, margins, header distance, and footer distance intentionally.
- Add page breaks or section breaks when the document logic requires them; do not rely on accidental flow.
- Use real table rows/cells with explicit column widths. Do not use tables as decorative page layout unless the task is a form.
- Preserve image aspect ratios and compress/crop deliberately. Do not stretch logos, signatures, screenshots, or diagrams.
- Use comments or clear inline markers for reviews. Do not hide all feedback in a final summary.
- For existing documents, preserve the original style unless the user asked for redesign.

## Tables and forms

Tables and forms cause many DOCX failures. Treat them as geometry, not decoration.

- Decide the table's purpose before creating it: comparison, schedule, budget, compliance matrix, status grid, or data-entry form.
- Set fixed column widths based on content. Short fields such as date, owner, status, amount, score, or checkbox should be compact; narrative columns get space.
- Use enough cell padding and line spacing that text never looks pinned to borders.
- Do not use fixed row heights that can clip wrapped text.
- Align by data type: right-align numbers/currency, center compact statuses/dates/checkmarks, left-align narrative text.
- Repeat header rows for long tables when possible.
- Keep captions/source notes visually paired with their tables.
- Forms should feel fillable: clear labels, obvious response areas, generous row height, and restrained borders.

## Render and verification

Convert to PDF and inspect rendered pages:

```bash
libreoffice --headless --convert-to pdf output.docx
```

Then inspect the PDF visually. If a PDF page-render helper is available, render pages to PNGs and review the PNGs/contact sheet. If not, use the app's PDF inspection/read capability and page through the rendered PDF.

Programmatic sanity check:

```python
from docx import Document

doc = Document("output.docx")
print(f"Paragraphs: {len(doc.paragraphs)}")
print(f"Tables: {len(doc.tables)}")
for p in doc.paragraphs:
    if p.style and p.style.name.startswith("Heading"):
        print(p.style.name, p.text[:100])
for i, table in enumerate(doc.tables, 1):
    print(f"Table {i}: {len(table.rows)} rows x {len(table.columns)} cols")
```

Visual QA checklist:

- Expected page count and no accidental blank pages.
- Title, headings, body, captions, footnotes, and callouts have distinct hierarchy.
- No clipped text, overlapping objects, missing glyphs, or broken images.
- No orphan headings at page bottoms or stranded captions.
- Tables fit the page, columns are deliberate, rows expand, and text has padding.
- Lists wrap with correct hanging indents.
- Headers, footers, page numbers, dates, confidentiality labels, and source notes are aligned and consistent.
- Existing-document edits did not unintentionally restyle unrelated sections.
- Google Docs-ready output has no decorative Word title underline/border residue.

## Editing, redlines, and comments

When editing an existing DOCX:

- Preserve the source file and create a new output file.
- Make the smallest change that satisfies the request.
- Preserve styles, margins, headers, footers, numbering, and table geometry unless the user asked for redesign.
- For reviews, attach comments/markers near the relevant passage. Avoid dumping all feedback at the end.
- For redline-like edits, make changes traceable through comments, revision notes, or a companion summary if true tracked changes are not available.
- Do not rewrite whole sections just to improve tone unless the user asked for a rewrite.

## Common bugs

| Symptom | Cause | Fix |
| --- | --- | --- |
| Heading looks right but navigation pane is empty | Fake heading formatting | Apply real Heading styles |
| Bullets wrap badly | Manual bullets or missing hanging indent | Use real numbering definitions |
| Table text is clipped | Fixed row height or tiny cell padding | Allow row growth and increase padding |
| Table runs off page | Autofit/equal columns/default width | Set explicit widths and compact short columns |
| Google Docs import shows a title line | Word Title style border residue | Use a plain formatted title paragraph and sanitize/rebuild the title |
| Footer overlaps content | Bad margins/footer distance | Adjust section properties and re-render |
| Images distort | Forced width and height | Preserve aspect ratio and crop intentionally |
| Existing doc loses branding | Rebuilt from scratch | Start from template/source document and reuse styles |
| Render differs from package inspection | DOCX is layout-engine dependent | Trust rendered PDF/PNGs and fix the file |

## When to push back

- "Editable PDF" usually means DOCX or a PDF form; clarify which behavior matters.
- Pixel-perfect layout belongs in PDF, not DOCX.
- Spreadsheet-like formulas or interactive grids belong in XLSX.
- Slide-native storytelling belongs in PPTX.
- Legal/contracts need source text or user-approved clauses; do not invent legal language.

## Stopping criterion

Ship only when the `.docx` opens without repair prompts, uses real Word structure, matches the chosen style/template, renders cleanly page by page, and has no clipped content, broken tables, accidental restyling, or unresolved placeholders. Return the final DOCX only unless the user asks for QA artifacts.
