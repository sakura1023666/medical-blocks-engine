### Task 9: Table2 Panel 合并脚本

**Files:**
- Create: `{STUDY}/scripts/merge_table2_dual_bmd_panels.R`

**Interfaces:**
- Consumes: QCT / DXA 两次 multivariate 导出的 Table2 xlsx（或 `ctx` 落盘 csv）
- Produces: 单一 `Table 2. ...xlsx`，Panel A=QCT-vBMD，Panel B=DXA T-score；脚注两套 n 与变量锁

- [ ] **Step 1: 实现读写合并（优先 `openxlsx`/`pub_xlsx` 外科式；若尚无表则先 csv rbind + `export_sci_table`）**
- [ ] **Step 2: 冒烟用两张假 Panel csv 合并出文件**

---

