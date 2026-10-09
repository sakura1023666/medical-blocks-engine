#!/usr/bin/env python3
"""Strip NHANES weight rows from xlsx via raw XML (works on broken drawing refs)."""
import os
import re
import shutil
import tempfile
import zipfile
import xml.etree.ElementTree as ET

STUDY = "/mnt/g/02block_result/24_diabetes/incidence_38341157"
NS = {"m": "http://schemas.openxmlformats.org/spreadsheetml/2006/main"}
WT_ROW = re.compile(r"^(WT[A-Z0-9_]+|SDMV[A-Z0-9_]*|Source_File|new_Weight|new_weight)$", re.I)
ET.register_namespace("", NS["m"])


def cell_value(c, ss):
    t = c.get("t")
    v = c.find("m:v", NS)
    if t == "s" and v is not None and v.text is not None:
        i = int(v.text)
        return ss[i] if i < len(ss) else ""
    if v is not None and v.text is not None:
        return v.text
    is_el = c.find("m:is", NS)
    if is_el is not None:
        return "".join((t2.text or "") for t2 in is_el.findall(".//m:t", NS))
    return ""


def read_ss(z):
    if "xl/sharedStrings.xml" not in z.namelist():
        return []
    root = ET.fromstring(z.read("xl/sharedStrings.xml"))
    out = []
    for si in root.findall("m:si", NS):
        texts = [t.text or "" for t in si.findall(".//m:t", NS)]
        out.append("".join(texts))
    return out


def strip_file(path):
    with tempfile.TemporaryDirectory() as td:
        tmp = os.path.join(td, "out.xlsx")
        shutil.copy2(path, tmp)
        with zipfile.ZipFile(tmp, "a") as z:
            sh = [n for n in z.namelist() if n.startswith("xl/worksheets/sheet") and n.endswith(".xml")][0]
            ss = read_ss(z)
            root = ET.fromstring(z.read(sh))
            drop = set()
            for row_el in root.findall("m:sheetData/m:row", NS):
                rnum = int(row_el.get("r", "0"))
                for c in row_el.findall("m:c", NS):
                    ref = c.get("r", "")
                    if not ref.startswith("A"):
                        continue
                    val = str(cell_value(c, ss)).strip()
                    if WT_ROW.match(val):
                        drop.add(rnum)
                        break
            if not drop:
                return False
            sheet_data = root.find("m:sheetData", NS)
            for row_el in list(sheet_data.findall("m:row", NS)):
                if int(row_el.get("r", "0")) in drop:
                    sheet_data.remove(row_el)
            new_xml = ET.tostring(root, encoding="utf-8", xml_declaration=True)
            # rewrite zip
        with zipfile.ZipFile(path, "r") as zin:
            with zipfile.ZipFile(tmp, "w", compression=zipfile.ZIP_DEFLATED) as zout:
                for item in zin.infolist():
                    data = zin.read(item.filename)
                    if item.filename == sh:
                        data = new_xml
                    zout.writestr(item, data)
        shutil.move(tmp, path)
    return True


def main():
    n = 0
    bi = os.path.join(STUDY, "by_index")
    for idx in os.listdir(bi):
        for root, _, files in os.walk(os.path.join(bi, idx)):
            for fn in files:
                if not fn.endswith(".xlsx") or "NHANES" not in fn:
                    continue
                p = os.path.join(root, fn)
                try:
                    if strip_file(p):
                        n += 1
                        print("stripped:", p)
                except Exception as e:
                    print("fail:", p, e)
    print("total:", n)


if __name__ == "__main__":
    main()
