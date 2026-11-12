# II型糖尿病 × MIMIC-IV / eICU-CRD / NWICU(NB002 模块2,2026-11-06)

- 定义母本:《II型糖尿病-MIMIC、eICU、NWICU.pdf》= PMID 42898695(Metabol Open 2026)+补充 docx TABLE0;逐字定义与 PI 台账=`冻结定义.md`。
- 判定单位=患者(横断面,一人一行);主口径=原文各库定义,eICU 另出 DN_strict(Type II∪250.x0/x2∪E11)。
- 每库四件套:纳排.xlsx(18 列)/纳排.md(提取理由)/样本 CSV(原始列+组分标志+DN,UTF-8 BOM,衍生列可重算)/样本_数据说明.md(逐列八字段+三节),另有 提取图.png(流程/k分布/组分命中)与 work/(提取+审计脚本、stdout 快照、audit_result)。

| 库 | 池(成人 ICU) | DN=1 | 主口径要点 |
|---|---|---|---|
| MIMIC-IV v3.1 | 65,366 | **17,685**(27.05%) | ICD-9 250x0/x2 ∪ ICD-10 E11*,任一 ICU hadm |
| eICU-CRD v2.0 | 92,171 | **11,764**(可判 88,624 内 13.27%;NA 3,547 留空) | 文本路剔 Type I/insulin ∪ 码路 250.x/E11(**原文宽松,码路含 1 型**;要确认 2 型用 DN_strict=2,963(并集)) |
| NWICU v0.1.0 | 22,809 | **2,214**(9.71%) | 库仅 ICD-10→E11 单路;c1 结构性恒 0 |

- 三库 DN=1 ID 集经独立写法审计 md5 逐位一致(work/audit_result.txt)。减法链全部闭合(差=0)。
- 自检轮二(11-06)更正与登记:eICU 年龄顶码 `> 89` 按成人计(首版误剔 3,681 人,已重跑);PI-6 该条款,PI-7 原文未要求 ICU stay(MIMIC 全院读法 44,005/NWICU 3,336 并列实测,eICU 本即 ICU),PI-8 外周糖尿病串不入正向集(110 stay 判 0),insulin-dependent 条款空转,详见各库 ② 与冻结件 PI 台账。
- 真源:Win G:\FTP\mimic-iv-3.1 / G:\DB\eICU / 29:/mnt/sda/NWICU;全程只读。**PhysioNet Credentialed 1.5.0 数据衍生件禁外传;交付≠发送。**
