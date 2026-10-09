#!/usr/bin/env python3
"""Edit selected XLSX cells by patching worksheet XML, preserving the workbook."""

import csv
import os
import sys
import tempfile
import zipfile
import xml.etree.ElementTree as ET

NS_MAIN = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
NS_DOC = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
NS_PKG = "http://schemas.openxmlformats.org/package/2006/relationships"


def worksheet_path(zin: zipfile.ZipFile, requested_sheet: str) -> str:
    workbook = ET.fromstring(zin.read("xl/workbook.xml"))
    sheets = workbook.find(f"{{{NS_MAIN}}}sheets")
    selected = None
    for sheet in sheets:
        if not requested_sheet or sheet.attrib.get("name") == requested_sheet:
            selected = sheet
            break
    if selected is None:
        raise ValueError(f"Worksheet not found: {requested_sheet}")
    rel_id = selected.attrib[f"{{{NS_DOC}}}id"]
    rels = ET.fromstring(zin.read("xl/_rels/workbook.xml.rels"))
    target = None
    for rel in rels:
        if rel.attrib.get("Id") == rel_id:
            target = rel.attrib["Target"]
            break
    if target is None:
        raise ValueError(f"Worksheet relationship not found: {rel_id}")
    target = target.replace("\\", "/").lstrip("/")
    return target if target.startswith("xl/") else f"xl/{target}"


def row_number(cell_ref: str) -> int:
    digits = "".join(ch for ch in cell_ref if ch.isdigit())
    if not digits:
        raise ValueError(f"Invalid cell reference: {cell_ref}")
    return int(digits)


NS_MC = "http://schemas.openxmlformats.org/markup-compatibility/2006"


def patch_sheet(xml_bytes: bytes, edits: list[tuple[str, str]]) -> bytes:
    ET.register_namespace("", NS_MAIN)
    root = ET.fromstring(xml_bytes)
    # ET 重序列化会丢弃未使用的 xmlns 声明（x14ac/xr/xr2/xr3 只出现在
    # mc:Ignorable 属性值里），留下悬空 Ignorable → Excel「部分内容有问题」。
    # 该属性删除后文件严格合规，任何调用方都不再依赖后续 strip 兜底。
    for attr in list(root.attrib):
        if attr == f"{{{NS_MC}}}Ignorable" or attr == "Ignorable":
            del root.attrib[attr]
    sheet_data = root.find(f"{{{NS_MAIN}}}sheetData")
    if sheet_data is None:
        raise ValueError("Worksheet has no sheetData")

    rows = {int(row.attrib["r"]): row for row in sheet_data}
    for ref, value in edits:
        rn = row_number(ref)
        row = rows.get(rn)
        if row is None:
            row = ET.Element(f"{{{NS_MAIN}}}row", {"r": str(rn)})
            sheet_data.append(row)
            rows[rn] = row
        cell = next((c for c in row if c.attrib.get("r") == ref), None)
        if cell is None:
            cell = ET.SubElement(row, f"{{{NS_MAIN}}}c", {"r": ref})
        cell.attrib["t"] = "inlineStr"
        for child in list(cell):
            cell.remove(child)
        inline = ET.SubElement(cell, f"{{{NS_MAIN}}}is")
        text = ET.SubElement(inline, f"{{{NS_MAIN}}}t")
        text.text = value

    ordered_rows = sorted(list(sheet_data), key=lambda node: int(node.attrib["r"]))
    sheet_data[:] = ordered_rows
    return ET.tostring(root, encoding="utf-8", xml_declaration=True)


def main() -> None:
    if len(sys.argv) not in (3, 4):
        raise SystemExit("usage: xlsx_edit_cells.py workbook.xlsx edits.tsv [sheet]")
    path, edits_path = sys.argv[1], sys.argv[2]
    requested_sheet = sys.argv[3] if len(sys.argv) == 4 else ""
    edits = []
    with open(edits_path, newline="", encoding="utf-8") as handle:
        for row in csv.DictReader(handle, delimiter="\t"):
            edits.append((row["cell"], row["value"]))
    if not edits:
        return

    with zipfile.ZipFile(path, "r") as zin:
        target = worksheet_path(zin, requested_sheet)
        patched = patch_sheet(zin.read(target), edits)
        fd, tmp = tempfile.mkstemp(suffix=".xlsx", dir=os.path.dirname(path) or ".")
        os.close(fd)
        try:
            with zipfile.ZipFile(tmp, "w") as zout:
                for item in zin.infolist():
                    payload = patched if item.filename == target else zin.read(item.filename)
                    zout.writestr(item, payload)
            os.replace(tmp, path)
        finally:
            if os.path.exists(tmp):
                os.unlink(tmp)


if __name__ == "__main__":
    main()
