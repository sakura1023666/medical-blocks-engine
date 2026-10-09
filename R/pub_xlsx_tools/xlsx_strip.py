#!/usr/bin/env python3
"""Strip broken drawing refs + xml:space inline attrs from an .xlsx (openpyxl/openxlsx roundtrip fix).

Usage: xlsx_strip.py <path.xlsx>
- removes xl/drawings/* and <drawing/> element + rels (openxlsx writes a dangling drawing rel that
  makes openpyxl raise KeyError: 'xl/drawings/drawing1.xml')
- removes xml:space="preserve" (openpyxl writes inlineStr cells that openxlsx then reads back as a
  literal 'xml:space="preserve">...' text blob)
Rewrites the zip in place. Prints 'stripped' or 'clean'.
"""
import zipfile, re, sys
from pathlib import Path
from lxml import etree

M = "{http://schemas.openxmlformats.org/spreadsheetml/2006/main}"

def main(path):
    with zipfile.ZipFile(path) as z:
        files = {n: z.read(n) for n in z.namelist()}
    changed = False
    for n in list(files):
        if "/drawings/" in n:
            del files[n]; changed = True
    for n in list(files):
        if re.match(r"xl/worksheets/_rels/sheet\d+\.xml\.rels", n):
            xml = etree.fromstring(files[n])
            for rel in list(xml):
                # 旧版只匹配小写 "drawing"，漏掉 vmlDrawing（大写 D）→ 悬空 rel 触发
                # Excel「部分内容有问题」修复弹窗。这里对 drawing / vmlDrawing / legacyDrawing
                # 一并剔除（对应部件已从包中删除）。
                typ = str(rel.get("Type", "")).lower()
                if "drawing" in typ:
                    xml.remove(rel); changed = True
            files[n] = etree.tostring(xml, xml_declaration=True, encoding="UTF-8")
    for n in list(files):
        if re.match(r"xl/worksheets/sheet\d+\.xml", n):
            xml = etree.fromstring(files[n])
            for tag in ("drawing", "legacyDrawing", "tableParts"):
                for el in xml.findall(M + tag):
                    xml.remove(el); changed = True
            # openpyxl/lxml 往返会丢掉 x14ac/xr/xr2/xr3 的 xmlns 声明（它们只出现在
            # Ignorable 属性值里、不作为真实元素前缀），留下 ns1:Ignorable 引用未声明
            # 前缀 → Excel 报「部分内容有问题」。连同 markup-compatibility 声明一起删。
            for el in xml.iter():
                for attr in list(el.attrib):
                    if attr.endswith("}Ignorable") or attr == "Ignorable":
                        del el.attrib[attr]; changed = True
            s = etree.tostring(xml, xml_declaration=True, encoding="UTF-8").decode("utf-8")
            s2 = s.replace(' xml:space="preserve"', "")
            if s2 != s:
                changed = True
            files[n] = s2.encode("utf-8")
    for n in list(files):
        if n == "xl/sharedStrings.xml":
            t = files[n].decode("utf-8", "replace")
            t2 = t.replace(' xml:space="preserve"', "")
            if t2 != t:
                files[n] = t2.encode("utf-8"); changed = True
    if "[Content_Types].xml" in files:
        xml = etree.fromstring(files["[Content_Types].xml"])
        ch2 = False
        for el in list(xml):
            v = str(el.get("PartName") or "") + str(el.get("Extension") or "")
            if "drawing" in v.lower():
                xml.remove(el); ch2 = True
        if ch2:
            files["[Content_Types].xml"] = etree.tostring(xml, xml_declaration=True, encoding="UTF-8")
            changed = True
    if changed:
        tmp = Path(str(path) + ".tmp")
        with zipfile.ZipFile(tmp, "w", zipfile.ZIP_DEFLATED) as z:
            for k, v in files.items():
                z.writestr(k, v)
        tmp.replace(path)
    print("stripped" if changed else "clean")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("usage: xlsx_strip.py <path.xlsx>", file=sys.stderr); sys.exit(2)
    main(sys.argv[1])
