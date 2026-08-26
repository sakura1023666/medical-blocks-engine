### Task 9: 飞书挂接

**Files:**
- Create or modify: `run/feishu/run_feishu_setup_sle_aki_tables.R`（可复用 `run_feishu_setup_routine_table.R` 模式）
- 工作计划行：模块名含 `SLE` / `发病预后两阶段`；编号取当前最大 B + 1（查飞书或本地 xlsx）

**Interfaces:**
- `BLOCK_RESULT_ROOT` 含 `G:/02block_result`；扫描 `29_SLE`
- `.env.feishu` 已有 `FEISHU_APP_ID/SECRET/BITABLE_APP_TOKEN`

- [ ] **Step 1: dry-run `run_feishu_resync_block_result.R --dry-run`**
- [ ] **Step 2: 写入工作计划「进行中」**
- [ ] **Step 3: 全批成功后 mark done**

---
