# 分析套路决策树：环境 ExWAS → 胃癌（发病地基）

对抗阅读：`adversarial_lit_reading/rounds/A_tree_round2_revised_paper_004_Q*.md`  
论文：Dong 等，Ecotoxicology and Environmental Safety 2026，doi:10.1016/j.ecoenv.2025.119544。  
用户数据：NHANES 2003–2016 自报胃癌（事件 31 / 39149）加上营养提取目录中的金属、汞、邻苯、PFAS。原文 73 种毒物并未都在该提取里。

## 地基

发病。结局是「会不会发生（自报）胃癌」，主模型是 logistic，不是 Cox。  
方法后缀挂在已有环境块旁边的新文件上，不改 `01block_wqs_environment.R` 的 P 值搜参，也不改旧 VOC 课题。

## 顺序

1. 按 cycle + SEQN 合并结局与环境列（`exwas_gastric_assemble`）。
2. 检出限/缺失规则：缺失 >40% 或低于检出 >90% 剔除；低于检出 >30% 二分类；其余自然对数。
3. mice，m=5，迭代 5，种子 123456。操作层取第 1 套 complete。
4. **ExWAS 不加权**，全调整 logistic，BH-FDR；类别内再做 BH（`exwas_unweighted`）。
5. 弹性网（alpha 11 档，5 折）做 ERS；bootstrap 纳入频率种子 2024。ERS 与结局：Model1 空模、Model2 协变量。权重列齐全才 `svyglm`。
6. WQS 固定 q=4、B=1000，不按 P 值换参（`wqs_exwas_fixed`）。
7. 年龄 <60 / ≥60 与性别分层沿用原文 Figure 3，不是另选 65 岁。
8. 炎症中介仅在白细胞等列存在时做；当前提取没有血常规，该图不能编造。

## 对抗阅读采纳的边界

- 每 IQR 的 OR 是报告尺度，不是事先声明线性。RCS 是事后诊断。
- ERS 高/低的组数是事先定的两组，切点是样本中位数。
- 弹性网拟合原文没写权重；加权的是 ERS 的 logistic、描述、RCS、亚组和中介。
- 七周期不能沿用单周期 `wtsa2yr`。设计列目前不在结局 csv 里，加权步骤会写明缺列并停止假装加权。
- 尼古丁代谢物未出现在本提取中，不把吸烟标志物同时当暴露和协变量。
- 自报胃癌是诊断后测量暴露，反向因果比原文牙周炎更重，结论只写关联。

## 图和表对照

| 原文 | 本课题产出 | 说明 |
|---|---|---|
| Figure 1 流程 | 合并日志中的 n 与事件数 | 纳排已在上游 csv |
| Figure 2 火山图 | `Figure_2_ExWAS_volcano.pdf` | 不加权 ExWAS |
| Figure 3 年龄性别分层 | 待分层块；切点 60 | 事件仅 31，层内会极不稳定 |
| Figure 4 ERS | `Table_ERS_logistic.csv`、`Table_S5_ERS_inclusion.csv` | |
| Figure 5 炎症中介 | 缺血常规则不出图 | 不补假数 |
| Table 1 基线 | 仅有年龄、性别可描述 | 原文协变量大多不在 csv |
| Table 2 ExWAS | `Table_2_ExWAS_unweighted.csv` | |
| 补充表 1 暴露筛查 | `Table_S1_exposure_screen.csv` | |
| WQS | `Table_WQS_weights.csv` | 固定参数 |

入口：`run/environment_exwas/run_environment_exwas_batch.R`  
配置：`/mnt/g/02block_result/51_gastric cancer/environment_41380607/config_environment_exwas_gastric.R`
