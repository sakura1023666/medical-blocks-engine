# 联合轨迹发病 指标池筛选证据链 — <疾病> × <数据库>

> 规则：`.cursor/rules/trajectory_joint_index_screening.mdc`
> 写 `config$joint_trajectory$index_pairs` **之前**必须填完本表并经用户确认。

## 0. 队列与波次

- 数据库 / 队列：
- 轨迹波次（waves）：
- 基线波成分缺失剔除：见 Fig1 诚实分项（`Missing <components> (n = …)`）

## 1. Gate 0 — 疾病成分硬排除

| disease_vars（结局/诊断/疾病标志物） | 命中整指标（剔除） |
|---|---|
| | |

## 2. Gate 1 — 逐波可算率（`screen_trajectory_joint_index_pool.R` 输出）

| index | 成分 | w<k> 覆盖 | 基线缺失 n | 建议 |
|---|---|---|---|---|
| | | | | |

## 3. Gate 2 — PubMed 检索证据（近 15 年）

| 对 (A,B) | 疾病×A 命中 | 疾病×B 命中 | 疾病×A+B 联合 | 分级（预设 / Exploratory） | PMIDs |
|---|---|---|---|---|---|
| | | | | | |

检索式记录：

```
("disease"[title/abstract]) AND ("A"[title/abstract]) AND (trajectory OR "growth curve" OR latent class)
("disease") AND ("A") AND ("B") AND (joint OR dual)
```

## 4. 搜寻不到时的处理（用户授权口径）

- [ ] 标 **Exploratory**：仍跑，Methods/图题/中期写明；不作中心结论
- [ ] Limitations 写「无外部先例，假设生成性」
- [ ] 禁止编造引用
- [ ] Exploratory 对数 >2 → 需用户再次确认

## 5. 最终锁定 index_pairs

```r
index_pairs = list(
  A_B = c("A", "B")   # 预设/Exploratory 注明
)
```

- [ ] 用户已在对话确认名单：（日期/原话）
- [ ] 体系命名贯穿表/图/Methods
- [ ] 多重比较策略（体系数 >2 时）：
