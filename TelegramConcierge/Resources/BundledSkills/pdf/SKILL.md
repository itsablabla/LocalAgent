---
name: pdf
description: Generate polished PDFs of any kind — presentations, essays, reports, invoices, letters — with a render-to-PNG visual QA loop. Use when the user asks for a PDF, report, printable document, presentation, invoice, or contract.
---

# PDF Skill

PDFs are not one thing. A pitch deck and a research paper need opposite layout strategies: the deck needs visual variety between pages, the paper needs rigid consistency. **Classify the document type first**, then apply the rules for that type.

## Codex-quality contract

Good PDFs come from a render-and-revise loop, not from hoping the first HTML export is fine.

Before delivering a PDF:

1. Decide the document archetype and design system before drafting.
2. Build source in HTML/CSS unless the user explicitly needs a different source format.
3. Render the PDF.
4. Render the PDF pages to PNGs and inspect those images at readable size.
5. Fix objective layout defects and re-render. Repeat up to 3 times.

The shipping gate is visual: all pages must look clean in rendered page images. Text extraction or a successful PDF file write is not enough.

Use the bundled helper when possible:

```bash
python3 ${CLAUDE_SKILL_DIR}/render_pdf_pages.py output.pdf --out-dir pdf_qa
```

The helper prefers Poppler's `pdftoppm`, then `pymupdf` if installed. If neither renderer is available, use `read_file` on the PDF as the fallback visual check and state that PNG QA was unavailable only if the user asks about QA details.

Keep scratch artifacts in a task-scoped folder such as `tmp/pdfs/<task-slug>/` or next to the generated source in `pdf_qa/`. Unless the user asks for intermediates, return only the final PDF.

## Workflow

1. **Classify the document type** (see matrix below).
2. **Pick the renderer** — `weasyprint` by default (Python-installable, great CSS support); `chromium --headless --print-to-pdf` for complex CSS (grid, flex edge cases). Never use imperative libraries (reportlab / fpdf) for flowing content.
3. **Plan the design** — page geometry, type scale, headings, tables/figures, callouts, headers/footers, and section breaks.
4. **Write one HTML + CSS file.** Baseline stylesheet below; type-specific additions in each section.
5. **Render**: `weasyprint input.html output.pdf`
6. **Verify visually.** Prefer `render_pdf_pages.py` and inspect the PNG pages. If page rendering dependencies are unavailable, `read_file` on the PDF — the rendered pages come back as inline multimodal content. Inspect every page of multi-page docs, not just page 1.
7. **Fix objective bugs and re-render.** Cap at 3 iterations. Fix layout bugs, not subjective polish.

## Document type matrix

| Type | Examples | Layout rule | Density | Apply rules in |
| --- | --- | --- | --- | --- |
| **Presentation / deck** | Pitch, value props, summary slides | Vary layouts across consecutive pages by default; avoid repeated patterns unless a reference/template requires consistency | 150-200 wds/page target | `Presentation` section |
| **Essay / paper / article** | Research paper, op-ed, analysis | **Same layout every page** — single column, consistent rhythm | 400+ wds/page typical | `Essay` section |
| **Long-form report** | 20+ pages, structured, with TOC | Same as essay + chapters, TOC, running header | 300+ wds/page | `Report` section |
| **Transactional** | Invoice, receipt, statement, quote | Tabular, precise alignment, minimal decoration | Tables drive it | `Transactional` section |
| **Letter / memo** | Formal correspondence, cover letter | Single-page block-format template | Correspondence | `Letter` section |
| **Brochure / marketing** | Fold brochure, one-sheet, flyer | Visual-heavy, brand-driven | Designer-intensive | Attempt only for simple one-sheets or when the user provides brand/reference direction |

Don't conflate types. A "report" with card grids and pullquotes is wrong; a pitch deck with 6 dense prose pages is wrong.

### Rules and exceptions

The layout rules below are strong defaults, not universal law. They prevent common low-quality agent output, but the best PDF is the one that fits the user's intent and survives visual QA.

You may override a default when at least one of these is true:

- The user explicitly asks for a format or layout that conflicts with the default.
- A supplied reference/template clearly uses that layout and the user wants it followed.
- The content type genuinely needs the exception, such as a compact newsletter, reference appendix, form, catalog, academic handout, or brand-led one-sheet.
- The rendered pages prove the exception is cleaner, more readable, and more complete than the default.

When taking an exception, keep it deliberate and limited. Do not use an exception as permission to fall back into generic card grids, cramped columns, decorative clutter, or clipped content.

## Shared foundation

### Pre-render design plan

Write a short internal plan before generating the source:

- **Archetype**: presentation, essay, report, transactional, letter, or brochure-adjacent.
- **Page budget**: expected page count, density per page, and where intentional page breaks belong.
- **Typography**: font stack, body size, heading ladder, line height, and page furniture.
- **Information forms**: prose, list, table, chart, callout, figure, appendix, or form fields.
- **Risk areas**: long tables, narrow columns, images, citations, page counters, headers/footers, or legal text.

Then implement the plan through reusable CSS classes, not one-off inline styling. Revise the plan if the rendered pages show a better structure is needed.

### Typography baseline

- One serif for body, one sans-serif for headings. Charter + Inter is a reliable pairing (both exist on macOS + common Linux). Always list fallbacks: `'Charter', 'Georgia', serif`.
- Body 10-12pt, line-height 1.4-1.6. Margins 1.8-2.5cm.
- Heading scale: H1 ~2x body, H2 ~1.5x, H3 ~1.2x. Similar H1/H2 sizes break hierarchy.
- Page numbers: footer, right-aligned, 9pt gray.
- Justify is fine for Italian / Spanish / French / German; left-align English (narrow columns create ugly rivers).
- CJK: include font stack like `'PingFang SC', 'Hiragino Sans', 'Noto Sans CJK', sans-serif`. RTL (Arabic, Hebrew): `dir="rtl"` on the relevant block.

### Baseline CSS (drop into `<style>` for any type)

```css
@page { size: A4; margin: 2cm 2cm 2.5cm 2cm;
  @bottom-right { content: counter(page) " / " counter(pages); font-family: 'Inter', sans-serif; font-size: 9pt; color: #888; } }
* { box-sizing: border-box; }
html { font-size: 11pt; }
body { font-family: 'Charter', 'Georgia', serif; line-height: 1.5; color: #222; margin: 0; }
h1, h2, h3, h4 { font-family: 'Inter', system-ui, sans-serif; font-weight: 600; line-height: 1.25; page-break-after: avoid; margin: 1.4em 0 0.4em; }
h1 { font-size: 22pt; margin-top: 0; } h2 { font-size: 16pt; } h3 { font-size: 13pt; }
h4 { font-size: 11pt; text-transform: uppercase; letter-spacing: 0.04em; color: #555; }
p { margin: 0 0 0.7em; }
a { color: #0b57d0; text-decoration: none; }
img, svg, figure { max-width: 100%; height: auto; page-break-inside: avoid; }
table { width: 100%; border-collapse: collapse; margin: 0.8em 0; font-size: 10pt; }
th, td { padding: 6pt 8pt; border-bottom: 0.5pt solid #ddd; text-align: left; vertical-align: top; }
th { background: #f6f8fa; font-family: 'Inter', sans-serif; font-weight: 600; font-size: 9.5pt; }
tr { page-break-inside: avoid; }
blockquote { border-left: 3pt solid #bbb; margin: 0 0 1em; padding: 0 0 0 1em; color: #555; }
```

### Verification (all types)

- Prefer rendering pages to PNG with `render_pdf_pages.py`; inspect every page image. If unavailable, `read_file` the output PDF and inspect every page.
- Check typography hierarchy, margins, page breaks, orphan headings, image overflow, table cutoffs, empty pages.
- For data-heavy or visual content: also verify images render (not broken icons), tables fit page width, columns align.
- Check that repeated page furniture is intentional and consistent: page numbers, running headers, footers, source notes, and appendix labels.
- Do not deliver if any page has clipped text, overlapping elements, unreadable glyphs, broken images, tables cut at the page edge, large accidental blank gaps, or placeholder/tool-token text.

### Tables, figures, and forms

Tables and form-like layouts are where most bad PDFs show their seams.

- Use tables only for repeated records with shared fields. Do not package normal prose into table cells.
- Set deliberate column widths. Short values such as dates, quantities, status, currency, and checkmarks should be compact; narrative columns get the width.
- Use `table-layout: fixed` when it prevents width drift, but allow row height to expand. Never clip rows to a fixed height.
- Give cells enough padding and line-height that text does not look pinned to borders.
- Align by data type: right-align numbers, center compact statuses/dates, left-align narrative text.
- Repeat table headers on page breaks when the renderer supports it.
- Keep captions visually paired with figures/tables; avoid a caption at the bottom of one page and its object on the next.
- For forms, make fields large enough to use. Avoid dense spreadsheet-like grids unless the user requested a spreadsheet-style form.

### Visual QA loop

For each render pass, inspect in this order:

1. **Page scan**: page count, no blank pages, no obvious top/bottom clipping.
2. **Hierarchy**: title, headings, body, captions, footnotes are visually distinct.
3. **Flow**: no orphan headings, stranded captions, accidental half-empty content pages, or awkward section breaks.
4. **Objects**: tables fit, figures are sharp, charts have readable labels, images are not broken.
5. **Furniture**: page numbers, headers, footers, source notes, and legal/footer text are present and aligned.
6. **Content hygiene**: no placeholders, lorem ipsum, hidden TODOs, raw tool tokens, or citation debris.

Only iterate on objective defects. Stop after 3 QA loops and tell the user what remains if a renderer or source limitation prevents a clean result.

## Presentation

Pitch decks, feature summaries, value props. Vary layouts on consecutive pages by default. Avoid repeating the same pattern unless the deck is following a template, reference, or intentionally systematic operating-review format. Do not default to a square card grid on every page — that's the "lazy deck" failure mode.

### Content volume rule

**Before choosing a visual pattern, check how much content you actually have for each element on the page.** If individual items (cards, layers, panes) contain less than ~100 words each, the default is flowing prose with **bold inline headings** rather than a visual pattern. Visual patterns (Stack, Split, Pillars) exist to organize substantial content, not to dress up thin bullet points as cards.

- **Stack with thin items** (each item < 100 words): use flowing prose instead. Write each point as a bold heading + paragraph in a single running column.
- **Split with thin content**: only use when BOTH sides have enough to fill their pane. If the text side is under ~150 words, merge everything into a single flowing column. An image floating within prose is better than a half-empty split layout.
- **Pillars/cards**: use when each card has enough substance to compare or scan. Three title-and-one-liner cards is usually a bullet list pretending to be a layout — write it as prose unless a reference/template calls for cards.

**When in doubt, prefer dense running text over visual patterns.** A well-written paragraph is always better than a half-empty card grid.

### No text-only two-column layouts

Default to a single full-width column for prose. Two-column pure text often looks fragmented and is hard to read in agent-generated PDFs.

Use two-column pure text only when the format genuinely benefits from it: newsletters, dense handouts, indexes, glossaries, compact appendices, or a supplied reference/template. When both columns would be normal narrative prose, use a single column instead. Two-column layouts remain a good fit when one column is an image/diagram and the other is text (the Split pattern).

### Named layout patterns

| Pattern | Best for | Key features |
| --- | --- | --- |
| **Manifesto** | Philosophy, vision, intros, narrative | Single-column running prose + large italic pull-quote with left accent bar. Avoid two-column text unless the user/reference calls for an editorial format. |
| **Stack** | Architecture layers, process steps, roadmaps | Vertical rows, bold uppercase tag left + description right. Best when each item has enough substance; otherwise use flowing prose. |
| **Split** | Feature showcases, comparisons | 40/60 or 50/50 horizontal: image/diagram one side, prose/list the other. Avoid text-vs-text splits unless comparison is the point and both sides fill their pane. |
| **Pillars** | Value props, capabilities | Grid of cards — usually 3-column or asymmetric, colored top-border accent. Avoid square grids unless following a template/reference. Best when each card has enough substance to scan. |
| **Hero** | A concept better shown than told | Full-width image/diagram + caption + short context |
| **Quote** | Section transitions, memorable statements | Large typographic treatment (28-40pt italic), minimal surround |
| **Data** | Technical depth, metrics | Table or chart carries the page, annotation supports |

**Plan the sequence before rendering.** Example 5-page deck: cover → Manifesto → Stack → Split → Hero → Quote. Adjacent pages should usually differ in rhythm unless consistency is intentional.

**Density target**: 150-200 words per content page. Below that, the page often reads as a headline, not a section. Add an "intro bridge" (2-3 sentence paragraph) under every H2 for context, unless the page is intentionally visual, a divider, or a quote page.

**Cover / divider pages** (intentionally sparse): use flex distribution so content doesn't bunch at the top.
```css
.cover { min-height: 24cm; display: flex; flex-direction: column; justify-content: space-between; }
```

### CSS snippets for patterns

```css
/* .manifesto-cols intentionally omitted; use only for editorial/reference-driven exceptions */
.pull-quote { font-size: 20pt; font-style: italic; color: #0b57d0; border-left: 4pt solid #0b57d0; padding: 0.8cm 1cm; margin: 1.5cm 0; background: #f0f7ff; }
.stack-layer { display: grid; grid-template-columns: 180px 1fr; gap: 1cm; padding: 0.8cm; border: 1pt solid #eee; margin-bottom: 0.5cm; border-radius: 4pt; page-break-inside: avoid; }
.layer-label { font-family: 'Inter', sans-serif; font-weight: 800; color: #0b57d0; text-transform: uppercase; font-size: 9pt; letter-spacing: 0.1em; }
.split-view { display: flex; gap: 1.5cm; flex-grow: 1; }
.visual-pane { flex: 1; background: #f9f9fb; border-radius: 8pt; padding: 1cm; display: flex; align-items: center; justify-content: center; page-break-inside: avoid; }
.pillar-grid { display: grid; grid-template-columns: 1fr 1fr 1fr; gap: 0.8cm; }
.pillar-card { padding: 0.8cm; border-top: 4pt solid #0b57d0; background: #fff; box-shadow: 0 4pt 12pt rgba(0,0,0,0.03); page-break-inside: avoid; }
.quote-page { display: flex; flex-direction: column; justify-content: center; min-height: 24cm; }
.quote-page blockquote { font-size: 32pt; line-height: 1.25; font-style: italic; color: #0b57d0; border: none; padding: 0; max-width: 14cm; }
```

## Essay / paper / article

Research papers, op-eds, analyses. Consistency is the default goal, not variety. Most pages use the same single-column layout, same typography, same rhythm. Readers shouldn't notice layout — it should disappear under the prose.

Avoid card grids, pull-quotes, decorative accents, or column variety in essays. Use an exception only for a legitimate editorial/article format, a supplied reference, or a figure/callout that materially improves comprehension.

### Structure
- Page 1: title + author/affiliation + date at top, then body starts ~1/3 down the page
- Body: single column, 10-12pt, line-height 1.5-1.6
- Section headings (H2) with modest top margin; no boxes or background fills
- First paragraph after a heading: no indent. Subsequent paragraphs: small first-line indent (1em) OR blank-line separation, not both
- Footnotes at page bottom with 9pt, separator rule above
- Running footer: page number only (or "Author — Title — page N"), 9pt gray

### Essay-specific CSS additions

```css
body { font-size: 11pt; line-height: 1.55; }
h1.paper-title { font-size: 20pt; margin: 0 0 0.3em; }
.authors { font-family: 'Inter', sans-serif; font-size: 11pt; color: #555; margin-bottom: 2em; }
p + p { text-indent: 1em; }  /* first-line indent from paragraph 2 onward */
h2 + p, h3 + p { text-indent: 0; } /* no indent right after a heading */
.footnote { font-size: 9pt; line-height: 1.35; color: #444; }
```

**Density**: 400+ words/page is typical. A half-empty essay page signals awkward section breaks, not minimalism.

## Report

Long-form (20+ pages, structured, formal). Like essay but with:
- **Table of contents** on page 2 (auto-generated if the renderer supports it; weasyprint does via `target-counter`)
- **Chapter title pages**: sparse page with just chapter number + title, then body starts on the next page
- **Running header**: chapter name left, page number right, 9pt, thin bottom border
- **Appendix** and **index** if applicable

Density and typography inherit from essay. Same consistency rule applies.

## Transactional

Invoices, receipts, statements, quotes. Precision over decoration.

### Structure
- **Header block**: two columns. Left = sender logo/name + address. Right = document type ("INVOICE"), number, date, due date.
- **Recipient block**: below header, left-aligned, with clear label ("Bill to:").
- **Line-item table**: consistent column widths, right-aligned numeric columns. Use `font-variant-numeric: tabular-nums` for alignment.
- **Totals row**: bold, top border, right-aligned.
- **Footer**: payment terms, bank details, legal disclaimers in 8-9pt gray.

No color beyond a single brand accent. No gradients, shadows, or marketing flair.

### Transactional CSS additions

```css
.invoice-header { display: grid; grid-template-columns: 1fr 1fr; gap: 2cm; margin-bottom: 2cm; }
.invoice-header .meta { text-align: right; }
.invoice-header h1 { font-size: 24pt; text-transform: uppercase; letter-spacing: 0.08em; margin: 0 0 0.5em; color: #0b57d0; }
.line-items { font-variant-numeric: tabular-nums; }
.line-items td.num, .line-items th.num { text-align: right; }
.line-items tr.total td { font-weight: 700; border-top: 1pt solid #222; }
.legal-footer { font-size: 8.5pt; color: #777; margin-top: 2cm; border-top: 0.5pt solid #ddd; padding-top: 0.5cm; }
```

## Letter / memo

Formal single-page correspondence: cover letter, business letter, internal memo.

### Structure (block format)
- Sender letterhead / name + address, top-left
- Date, ~1 line below
- Recipient name + address, ~2 lines below date
- Salutation ("Dear X,"), ~1 line below
- Body paragraphs, block style (no indent, blank line between)
- Closing ("Sincerely,"), ~1 line below last paragraph
- Signature space (3 lines), then printed name + title

Margins 2.5-3cm. Usually no page number on a single page. Keep decoration minimal unless the user supplies letterhead or brand direction.

## Brochure / marketing

Treat brochures, flyers, one-sheets, and marketing collateral as high-risk rather than impossible. They depend on brand identity, imagery decisions, and visual craftsmanship.

Attempt them when the user provides brand/reference direction, the format is a simple one-page flyer/one-sheet, or a polished-enough draft is useful. Keep expectations grounded: use real or provided imagery, avoid generic stock-like filler, and verify the rendered page carefully. For complex folded brochures or brand-critical collateral, ask for brand assets/reference examples or offer a pitch deck (Presentation type) as an adjacent deliverable.

## Common bugs

| Symptom | Cause | Fix |
| --- | --- | --- |
| Body text huge on every page | Root `font-size` unset (inherits 16pt default) | `html { font-size: 11pt; }` |
| Heading alone at page bottom | No `page-break-after: avoid` on h1-h4 | Add to heading CSS |
| Table cut at right edge | Column widths sum > page width | `width: 100%` with % columns, or `table-layout: fixed` |
| Image bleeds off page | No `max-width` on img | `img { max-width: 100%; height: auto; }` |
| "1 of 0" page counter | Renderer doesn't support `counter(pages)` | Use weasyprint (supports it) or drop "/ N" |
| Fonts inconsistent across machines | Font name unavailable on rendering host | Always list fallbacks |
| Every paragraph indents | Parent stylesheet's `text-indent` | `p { text-indent: 0; }` explicitly |
| Cover content bunched at top | Missing flex on page container | flex-column + `justify-content: space-between` on a 24cm min-height container |
| Content page half-empty | Under-written section | Merge pages, expand prose, add intro bridge under H2, or enlarge a figure |
| Every page looks unintentionally identical (presentation) | One layout pattern applied to all | Alternate Manifesto / Stack / Split / Pillars / Hero / Quote / Data, unless consistency follows a template/reference |
| Stack/Pillars page looks like a bullet list | Items have <100 words each, dressed up as cards | Rewrite as flowing prose with bold inline headings |
| Split page half-empty | Text pane has <150 words, bottom of page is whitespace | Switch to single-column flowing text; float images inline |
| Two columns of text side by side feel fragmented | Text split into columns without a real reason | Use full-width single column, unless it is a newsletter, handout, appendix, index, or reference/template-driven exception |
| Essay has pullquotes or card grids | Misclassified as presentation | Strip decorative elements; essays want consistency |
| Invoice columns misaligned | Mixed numeric + text columns, no tabular figures | `font-variant-numeric: tabular-nums` on numeric cells |
| Tables cut at page breaks | No `page-break-inside: avoid` on rows | Add to `tr` |
| Text looks pinned inside table cells | Insufficient padding or line-height | Increase `td/th` padding and line-height; adjust vertical alignment |
| Caption separated from figure/table | Page break between related elements | Wrap in `figure` or a keep-together container with `page-break-inside: avoid` |
| Repeated table header missing | Renderer/table CSS not configured | Use semantic `thead`; for WeasyPrint, ensure header rows are in `<thead>` |
| Large blank gap before a table/figure | Object cannot fit in remaining page space | Split the table, shrink object modestly, or move the section break intentionally |
| PNG QA shows different layout than expected | Browser/WeasyPrint CSS mismatch | Use the renderer's supported CSS subset; simplify grid/flex if needed |

## Images and figures

- Embed raster at 2x the final rendered size, then let CSS scale. Avoids blur on high-DPI print.
- SVG for charts (vector, infinite resolution). JPEG q85 for photos. PNG for screenshots / line art.
- All images: `page-break-inside: avoid`.
- For charts, generate SVG via matplotlib/plotly and embed.

## Stopping criterion

The document looks right for its type and intent. A presentation usually varies cleanly across pages; an essay usually reads as continuous prose; an invoice aligns precisely; a letter follows block format. Any exception is intentional, limited, and validated visually. Nothing clipped, no orphan headings, no accidental half-empty content pages. Ship.
