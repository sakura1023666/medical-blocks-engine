# 质控报告模板

复制到 `reports/pub_qc_YYYY-MM-DD.md`，填实后删除本说明行。

```markdown
# 发表质控报告

- 项目根：`<path>`
- 审阅结论：**PASS** | **WARN** | **FAIL**
- 是否建议交稿：是 / 否（附条件：…）
- 审阅范围：仅 【success】（`all_success` n=… | index=`【success】…`）；已跳过 【failed】 n=…
- Nature P0：已清零 / 仍有 n 条 / 用户接受残留
- Methods H1（轨道 B）：已定稿 / 待作者 → 见 `H1_Methods_P0_author_adjudication.md`
- routine：`trajectory` / `incidence` / `tst` / …
- 日期：YYYY-MM-DD
- Agent：pub-qc-after-project + nature-statistics + nature-figure

## 摘要
- Layer A 结构：x PASS / y FAIL
- Layer B 数字：x 对照通过 / y 冲突 / z 未收获
- Layer C 逻辑：P0=n，P1=n，P2=n
- Layer D Nature：statistics P0=n；figure FAIL=n（须修完才可 PASS）

## Layer A — 结构
| 项 | 结果 | 证据路径 |
|----|------|----------|
| 四目录 | PASS/FAIL | … |

## Layer B — 交叉数字
| 对照 | 左值 | 右值 | 结果 | 证据 |
|------|------|------|------|------|
| Fig1 vs attrition | … | … | PASS/FAIL/未收获 | … |

## Layer C — 逻辑
| ID | 级别 | 问题 | 建议 |
|----|------|------|------|
| C1 | P0/P1/P2 | … | … |

## 下一步（给用户）
1. …
2. …

## 附录
- inventory 脚本输出（若有）
- 未打开的文件清单（明确未审，避免假装全看过）
```

### issues.csv 列（可选）

```text
layer,severity,item,left_source,left_value,right_source,right_value,note,evidence_path
```
