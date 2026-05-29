---
name: xlsx
description: Create and edit Microsoft Excel .xlsx workbooks with reliable data types, formulas, formatting, tables, multiple sheets, and programmatic verification. Use for spreadsheets, budgets, reports, invoices, CSV conversions, trackers, and structured data.
---

# XLSX Skill

Use this skill when the user needs a real spreadsheet. Spreadsheet quality starts with data integrity: correct sheets, headers, rows, data types, formulas, ranges, and formats. Visual polish matters after the workbook is structurally correct.

Do not fake spreadsheet verification with screenshots alone. Open the workbook programmatically and inspect cells, dimensions, formulas, and types.

## Reliable Workflow

1. Decide the mode: create new workbook, edit existing workbook, template-follow, or CSV/data conversion.
2. For existing workbooks, inspect and preserve before editing. Never rebuild unless asked.
3. Define the workbook schema: sheets, columns, row counts, formulas, formats, validation, charts/tables.
4. Choose the authoring path: `openpyxl`, pandas plus `openpyxl`, or template editing.
5. Write typed values, formulas, widths, formats, freeze panes, filters, and sheets.
6. Reopen the saved file and verify structure programmatically.
7. If formulas matter, recalculate with Excel/LibreOffice when available or clearly verify formula text/ranges.
8. If visual layout matters, render/convert to PDF or inspect in a spreadsheet app when available.
9. Fix objective defects and repeat up to 3 times.

Do not overwrite the user's original workbook unless explicitly asked.

## Tool Choice

Use `openpyxl` for most `.xlsx` creation and editing. This `Workbook()` pattern is only for new workbooks:

```python
from openpyxl import Workbook
from openpyxl.styles import Font, Alignment

wb = Workbook()
ws = wb.active
ws.title = "Summary"
ws["A1"] = "Metric"
ws["B1"] = "Value"
ws["A1"].font = ws["B1"].font = Font(bold=True)
ws["B2"] = 42
ws["B2"].number_format = "#,##0"
ws.freeze_panes = "A2"
wb.save("output.xlsx")
```

For existing workbooks, start by loading the file:

```python
from pathlib import Path
from shutil import copyfile
from openpyxl import load_workbook

src = Path("input.xlsx")
out = Path("output.xlsx")
copyfile(src, out)

wb = load_workbook(out)
ws = wb["Sheet1"]
ws["B2"] = 42
wb.save(out)
```

Use pandas when the source data already lives naturally in DataFrames:

```python
import pandas as pd
df.to_excel("output.xlsx", index=False, sheet_name="Data")
```

Then reopen with `openpyxl` for formatting, formulas, widths, freeze panes, filters, and validation.

Use pandas only for new workbooks, new sheets, raw data imports, or controlled table replacement. Do not use pandas `to_excel()` to rewrite an existing workbook unless the user asked for a rebuild; it can drop formulas, formatting, charts, images, tables, filters, hidden sheets, named ranges, and workbook properties.

Use an existing workbook as the starting point when the user supplies one. Preserve formulas, named ranges, charts, images, hidden sheets, row/column dimensions, filters, freeze panes, merged cells, validation, protection, and existing formatting unless the user asks to redesign.

## Existing Workbook Edits

When the user asks to edit an existing `.xlsx`, this mode overrides creation guidance.

Hard rules:

- Do not start from `Workbook()`.
- Do not export the whole workbook through pandas.
- Do not recreate sheets that already exist unless the user asks for a rebuild.
- Save to a new output path unless the user explicitly asks to overwrite.
- Edit only the requested cells, ranges, rows, columns, or sheets.
- Preserve unknown sheets and workbook-level objects.
- Preserve formulas unless the requested edit changes them.
- Preserve existing formatting, widths, heights, filters, freeze panes, hidden rows/columns/sheets, charts, images, comments, data validation, merged cells, named ranges, and protection whenever possible.

Before editing, make a small manifest:

```python
from openpyxl import load_workbook

def workbook_manifest(path):
    wb = load_workbook(path, data_only=False)
    try:
        defined_names = sorted(wb.defined_names.keys())
    except AttributeError:
        defined_names = sorted(dn.name for dn in wb.defined_names.definedName)
    return {
        "sheets": wb.sheetnames,
        "defined_names": defined_names,
        "tables": {ws.title: sorted(ws.tables.keys()) for ws in wb.worksheets},
        "charts": {ws.title: len(ws._charts) for ws in wb.worksheets},
        "images": {ws.title: len(ws._images) for ws in wb.worksheets},
        "dimensions": {ws.title: (ws.max_row, ws.max_column) for ws in wb.worksheets},
        "hidden_sheets": [ws.title for ws in wb.worksheets if ws.sheet_state != "visible"],
    }

before = workbook_manifest("input.xlsx")
```

After editing, compare the manifest. Any sheet, table, chart, image, named range, hidden-sheet state, or unexpected dimension change must be intentional and explainable.

For targeted edits, verify only the intended cells changed when practical:

```python
from openpyxl import load_workbook

before = load_workbook("input.xlsx", data_only=False)
after = load_workbook("output.xlsx", data_only=False)

for sheet in before.sheetnames:
    if sheet not in after.sheetnames:
        print("missing sheet:", sheet)
        continue
    ws0, ws1 = before[sheet], after[sheet]
    for row in range(1, max(ws0.max_row, ws1.max_row) + 1):
        for col in range(1, max(ws0.max_column, ws1.max_column) + 1):
            a = ws0.cell(row, col).value
            b = ws1.cell(row, col).value
            if a != b:
                print(sheet, row, col, a, "->", b)
```

Use that diff to confirm changes are limited to the request. For large files, restrict the comparison to relevant sheets/ranges plus manifest checks.

## Schema First

Before writing, decide:

- Sheet names and their purpose.
- Header row and expected row counts.
- Data types: text, number, currency, percent, date, datetime, boolean.
- Formulas and the exact ranges they should cover.
- Summary sheets, lookup sheets, assumptions, and raw data sheets.
- Formatting: number formats, widths, freeze panes, filters, tables, conditional formatting.
- Protection/hidden sheets, if requested.
- Whether charts or print-ready layout are required.

Ask only when the missing schema changes the workbook materially. Otherwise choose sensible defaults and make assumptions visible in the workbook.

## Data Integrity Rules

- Write numbers as numbers, not strings.
- Write dates as `datetime.date` or `datetime.datetime`, then set number formats.
- Write formulas as strings beginning with `=`.
- Do not include leading/trailing whitespace in headers or string cells.
- Avoid merged cells in data tables; they break sorting/filtering.
- Use one header row for tabular data.
- Keep raw data separate from summaries when the workbook is analytical.
- Freeze panes and add filters for tables users will scan.
- Use Excel tables when users need filtering/sorting/structured references.
- Use explicit number formats for currency, percentages, dates, and decimals.

## Formulas

`openpyxl` writes formulas but does not calculate them. To verify formulas, inspect the formula text/ranges. If calculated values matter and LibreOffice is available, open/save headlessly to recalculate:

```bash
libreoffice --headless --convert-to xlsx --outdir recalculated output.xlsx
```

Common formulas:

| Need | Formula |
| --- | --- |
| Sum | `=SUM(B2:B10)` |
| Count nonblank | `=COUNTA(A2:A10)` |
| Average | `=AVERAGE(B2:B10)` |
| Conditional sum | `=SUMIF(A:A,"Category",B:B)` |
| Lookup modern Excel | `=XLOOKUP(A2,Lookup!A:A,Lookup!B:B,"")` |
| Lookup compatible Excel | `=VLOOKUP(A2,Lookup!A:B,2,FALSE)` |
| Today | `=TODAY()` |

Use absolute references (`$A$1`) where copying formulas should not shift a range.

## Verification

Always reopen the workbook:

```python
from openpyxl import load_workbook

wb = load_workbook("output.xlsx", data_only=False)
print(wb.sheetnames)
for sheet in wb.sheetnames:
    ws = wb[sheet]
    print(f"{sheet}: {ws.max_row} rows x {ws.max_column} cols")
    headers = [cell.value for cell in ws[1]]
    print("headers:", headers)
    for row in ws.iter_rows(min_row=2, max_row=min(ws.max_row, 4), values_only=False):
        print([(c.value, c.data_type, c.number_format) for c in row])
```

Check:

- Expected sheet names.
- Expected row and column counts.
- Headers match the schema exactly.
- Values have correct types: numbers are numeric, dates are dates, formulas are formulas.
- Formulas cover the intended ranges and are not accidentally plain text.
- Totals/subtotals reference the correct rows.
- No stray blank rows/columns inside tables.
- Freeze panes, filters, widths, number formats, and conditional formatting are present when expected.
- Existing workbooks did not lose sheets, formulas, charts, or named ranges unintentionally.
- Existing workbook edits are limited to requested cells/ranges/sheets plus any intentional dependent updates.

For formula cached values after recalculation, open with `data_only=True`:

```python
wb = load_workbook("output.xlsx", data_only=True)
print(wb["Summary"]["B10"].value)
```

If the workbook needs to print or be visually polished, convert to PDF and inspect:

```bash
libreoffice --headless --convert-to pdf output.xlsx
```

## CSV And Data Imports

- Detect delimiter and encoding when not obvious.
- Preserve leading zeros for IDs, ZIP codes, phone numbers, SKU codes, and account numbers by storing them as text.
- Trim accidental whitespace unless whitespace is meaningful.
- Convert numeric/date fields deliberately; do not let every field become text.
- Keep an untouched raw import sheet if transformation choices matter.

## Common Failures

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| SUM returns wrong result | Numbers stored as text | Write numeric types and set formats separately |
| Dates sort alphabetically | Dates stored as strings | Use date/datetime objects and date formats |
| Formula visible as text | Missing leading `=` or cell stored as text | Write formula string beginning with `=` |
| Formula result stale/missing | Workbook not recalculated | Use Excel/LibreOffice recalculation or verify formula text |
| Filter/sort breaks | Merged cells or blank rows in data | Avoid merges and keep tables rectangular |
| Leading zeros disappear | IDs treated as numbers | Store identifier columns as text |
| Columns too narrow | No auto-fit in openpyxl | Set widths explicitly based on content |
| User edits wrong cells | Inputs and formulas mixed | Separate input cells, summaries, and protected/formula areas |
| Existing formulas lost | Rebuilt sheet from scratch | Preserve workbook and edit only required cells/ranges |
| Existing formatting/charts vanished | Workbook rewritten through pandas or `Workbook()` | Load/copy the original workbook and edit in place |

## When To Redirect

- Narrative reports belong in DOCX or PDF.
- Fixed invoices/printable statements may be PDF unless formulas/editing matter.
- Dashboards with heavy interactivity may need a BI tool or app.

## Stopping Criterion

Ship when the workbook opens cleanly, has the expected sheets and schema, stores values with correct data types, contains correct formulas/ranges, preserves requested template behavior, and passes programmatic verification. If print layout or visual polish matters, also verify the rendered output.
