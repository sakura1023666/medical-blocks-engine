# Task 8 Report — Runner + Worker batch（NLR 冒烟）

**日期**: 2026-08-26  
**状态**: ✅ 完成（NLR 全链 success）

## 验证命令

```bash
Rscript run/sle_aki_inc_prog/run_sle_aki_inc_prog_batch.R \
  --config "G:/02block_result/29_SLE/inincidence_prognosis_39003396_42304330/config_sle_aki_inc_prog_batch.R" \
  --only-index NLR --workers 1 --no-skip
```

## 关键结果

| 项 | 值 |
|----|-----|
| 结局标签 | `AKI` / `No AKI`（data_clean 分布 110 / 160） |
| Stage0 队列 | SLE∩baseline n=270，AKI=110 |
| Stage1 分析 n | 90（NLR 非缺失 + 极端值修剪后） |
| Stage2 AKI 亚队列 | n=49，28d 事件=11 |
| Worker 耗时 | 264.6s（全链含共享层 ~7min） |
| 产出目录 | `by_index/【success】NLR/` |

## 本轮修复

1. **km_strata 分层注入** — `ip_two_stage_patch_km_strata_for_index()`（含 `degrade_done` 等 Cox 降级分支）
2. **Stage2 index_var 注入** — `ip_two_stage_patch_stage2_blocks_for_index()` + 续跑时 `ctx$config` 同步
3. **segmented_cox anchor** — `cox_highest_group_model2_hr` 为空向量时 `is.finite()` 报错；四块 segmented 均已防护

## 已知 Minor（非阻塞）

- `python3` 缺失 → PDF 栅格化警告（图仍落盘）
- code 包 MANIFEST 可能 26/31 block（共享层块未全镜像，待 Task 10 统一）
- Cox 闸门全降级（crude_ns）时仍继续 KM/RCS/亚组（worker 已设 `degrade_done`）
- 旧 Figure 编号镜像可能有历史残留（全量 batch 前建议清根目录 Figures）

## 下一步

- Task 9: 飞书挂接 `29_SLE`
- Task 10: 6 指标全量 `--workers auto` + Blocks_catalog 72_* 登记
