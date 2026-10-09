# Design: TST 特征密度闸门（density_gate）

**日期**：2026-08-28（2026-08-31 修订：覆盖率砍列 + landmark 生效）  
**状态**：用户已确认；覆盖率砍列与 landmark 传参已按用户要求开启  
**课题锚点**：Yang et al. 2025 pbaf003 · \(N_{\mathrm{lit}}=13610\), \(F_{\mathrm{lit}}=226\)  
**密度**：\(r = N_{\mathrm{lit}}/F_{\mathrm{lit}} \approx 60.22\) **人/变量**

---

## 1. 目标

引擎级：

- **临床/文献有序名单优先**：名单 ∩ 数据 = \(F_{\mathrm{cand}}\)
- 原文密度 \(r=N_{\mathrm{lit}}/F_{\mathrm{lit}}\) 只作参考维数 \(F^*=\lfloor N/r\rfloor\)
- **仅当** \(F_{\mathrm{cand}} < F^*\) → 按覆盖率从其余 item **补齐到 \(F^*\)**
- **day1 覆盖率砍列（默认开启）**：dense+ffill 后，day1 缺失 >
  `feature_missing_threshold`（默认 30%）的特征 DROPPED；
  `density_gate_apply_coverage_drop=FALSE` 可关闭
- 患者级缺失 ≤30% 仍剔除

## 2. 已锁定参数

| 项 | 值 |
|----|-----|
| \(F_{\mathrm{cand}}\) | 病种 `feature_priority` ∩ 库内 item |
| \(N\) | `tst_cohort` 出组人数 |
| \(F_{\mathrm{cand}} \ge F^*\) | 先全收临床名单，再按 day1 覆盖率砍列 |
| \(F_{\mathrm{cand}} < F^*\) | 补齐到 \(F^*\)，再覆盖率砍列 |
| day1 砍列 | **默认开启** |

## 3. 流程

```
tst_cohort → N
小时长表 ∩ feature_priority → F_cand
F* = floor(N / (N_lit/F_lit))
gate keep → dense 24h → ffill → day1 覆盖率砍列 → 患者缺失≤30% → 导出
```

## 4. Landmark 生效（unit `L{H}_*`）

- prepare：`n_days = H/24`，过滤 `landmark_ids[[H]]`，共享 `train/val/test_ids` 交集
- 默认 `landmark_allow_sliding=FALSE`（仅入院起连续 n_days）
- `prepare_meta.json` 含 `landmark_hours`；L24 与 L120 的 D / n_patients / AUC 不得相同

## 5. 验收（AKI）

- 闸门后约 44 → 覆盖率砍列后约 20 维；`decision` 含 `+coverage_drop`
- L24_B：`D=1`；L120_B：`D=5`；eligible N 随 landmark 递减
