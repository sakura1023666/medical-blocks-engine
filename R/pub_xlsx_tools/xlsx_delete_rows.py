#!/usr/bin/env python3
"""Delete rows from the active sheet of an .xlsx via openpyxl (keeps styles.xml / borders).

Usage: xlsx_delete_rows.py <path.xlsx> 34,39,71
Rows are 1-based. Pass a pre-stripped file (see xlsx_strip.py) so openpyxl can open it.
"""
import sys, warnings
warnings.filterwarnings("ignore")
import openpyxl

def main(path, rows):
    wb = openpyxl.load_workbook(path)
    ws = wb.active
    for r in sorted({int(x) for x in rows.split(",") if x.strip()}, reverse=True):
        if r >= 1:
            ws.delete_rows(r, 1)
    wb.save(path)
    print("deleted", sorted({int(x) for x in rows.split(",") if x.strip()}, reverse=True))

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("usage: xlsx_delete_rows.py <path.xlsx> <rows,csv>", file=sys.stderr); sys.exit(2)
    main(sys.argv[1], sys.argv[2])
