# Nature figure QC — sleep dyslipidemia mainval（2026-11-27 re-audit）

- Figures root: `…/summary_results/Figures` (`pdf/` + `image_information/`)
- Formats: PDF-only default; 8 stems; vector PDF (`bad_pdf_raster=0`)
- Fonts: Times / Liberation Serif family (Layer A4 PASS)
- Underscores: Layer A3 PASS after Fig7 subtitle scrub (`Sleep Group`, not `Sleep_Group`)

## Figure-level

| Figure | Check | Result |
|------|-------|--------|
| Fig5 ROC | NHANES AUC label = 0.764 (not 0.765); aligns Table S4 | **PASS / P0-1 FIXED** |
| Fig7 Subgroup | P-int on first level of each stratum; 3-cohort panels | **PASS / P0-9 FIXED** |
| Fig1–4,6,S1 | Present under `pdf/` + md; no flat root PDFs | PASS |
| Collision | Dense forest text may warn; delivery kept vector | WARN (not P0) |

## image_information

- Fig5/Fig7 md have `## 图面说明` + `## 分析上下文`; AUC / P-int numbers match PDF text.
- No programming underscores in Fig5/Fig7 md.

## Conclusion

**PASS** (with non-blocking collision WARN for dense Fig7). All 9 former P0 FIXED (Fig5 AUC=0.764; S1 no S10; bootstrap B=200 seed; RCS knots 5/35/65/95 ref 7.5; MICE limitation; WTMEC no cycle multipliers; S9 subset footnote; Table4 no ragcod on primary; Fig7 P-int).
