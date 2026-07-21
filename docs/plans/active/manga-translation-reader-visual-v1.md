# 漫画翻译视觉 Reader V1

- **status**: active
- **created**: 2026-07-21
- **product authority**: [漫画翻译设计与演进指南](../../manga-translation-design.md)
- **reset audit**: [漫画翻译产品重置](../completed/manga-translation-product-reset.md)
- **research**: [漫画翻译工作流调研](../../research/manga-translation-workflows.md)

## 结果与边界

当前目标是低操作成本的 Reader 阅读翻译。用户显式翻译当前页后，Reader 显示一张原文不再干扰、译文
位于对应区域的视觉译制页；缩放、平移、单双页、切页和返回缓存继续工作。文字列表、结构化文档、模型
响应、编译成功和测试数量都不是产品结果。

V1 不建设专业漫画制作台，不承诺印刷级修图、所有拟声词/艺术字完美处理、PSD/CBZ 导出或整章人工
工作流。后续制作分支复用本计划的数据和渲染边界，但有独立入口与验收。

## 选定的首条完整路线

```text
Reader 原图
  -> 制图 sidecar：检测/OCR，返回区域原文与可回送的渲染模板
  -> NextE：规范化 ComicPageDocument，装配前页/摘要/术语
  -> 已选 API 或 Codex provider：按 blockId 返回上下文译文
  -> 制图 sidecar：导入译文，消字/修复/排版并返回结果图片
  -> NextE：校验并缓存非破坏性衍生页
  -> Reader：显示视觉译制页
```

首个 sidecar profile 兼容 `manga-translator-ui` 当前公开的“导出原文”和“导入译文并渲染”Web API。
NextE 只做窄协议互操作，不复制其 GPL 实现或模型权重。sidecar 是初始外部质量路线，不是永久绑定；
未来本地检测/渲染或其他服务实现同一内部接口即可替换。

整图出图是第二条完整入口，不被本计划废弃。任何能接收原页与上下文并直接返回译制图片的 provider
可以实现 `ComicWholePageRenderBackend`，跳过 sidecar 检测/OCR/import，但仍要经过统一视觉产物校验、
render identity、缓存、原图回退和 Reader 发布。当前 API/Codex analyzer 只返回结构化文本，尚不能冒充
该能力；以后若对应端点/模型真实支持图片输出，可以在不改变 Reader 结果协议的情况下接入。

整页多模态仍可提供图像语境、转录对照或上下文译文，但当前 `geometry=false` 的 analyzer 不能独立发布
视觉页。sidecar 不可达或输出不合格时，Reader 保留原图并显示可重试失败，不显示文字面板代替结果。

## 稳定接口与身份

实现前后都保持三个独立边界：

- `ComicRegionRenderBackend`：检测/OCR 与后续 source treatment/render；拥有 backend profile 和短期适配器模板；
- `ComicWholePageRenderBackend`：可选的整图出图能力；直接返回衍生图片和 provider identity，不伪造逐框
  geometry；
- `ComicTextTranslator`：接收规范 block、整页图像和画廊上下文，按 blockId 返回译文；复用 API/Codex
  传输与认证，但不复用整页 analysis-only 响应结构；
- `ComicRenderedPageRepository`：保存可再生成的视觉衍生页及其完整身份，不把文件路径当内容身份。

render identity 至少包含：稳定画廊/页身份、原图 SHA-256、region/backend profile 与 revision、OCR/document
revision、translation provider/model/prompt/context/glossary revision、source-treatment profile、layout profile、
render backend/profile/revision、目标语言。任一可见输入变化都必须使下游衍生页过期；只改译文不得重跑
检测/OCR，只改布局不得重新调用翻译模型。

`ComicRenderedPage` 至少记录 project/page、source image hash、artifact hash、MIME、宽高、render identity、
创建/访问时间和状态。原图、sidecar 模板、生成文档和衍生图片都属于可再生成数据，默认不进入备份/同步；
未来人工译文、locked 术语和用户备注必须另行定义用户数据所有权。

## 设置与安全

漫画翻译仍是设置首页三个独立翻译入口之一。其页面内保持两个同级能力组：已有“翻译模型”和新增
“制图服务”；不在总翻译入口下继续嵌套，也不把 sidecar 伪装成第三种 LLM provider。制图服务只包含
地址、可选认证和连接状态；高级 detector/OCR/render 参数不在 V1 堆成 Reader 设置按钮。

sidecar 凭据与 API Key/Codex token 分开保存、分开脱敏、分开备份审计。远端图片上传只能由用户显式
翻译动作触发；Reader 预取和页面出现不得调用。协议适配器必须限制请求图片、ZIP/JSON、条目数量、文本、
模板和结果图片大小，拒绝路径穿越、压缩炸弹、异常 MIME/尺寸及不匹配页面身份。HTTP 仅用于用户明确
配置的本地/私网 sidecar，并持续提示明文传输；公网地址要求 HTTPS。

## 实施阶段

### A. 协议与领域契约

- [ ] 固定 upstream revision/profile，并保存不含漫画隐私的最小 export/import fixture；
- [ ] 定义 region、adapter template、translation batch、render profile 和 rendered artifact 模型；
- [ ] 同时定义 `ComicWholePageRenderBackend` 能力与统一产物校验接口，首个提交不要求真实 provider 实现；
- [ ] 明确各 revision、cache key、stale 传播、失败保留和清理语义；
- [ ] 用 fake backend 证明无 geometry、缺 block、重复 block、越界区域和错误图片不能进入 render-ready。

### B. Sidecar 适配器

- [ ] 实现 bounded multipart export 请求与 ZIP/JSON 解析，规范化区域、顺序、原文和 backend template；
- [ ] 实现 bounded import/render 请求，校验返回图片签名、尺寸、内容 hash 和页身份；
- [ ] sidecar 版本/能力不兼容时本地失败，不让部分结果覆盖最后成功检查点；
- [ ] 设置页仅增加同级“制图服务”配置与连接检查，不改变三个翻译入口层级。

### C. 上下文文本翻译

- [ ] 从现有 Responses/Codex 传输抽出 `ComicTextTranslator`，输出必须按 blockId 完整对齐；
- [ ] 提供当前页图像、区域原文、最近前页、滚动摘要、术语与风格约束，并保持既有预算/脱敏边界；
- [ ] 缺块、重复块、未知块、空译文或身份不匹配时拒绝候选；
- [ ] 缓存 identity 使用模型实际可见的受限上下文，不因未发送内容制造错误 miss。

### D. 视觉编排与缓存

- [ ] 将现有 orchestrator 收窄为分析/翻译检查点，再组合 region -> translation -> render stages；
- [ ] 建立有界衍生页缓存；进程重启可命中，清理不会被旧飞行请求回填；
- [ ] 失败保留原图和最后成功衍生页，过期结果只写回创建它的 page identity；
- [ ] 任何 analysis-only 文档都不能返回 Reader-ready 状态。
- [ ] 分阶段 sidecar 与整图出图 backend 汇合到同一 `ComicRenderedPage` 发布边界，Reader 不感知路线差异；

### E. Reader 替换

- [ ] 保留现有显式动作、本地文件输入和 route/page/file/UI epoch fences；
- [ ] 删除 `ComicTranslationSheet` 作为主结果，生成中/失败/待复核改为页面状态；
- [ ] Reader 在同一页原图与衍生页间切换，衍生页走现有图片加载、缩放、平移和切页路径；
- [ ] 原文/译文检查仅作为翻译页的次级入口，未实现时可以暂不提供，不能阻塞视觉结果；
- [ ] 快速切页、单双页、长图、失败重试、返回缓存均不串页、不重复调用 provider。

### F. 验收与关闭

- [ ] fake backend、fixture、parser、identity、cache、failure 和 security tests 通过；
- [ ] signed app、`entry@ohosTest`、持久化/secret/backup/i18n/V2 门禁通过；
- [ ] 在用户指定设备上用合法样页完成一次受控 sidecar + 已选 provider 真实链路；
- [ ] 提供同页原图与视觉译制页截图，证明原文不与译文竞争；
- [ ] 证明缩放/平移/切页正常，返回同页命中衍生页缓存且不调用 sidecar/provider；
- [ ] 失败时原图保持可读，不出现文字列表替代品。

只有 F 全部满足才允许称为“漫画翻译视觉 Reader V1 完成”。A–D 单独完成只能称为基础设施阶段。

## 第一阶段提交边界

第一个代码提交只做 A：领域模型、身份/失效规则、fake backend 和 fixture 测试。它不改 Reader UI、不增加
设置项、不调用模型、不上传图片、不操作设备。协议契约通过后再进入 B，避免再次让 UI 领先于真实产物。
