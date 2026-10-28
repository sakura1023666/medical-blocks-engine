# 修改记录_changelog(Aiya-NB004-midterm-report)

## 2026-10-19（C06 目录跨页）

- 血脂异常预后中期目录溢到第 2 页，C06 只读含“目录”的第一页，把后半章判成缺页码，成品被改名为 REJECTED。
- `run_checklist` 从目录页起连续收集，直到出现第一章正文（标题且含“注释”或页面较长）再停。

## 2026-10-12（WSL 打印：图也走盘符）

- 第一次 build 文本能出、C04 应嵌 8 / 实嵌 1：PNG 落在 `/tmp`，`<img src="file:///tmp/...">` 与 `file:///mnt/g/...` 都进不了 Windows Chrome。
- 打印走 `.exe` 时，临时目录改到项目下 `_report_build_tmp`（盘符路径），图片 URI 与 HTML 一样经 `wslpath -w`。重 build 后 C04 通过。

## 2026-10-12（WSL 打印：Windows Chrome）

- 本机无 `/usr/bin/google-chrome`。`find_browser` 在 Linux 候选之后增加 `/mnt/c/Program Files/.../chrome.exe` 与 Edge。`print_pdf` 对 `.exe` 用 `wslpath -w` 把 HTML/PDF 换成盘符（`/mnt/e` → `E:\`），不传 `--no-sandbox`。探针：`_chrome_probe.pdf` 已写出后删除。

## 2026-10-12（Medical Blocks 仓库副本 + Phase 7 挂点）

- 自 `192.168.68.34:/home/ps/.claude/skills/Aiya-NB004-midterm-report/` 拉回 `.cursor/skills/Aiya-NB004-midterm-report/`（约 110KB；未带 `__pycache__` 与 `build_report.py.bak*`）。去 AI 味依赖一并从 34 拉回 `.cursor/skills/step05-Aiya-humanizer-zh/`。
- SKILL.md 增「Medical Blocks 挂点」：Phase 6 PASS/WARN 且 Nature P0 已清后，对刚审完的 success 发表根直接 inspect→content.json→step05→build，该目录视为已确认，不再二次询问。单独点名出中期仍走第 0 步确认。引擎 `build_report.py` 未改。

## 2026-10-10(d)(用户指令:纳排图入中期,推翻旧豁免;与 step06 同批同改)
- **Figure 1 纳排流程图即日起纳入中期报告并配描述**(旧"默认不纳入+待终稿补充"作废):主图嵌入背景/数据来源章或基线章之首,中文 caption+annotation 逐层描述,人数按 dump 实数闭合对账;排除任何图(含流程图)须用户当次明确指示。
- 改动:SKILL.md 三处(豁口段/JSON 示例空数组/字段说明行);engine/build_report.py 仅注释行(零逻辑,不设备份);与 step06 改后仍字节一致。

## 2026-10-10(c)(用户指令,398 起因:报告缺省文件名改为 `<客户老师>中期分析结果.pdf`)

- **引擎**:cmd_build 缺省名逻辑重写——客户非空=`<客户老师>中期分析结果.pdf`(客户按项目信息照录+自动补"老师");客户空=回退 `<暴露指标>_<结局>_<分析方法>_中期分析结果.pdf`(旧格式去客户括号段)。备份 build_report.py.bak-naming-20261010。
- **SKILL.md** 四处同步:第 4 步缺省输出段(并声明 10-09"报告名英文化+中文客户名先问"旧口径作废)、「封面与命名」输出文件名格式、「字段缺失的处理」、红线⑦。
- **两份同步**:本次用户明确要求 step06 与 NB004 两份同改(打破 10-10(b) "源不动只改副本"惯例),引擎与 SKILL.md 改动后仍字节一致。
- **回归**:398 项目不带 --out build → 缺省名自动生成 `樊鹏飞老师中期分析结果.pdf`,15 页,出厂闸门 10 项检查通过。
- 09-20 照录纪律延续(客户名不转拼音);`--out` 仅用于用户当次指定文件名或客户与拼接字段均为空的残缺场景。


## 2026-10-10(b)(自 step06 同步:标题字体修复补丁 + 结果检查清单/出厂闸门 C01–C10)

- **同步内容**(引擎 build_report.py 整文件覆盖,与 step06 字节一致;SKILL.md 同步新章节后身份行重写为本副本):①**Liberation Sans 字体补丁**(7 处标题类 CSS 前插,修 Chrome Type3 合成粗体子集损坏致标题编号 ⊠ 乱码——复制时点早于该补丁,本次带上);②**结果检查清单/出厂闸门 C01–C10**(build 自动机检,FAIL 先自动重打一次、仍 FAIL 改名 `.REJECTED.pdf` 非零退出;`--verify` 独立复检入口;明细与新增纪律见 step06 同日条目及 SKILL.md「结果检查清单」章节)。
- **smoke**:398 项目 build --out /tmp 复验:15 页、出厂闸门 10 项检查通过,报告已生成。
- 引擎 .bak/.orig 旧备份未动;后续引擎迭代仍以本副本为准(step06 为源存档)。

## 2026-10-10 复制为 Aiya-NB004-midterm-report(NB 系列岗位副本)
- 本目录=`~/.claude/skills/Aiya-NB004-midterm-report/`,自 `~/.claude/skills/step06-Aiya-midterm-report-pdf/` 复制(排除 `__pycache__`/`._*`);源不动,后续迭代只改本副本。
- SKILL.md 换身份:frontmatter `name` → `Aiya-NB004-midterm-report`、标题 (step06)→(NB004)、`<本skill目录>` 示例路径改指本目录;引擎 `engine/build_report.py`(含 .bak/.orig)与源逐字节一致。

## 2026-09-20(Alice 样式混合章宽表被挤竖版:章内按节切方向块,349 补充册起因)

- **缺陷**:`build_chapter_blocks` 整章一个 (orientation, html) 块,章方向由**最后一张表**的列数决定;混合章(窄表在宽表之后)中 >8 列宽表被渲染进竖版页,15 列表逐字折行不可读(349 补充册表 8/表 12,14:41 版即存在、当时验收误记"自动横版")。
- **修复**:章内按节切块——节的表 ncols>8 → 该节独立成横版块,方向变化处 flush 当前块;章标题/intro/formula 并入首节朝向块;图与 index_items 节不改朝向(与旧行为一致)。探针标记/[chN]编号/两遍渲染逻辑零改动。
- **回归**:349 主报告(content.json)重出至 /tmp 比对——页数 15、横版页位(第 8 页)、逐页文本与在版 PDF 一致(仅分析日期自动戳当日),旧行为在"章内方向单一"项目零影响。349 补充册重出 25 页,表 8/12 横版全列可读,表 11(5 列)回归竖版。
- **附带口径确认**:`exclude_figures` 可由用户当次指示将**全部**图(含 S 系列)登记,实现"纯表分册"(349 补充册 6 图全排除,图仅在主报告嵌入)。

## 2026-09-17(指标公式必含:新增 `formula` 字段,349 项目起因)

- **背景**:用户指出 349 AIP-WHtR 中期 PDF 无暴露指标计算公式——原 SKILL.md 从未要求公式入报告,方法章只有统计方法叙述,公式仅在背景章以文字带过。
- **engine/build_report.py**:新增 chapter/section 级 `formula` 字段(str 或 str 数组),居中、无首行缩进、Times/SimSun 12pt 渲染于所属 intro 之后、sections/表格之前;`LANDSCAPE_CSS` 由 CSS 派生自动继承。新增 `check_formula` 校验(非空字符串或字符串数组,否则退出)与 `formula_paras` 渲染函数。排版/打印/页码逻辑零改动。
- **SKILL.md**:①项目信息字段表新增 `指标计算公式` 说明(权威出处,缺字段时问用户、禁编造);②第 2 步新增「指标公式必含规则」(衍生/复合指标必须有显式公式,行内文字描述不算;log10→log₁₀、*→× 属排版规范化;纯测量值类暴露豁免);③字段说明加 `formula`;④第 3 步改写禁区:`formula` 不动、不计入数字 token 比对基线;⑤第 5 步验证加「指标公式」项(居中行+Unicode 符号不丢字);⑥红线新增⑥;⑦frontmatter description 补一句。
- (349 项目首例回填重出:`数据与方法` 章 intro 末句引导 + `formula` 一条中文变量名计算式)

## 2026-09-09(打印浏览器换 chrome-headless-shell)

- aiya-ai 实测:playwright 完整版 chrome `--headless=new` 打印后进程不退出(subprocess 120s 超时,PDF 已写出但引擎崩溃退出)。BROWSER_CANDIDATES Linux 段新增 `~/.cache/ms-playwright/chromium_headless_shell-*/chrome-headless-shell-linux*/chrome-headless-shell` 并置于完整版之前;`print_pdf` 对 headless-shell 不传 `--headless*` 参数(其本身即 headless,传参反致异常),`--no-sandbox` 保留。326 项目实测 3 个打印作业顺利完成。(两文件:build_report.py 浏览器发现+print_pdf;渲染/排版逻辑零改动)

## 2026-09-09(封面副标题口径 v2:取消的是"标题副题"行,用户澄清)

- 用户澄清:要取消的副标题=封面主标题第二行(标题副题),且"中期分析结果"并入数据来源行。新增约定:**`标题副题` 填 无/-/—** → 不渲染第二行,客户名缀主标题末行("…关联性分析–lydia老师"),`类型` 值追加到数据来源行尾("基于MIMIC-IV v3.1公共数据库–中期分析结果"),独立副标题行不渲染。v1 的 `类型`=无 只删独立行逻辑保留(两约定独立生效)。SKILL.md 字段说明同步。(326 项目 `HRR_AKI_lydia老师_中期分析结果.pdf` 16 页复验:表1-3/图1-5、声明唯一、探针零)

## 2026-09-09(封面副标题可取消)

- 新约定:`项目信息-中期.md` 的 `类型` 填 **无 / - / —** 时封面不渲染副标题行(标题副题第二行已含"中期分析结果"字样避免重复);缺省行为不变。326 项目首例(用户要求"第一页取消副标题")。另:客户名补"老师"由引擎既有逻辑负责,交付文件名如用 --out 自定义须自行带上(326 例 `HRR_AKI_lydia老师_中期分析结果.pdf`)。

## 2026-09-09(项目信息文件名·双名均可,用户改口径)

- 口径更新:引擎行为保持双名兼容(**优先 `项目信息-中期.md`,回退 `项目信息.md`,两者任一即可**),SKILL.md 约定表/字段说明/第 0 步缺件判断同步改为"两名均可"。(此前同日条目写的"改为读取新名"以本条为准)

## 2026-09-09(项目信息文件名)

- 项目信息文件名 **`项目信息.md` → `项目信息-中期.md`**(用户指示,326 SLE 项目起因):`parse_project_md` 优先读 `项目信息-中期.md`,不存在时回退 `项目信息.md`(旧项目兼容);SKILL.md 全文引用、inspect dump 标题行、`--project` help、封面注释同步改名。(仅读文件名一处逻辑改动,解析/渲染零改动)

## 2026-09-09

- engine/build_report.py `bottom_end_note` 修复结尾声明贴底失效:本机 Chrome 打印输出 Type3 子集字体,声明行逐字成 span,"分析日期"不再完整出现在任何单 span 内 → `bottom=0.0` 直接 return、声明紧跟表格不贴底。改为**按行拼接 span 文本后匹配**("分析日期" in joined line text),命中取该行 span 底部最大值;其余逻辑(62.4pt 底边距、7pt 余量、页数+1 二分回退)不动。(yyq/man eGFR×术中低体温中期报告 18 页版实测:修复前声明位于缩略词表正下方,修复后贴末页页底;仅此一处改动)

## 2026-09-08

- SKILL.md 执行流程插入强制「第 3 步:去 AI 味」(原 3→4、4→5 顺延):build 前调用 step05-Aiya-humanizer-zh 对 content.json 叙述字段(chapters[].intro / sections[].intro / sections[].annotation 等)去 AI 味,改写写回 content.json 本身;禁区=数值零改动(数值区间 en-dash 属数字不动)/表图N引用不变/JSON 结构与文件名引用不变/不增删信息;机械校验=备份 content.json.bak-prehumanize.json + 改前后数字 token 序列比对 + 键集合与引用列表比对;并向项目目录 修改记录_changelog.md 追加条目。第 5 步验证新增「去 AI 味复核」(pdftotext AI 痕迹标志词零残留)。frontmatter description 与开头思路句同步提及。(用户要求:去 AI 味之后再生成 PDF;377 项目手工先例固化;step05 SKILL.md 与 engine/build_report.py 均未改动)
