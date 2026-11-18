# 复用地图：预后 v2 发表 P0 防复发门控（2026-10-26）

来源：Hip arthroplasty + AKI（`prognosis_v2_41904528`）Nature 多轮 P0（Fig3/6/7/4、S7 方向、PH、取材、MICE、下划线、中介 Model2 诚实脚注）。

## 下次课题怎么用（不要再手审一遍才发现）

1. **规则（Agent 必读）**：`.cursor/rules/prognosis_v2_pub_p0_gate.mdc`（alwaysApply）
2. **清单**：`pub-qc-after-project/checklist.md` **§B4**
3. **失败模式表**：`nature-statistics/references/common-failure-modes.md` →「Medical Blocks 预后 v2 漏检」
4. **机器门控**：remirror / 交付收尾调用

```r
source("R/pv2_pub_p0_gate.R")
pv2_pub_p0_gate(
  summary_root = "<...>/summary_results",
  locked_scheme = "binary",          # 或 cascade 锁定值
  contrast_lab = "High vs Low",
  require_ph_table = TRUE,
  require_mediation = TRUE,
  stop_on_fail = TRUE
)
```

CLI 等价：

```bash
Rscript -e 'source("R/pv2_pub_p0_gate.R"); pv2_pub_p0_gate("<summary_results>", locked_scheme="binary")'
```

5. Hip 薄封装已挂：`run/prognosis_v2/remirror_hip_aki_pub.R` 末尾。新课题 remirror 复制同一调用即可。

## 覆盖的失败模式

| ID | 问题 | 门控点 |
|----|------|--------|
| P0-1 | KM ≠ 锁定 binary | Fig3 PDF：Low/High；禁 Q1+Q4 |
| P0-2 | Fig6 ≠ S8 Direct | S8 Direct HR 点估计 ∈ Fig6 文本 |
| P0-3 | Fig7 无 High vs Low / 无 P-int | 轴标 + `P-int` |
| P0-4 | RCS 仅 P-overall | 必须 `P-linear`（+ P-nonlinear） |
| P0-5 | S7 path a 反向 | 脚注/题名反写信号 |
| P0-6 | 无 PH | Table S9 / proportional 表存在 |
| P0-7/8 | Methods 缺 MICE 裁决 / 取材时点 | Methods 关键词 |
| 展示 | Fig2 `_` | PDF + 图面说明扫下划线 |
| 脚注 | 假 Model3 / 假共线 | 规则 + Agent §B4（机器难判诚实性，靠清单） |

## 相关引擎文件

| 文件 | 作用 |
|------|------|
| `R/pv2_pub_p0_gate.R` | 机器半边 |
| `R/pv2_literature_pub_tables.R` | S7 强制暴露→中介 |
| `R/quantile_scheme_cascade.R` | 分位锁定 |
| `docs/reuse/2026-10-23-prognosis-v2-hip-aki-pub-reuse-map.md` | 宽表 / 交付白名单 |

## 反例

- 只跑结构 DPI QC 就 PASS，不过 §B4 / 不跑 `pv2_pub_p0_gate`
- 修完图不挂 gate，下一课题 remirror 再踩同一坑
- 把 Hip `_fix_p0_hip_aki_pub.R` 当长期入口（一次性脚本应归档；门控在引擎）
