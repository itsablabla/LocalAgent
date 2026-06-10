---
name: pdf
description: Create polished PDF documents with HTML/CSS source, renderer-aware layout, and visual QA by rendering pages to images. Use for fixed-layout reports, essays, invoices, letters, printable handouts, slide-style PDFs, and other final PDFs.
---

# PDF Skill

PDF quality comes from judgment plus inspection. Use this skill to make final fixed-layout documents that survive printing, sharing, and close reading.

This skill is deliberately not a design template. Do not force every PDF into the same visual style. Choose the structure, density, typography, and amount of visual treatment that fits the user's intent, source material, audience, and any supplied reference.

`${CLAUDE_SKILL_DIR}/reference.md` holds the detail: document-type guidance (essay/report/transactional/letter/slide/flyer), typography and layout defaults, a starter CSS foundation for both flowing and slide-style pages, the full QA checklist, and the symptom→fix table. Read it before designing, and again when fixing layout defects.

## Non-Negotiable Workflow

1. Identify the document type and audience (classify before designing — see reference.md).
2. Choose a source format. Default to HTML/CSS for new PDFs.
3. Build the document with reusable CSS and intentional page geometry.
4. Render the PDF.
5. Render the PDF pages to PNGs and inspect them visually.
6. Fix objective defects and re-render. Repeat up to 3 times.

The file existing is not enough. Text extraction is not enough. A PDF is ready only when the rendered pages look correct.

## Source And Renderer

Default path for new PDFs:

```bash
weasyprint input.html output.pdf
python3 ${CLAUDE_SKILL_DIR}/render_pdf_pages.py output.pdf --out-dir pdf_qa
```

The QA helper tries Poppler's `pdftoppm`, then PyMuPDF. If neither is available, inspect the PDF through another visual route and mention the limitation only if it affects confidence.

Use WeasyPrint for most documents: reports, essays, invoices, letters, contracts, tables, headers/footers, page counters, and print CSS. Use headless Chromium (`chromium --headless --disable-gpu --print-to-pdf=output.pdf input.html`) when the design depends heavily on browser layout behavior such as complex flex/grid, canvas output, or interactive-to-static screenshots. Avoid imperative PDF libraries such as reportlab/fpdf for flowing documents — they are fine for precise generated forms or labels, but make ordinary layout harder than HTML/CSS.

Keep scratch files in a task-specific folder such as `tmp/pdfs/<task-slug>/`. Unless the user asks for internals, deliver the final PDF.

## Design Judgment

Before writing the source, make a short internal plan:

- Document type and audience.
- Page size and likely page count.
- Reading density: sparse, normal, dense, or appendix-like.
- Typography: body size, heading ladder, line height, and font fallbacks.
- Main content forms: prose, table, figure, chart, callout, form field, image, appendix.
- Risk areas: long tables, footnotes, narrow columns, images, page breaks, legal text, totals, source notes.

Use the simplest layout that expresses the content well. Prefer clear hierarchy over decoration. If the user provides a reference, template, brand guide, or explicit preference, follow that unless it causes objective quality problems.

Do not invent facts, citations, logos, signatures, legal terms, tax IDs, payment information, customer names, partner marks, product screenshots, or data. If placeholders are needed, make them obvious.

## Visual QA

Inspect every rendered page image. For long documents, at minimum inspect every distinct layout type plus first/last pages and any page with tables, figures, footnotes, or dense content. Check for: clipped/overlapping text, accidental blank pages, stranded headings, separated captions, overflowing tables, distorted images, inconsistent page furniture, and leftover placeholders. The full checklist and the common-fixes table are in reference.md.

Fix objective defects first. Do not spend iterations on subjective polish while there are still layout errors.

## Stopping Criterion

Ship when the rendered pages match the user's intent and have no objective layout defects. The design does not need to follow a house style; it needs to be clear, complete, visually stable, and appropriate for the document type.
