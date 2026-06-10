#!/usr/bin/env python3
"""Verify .xlsx workbooks: structural manifest, content inspection, cell diff.

Subcommands:
  manifest book.xlsx
      Workbook-level structure: sheets, dimensions, tables, charts, images,
      defined names, hidden sheets. Run before AND after editing an existing
      workbook — any difference must be intentional and explainable.

  inspect book.xlsx [--sheet NAME] [--rows N]
      Per-sheet headers plus the first N data rows as
      (value, data_type, number_format) triples. Verifies types and formats,
      not just values.

  diff before.xlsx after.xlsx [--sheet NAME] [--limit N]
      Cell-by-cell value diff (formulas as text, not cached results).
      Confirms edits are limited to the intended cells.

All output is JSON.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

try:
    from openpyxl import load_workbook
except ImportError:
    print("error: openpyxl is required (python3 -m pip install openpyxl)", file=sys.stderr)
    raise SystemExit(1)


def build_manifest(path: Path) -> dict:
    wb = load_workbook(path, data_only=False)
    try:
        defined_names = sorted(wb.defined_names.keys())
    except AttributeError:  # older openpyxl API
        defined_names = sorted(dn.name for dn in wb.defined_names.definedName)
    return {
        "sheets": wb.sheetnames,
        "defined_names": defined_names,
        "tables": {ws.title: sorted(ws.tables.keys()) for ws in wb.worksheets},
        "charts": {ws.title: len(ws._charts) for ws in wb.worksheets},
        "images": {ws.title: len(ws._images) for ws in wb.worksheets},
        "dimensions": {ws.title: [ws.max_row, ws.max_column] for ws in wb.worksheets},
        "hidden_sheets": [ws.title for ws in wb.worksheets if ws.sheet_state != "visible"],
        "frozen_panes": {ws.title: ws.freeze_panes for ws in wb.worksheets if ws.freeze_panes},
    }


def inspect(path: Path, sheet: str | None, rows: int) -> dict:
    wb = load_workbook(path, data_only=False)
    sheets = [sheet] if sheet else wb.sheetnames
    out: dict = {}
    for name in sheets:
        if name not in wb.sheetnames:
            out[name] = {"error": "sheet not found"}
            continue
        ws = wb[name]
        headers = [cell.value for cell in ws[1]] if ws.max_row >= 1 else []
        sample = []
        for row in ws.iter_rows(min_row=2, max_row=min(ws.max_row, 1 + rows)):
            sample.append([
                {"value": c.value, "type": c.data_type, "format": c.number_format}
                for c in row
            ])
        out[name] = {
            "rows": ws.max_row,
            "cols": ws.max_column,
            "headers": headers,
            "sample_rows": sample,
        }
    return out


def diff(before_path: Path, after_path: Path, sheet: str | None, limit: int) -> dict:
    before = load_workbook(before_path, data_only=False)
    after = load_workbook(after_path, data_only=False)
    changes: list = []
    result: dict = {
        "sheets_removed": [s for s in before.sheetnames if s not in after.sheetnames],
        "sheets_added": [s for s in after.sheetnames if s not in before.sheetnames],
        "cell_changes": changes,
    }
    sheets = [sheet] if sheet else [s for s in before.sheetnames if s in after.sheetnames]
    truncated = False
    for name in sheets:
        if name not in before.sheetnames or name not in after.sheetnames:
            continue
        ws0, ws1 = before[name], after[name]
        for row in range(1, max(ws0.max_row, ws1.max_row) + 1):
            for col in range(1, max(ws0.max_column, ws1.max_column) + 1):
                a = ws0.cell(row, col).value
                b = ws1.cell(row, col).value
                if a != b:
                    if len(changes) >= limit:
                        truncated = True
                        break
                    changes.append({
                        "sheet": name,
                        "cell": ws1.cell(row, col).coordinate,
                        "before": a,
                        "after": b,
                    })
            if truncated:
                break
        if truncated:
            break
    result["total_shown"] = len(changes)
    result["truncated"] = truncated
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description="Verify .xlsx workbooks.")
    sub = parser.add_subparsers(dest="command", required=True)

    p_manifest = sub.add_parser("manifest")
    p_manifest.add_argument("book", type=Path)

    p_inspect = sub.add_parser("inspect")
    p_inspect.add_argument("book", type=Path)
    p_inspect.add_argument("--sheet")
    p_inspect.add_argument("--rows", type=int, default=3)

    p_diff = sub.add_parser("diff")
    p_diff.add_argument("before", type=Path)
    p_diff.add_argument("after", type=Path)
    p_diff.add_argument("--sheet")
    p_diff.add_argument("--limit", type=int, default=200)

    args = parser.parse_args()

    paths = [getattr(args, k) for k in ("book", "before", "after") if hasattr(args, k)]
    for p in paths:
        if not p.expanduser().exists():
            print(f"error: file not found: {p}", file=sys.stderr)
            return 2

    if args.command == "manifest":
        out = build_manifest(args.book.expanduser())
    elif args.command == "inspect":
        out = inspect(args.book.expanduser(), args.sheet, args.rows)
    else:
        out = diff(args.before.expanduser(), args.after.expanduser(), args.sheet, args.limit)

    print(json.dumps(out, indent=2, default=str))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
