# AKI SOSM+WPR 原文复刻进度

- Task 1: complete（prognosis dev-ext 与 Survivor/Non-survivor 标签；独立审查通过）
- Task 2: complete（SOFA 数值分层、患者级隔离 ctx、staging/checkpoint 守卫；独立审查通过）
- Task 3: complete（联合 tertile 冻结、三列 Cox、grouped RCS、PH/landmark 锁定；权威 checkpoint provenance 经真实文件 bootstrap 与仿冒攻击测试；独立审查通过）
- Task 4: complete（Figure 2–6 + Table 2/S4–S10；控制器接手子代理中断，修复 6 个真实 bug，真实数据冒烟 SMOKE_OK，视觉抽查面板对齐原文）
- Task 5: complete（分层五模型冻结资产包 + eICU 同层纯预测外验；独立审查发现 C1 SOFA入模/C2 restrict_to_train泄漏/I1 层归属/I2 fail-closed/I3 笔误，全部 TDD 关闭；真实冒烟 sofa_le10 层 24 特征无 SOFA、三路往返一致、AUC 0.806/0.806/0.770）
- Task 6: complete（分层/overall Boruta+SHAP+个体解释，Figure 7/8/S2–S5 入口；冻结模型三重身份核验（文件md5==manifest、内存digest==资产digest、返回checksum），控制器补防重训负向测试锁死 digest 守卫；两测试绿，真实 logistic/sofa_le10 冒烟 SMOKE_OK，Fig8 AUC 与 Task5 一致）
- Task 7: complete（原文 profile 34 角色编号连续 Fig1-8/S1-8/Table1-2/S1-16；Figure 1 真实双库纳排（按目录判库，26055→18394 / 15270→10558，逐步排除账本）；Table 1 Survivor/Non-survivor 零 AKI 残留；S1 证据不足标注；MANIFEST 诚实状态 ready17/smoke3/legacy9/pending5；测试绿）
- Task 8: complete（CLI build_aki_sosm_wpr_replication.R；全量三层×五模型 ready_full、eICU no_refit 冻结外验、S11 525行；Fig1/7/8/S1-S8 全出；四格式16/16/16/16；18表；原子替换 publication_literature_final；OBSOLETE.md 指向新稿；决策树更新 SOFA分层+28天适配）
- Task 9: complete（独立验收 audit_task9_final.R 25/25 PASS：编号连续、四格式parity、xlsx零损坏、禁90天、禁AKI/No-AKI误标、S9基线血糖口径、MANIFEST溯源+verification证据、trained_in=MIMIC；视觉复核发现 Fig8 仅单模型→修正为每格五模型ROC叠加+SHAP最优，重出后验收仍全绿）
- Task 6: complete（冻结 SHAP/Boruta/个体解释面板 Figure 7/8/S2–S5 组装层；eICU SHAP 解释模型哈希==MIMIC manifest 冻结哈希、bake 与 Task5 预测同口径、特征回映全覆盖、paired cases 本库本层缺类硬失败；fixture 面板数断言全绿 + 真实 logistic/sofa_le10 冒烟 SMOKE_OK，Fig8 AUC 与 Task5 一致）
# SDD Progress Ledger

Plan: docs/superpowers/plans/2026-08-26-pub-figure-onplot-annotations.md
Workspace: in-place (no git repo; commits skipped)

Task 1: complete (no-git, review Approved; Minor: forest formatC vs signif; brief Step3 should sync formatC)
Task 2: complete (review Approved; Minor: KM/Forest empty-state tests optional)
Task 3: complete (review Approved; Minor: fixture depth, db_dirs hardcode)
Task 4: complete (review Approved)
Task 5: complete (review Approved)
Task 6: complete (review Approved; Minor: nhanes→eICU pre-existing)
Task 7: complete (review Approved)
Task 8: complete (rule Approved by controller spot-check)
Task 9: tests OK; awaiting final review
Task 9: complete (final review Ready after Important #1/#2 fixes; tests OK)
Task 8: complete (rule Approved)
Task 9: complete (tests OK; Important #1/#2 fixed; final re-review Ready)
Feature: READY (no-git workspace; commits skipped)
Task 3: complete (review Approved)
Task 4: complete (spot-check kind)
Task 5: complete
Task 6: complete

Task 7: complete
Task 8: complete (DONE_WITH_CONCERNS: ward sparse covars dropped)
Task final-fix: image_information rewritten; Ready

# SDD Progress Ledger — pub-digits est2/cutoff3
Plan: docs/superpowers/plans/2026-09-22-pub-digits-est2-cutoff3.md
Workspace: /mnt/e/01block/01Block-new-Final
Constraint: NO git commit unless user asks
Started: 2026-09-22

Task 1: complete (no-commit, review Approved; Minors: cwd/repo-root, RED override path not executed yet)
Task 2: complete (no-commit, review Approved; L53 1.234 formatC fix ok; Minor/track: test_result_review_guards L14–15 vs p=3 pre-existing)
Task 3: complete (no-commit, review Approved)
Task 4: complete (no-commit, review Approved; Minor: .fc default d=3 out of scope)
Task 5: complete (spec coverage self-check; greps clean; test_pub_digits_defaults PASS; no commit)
Task 5: complete (no-commit, controller Approved — verification report complete, greps clean, defaults test PASS)
Final review: Ready to ship (no Critical/Important; Minors tracked: guards P4digit, test cwd, .fc d=3)
Feature: READY (no-commit; user may commit when ready)
Task 1: complete (no-commit, review Approved; report discordance table corrected by controller)
Task 2: complete (no-commit, review Approved; Minor: note bone markers vs skill tension for Methods)
Task 3: complete (no-commit, review Approved; Minors for final: kappa golden assert, strata AAC type, AUC direction test)
Task 4: complete (no-commit, review Approved; Important deferred: 3cat kappa, BA panel config, catalog=T7, four-dir=T10)
Task 5: complete (no-commit, review Approved; Important: fix .osteo75_auc_continuous default direction in follow-up/T7)
Task 5: complete (no-commit, review Approved; Important: fix .osteo75_auc_continuous default direction in follow-up/T7)
Task 6: complete (no-commit, review Approved)
Task 7: complete (no-commit, review Approved; AUC direction fixed)
Task 8: complete (no-commit, review Approved; Minor: dry-run via source not CLI)
Task 8: complete (no-commit, review Approved; Minor: dry-run via source not CLI)
Task 8: complete (no-commit, review Approved; Minor: dry-run via source not CLI)
Task 8: complete (no-commit, review Approved; Minor: dry-run via source not CLI)
Task 9: complete (no-commit, review Approved; Minor: plain openxlsx not export_sci_table)
Task 10: BLOCKED pending user authorization (开跑)
Task 10: AUTHORIZED by user 开跑 at 2026-09-22
Task 10: complete (DONE_WITH_CONCERNS cleared: Fig2 MV OR forest fixed by redraw script; review deferred spot-check)

# SDD Progress Ledger — PE alteplase IPW dual-db
Plan: docs/superpowers/plans/2026-10-09-pe-alteplase-ipw-dual-db.md
Spec: docs/superpowers/specs/2026-10-09-pe-alteplase-ipw-dual-db-design.md
Workspace: /mnt/e/01block/01Block-new-Final (no git repo; commits skipped unless user asks)
Started: 2026-10-09
Task 1: complete (no-git, review Approved; Important tracked: critic_model metadata vs deepseek provenance; Minors: chunk id naming, no Q1-3/6-7)
Task 2: DONE_WITH_CONCERNS — awaiting user confirm on MIMIC iv=alteplase union + foundation before Task 3
Task 2: complete (user confirmed foundation; exposure MAIN=A rx∪iv; sensitivity optional rx-only; controller Approved after concerns cleared)
User gate 2026-10-09: 地基确认; 暴露选A(代理判断合理); 图/表对齐原文献+卒中一个不能少
Task 3: complete (no-git, review Approved; awaiting user confirm decision_tree_ipw_pe_alteplase.md §0 before Task 4)
Exposure MAIN locked to prescription-only (425/70); decision tree §0 checked; starting Task 4
Task 4: complete (no-git, review Approved; exposure MAIN=rx-only)
