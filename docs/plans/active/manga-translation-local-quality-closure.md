# 端侧漫画翻译质量收口

状态：进行中<br>
最近复核：2026-07-27<br>
范围：只收口 Reader 的端侧视觉翻译质量证据与下一项可验证改进；不把 Torii、其他云端 provider、设置页或制作/导出工作流变成当前任务。
设备选择：用户指定 `237`；如需真实翻译或 UI 验证，只能先实时解析该短名，再对唯一 Connected target 获取 lease。

## 唯一当前目标

确定当前端侧 `YSGYolo + Core Vision + PP-OCRv5 + CTD + AOT` 在真实漫画页上**可安全翻译的边界**，并只在
固定样本证明一个明确根因后实现一个候选修复。用户仍可选择 Torii 整图路线；它是并行功能和质量对照，
不替代、不阻塞、也不扩张本计划。

本计划结束前，不把“已有模型下载、某一页可读、单元测试通过”描述为端侧漫画翻译完成。

## 当前完成度（防止无限扩张）

| 项目 | 状态 | 已有证据 / 下一步边界 |
|---|---|---|
| 端侧链路可运行 | 已完成 | P1、P11 都已完成真实 provider 请求后导入同一冻结响应，本地分析与成图可重复运行。 |
| 性能可观测 | 已完成 | P11：provider 11.942 s；端侧 4.077 s（analysis 2.495 s、render 1.582 s）。这不是整页质量通过。 |
| P11 的单页候选 A/B | 已完成且否决 | 仅容器约束的 candidate 无视觉收益且变慢，已停止该分支。 |
| 真实 evidence 能进入审核集 | 已完成 | P11 录制按图像 identity 归入既有 dev family，并能生成只含该页的 7 区域审核包。 |
| 可量化准确率 / 质量基线 | 未完成 | 34 页样本有观察值但没有完成真值；不能给出检测率、译文正确率、视觉通过率。 |
| 下一项算法改动 | 未选择 | 只允许在 P11 真值审核后，从 OCR/geometry、translation、mask/inpaint、typography 中选一个可证伪根因；当前不继续写启发式。 |

因此本轮的工作不是继续堆模型、样本或 provider，而是把已有一次真实 P11 的失败原因从“截图印象”收敛为
可复查标签；一旦真值完成，最多实施一个候选并在冻结响应上 A/B。该候选若失败，本轮直接结束端侧调优分支，
不进入无止境阈值迭代。

## 已完成的实现与证据

- Reader 已具备端侧完整阶段：本地页文件 → region/OCR → 用户选择的 LLM 翻译 → CTD mask/AOT 修复 →
  排版 PNG → 原图/译图切换、缓存和失败保留原图。阶段实现集中在
  `ComicTranslationRuntimeService` 与 `ComicLocalVisualBackend`。
- 真实页 recording/replay 已可导出 source identity、分析文档、译文、glyph/container mask、layout、最终图和
  分阶段耗时；常规渲染迭代可冻结上游，不应反复调用 LLM。
- 已关闭的局部回归包括：同气泡多列重复绘制、窄竖框 Latin 拆词、跨文本块错误桥接、明显污染拟声词的错误回填、
  缓存/错误分类和 AOT 临时内存归属。
- 设备 237 的真实五页生产回放中，analysis+render 为 4.985–6.127 秒，中位数 5.339 秒；AOT 与 CTD 是主耗时，
  不是 YSGYolo detector。更高文字密度的 recording 也确认 AOT 通常占 render 的 64–75%。

## 2026-07-27 资格实测：真实 trace 已通，但尚不是 Core 基线

- 设备 `237` 上，单页 P1 的 debug bridge 已按“测试模块导出 → 主应用使用当前已选源 → 测试模块导入并本地渲染”
  完成。导出/导入各为 `ComicLocalExternalReplay` 2/2；每次必须通过 `aa test -s timeout 60000`，默认 5 秒
  Hypium timeout 不足以覆盖真实页本地分析，不是产品超时或 provider 失败。
- 该页的唯一 provider 请求耗时 10.866 秒，trace 身份为 `migrated-manga-codex` / `gpt-5.4-mini` /
  `comic-text-responses-v8` / `zh-CN`，7 个翻译块全部返回。它是设备实际配置的事实；在配置重新核对前，不能把这条
  证据写成 Luna 模型基线。
- 同一冻结响应的端侧分析/成图分别为 3.995 / 3.040 秒（总计 7.035 秒）；分析主项是 proposal mask 2.405 秒、
  system OCR 0.829 秒、detector 0.512 秒，渲染主项是 AOT 1.453 秒（6 次）和 layout 1.157 秒。7 个 block
  合并为 6 个 layout，没有跳过组。
- 视觉核验**拒绝将该页作为质量通过结论**：变化集中在下半文字区（32 阈值差异框
  `x=63..1167, y=376..1934`；1200–1599 行带变化 8.75–10.34%），而上半人物/车体保持原图。当前可见问题是
  非容器矩形的空间利用、窄框排版与描边比例，不能误诊为整页或顶部的 inpaint 损坏。三组有已接受的闭合容器，
  另外三组没有；单页尚不能证明任何生产规则。
- P1 属于一次端到端资格探针，**不属于现有 dev-12**。下一条真实请求只能使用既有 dev 中的 P11
  `authorized-color-gallery-a`，复用完全相同的 bridge 和记录字段；不得扩成连续扫页或重复请求 P1。
- dev P11 已完成一条真实基线：provider 11.942 秒，端侧 analysis/render 为 2.495 / 1.582 秒，总计
  4.077 秒；7 个返回 block 中 3 个进入 drawable layout，另 4 个带 `local_source_geometry_not_supported`
  的安全保留（其中一个是 SFX）。三个 layout 均为单 block，故 P11 的失败**不是跨气泡合并**。
- P11 的 `vertical-container-candidate-v1` 在同一冻结响应上只改动唯一 accepted 容器块：可用区从
  `166×524` 改为约 `224×464`，字号从 29 降至 26。它没有改善长译文的分列、空间利用或整体视觉平衡，端侧总计
  反增至 4.329 秒；候选在真实视觉 A/B 中否决，禁止接入 Reader 或继续阈值微调。P11 中显眼的白色气泡是原图
  设计的一部分，不能被误记为 CTD/AOT 留下的白色残块。
- P11 三个实际绘制块的原文/译文长度为 `32→26`、`24→17`、`51→42`，字号为 `30/30/29`，描边均为 `9.5`。
  其中长块虽有接受的容器候选，当前 production 仍按 `166×524` 的原始文字几何排版；它证明竖排目标语言的
  分列与字面可读性需要真值审核，但不能单凭截图把问题归因为 mask、inpaint 或容器召回。
- P11 的真实录制已拉回仅本地忽略的 evidence 目录，并由数据集工具生成单页审核包：它绑定 source、analysis、
  render、provider trace 和时序，保留 7 个 `needs_review` 候选，尚未产生任何伪造真值。此前模板工具错误要求
  一个 family 内每一页都含同一 recording，已修正为只纳入真正匹配该 recording 的页；catalog 以 P11 图像 hash
  归属到既有 `authorized-color-gallery-a` dev family，避免真实 trace 因录制 ID 更新而被误归为 `unassigned`。

## 当前未通过的质量门与根因

| 层 | 当前事实 | 因此不能做的事 |
|---|---|---|
| 容器/geometry | 冻结五页有 28 个最终 layout，但只有 6 个容器候选、5 个高置信；闭合气泡不是普通页的全覆盖信号。 | 不能把容器 mask 直接接管所有 AOT/排版，也不能用 OCR 矩形扩大填色。 |
| 检测与 OCR | 艺术字、描边字、开放背景和复杂拟声词仍会漏检、错录或得到污染 transcript。 | 不能靠 LLM 或字号规则补回没有可靠 geometry 的文字。 |
| 消字/修复 | CTD 常覆盖彩色字核却漏掉白色描边；AOT 对复杂纹理并不等于高质量修复模型。 | 不能把残留白边、平块或纹理破坏当成单纯排版问题。 |
| 排版 | 已修复多项已证实的 block/group 问题，但开放气泡、艺术字和复杂背景没有可安全边界。 | 不能继续增加没有跨页样本支持的 layout heuristic。 |
| 数据与验收 | 5 页 smoke 之外，本地 `reader-acceptance` inventory 已有 34 个唯一真实页、251 次观察：dev 12、holdout 10、train 4、未归类 8；对应 container review 与 ground-truth template 都已生成，但全部仍为 `needs_review`。更关键的是，dev-12 原有的 35 次 observation 全部来自 `deterministic-placeholder` / `container-calibration-v1` / `container-calibration-only`，不是实际翻译；P11 刚补入的一次真实 trace 也仍未标注。 | 不能把校准占位图当翻译结果、宣称总体准确率、训练新模型或以单页截图决定下一项实现。 |

## 本计划的固定顺序

1. **先分离校准与翻译证据。** 不再新找样本。既有 dev-12 只可作为 geometry/container 校准集，不能叫
   翻译 Core-12；35 次现有 observation 均为占位 trace。先在 template 标明文字目标、可改动区域、容器存在性和
   严重缺陷类别，未归类 8 页不得混入。真实图、OCR 与译文只保留本地开发产物，不提交仓库。
2. **标注现有 P11，并冻结真值。** P1 已证明 bridge 可用，P11 已有一次非 placeholder trace，且它的单页审核包
   已可从冻结录制重建；现在只用原图审核 P11 的可翻译区域、应保留区域、长竖排 block 的真实容器与视觉缺陷。
   P11 的 container candidate 已被 A/B 否决，不能以它替代真值；未完成标注前不再发起第二条 dev provider 请求。
3. **建立当前基线。** 只对第 2 步合格的同一批冻结文档与译文跑 production profile，输出
   detection/OCR/geometry/translation/visual/timing 的逐页报告。校准占位图或新鲜、未冻结的 LLM 请求均不能替代它。
4. **只选择一个根因。** 依据报告选择最高影响、可分离的一层（容器召回、艺术字 detection/OCR、mask/inpaint
   或 layout），写明预期改善指标与负向保护后才实现一个候选。一次候选只能改变一层。
5. **Core A/B 后再决定。** 候选必须改善目标类别、不得回退保护类别和性能预算；失败就记录否决原因并停止该
   分支，不调第二轮阈值。只有通过 Core 的候选才进入按画廊隔离的 holdout。

## 收口与停止条件

- **本轮成功**：geometry 真值、一次合格的真实翻译基线和首个候选的 A/B 证据完整，形成“下一项唯一模型/算法改动”或“当前模型
  栈到此无安全改进”的结论；不是要求本轮宣布产品完成。
- **基线前置失败**：若无法取得一条非 placeholder、可复现且不回退的真实翻译 trace，则停止讨论端侧成图质量；
  只保留 geometry/container 诊断，并把翻译源接入或运行失败单列为阻塞事实。
- **立即停止某候选**：需要依赖合成图、跨画廊泄漏、重复付费翻译、扩大 OCR 矩形填色、或无法报告对负向样本
  的影响。
- **端侧路线暂停条件**：没有许可清晰且可在 Core 上改善关键缺口的模型/数据来源时，不再增加启发式；保留
  已有无损回退，等待独立的模型/数据授权决策。

## 非目标

- 不新增云端 provider、不重新研究 Torii 模型/提示词/字体；
- 不改变用户在 Torii 与端侧之间的选择权；
- 不把 Core-12 当作训练集，也不在未明确数据来源/许可前开始训练；
- 不提交真实漫画页、OCR、译文、密钥或录制产物。
