"""Recompute Fig2 bar P-values the same way as redraw_fig3_sapsii.py."""
from pathlib import Path
import numpy as np
from scipy.stats import mannwhitneyu

# From prior Fig2 / table2 style day metrics if CSV exists; else print discrete MWU note
# Try reading any saved day metrics
cands = list(Path(r"G:/02block_result/33_AKI/two_stage_transformer_40041421").rglob("*fig2*"))
print("fig2 cands", cands[:10])

# Theoretical: n=5 vs 5 complete separation
u = mannwhitneyu([1,2,3,4,5],[0,0,0,0,0], alternative="two-sided")
print("complete sep example p=", u.pvalue, "fmt3=", f"{u.pvalue:.3f}")

# Typical pattern TF auc > APSIII every day
# Use approximate values from Fig2 text extraction earlier: Day1 TF 0.81 APS 0.65, Day5 0.82 vs 0.65
# Acc ~0.72 vs 0.63 style - need real numbers from rebuild if possible

# Load from Table2 xlsx if possible
from openpyxl import load_workbook
p = Path(r"G:/02block_result/33_AKI/two_stage_transformer_40041421/summary_results/Tables/Table 2-MIMIC-Daily_performance_Transformer.xlsx")
wb = load_workbook(p, data_only=True)
ws = wb.active
for i, row in enumerate(ws.iter_rows(values_only=True), 1):
    if i <= 15:
        print(i, row)
