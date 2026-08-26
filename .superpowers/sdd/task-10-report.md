# Task 10 Report — 全量 6 指标 batch

**日期**: 2026-08-26  
**状态**: ✅ 6/6 success

## 结果

| 指标 | 状态 | 备注 |
|------|------|------|
| PNI | success | |
| GNRI | success | 续跑修 RCS 范围后通过 |
| NLR | success | Task 8 冒烟 |
| SII | success | |
| BMI | success | 修 RCS ylim / 不收敛后通过 |
| PLR | success | |

产出根: `G:/02block_result/29_SLE/inincidence_prognosis_39003396_42304330/by_index/【success】{INDEX}/`

## 本轮修复

1. `multivariate_prognosis` 导出表漏传 `tb2`（Cox 无系数时爆）
2. `rcs_prognosis` 预测轴用完整病例范围；绘图 ylim 过滤 ±Inf；绘图失败不阻断 cutoff

## 已知 Minor

- `python3` 缺失 → PDF 栅格化警告
- code 包 MANIFEST 部分 block 未镜像（共享层块）
- Stage2 Cox 闸门多指标 `crude_ns` 降级后仍跑 KM/亚组

## 下一步

- Task 9: 飞书挂接 `29_SLE`
