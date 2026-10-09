### Task 3: 暴露 Block + 注册 + 决策树

**Files:**
- Create: `Blocks/69_ipw_diabetes_stroke_full/10block_ipw_alteplase_exposure.R`
- Modify: `R/pipeline_runner.R`（注册 `ipw_alteplase_exposure`）
- Create: `Decisiontree/decision_tree_ipw_pe_alteplase.md`
- Run: `python3 scripts/update_blocks_catalog.py`（若新增 register_block）

**Interfaces:**
- Consumes: `ctx$data$imputed`；`config$ipw_alteplase` list  
- Produces: columns `Alteplase`, `surv_time_28d`, `surv_event_28d`；替换流水线中原 `ipw_diabetes_exposure` 位

- [ ] **Step 1: 实现暴露块（逻辑）**

```r
# config$ipw_alteplase 示例
# list(
#   exposure_var = "Alteplase",
#   rx_flag_var = "ymtmd",      # 或预合并列 Alteplase_rx
#   iv_flag_var = "...",        # MIMIC/eICU 不同则在 data 层先统一成 Alteplase
#   prefer_precomputed = TRUE,  # 若宽表已有 Alteplase=0/1 则直接用
#   followup_days = 28L,
#   time_source = "hosp_survival_day",
#   event_source = "death_within_hosp_28days",
#   time_var = "surv_time_28d",
#   event_var = "surv_event_28d"
# )
# 28d 结局派生复制 01block_ipw_diabetes_exposure.R 中 pipeline_outcome_as_01 逻辑
```

优先在 Task 2 就把 `Alteplase` 写进宽表，本块 `prefer_precomputed=TRUE` 只校验+派生结局，避免双库列名分叉。

- [ ] **Step 2: `register_block("ipw_alteplase_exposure", ...)` + `pipeline_runner.R` 映射**

- [ ] **Step 3: 写 `Decisiontree/decision_tree_ipw_pe_alteplase.md`**

内容须引用对抗阅读 chosen 结论；流水线块列表与卒中定稿同构，仅暴露块名与库参数不同；注明双栏拼图收口。

- [ ] **Step 4: 更新 catalog**

```bash
python3 scripts/update_blocks_catalog.py
```

- [ ] **Step 5: 用户确认决策树**（聊天展示 mermaid）后方可 Task 4 写项目 config。

---

