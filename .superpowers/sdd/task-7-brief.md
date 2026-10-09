### Task 7: Catalog 同步

**Files:**
- Modify: `docs/Blocks_catalog.md`（AUTO 段）

- [ ] **Step 1: 确认三文件均 `register_block`**

- [ ] **Step 2: Run**

```bash
cd /mnt/e/01block/01Block-new-Final
python3 scripts/update_blocks_catalog.py
```

Expected: catalog 出现 `dxa_qct_agreement`, `diagnostic_vs_fracture`, `modality_discordance_profile`。

- [ ] **Step 3: `rg "dxa_qct_agreement" docs/Blocks_catalog.md` 有命中**

---

