# 单库发病 ML 预测定稿标准包

**日期:** 2026-08-27  
**范围:** `ml_dual` / 单库发病预测（`db_mode=nhanes` 等）；全课题默认，禁止再出现空图号、同名附表、非胜出分位表。

## 主图（连续，无空号）

| 号 | 内容 |
|----|------|
| Figure 1 | Flowchart |
| Figure 2 | RCS |
| Figure 3 | ML performance combined 2×4 |
| Figure 4 | SHAP |
| Figure 5 | Subgroup Forest |

- 无 KM / 无相关热图时不预留 Fig3 槽。
- **Figure S1（特征选择）规则**：
  - **仅 LASSO**：S2A（LassoGenes）+ S2B（LassoModel）**上下拼** → `Figure S1. Lasso.pdf`
  - **其它单方法**（Boruta / RF / …）：该方法 S2 图**直接升为** S1，**不拼**
  - **≥2 方法**：韦恩 / Upset → `Figure S1. Venn.pdf`（最终 ML 特征仍可锁定 LASSO）

## 主表（胜出分位后全部顺延）

| 号 | 内容 |
|----|------|
| Table 1 | Baseline |
| Table 2 | Logistic（**仅闸门胜出 grouping**，如 quartile） |
| Table 3 | ML performance wide **training** |
| Table 4 | ML performance wide **validation** |

- 非胜出 tertile / binary **删除，不进发表包**。
- 其后若有其它主表，继续顺延（本包默认到 Table 4）。

## 附表（标题带 train/val，编号连续）

示例顺序（按实际存在文件顺延，禁止同名）：

1. Baseline before/after imputation **(training set)**  
2. Baseline before/after imputation **(validation set)**  
3. Normality  
4. Baseline by training and validation sets  
5. Univariate  
6. VIF screen  
7. Hyperparameters  
8. Log-Loss  
9. DeLong **(training set)**  
10. DeLong **(validation set)**  
11. NRI and IDI **(training set)**  
12. NRI and IDI **(validation set)**  

## 引擎硬修

- `force_export=FALSE` + `gate_enable=TRUE`（预测包）；finalize 删非胜出分位表。
- `pub_caption_strip_parentheses` / shorten **保留** training/validation set 标签。
- 栅格化：`python3` → fallback `python` / `MEDICAL_BLOCKS_PYTHON`。
- code bundle：按唯一源文件路径计数。

## 本课题验收

`08_术中低体温症` / `【success】Preop_Cr`：Fig1–5 连续；无 Fig3 空洞；无 tertile/binary 主表；S 表无同名对；栅格化与 code 包告警消除或可解释。
