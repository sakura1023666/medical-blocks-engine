### Task 5: MIMIC shared + unit 全链

**Files:**
- Write under: `.../Medication_regimen_model_alteplase_ipw/` checkpoints、`by_unit/【success】main`（或 `main_MIMIC`）

- [ ] **Step 1: shared**

```bash
"/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe" \
  run/ipw_pe_alteplase/run_ipw_pe_alteplase_batch.R \
  --config "G:/02block_result/47_PE/Medication_regimen_model_alteplase_ipw/config_ipw_pe_alteplase_MIMIC.R" \
  --shared-only --no-skip
```

- [ ] **Step 2: unit main**

```bash
"/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe" \
  run/ipw_pe_alteplase/run_ipw_pe_alteplase_batch.R \
  --config "G:/02block_result/47_PE/Medication_regimen_model_alteplase_ipw/config_ipw_pe_alteplase_MIMIC.R" \
  --only-unit main --workers 1 --no-skip
```

- [ ] **Step 3: 清单验收（对照卒中键）**

```bash
SUCCESS=".../by_unit/【success】main"   # 以实际目录名为准
ls "$SUCCESS/Figures" | rg 'Figure (1|2|3|4|5|S1|S2|S3|S4)'
ls "$SUCCESS/Tables"  | rg 'Table (1|S1|S2|S3|S4)'
```

Expected: 角色齐全；Fig5 标题含 STEPP / composite risk；Table1 为 sIPTW 基线。

---

