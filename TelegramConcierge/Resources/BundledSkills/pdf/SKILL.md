---
name: pdf
description: Create polished PDF documents with HTML/CSS source, renderer-aware layout, and visual QA by rendering pages to images. Use for fixed-layout reports, essays, invoices, letters, printable handouts, slide-style PDFs, and other final PDFs.
---

# PDF Skill

PDF quality comes from judgment plus inspection. Use this skill to make final fixed-layout documents that survive printing, sharing, and close reading.

This skill is deliberately not a design template. Do not force every PDF into the same visual style. Choose the structure, density, typography, and amount of visual treatment that fits the user's intent, source material, audience, and any supplied reference.

## Non-Negotiable Workflow

1. Identify the document type and audience.
2. Choose a source format. Default to HTML/CSS for new PDFs.
3. Build the document with reusable CSS and intentional page geometry.
4. Render the PDF.
5. Render the PDF pages to PNGs and inspect them visually.
6. Fix objective defects and re-render. Repeat up to 3 times.

The file existing is not enough. Text extraction is not enough. A PDF is ready only when the rendered pages look correct.

Use the bundled helper when possible:

```bash
python3 ${CLAUDE_SKILL_DIR}/render_pdf_pages.py output.pdf --out-dir pdf_qa
```

The helper tries Poppler's `pdftoppm`, then PyMuPDF. If neither is available, inspect the PDF through the app's PDF/page preview capability or another visual route, and mention the limitation only if it affects confidence.

## Source And Renderer

Default path for new PDFs:

```bash
weasyprint input.html output.pdf
python3 ${CLAUDE_SKILL_DIR}/render_pdf_pages.py output.pdf --out-dir pdf_qa
```

Use WeasyPrint for most documents: reports, essays, invoices, letters, contracts, tables, headers/footers, page counters, and print CSS.

Use headless Chromium when the design depends heavily on browser layout behavior such as complex flex/grid, canvas output, or interactive-to-static screenshots:

```bash
chromium --headless --disable-gpu --print-to-pdf=output.pdf input.html
```

Avoid imperative PDF libraries such as reportlab/fpdf for flowing documents unless there is a specific reason. They are fine for precise generated forms or labels, but they make ordinary document layout harder than HTML/CSS.

Keep scratch files in a task-specific folder such as `tmp/pdfs/<task-slug>/` or beside the source. Unless the user asks for internals, deliver the final PDF.

## First Decision: What Kind Of PDF Is This?

Classify before designing. Different PDFs want different rhythm.

| Type | Examples | What good usually means |
| --- | --- | --- |
| Essay / paper / article | Academic paper, op-ed, long prose | Consistent reading rhythm, restrained headings, good line length |
| Report / brief | Executive brief, analysis, board packet | Clear findings, evidence hierarchy, navigable sections, useful tables/figures |
| Transactional | Invoice, receipt, quote, statement | Precise alignment, obvious parties/dates/totals, sober styling |
| Letter / memo | Cover letter, formal letter, decision memo | Conventional structure, complete metadata, simple page furniture |
| Slide-style PDF | Pitch, board slides, presentation handout | Fixed pages, strong claims, proof objects, readable thumbnails |
| Flyer / one-sheet | Event flyer, sell sheet, brochure page | Clear offer, scannable hierarchy, real assets, visible CTA |

These are starting points, not laws. If the user provides a reference, template, brand guide, or explicit preference, follow that unless it causes objective quality problems.

## Design Judgment

Before writing the source, make a short internal plan:

- Document type and audience.
- Page size and likely page count.
- Reading density: sparse, normal, dense, or appendix-like.
- Typography: body size, heading ladder, line height, and font fallbacks.
- Main content forms: prose, table, figure, chart, callout, form field, image, appendix.
- Risk areas: long tables, footnotes, narrow columns, images, page breaks, legal text, totals, source notes.

Use the simplest layout that expresses the content well. Prefer clear hierarchy over decoration. Add visual treatments only when they help the reader understand, decide, compare, or act.

Do not invent facts, citations, logos, signatures, legal terms, tax IDs, payment information, customer names, partner marks, product screenshots, or data. If placeholders are needed, make them obvious.

## Flexible Defaults

These defaults are useful, but they are not mandatory:

- Body text: usually 10-12pt for A4/Letter prose.
- Line height: usually 1.4-1.6 for reading.
- Margins: usually 1.8-2.5cm for reports/articles; wider for formal letters; smaller only when density demands it.
- Fonts: use available system fonts with fallbacks. A serif body plus sans headings works well for prose; all-sans works well for business/technical documents.
- Page numbers: use quiet footers for multi-page documents unless a cover or one-page format makes them unnecessary.
- Tables: use deliberate column widths, repeated headers where possible, padded cells, and numeric alignment.
- Images: preserve aspect ratio, keep them sharp, and pair them with captions/source notes when they are evidence.

Override these whenever the user's target, reference, language, or content makes another choice better.

## Minimal CSS Foundation

Start from this only when it fits. Adjust it rather than letting it become the design.

```css
@page {
  size: A4;
  margin: 2cm 2cm 2.4cm 2cm;
  @bottom-right {
    content: counter(page);
    font-family: Inter, Arial, sans-serif;
    font-size: 9pt;
    color: #777;
  }
}

* { box-sizing: border-box; }
html { font-size: 11pt; }
body {
  margin: 0;
  color: #222;
  font-family: Charter, Georgia, serif;
  line-height: 1.5;
}
h1, h2, h3 {
  font-family: Inter, Arial, sans-serif;
  line-height: 1.2;
  page-break-after: avoid;
}
h1 { font-size: 22pt; margin: 0 0 0.6em; }
h2 { font-size: 16pt; margin: 1.3em 0 0.4em; }
h3 { font-size: 12.5pt; margin: 1em 0 0.3em; }
p { margin: 0 0 0.7em; }
img, svg, figure { max-width: 100%; height: auto; page-break-inside: avoid; }
table { width: 100%; border-collapse: collapse; margin: 0.8em 0; }
thead { display: table-header-group; }
tr { page-break-inside: avoid; }
th, td {
  padding: 6pt 8pt;
  border-bottom: 0.5pt solid #ddd;
  text-align: left;
  vertical-align: top;
}
th {
  font-family: Inter, Arial, sans-serif;
  font-weight: 600;
  background: #f6f7f8;
}
.num { text-align: right; font-variant-numeric: tabular-nums; }
.keep-together { page-break-inside: avoid; }
```

For slide-style PDFs, switch to fixed pages instead of flowing A4:

```css
@page { size: 13.333in 7.5in; margin: 0; }
html, body { margin: 0; padding: 0; }
.slide {
  width: 13.333in;
  height: 7.5in;
  page-break-after: always;
  position: relative;
  overflow: hidden;
}
.slide:last-child { page-break-after: auto; }
```

## Type-Specific Guidance

Use only the relevant part.

### Essays, Papers, Articles

Prioritize reading comfort and consistency. Avoid over-designed pages unless the user asked for an editorial layout. Use clear title/byline/date, restrained headings, consistent paragraph rhythm, and captions/source notes for figures. A mostly empty page in a prose document is usually a layout problem unless it is an intentional title, section, or references page.

### Reports And Briefs

Make the document useful for decisions. Put conclusions early. Use sections that combine finding, evidence, and implication. Use callouts sparingly for decisions, risks, definitions, or key findings. Tables and charts should answer a real question, not decorate the page. For longer reports, include navigation such as a TOC, running headers, appendix labels, or source notes.

### Transactional PDFs

Precision matters more than style. Clearly show sender, recipient, document number, issue date, due date or validity period, currency, line items, subtotal, taxes/discounts if applicable, total, and payment/terms when money is due. Align numeric columns and totals. Do not invent tax IDs, bank details, invoice numbers, or legal language.

### Letters And Memos

Follow the expected convention. Letters need sender, date, recipient, salutation, body, closing, and signature block when applicable. Memos need To/From/Date/Subject and a direct opening purpose or recommendation. Keep decoration minimal unless a supplied letterhead or brand reference calls for it.

### Slide-Style PDFs

Design fixed pages, not a report with big headings. Each important page should have a clear claim and something that supports it: data, table, diagram, screenshot, timeline, quote, image, or comparison. Vary page layouts when variety helps comprehension, but do not force variety in appendices, operating reviews, or template-driven work. Check both full-size readability and thumbnail/contact-sheet rhythm.

### Flyers And One-Sheets

Make the subject or offer obvious quickly. Use real or provided assets where the visual subject matters. Keep CTA, date, location, price, contact, or next action easy to find. A flyer can be expressive; it still cannot have clipped text, low-resolution assets, or vague filler where concrete details are needed.

## Visual QA Checklist

Inspect every rendered page image. For long documents, at minimum inspect every distinct layout type plus first/last pages and any page with tables, figures, footnotes, or dense content.

Check:

- Correct page count and no accidental blank pages.
- No clipped, overlapping, or unreadably small text.
- Margins and page breaks look intentional.
- Headings are not stranded at page bottoms.
- Captions stay with figures/tables.
- Tables fit the page and columns align.
- Images render, are sharp enough, and preserve aspect ratio.
- Page numbers, headers, footers, dates, source notes, and labels are consistent.
- No placeholders, lorem ipsum, TODOs, raw tool output, or broken links remain.
- For transactional documents, totals reconcile and numeric formatting is consistent.
- For slide-style PDFs, each page reads at thumbnail size and at full size.

Fix objective defects first. Do not spend iterations on subjective polish while there are still layout errors.

## Common Fixes

| Symptom | Likely fix |
| --- | --- |
| Text too large | Set `html { font-size: 10pt; }` or `11pt`; avoid browser 16px defaults |
| Heading alone at bottom | Add `page-break-after: avoid` to headings |
| Table spills horizontally | Set explicit column widths, reduce padding, or use `table-layout: fixed` |
| Table row clips text | Remove fixed row heights; allow wrapping |
| Table header missing after page break | Use semantic `thead { display: table-header-group; }` |
| Caption separates from object | Wrap object and caption in `figure` or `.keep-together` |
| Image overflows | Add `max-width: 100%; height: auto` |
| Big blank gap before figure/table | Split/shrink the object or move the break intentionally |
| Page counter wrong | Use WeasyPrint for `counter(pages)` or omit total page count |
| Fonts change unexpectedly | Use font fallbacks and avoid relying on unavailable fonts |
| PDF differs from browser preview | Simplify CSS to the renderer's supported subset |

## Stopping Criterion

Ship when the rendered pages match the user's intent and have no objective layout defects. The design does not need to follow a house style; it needs to be clear, complete, visually stable, and appropriate for the document type.
