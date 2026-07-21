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

首个 sidecar profile 以 `manga-translator-ui v1.9.9` / commit
`696dc63bd0b4803f96cc3d4f844322cef4910f8e` 为上游基线，并要求 NextE 兼容补丁提供
`/translate/import/json/nexte-load-text-v1`。vanilla v1.9.9 的 import 虽返回 200，却没有真正应用
`load_text` 工作流参数；未暴露专用路由的服务不属于该 profile。不能把未固定的 `main` 或 v2.x 当作
同一 profile：截至 2026-07-21 的静态复核中，其导出响应模型与 `TextBlock.to_dict()` 字段也已失配。
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
revision、translation source profile/revision/model/prompt/context/glossary revision、source-treatment profile、layout profile、
render backend/profile/revision、目标语言。任一可见输入变化都必须使下游衍生页过期；只改译文不得重跑
检测/OCR，只改布局不得重新调用翻译模型。

`ComicRenderedPage` 至少记录 project/page、source image hash、artifact hash、MIME、宽高、render identity、
创建/访问时间和状态。原图、sidecar 模板、生成文档和衍生图片都属于可再生成数据，默认不进入备份/同步；
未来人工译文、locked 术语和用户备注必须另行定义用户数据所有权。

## 设置与安全

漫画翻译仍是设置首页三个独立翻译入口之一。API/Codex 连接、认证、模型目录和用量先迁移到共享
[LLM 源管理计划](llm-source-profiles.md)；漫画页面只选择 `sourceProfileId + modelId`，并保留同级的
“制图服务”。不在总翻译入口下继续嵌套，也不把 sidecar 伪装成第三种 LLM provider。制图服务只包含
地址、账号认证和连接状态；客户端自动登录并刷新内存会话，高级 detector/OCR/render 参数不在 V1 堆成
Reader 设置按钮。

sidecar 凭据与 API Key/Codex token 分开保存、分开脱敏、分开备份审计。远端图片上传只能由用户显式
翻译动作触发；Reader 预取和页面出现不得调用。协议适配器必须限制请求图片、ZIP/JSON、条目数量、文本、
模板和结果图片大小，拒绝路径穿越、压缩炸弹、异常 MIME/尺寸及不匹配页面身份。HTTP 仅用于用户明确
配置的本地/私网 sidecar，并持续提示明文传输；公网地址要求 HTTPS。

## 实施阶段

共享 LLM 源迁移在 B/C 之前完成。视觉领域契约 A 不依赖现有漫画专用设置，可以先独立提交；之后不再
给 `ComicTranslationProviderSettings` 增加字段或继续扩张专用凭据 UI。

### A. 协议与领域契约

- [x] 固定 upstream revision/profile，并保存不含漫画隐私的最小 export/import fixture；
- [x] 定义 region、adapter template、translation batch、render profile 和 rendered artifact 模型；
- [x] 同时定义 `ComicWholePageRenderBackend` 能力与统一产物校验接口，首个提交不要求真实 provider 实现；
- [x] 明确各 revision、cache key、stale 传播、失败保留和清理语义；
- [x] 用 fake backend 证明无 geometry、缺 block、重复 block、越界区域和错误图片不能进入 render-ready。

### B. Sidecar 适配器

- [x] 实现 bounded multipart export 请求与 ZIP/JSON 解析，规范化区域、顺序、原文和 backend template；
- [x] 实现 bounded import/render 请求，校验返回图片签名、尺寸、内容 hash 和页身份；
- [x] sidecar 版本/能力不兼容时本地失败，不让部分结果覆盖最后成功检查点；
- [x] 设置页仅增加同级“制图服务”配置与连接检查，不改变三个翻译入口层级。

### C. 上下文文本翻译

- [x] 从现有 Responses/Codex 传输抽出 `ComicTextTranslator`，输出必须按 blockId 完整对齐；
- [x] 提供当前页图像、区域原文、最近前页、滚动摘要、术语与风格约束，并保持既有预算/脱敏边界；
- [x] 缺块、重复块、未知块、空译文或身份不匹配时拒绝候选；
- [x] 缓存 identity 使用模型实际可见的受限上下文，不因未发送内容制造错误 miss。

### D. 视觉编排与缓存

- [x] 将现有 orchestrator 收窄为分析/翻译检查点，再组合 region -> translation -> render stages；
- [x] 建立有界衍生页缓存；进程重启可命中，清理不会被旧飞行请求回填；
- [x] 失败保留原图和最后成功衍生页，过期结果只写回创建它的 page identity；
- [x] 任何 analysis-only 文档都不能返回 Reader-ready 状态。
- [ ] 分阶段 sidecar 与整图出图 backend 汇合到同一 `ComicRenderedPage` 发布边界，Reader 不感知路线差异；

### E. Reader 替换

- [x] 保留现有显式动作、本地文件输入和 route/page/file/UI epoch fences；
- [x] 删除 `ComicTranslationSheet` 作为主结果，生成中/失败/待复核改为页面状态；
- [x] Reader 在同一页原图与衍生页间切换，衍生页走现有图片加载、缩放、平移和切页路径；
- [ ] 原文/译文检查仅作为翻译页的次级入口，未实现时可以暂不提供，不能阻塞视觉结果；
- [ ] 快速切页、单双页、长图、失败重试、返回缓存均不串页、不重复调用 provider。

### F. 验收与关闭

- [x] fake backend、fixture、parser、identity、cache、failure 和 security tests 通过；
- [x] signed app、`entry@ohosTest`、持久化/secret/backup/i18n/V2 门禁通过；
- [x] 在用户指定设备上用合法样页完成一次受控 sidecar + 已选 provider 真实链路；
- [x] 提供同页原图与视觉译制页截图，证明原文不与译文竞争；
- [x] 证明缩放/平移/切页正常，返回同页命中衍生页缓存且不调用 sidecar/provider；
- [x] 失败时原图保持可读，不出现文字列表替代品。

只有 F 全部满足才允许称为“漫画翻译视觉 Reader V1 完成”。A–D 单独完成只能称为基础设施阶段。

## 第一阶段提交边界

第一个代码提交只做 A：领域模型、身份/失效规则、fake backend 和 fixture 测试。它不改 Reader UI、不增加
设置项、不调用模型、不上传图片；设备回归也只运行离线 fixture。协议契约通过后再进入 B，避免再次让 UI
领先于真实产物。

2026-07-21：领域契约已在设备 `237` 完成 184/184 Hypium 回归，其中新增视觉契约 6/6 通过；signed app
与 `entry@ohosTest` 构建、V2 门禁和 `git diff --check` 通过。随后固定首个 sidecar profile 为
`manga-translator-ui v1.9.9`，保存协议派生的原创合成 export/import fixture，并加入字段漂移、页身份和
模板 hash 拒绝测试；阶段 A 至此关闭。最终 signed app 与 `entry@ohosTest` 构建通过，设备 `237` 完整
Hypium 为 205/205，其中新增 sidecar 协议 4/4 通过。真实 sidecar 网络调用、ZIP 解包和返回 PNG 校验
仍属于阶段 B。

2026-07-21：阶段 B 的无 UI 传输子阶段完成。NextE 按固定提交的真实 FastAPI 字段发送
`image + config` 到 export、发送 `image + json_file + config` 到 import；请求图片、multipart、响应 ZIP、
JSON/TXT 和 PNG 均有独立上限。ZIP central/local header 会在系统 zlib 解包前检查，且只允许固定两个根
条目；公共 HTTP、认证 header 注入、源图 hash 漂移、profile 字段漂移、非 PNG、不可解码 PNG 和尺寸不符
均在写入视觉产物前失败。设备 `237` 的 fake transport 完整链路、ZIP 解包、blockId 回填、PNG 解码与原子
落盘测试 3/3 通过；完整 Hypium 为 208/208。制图服务设置与真实 sidecar 连接检查仍是 B 的剩余项，
当前代码不会因 Reader 出现或预取而上传图片。

2026-07-21：阶段 B 已补齐同级“制图服务”设置、凭据隔离与只读 capability 检查；检查只请求
`openapi.json`，不会上传漫画页。阶段 C 随后完成：`ComicTextTranslator` 复用现有 API/Codex Responses
传输、Codex token 刷新和统一 LLM 源选择，但使用独立的逐块响应协议。请求同时携带经最终 SHA-256/MIME
复核的当前页图像、全部 sidecar block 原文，以及受限的前页、滚动摘要、术语、翻译记忆和风格上下文；
context fingerprint 只覆盖协议实际发送的受限内容。模型响应会按原 document 顺序重建 batch，少块、重复
blockId、未知 blockId、空译文和 project/page/image/language 身份漂移均在 render 前拒绝。signed app 与
`entry@ohosTest` 构建、V2 门禁和 `git diff --check` 通过；设备 `237` 完整 Hypium 为 214/214，其中新增
多模态逐块翻译器协议 3/3 通过。阶段 D 的视觉编排与持久衍生页缓存仍未完成，因此当前 Reader 仍不能
把本阶段单独当作完整漫画翻译结果。

2026-07-21：阶段 D 的分阶段路线基础设施已闭环。`ComicVisualTranslationOrchestrator` 只发布经过
完整 identity 校验的 `ComicRenderedPage`，按 region -> context-aware translation -> render 顺序执行；
analysis document 与 translation batch 不再具有 Reader-ready 出口。Translator 返回的 source/model/prompt/
context/glossary identity 必须与当前请求逐项一致，错误批次在 render 前失败。衍生页仓库以原图、上下文、
provider、sidecar 和 render profile 的严格 lookup key 持久化，启动后复核文件大小和 SHA-256；最多保留
64 页/512 MiB，cache clear epoch 阻止旧飞行请求重新写入可命中索引。失败重渲染不会覆盖最后成功页。
signed app、`entry@ohosTest`、V2 门禁和 `git diff --check` 通过；设备 `237` 完整 Hypium 为 220/220，
其中本阶段新增编排测试 6/6 通过。Reader 原图回退/发布 fence 与整图 backend 路由仍属于 D/E 的剩余项，
因此此时仍只是视觉基础设施，不是可验收的 Reader 翻译结果。

2026-07-21：Reader 分阶段路线已接入生产运行时。显式“翻译当前页”会使用已选共享 LLM 源与制图服务，
只读取当前页已验证的本地原图；成功结果以 `file://` 衍生图片重新进入现有单双页/连续阅读图片路径，菜单可在
原图与译图之间切换。旧文字结果 sheet 已从主结果路径移除，route/page/file/UI epoch fence 会拒绝快速切页后
的迟到发布。制图服务未配置的设备验收中，Reader 保持原图且只在顶栏下方显示非交互失败状态，没有文字列表
替代品；提示会明确指向制图服务而不是误报模型。最终 signed app 与 `entry@ohosTest` 构建、资源 JSON、V2
门禁和 `git diff --check` 通过，设备 `237` 完整 Hypium 为 221/221。该设备当前未配置可达的
`manga-translator-ui` sidecar，因此真实出图、原/译图对照、缩放切页与重启缓存证据仍未满足 F，不能称为 V1
完成。

2026-07-21：真实 sidecar 验收以 `manga-translator-ui v1.9.9` 对应提交
`696dc63bd0b4803f96cc3d4f844322cef4910f8e` 的 ARM64 CPU 镜像启动，并从实际路由确认 export/import
均通过 `X-Session-Token` 认证，而不是通用 `Authorization`。NextE 的传输、连接检查、secret 设置语义和
fake transport 断言已统一到该固定协议，避免能力检查成功但首次上传必然 401。修正后资源 JSON、signed app、
`entry@ohosTest`、V2 门禁和 `git diff --check` 通过，设备 `237` 完整 Hypium 为 221/221。真实样页出图与
Reader 缓存交互证据仍按 F 继续执行。

2026-07-21：真实 export 首次通过认证后暴露上游空配置会默认调用自身 OpenAI，空 key 导致 500；这与
“sidecar 负责视觉、NextE 选中的共享 LLM 源负责翻译”的边界冲突。使用同一真实镜像直接验证
`translator=original` 后，`/translate/export/original` 返回 200、OCR 区域和原文 ZIP，且不触发远端翻译。
协议 revision 因此升为 2，并固定 visual-only config；fake transport 同时断言 multipart 包含 `original`
且不包含 `openai`。后续真实链路不得向 sidecar 配置第二套 LLM。

2026-07-21：真实链路继续暴露 vanilla v1.9.9 的 `/translate/import/json` 会返回 200，却忽略
`prepare_translator_params()` 产生的 `load_text` 参数，随后再次检测/OCR并运行 sidecar translator；这正是
“接口成功但译图仍是原文”的根因。协议 revision 升为 3，固定上游 commit 的独立 GPL sidecar 补丁增加
`/translate/import/json/nexte-load-text-v1`，构建器会校验 commit、应用补丁并生成独立镜像；NextE 的
OpenAPI 检查要求专用路由，vanilla 服务会在图片上传前被拒绝。

同日设备 `237` 用合法日文画廊第 4 页完成真实验收。Reader 回调尺寸为 `2560x3634`，实际缓存源文件为
`1280x1817`；运行时现以编码文件的真实尺寸建立视觉身份，避免 export 身份误判。sidecar export 得到五个
区域，已选 Codex 源返回五个中文译文，专用 import 日志为 200 且没有第二次检测/OCR或 sidecar translator。
同页原图与视觉译制页、双击缩放、拖动平移、切到下一页再返回均已实机检查。切页返回以及应用重启后的
显式“翻译当前页”恢复得到同一 SHA-256
`8ecebff860bb4852d45d94bbafc786af49420b523495479235501ce966cdbb66`，期间 sidecar 无 POST，持久缓存路径
在 provider 调用前返回。F 的首条分阶段视觉 Reader 验收已满足；长图、双页和更广语料仍保留在 E 的后续
覆盖项，不能从这一个样本推断字体排版质量已经完成。最终 signed app 与 `entry@ohosTest` 构建、资源
JSON、sidecar builder 语法、V2 门禁和 `git diff --check` 通过；设备 `237` 完整 Hypium 为 221/221。

2026-07-21：sidecar 认证从“手工粘贴会话 token”收敛为账号自动登录。固定上游 v1.9.9 的源码事实是
`POST /auth/login` 接受用户名和密码、`GET /auth/check` 验证 `X-Session-Token`，服务端会话空闲 60 分钟
失效。NextE 将账号凭据保存在应用私有存储，备份仅进入加密 secret 分区；登录所得 token 只保存在内存，
并发请求共用一次登录，401 时失效被拒绝的 token、重新登录并最多重放一次。旧版本保存的原始 token 继续
兼容，直到用户主动保存账号凭据，避免升级时静默丢失认证。凭据不进入视觉 revision 或衍生页缓存身份，
但其指纹进入运行时 backend 身份，兼顾译图缓存稳定与凭据轮换即时生效。连接检查会验证 OpenAPI、登录和
`/auth/check`，不上传漫画页。fake transport 覆盖登录合流、并发失效、旧 token、失败边界和 401 重试，
设备 `237` 完整 Hypium 为 226/226；真实账号密码仍由用户在设置页输入，验收过程没有读取或复制现存秘密。

2026-07-21：同一合法画廊第 5 页用于连续页和更广语料验收。前一页持久文档已进入本页 prompt，页面完成
七个 block 的翻译并生成视觉译图，证明滚动摘要与前页上下文路径真实运行；但视觉对照同时发现两个不同
问题：一个小气泡 `むぅ～…` 没有被 sidecar 导出，属于区域检测覆盖缺失；一个已有区域的日文被 OCR 错认，
旧 prompt 又把错误原文当成权威，导致中文出现错误的“去山里”语义。v2 虽明确要求模型结合整页图纠正
OCR，设备真实重译仍得到“我要去山里了”，因此没有作为修复提交。v3 保留整页上下文图，并按 blockId
追加有界放大的区域裁图，polygon 同时进入 prompt 与 context fingerprint；同页设备重译把该块修正为
“别说傻话了——我先走了！”，RDB 中相邻两次持久结果也分别保留了错误与修正译文，证明不是视觉错觉或
旧缓存。区域裁图设备协议测试 3/3 通过。该页仍不是完整质量通过：整块漏检需要后续残留原文/补充检测阶段
解决，不能靠翻译 prompt 或裁图伪造无 geometry 的 block。
