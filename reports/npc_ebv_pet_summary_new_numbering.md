# NPC EBV×PET：`summary（new）` 独立编号（不顺延旧 OS-ML）

输出根：`/mnt/g/02block_result/53_NPC/ml_40395549/summary（new）`  
旧 `summary_results/`（Table1–4 / Figure1–6 OS-ML）保持不动。

## 主文顺序（逻辑链）

| 序 | 产物 | 角色 |
|---|---|---|
| 1 | Figure 1 | EBV 多阈值分布 + T0 相对编码分数（科学编码可复现） |
| 2 | Figure 2 | EBV 分数 × PET 相关热图 |
| 3 | Table 1 | 五终点事件账本（OS / PFS / DM / DM+D / LR） |
| 4 | Figure 3 + Table 2 | 五终点 × C/E/P2/EP2 折外 36 月 IPCW-AUC |
| 5 | Figure 4 + Table 3 | **远转主叙事**：嵌套 AUC 柱 + EP2 配对 ΔAUC（对标报告 0.634→0.711 的折外口径） |
| 6 | Figure 5 + Table 4 | 调整 HR（DM/LR 原因特异 Cox） |
| 7 | Figure 6 | EBV×PET 四象限远转粗率（TLG>65 / NTR>0.64 外部门槛） |
| 8 | Figure 7 | 联合风险三分位 KM（OS/PFS/DM） |
| 9 | Figure 8 + Table 5 | 6/9/12 月界标：轨迹相对 EP2 的 ΔAUC |
| 10 | Figure 9 | 年代留出（≤2022 训 / 2023–2025 验） |
| 11 | Figure 10 | 决策曲线（跨模型净获益） |

## 补充

| 产物 | 角色 |
|---|---|
| Figure S1 | 远转竞争风险 CIF |
| Table S1 | EBV 记录类型编码词典 |
| Table S2 | 重定义轨迹计数 |
| Table S3 | 年代留出数值表 |
| Table S4 | DCA 净获益数值 |
| Table S5 | EBV×PET RERI |
| Table S6 | EBV 编码敏感性（严格检出 / 统一 5000 等） |
| Table S7 | 口径 A vs B 样本量 |
| Table S8 | 表观（再代入）嵌套 AUC（对照用，非主结论） |

## 验证口径（与旧 OS-ML 单次 75/25 对照）

- 重复 ×5 折、事件分层、折外线性预测 → 36 月 IPCW-AUC  
- 配对重采样 CI（固定 OOF 预测）  
- 竞争风险终点用 timeROC `AUC_1`  

入口：`Rscript run/npc_ebv_pet/rebuild_joint_pub_from_data.R`  
（`--quick` 仅冒烟；正式用默认 `--repeats 8 --boot 400`）
