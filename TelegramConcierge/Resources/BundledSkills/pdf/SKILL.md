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
| **Presentation / deck** | Pitch, value props, summary slides | Static slide deck: claim spine, proof objects, contact-sheet rhythm | 20-120 wds/slide target | `Presentation` section |
| **Essay / paper / article** | Research paper, op-ed, analysis | **Same layout every page** — single column, consistent rhythm | 400+ wds/page typical | `Essay` section |
| **Long-form report** | Executive briefs, analyses, board reports | Decision spine, evidence hierarchy, navigation, appendix strategy | 250-500 wds/page plus figures | `Report` section |
| **Transactional** | Invoice, receipt, statement, quote | Tabular, precise alignment, minimal decoration | Tables drive it | `Transactional` section |
| **Letter / memo** | Formal correspondence, cover letter, decision memo | Block letter or metadata-led memo; restrained hierarchy | Correspondence | `Letter` section |
| **Brochure / marketing** | Flyer, one-sheet, sell sheet | Offer hierarchy, real imagery/assets, CTA-first scanning | Designer-intensive | Attempt only for simple one-sheets or when the user provides brand/reference direction |

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

PDF presentations are static decks, not reports with big headings. They should feel authored at thumbnail size and useful at full size. Every non-divider slide needs a claim, a proof object, and a reason to exist.

If the user needs an editable PowerPoint, use the PPTX skill instead. Use this section when the requested deliverable is a PDF deck, slide-style PDF, board PDF, investor PDF, pitch PDF, or presentation handout.

### North star

A good PDF deck passes two tests:

- **Contact-sheet test**: when all pages are viewed as thumbnails, the deck has a coherent visual system, deliberate rhythm, and no repeated generic template.
- **Claim/proof test**: at full size, each slide makes one conclusion and proves it with a chart, table, diagram, product visual, timeline, quote, or image. Slides with only a topic title and decorative boxes fail.

Do not make a deck by spreading bullet lists across pages. Do not fill whitespace with cards, icons, gradients, or ornamental boxes. If a slide has no proof object, rewrite, merge, or delete it.

### Workflow for PDF decks

1. **Classify the deck mode**:
   - `source-led`: user supplied material that determines the story.
   - `reference-led`: user supplied a visual/style reference to beat or follow.
   - `template-led`: user supplied a template/source deck whose layout grammar should be preserved.
   - `from-scratch`: only prompt/source text is available.
2. **Extract the story**: facts, claims, data, audience, and decision the deck should support.
3. **Write a claim spine before designing**: one line per slide with `kicker`, `claim title`, `proof object`, and `source`.
4. **Lock a design system**: page size, margin grid, typography, color roles, chart grammar, image treatment, footer/source treatment.
5. **Plan the contact sheet**: choose slide rhythms before writing HTML. For a 10-slide deck, use at least 5 macro-layout families unless a template/reference intentionally repeats.
6. **Build slides in HTML/CSS as fixed pages**: one `.slide` per PDF page, no flowing report layout.
7. **Render to PDF, render pages to PNG, inspect contact sheet and full-size pages, then fix objective issues.**

### Claim spine rules

Every non-appendix, non-divider slide must have:

- **Kicker**: 1-3 words naming the role of the slide, e.g. `MARKET SHIFT`, `MARGIN BRIDGE`, `PRODUCT LOOP`.
- **Claim title**: a conclusion, not a topic label.
- **Proof object**: the main thing the eye reads: chart, table, flow, matrix, screenshot, image, timeline, architecture map, or evidence quote.
- **Support note**: one concise sentence or source note that makes the proof interpretable.

Bad title: `Revenue trends`

Good title: `Retention, not acquisition, is now carrying growth.`

Bad title: `Product features`

Good title: `The workflow is valuable because it removes three handoffs.`

If the title still works after swapping in any company/topic name, sharpen it.

### Slide budgets

Use slide real estate deliberately:

- Standard slide: one claim, one proof object, 20-80 words total.
- Analytical slide: one dominant chart/table plus 1-3 callouts, 40-120 words total.
- Product/visual slide: one real screenshot/image/diagram plus a short claim and labels.
- Divider/quote slide: intentionally sparse, but visually centered and balanced.
- Appendix slide: can be dense, but must still have readable table geometry and source notes.

Avoid the uncanny middle: a slide with a giant title, three shallow cards, and no evidence. If content is thin, merge slides or write a stronger narrative page. If content is dense, split it into a main slide plus appendix.

### Design system lock

Before writing HTML, choose:

- **Canvas**: default 16:9 landscape (`13.333in x 7.5in`) unless the user asks for A4/Letter slides.
- **Grid**: fixed safe margins and 12-column or simple thirds layout.
- **Typography**: one display/title face and one utilitarian label/body face, using installed/system fonts.
- **Palette**: neutral base plus one main accent and one secondary/support color. Avoid one-note navy/teal/gray/beige decks unless a brand requires it.
- **Chart grammar**: axes, gridlines, direct labels, callout style, positive/negative colors.
- **Container grammar**: use boxes only for real grouping, comparison, stages, or metrics.
- **Footer grammar**: source line, page marker, confidentiality label, or date; keep it quiet and consistent.
- **Image/brand policy**: use user-provided or verified assets. Do not invent logos, mascots, product UI, partner marks, or customer marks.

Premium decks usually look better with fewer boxes, stronger whitespace, direct labels, hairline rules, real proof objects, and restrained color.

### Macro-layout families

Choose layouts by the proof object, not by decoration. Mix families so the contact sheet looks designed:

| Family | Use when | Structure |
| --- | --- | --- |
| Claim + evidence | One argument needs explanation | Large claim, dominant proof object, compact note rail |
| Chart hero | Data carries the slide | Chart takes 60-75% of page, direct labels, 1-2 callouts |
| Metric bridge | Metrics need comparison | 3-5 KPIs connected by a rule, bridge, waterfall, or variance table |
| Product proof | User must inspect product/workflow | Screenshot or diagram first, labels attached to real UI/workflow points |
| System map | Architecture/process/loop | Nodes and connectors with clear direction; labels attached to objects |
| Timeline/roadmap | Sequence matters | Horizontal or vertical progression with stages, dates, and one implication |
| Editorial image | Brand/market/story depends on a visual | Full-bleed or large real image with overlaid claim and small caption |
| Quote/evidence | A source or user voice is the proof | Large quote, attribution, and implication; no filler boxes |
| Comparison matrix | Choices need evaluation | Matrix/table with deliberate column widths, not prose stuffed into cells |
| Appendix/table | Detail must be preserved | Dense but aligned table, small source/footer, no decorative chrome |

Hard gates:

- No repeated `title + subtitle + 3 equal cards` cadence unless the reference/template requires it.
- No more than 2 card-grid slides in a 10-slide deck.
- No 3 consecutive slides with the same macro-layout family unless the deck is an appendix or operating-review packet.
- No icons as proof. Icons may label navigation, but evidence must come from data, source text, diagrams, screenshots, images, or quotes.
- No decorative arrows. Arrows must encode direction or causality.

### Structured visual rules

Charts, diagrams, and tables are the main quality lever.

- Define what the visual proves before drawing it.
- Prefer direct labels over legends when space allows.
- Use consistent scales and units; never invent missing metrics to make a chart prettier.
- Label every chart with source/date when data is external.
- In diagrams, connectors must visibly attach to the right objects and avoid ambiguous crossings.
- Equal-role nodes/cards must share dimensions, padding, border logic, and text hierarchy.
- Text inside boxes needs real padding; if it only fits with tiny type or tight edges, shorten the copy or enlarge the object.
- Screenshots and images must be sharp, relevant, and inspectable. Do not use blurred atmospheric filler.
- Tables must have deliberate column widths. Compact columns for dates/status/numbers; wide columns for narrative.

If a visual is too complex to fit cleanly, simplify the argument. A simpler proof object beats a crowded "impressive" slide.

### PDF slide CSS foundation

For PDF presentations, override the normal A4 report foundation:

```css
@page { size: 13.333in 7.5in; margin: 0; }
* { box-sizing: border-box; }
html, body { margin: 0; padding: 0; font-family: Inter, Arial, sans-serif; color: #141414; }
.slide {
  width: 13.333in;
  height: 7.5in;
  padding: 0.45in 0.58in;
  page-break-after: always;
  position: relative;
  overflow: hidden;
  background: #f7f5ef;
}
.slide:last-child { page-break-after: auto; }
.kicker { font-size: 10pt; letter-spacing: 0.08em; text-transform: uppercase; color: #666; font-weight: 700; }
.claim { font-size: 28pt; line-height: 1.05; max-width: 9.8in; margin: 0.12in 0 0.28in; font-weight: 700; }
.support { font-size: 12pt; line-height: 1.35; color: #444; max-width: 3.1in; }
.source { position: absolute; left: 0.58in; bottom: 0.26in; font-size: 7.5pt; color: #777; }
.page-no { position: absolute; right: 0.58in; bottom: 0.26in; font-size: 7.5pt; color: #777; }
.proof-grid { display: grid; grid-template-columns: 2fr 1fr; gap: 0.34in; align-items: stretch; }
.proof-object { min-height: 4.4in; }
.note-rail { border-left: 1px solid rgba(0,0,0,0.18); padding-left: 0.22in; }
.metric { font-size: 30pt; line-height: 1; font-weight: 750; }
.metric-label { font-size: 10pt; line-height: 1.25; color: #555; margin-top: 0.06in; }
figure, img, svg, table { max-width: 100%; }
```

Use this as a starting point, not as a visual identity. Customize palette, typography, and layout rhythm for the deck.

### Contact-sheet QA

After rendering pages to PNG, make or inspect a contact sheet. The deck fails if:

- The first impression is generic consulting/card-grid output.
- Adjacent slides repeat the same geometry without intent.
- A slide has no obvious proof object.
- Titles are topic labels instead of claims.
- The visual hierarchy is unclear at thumbnail size.
- Text is cramped, clipped, or too small at full size.
- Charts/tables have detached labels, inconsistent scales, or unreadable units.
- Brand assets look invented, low-resolution, or unofficial.

Fix the weakest slides first. Do not chase tiny subjective polish until the claim/proof structure, contact-sheet rhythm, and full-size readability are solid.

## Essay / paper / article

Research papers, op-eds, analyses. Consistency is the default goal, not variety. Most pages use the same single-column layout, same typography, same rhythm. Readers shouldn't notice layout — it should disappear under the prose.

Avoid card grids, pull-quotes, decorative accents, or column variety in essays. Use an exception only for a legitimate editorial/article format, a supplied reference, or a figure/callout that materially improves comprehension.

### Essay modes

- **Academic / research paper**: title block, abstract if appropriate, sections, citations/footnotes, figures/tables with captions, references.
- **Analytical article / op-ed**: strong title, deck/subtitle if helpful, byline/date, continuous prose, restrained section headings.
- **Technical note**: concise thesis, numbered sections, code/math/figures only when they are the evidence.

Choose the mode before writing. Do not mix academic apparatus with magazine-style decoration unless the user asks for an editorial article.

### Structure
- Page 1: title + author/affiliation + date at top, then body starts ~1/3 down the page
- Body: single column, 10-12pt, line-height 1.5-1.6
- Section headings (H2) with modest top margin; no boxes or background fills
- First paragraph after a heading: no indent. Subsequent paragraphs: small first-line indent (1em) OR blank-line separation, not both
- Footnotes at page bottom with 9pt, separator rule above
- Running footer: page number only (or "Author — Title — page N"), 9pt gray
- Figures/tables: numbered caption above or below, source note if external, never separated from caption by a page break

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

### Essay QA

- Title page does not look like a slide.
- Heading levels are visibly distinct but restrained.
- Paragraph rhythm is consistent: no random extra spacing, mixed indentation, or isolated one-line paragraphs.
- Footnotes/citations are readable and do not collide with body text.
- Figures and tables fit inside the text measure and remain paired with captions.
- Last page is not accidentally sparse unless it is references/appendix.

## Report

Reports are decision documents. They need hierarchy, evidence, navigation, and appendices; they are not essays with a table of contents or slide decks printed on pages.

### Report workflow

1. **Classify the report**:
   - `executive brief`: 3-8 pages, decision/recommendation first.
   - `analytical report`: findings, evidence, charts/tables, implications.
   - `technical report`: methodology, system details, results, limitations.
   - `operating/board report`: status, metrics, risks, decisions, appendix.
2. **Write the report spine** before layout:
   - purpose
   - audience
   - decision or question
   - executive summary bullets
   - sections with findings/evidence/implications
   - appendix items
3. **Choose form factors by content**: prose for explanation, tables for repeated comparable records, charts for numeric patterns, callouts for decisions/risks, appendix for dense source detail.
4. **Render and inspect navigation**: TOC, running headers, section starts, figure/table captions, page numbers, appendix labels.

### Required structure for substantial reports

- **Cover**: title, subtitle/context, author/org, date, confidentiality if needed.
- **Executive summary**: 3-7 bullets or short paragraphs with conclusions, not a teaser.
- **Decision / recommendation box** when the report asks for action.
- **Table of contents** for 8+ pages (auto-generated if the renderer supports it; WeasyPrint supports `target-counter`).
- **Main sections**: each section begins with a finding or question, then evidence, then implication.
- **Figures/tables**: numbered, captioned, source-labeled, and referenced in nearby prose.
- **Risks / limitations** where uncertainty matters.
- **Appendix**: dense tables, raw assumptions, methodology, source list, glossary.
- **Running header/footer**: section name, page number, date/version/source label as appropriate.

### Report design rules

- Use a consistent page grid and heading ladder. Reports earn polish through rhythm, not decorative novelty.
- Use callouts sparingly: decision, risk, key finding, definition. Do not wrap every paragraph in boxes.
- Data tables need deliberate column widths, repeated headers, and enough padding. Long prose in cells usually belongs in subsections or bullets.
- Charts must have direct labels or clear legends, units, source/date, and readable axis text.
- Keep section openings compact. Avoid chapter divider pages unless the report is long enough that navigation benefits from them.
- Use page breaks intentionally before major sections; do not leave large blank gaps because a table barely missed the page.

### Report CSS additions

```css
@page {
  @top-left { content: string(section-title); font-family: 'Inter', sans-serif; font-size: 8.5pt; color: #777; }
  @top-right { content: counter(page); font-family: 'Inter', sans-serif; font-size: 8.5pt; color: #777; }
}
h2 { string-set: section-title content(text); border-top: 0.5pt solid #ddd; padding-top: 0.45cm; }
.exec-summary { border-left: 4pt solid #0b57d0; padding: 0.35cm 0.5cm; background: #f5f8ff; margin: 0.8cm 0 1cm; }
.decision-box, .risk-box { padding: 0.45cm 0.55cm; border: 0.75pt solid #d8dee8; background: #fbfcff; page-break-inside: avoid; }
figure { margin: 0.8cm 0; page-break-inside: avoid; }
figcaption { font-family: 'Inter', sans-serif; font-size: 8.5pt; color: #666; margin-top: 0.18cm; }
```

### Report QA

- Executive summary contains actual conclusions and can stand alone.
- TOC entries, page numbers, running headers, and section titles match.
- Every chart/table is referenced or clearly useful; no orphan graphics.
- Dense appendices are labeled as appendices, not mixed into the main narrative.
- Page breaks preserve captions with figures/tables and do not create accidental half-empty pages.
- Sources, dates, assumptions, and limitations are visible where needed.

## Transactional

Invoices, receipts, statements, quotes, purchase orders, estimates, and payment notices. Precision over decoration. The user or recipient should immediately know who pays whom, for what, by when, and how totals were calculated.

### Transactional document types

- **Invoice**: seller, buyer, invoice number, issue date, due date, line items, subtotal/tax/discount/total, payment instructions.
- **Quote / estimate**: scope, assumptions, validity date, optional acceptance/signature block.
- **Receipt**: paid status, payment method, transaction/date, items, total paid, remaining balance if any.
- **Statement**: account period, prior balance, activity, payments, current balance.

### Structure
- **Header block**: two columns. Left = sender logo/name + address. Right = document type ("INVOICE"), number, date, due date.
- **Recipient block**: below header, left-aligned, with clear label ("Bill to:").
- **Status strip** when useful: `Due`, `Paid`, `Overdue`, `Draft`, `Valid until`.
- **Line-item table**: description wide; quantity/rate/tax/amount compact and right-aligned. Use `font-variant-numeric: tabular-nums`.
- **Totals block**: subtotal, discount, tax, shipping/fees, payments/credits, balance due. Align decimals visually.
- **Terms/payment block**: payment method, bank details, due terms, quote validity, acceptance language.
- **Legal/footer**: tax IDs, registration details, disclaimers in 8-9pt gray.

No color beyond a single brand accent. No gradients, shadows, or marketing flair.

### Geometry rules

- Never let the totals block float ambiguously; it belongs under the amount column, right-aligned.
- Numeric columns use tabular figures and consistent decimals/currency.
- Descriptions wrap; numeric columns stay compact.
- If line items continue to another page, repeat the table header and carry totals only on the final page.
- Do not use fixed row heights that can clip descriptions.
- If there are no taxes/discounts, omit those rows rather than showing zero clutter.
- Do not invent tax IDs, payment accounts, invoice numbers, or legal terms. Use placeholders only when the user asks for a template.

### Transactional CSS additions

```css
.invoice-header { display: grid; grid-template-columns: 1fr 1fr; gap: 2cm; margin-bottom: 2cm; }
.invoice-header .meta { text-align: right; }
.invoice-header h1 { font-size: 24pt; text-transform: uppercase; letter-spacing: 0.08em; margin: 0 0 0.5em; color: #0b57d0; }
.status-strip { font-family: 'Inter', sans-serif; font-size: 10pt; padding: 0.25cm 0.35cm; border: 0.75pt solid #ddd; background: #f8fafc; margin: 0.5cm 0 1cm; }
.line-items { font-variant-numeric: tabular-nums; table-layout: fixed; }
.line-items thead { display: table-header-group; }
.line-items td.num, .line-items th.num { text-align: right; }
.totals { margin-left: auto; width: 45%; font-variant-numeric: tabular-nums; }
.totals td { border: none; padding: 4pt 0; }
.totals td:last-child { text-align: right; }
.totals tr.total td { font-weight: 700; border-top: 1pt solid #222; padding-top: 7pt; }
.legal-footer { font-size: 8.5pt; color: #777; margin-top: 2cm; border-top: 0.5pt solid #ddd; padding-top: 0.5cm; }
```

### Transactional QA

- Document number, dates, parties, and currency are visible.
- Totals reconcile with line items; no missing subtotal/tax/total logic.
- Numeric columns align; decimal/currency formatting is consistent.
- Payment/terms block is present when money is due.
- Multi-page line items repeat headers and do not split a row awkwardly.
- Print preview looks sober and official, not like a marketing flyer.

## Letter / memo

Formal correspondence, cover letters, business letters, short memos, decision memos. Keep letters simple; make memos scannable.

### Choose letter or memo

- **Letter**: external correspondence to a named recipient. Use block format.
- **Memo**: internal decision/update document. Use metadata (`To`, `From`, `Date`, `Subject`) plus short sections.
- **Board/decision memo**: closer to a short report; include decision, context, options, recommendation, risks, next steps.

### Letter structure (block format)
- Sender letterhead / name + address, top-left
- Date, ~1 line below
- Recipient name + address, ~2 lines below date
- Salutation ("Dear X,"), ~1 line below
- Body paragraphs, block style (no indent, blank line between)
- Closing ("Sincerely,"), ~1 line below last paragraph
- Signature space (3 lines), then printed name + title

### Memo structure
- Metadata block: `To`, `From`, `Date`, `Subject`.
- Opening: recommendation, decision needed, or purpose in the first paragraph.
- Body sections: context, analysis, recommendation, risks, next steps.
- Use bullets only for lists/actions; prose carries reasoning.
- For one-page memos, no page number. For multi-page memos, add quiet footer page numbers.

Margins 2.5-3cm. Keep decoration minimal unless the user supplies letterhead or brand direction.

### Letter / memo QA

- Recipient/sender/date metadata are complete.
- Tone fits the audience; no decorative presentation styling.
- Signature block or action/next steps are present when expected.
- A memo's recommendation or decision need appears in the first screen/page.

## Brochure / marketing

Treat brochures, flyers, one-sheets, sell sheets, event flyers, and light marketing collateral as high-risk but possible. They depend on brand identity, imagery decisions, offer hierarchy, and visual craftsmanship.

Attempt them when the user provides brand/reference direction, the format is a simple one-page flyer/one-sheet, or a polished-enough draft is useful. For complex folded brochures or brand-critical collateral, ask for brand assets/reference examples or offer a pitch deck (Presentation type) as an adjacent deliverable.

### Marketing workflow

1. Identify the format: flyer, one-sheet, sell sheet, event handout, simple brochure.
2. Define the hierarchy: audience, offer, proof, CTA, contact/action details.
3. Use real/user-provided/verified imagery where the subject matters. Do not use generic atmospheric filler.
4. Lock brand cues: colors, type, logo/mark placement only if assets are provided or verified.
5. Compose for scanning: headline, primary visual, 3-5 proof points, CTA, details.
6. Render and inspect at full size and thumbnail size.

### Marketing rules

- The first viewport/page must show the offer or subject, not just abstract decoration.
- Use one dominant visual or typographic idea. Do not scatter many small cards.
- Proof beats adjectives: include dates, location, price, features, outcomes, testimonials, or concrete differentiators.
- CTA/contact details must be legible and easy to find.
- Avoid invented logos, fake app screenshots, fake partner/customer marks, and low-resolution crops.
- For print flyers, preserve margins/bleed expectations if the user specifies them; otherwise keep important content safely away from edges.

### Marketing QA

- Can a reader understand the offer in 3 seconds?
- Is the CTA visible without searching?
- Are brand assets real/provided/verified?
- Does the page avoid stock-like filler and generic gradient/card composition?
- Are event/product/contact details complete and readable?

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
| Every page looks unintentionally identical (presentation) | One macro-layout applied to all slides | Re-plan the contact sheet with varied proof-object families, unless consistency follows a template/reference |
| Card-grid slide looks like a bullet list | Thin points dressed up as cards | Replace with one proof object, a claim + evidence slide, or merge into another slide |
| Slide has a title but no evidence | Topic label used as a claim | Rewrite the title as a conclusion and add a chart, table, diagram, image, quote, screenshot, or timeline |
| Report reads like a long essay | Missing decision spine and evidence hierarchy | Add executive summary, findings/evidence/implications, callouts only for decisions/risks |
| Executive summary is a teaser | It describes sections instead of conclusions | Rewrite as standalone conclusions and recommendations |
| Two columns of text side by side feel fragmented | Text split into columns without a real reason | Use full-width single column, unless it is a newsletter, handout, appendix, index, or reference/template-driven exception |
| Essay has pullquotes or card grids | Misclassified as presentation | Strip decorative elements; essays want consistency |
| Invoice columns misaligned | Mixed numeric + text columns, no tabular figures | `font-variant-numeric: tabular-nums` on numeric cells |
| Invoice total floats away from line items | Totals block not tied to amount column | Right-align totals under amount column; keep decimals/currency consistent |
| Flyer looks generic | No real offer hierarchy or imagery | Make offer/subject first, use verified/provided assets, show CTA clearly |
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
