# 漫画翻译工作流调研

- **性质**：外部方案与可行性参考，不是 NextE 实现规范或任务授权
- **首次整理**：2026-07-20
- **最近复核**：2026-07-22
- **对应设计**：[NextE 漫画翻译设计与演进指南](../manga-translation-design.md)

## 调研问题

本轮调研回答四个容易混在一起的问题：

1. 漫画翻译是否必须使用多模态模型；
2. OCR 质量不稳定时，系统如何继续工作；
3. 整页多模态缺少精确文字框、蒙版和字体信息时，后续能力如何衔接；
4. 多页画廊如何保持人名、称谓、口癖和剧情指代一致。

结论是：多模态不是必选项，OCR 也不是唯一入口。成熟工具通常将文字检测、OCR、翻译、消字和
排版拆成阶段；更值得复用的不是某个模型，而是可编辑的中间文档、人工修订入口和项目级上下文。

## 已形成的行业模式

### 1. 完整制图流水线

面向发布成品的工具通常采用：

```text
文字/气泡检测 -> OCR -> 翻译 -> 消字/修复 -> 排版/渲染 -> 人工检查
```

检测回答“文字在哪里”，OCR 回答“原文是什么”，翻译回答“目标语言怎么表达”，消字和排版处理
最终图片。它们是不同质量问题，失败也应能分阶段重试。

### 2. 可编辑中间文档

成熟工作流不会要求每次修订都重新跑整张图片。中间文档至少保存页号、阅读顺序、原文、译文、
可选坐标和人工修订。由此可以分别执行：

- 只检测/OCR 并导出原文；
- 只翻译现有文本；
- 导入人工译文后再渲染；
- 修改术语后只重翻受影响文本。

### 3. 人工修订是主流程，不是失败补丁

漫画文字会受到竖排、假名注音、艺术字、拟声词、低分辨率、遮挡和复杂背景影响。OCR 和整页视觉
模型都可能漏字、错序或补出图中不存在的文本。因此成熟工具普遍保留框选、改原文、改译文和重新
清理图片的入口，而不是把单次模型结果当成不可修改的事实。

### 4. 项目级上下文

逐页独立翻译容易造成人名和语气漂移。现有实践通常组合：

- 项目术语表；
- 前 1～2 页原文和译文；
- 更早剧情的短摘要；
- 用户锁定、模型不得覆盖的术语。

这比持续上传整本漫画图片更可控，也允许在不重新识图的情况下修订全章文本。

## 代表项目

许可证为 2026-07-20 对上游仓库的记录，只说明需要关注的复用边界；采用代码、模型或权重前必须
重新检查当前许可证及其依赖条款。

| 项目 | 工作流与可借鉴点 | 仓库许可证（复核日） |
|---|---|---|
| [Comic Translate](https://github.com/ogkalu2/comic-translate) | 检测/分割、OCR、翻译、消字、渲染和人工模式组成完整桌面工作流；LLM 可接收整页文本并选择性接收图片上下文。适合参考完整产品边界。 | Apache-2.0 |
| [manga-translator-ui](https://github.com/hgmzhn/manga-translator-ui) / [Workflows](https://github.com/hgmzhn/manga-translator-ui/blob/main/doc/en/WORKFLOWS.md) | 明确拆分“导出原文”“只翻译 JSON”“导入翻译并渲染”等流程；可编辑 JSON 保存区域、原文、译文、位置和渲染元数据。最适合参考阶段如何衔接。 | GPL-3.0 |
| [mokuro](https://github.com/kha-white/mokuro) | 检测和 OCR 后生成独立 `.mokuro` 文档，阅读器再把文档与原图组合。适合参考“先做阅读辅助、暂不修改图片”。 | GPL-3.0 |
| [manga-image-translator](https://github.com/zyddnys/manga-image-translator) | 模块化检测、OCR、翻译、修复和渲染，支持服务模式、术语表以及 OCR 前/翻译后词典。适合参考可替换处理器和服务端边界。 | GPL-3.0 |
| [Koharu](https://github.com/mayocream/koharu) | 本地优先的分阶段视觉/语言模型栈，包含编辑、CJK 排版、PSD 和本地接口。适合参考模块能力声明与可编辑导出。 | GPL-3.0 |
| [BallonsTranslator-Pro](https://github.com/thomaswantstobeaskeleton/BallonsTranslator-Pro) / [上下文设计](https://github.com/thomaswantstobeaskeleton/BallonsTranslator-Pro/blob/main/docs/TRANSLATION_CONTEXT_AND_GLOSSARY.md) | 使用项目术语表和前 1～2 页已完成内容给当前页提供上下文，并把术语表持久化在项目数据中。适合参考跨页一致性。 | GPL-3.0 |

这些项目主要是桌面或服务端技术栈，不能视为可直接嵌入 ArkTS 的移动端 SDK。GPL 项目可以用于理解
行为、数据形态和交互，但将其实现代码纳入 NextE 前必须单独评估许可证边界。Apache 项目也仍需
逐项核对依赖和模型权重条款。

## 可直接接入的托管图片翻译 API（2026-07-22）

下面只记录具有公开开发者文档和认证端点的服务。只有网页上传界面、浏览器扩展或营销页但没有公开 API
契约的产品不算可接入候选。除 Torii 已补充 NextE 两页原创样例的真实设备证据外，其余结论仍只来自官方
文档静态复核，尚未用 NextE 样页、真实密钥或付费额度验证质量、延迟、可用性和账单。

| 服务 | 公开能力 | 与 NextE 的匹配 | 当前判定 |
|---|---|---|---|
| [Torii Image Translator API](https://toriitranslate.com/api) | `POST /api/v2/upload` 一次返回最终译图、消字图、逐块原文/译文/坐标/方向/颜色/字体和更新后的跨页 `context`；支持自带 OpenAI/OpenRouter/Google/Anthropic/DeepSeek/xAI 或自托管兼容密钥。 | 作为独立 `ComicWholePageRenderBackend`：NextE 只上传整页和上下文、接收最终图片，不把 Torii 的 OCR/inpaint/typeset 子端点拆入端侧管线。`context` 最多 10,000 字符，可承接前页摘要和术语。 | **首个已验证云端整图 provider**：两页真实出图、跨页姓名一致和本地缓存不重复扣费已通过；站牌/拟声词质量仍需更广样本。其[隐私政策](https://toriitranslate.com/privacy)说明部分图片可能临时进入私有存储做诊断/质量控制，提取文本会转发给所选模型。 |
| [ImageTranslate.ai API](https://imagetranslate.ai/docs/api) | `POST /translate/image` 接收最大 20 MB base64 图片，提供 `manga` 模式、1000 字符 custom prompt、幂等键和 base64 PNG 结果；API 只对 Professional/Enterprise 开放，每次 10 advanced credits。 | 接口最短，适合 opaque whole-page render；只返回最终图片，无法逐块复核或只改一个人名。 | **协议可接但暂不推荐**：其[隐私政策](https://imagetranslate.ai/legal/privacy-policy)写明默认数据可无限期保留，实施前必须取得更明确的数据删除/保留承诺。 |
| [PixLab IMG-TRANSLATE](https://pixlab.io/endpoints/image-text-translate) | `POST /imgtranslate` 上传图片并完成检测、翻译、inpaint 和回填，支持日/中/韩等语言和字体/颜色/字号提示，可返回 base64 或原始图片。 | 通用图片翻译而非漫画专用；没有公开的跨页 context、逐块结果或幂等语义，但 whole-page adapter 很简单。 | **第二验证候选**：其[隐私政策](https://pixlab.io/privacy-policy)说明 API 图片默认内存处理并在完成后清除，且不用于训练，仍需实测竖排、拟声词和长图。 |
| [ImgText API](https://imgtext.io/api-docs) | 返回最终译图、消字图和 region breakdown，支持异步批量与 webhook。 | 数据形态很好，但当前 API 文档的 supported languages 只列出十种欧洲语言，与产品页声称的日/中/韩等 27 种语言不一致。 | **等待厂商确认**，不作为日文漫画候选。 |

### 公开费用复核（2026-07-22）

以下均为美元公开标价，不含税、汇率、支付手续费和用户自己的 LLM 费用。动态页面与结账页可能变化，
所以只能用于 provider 选择和预算量级，不能代替接入前的真实小额扣费证据。

#### Torii

[Torii 价格页](https://toriitranslate.com/pricing)显示一次性购买、credits 不过期：2,500 credits / $5.99、
6,000 / $12.99、15,000 / $29.99，并标注约 $2.40、$2.16、$1.92 / 1,000 credits。最后一档展示的
总价、数量与标注单价不能完全互相换算，正式预算应以结账页实际到账 credits 为准。按公开单位价，
1 credit 约 $0.00192～$0.00240。

| Torii 接法 | Torii 计费 | 估算平台费/页 | LLM 与凭据边界 |
|---|---:|---:|---|
| 整图、Torii 代付模型 | 1 credit 扫描 + 按所选模型、上下文、输入/输出长度计算的翻译 credits；官方称快速模型的标准漫画通常总计约 1 credit | 通常约 $0.00192～$0.00240，premium 模型和长上下文会增加 | 不传用户供应商 Key；用户仍通过必填 `translator` 参数选择 Torii 目录中的具体模型，Torii 代付供应商并折算为 credits |
| 整图、Torii BYOK | **固定 1 credit/图** + 用户供应商账单 | $0.00192～$0.00240 + LLM | `x-byok-*` 会把用户的 OpenAI/OpenRouter/Google/Anthropic/DeepSeek/xAI Key 交给 Torii；公开契约不包含 Codex OAuth |

API 的 `translator` 是必填参数，官方示例为 `gemini-3.1-flash-lite`；BYOK 不是另一套模型选择器，而是
附加在同一模型选择上的可选账单模式。当前交互式 API reference 列出了 Gemini 3.1 Flash Lite、DeepSeek
V4 Flash、Grok 4.20 为 `1+ credits`，Kimi K2.5、GPT-5.4、Gemini 3 Flash、Claude Sonnet 4.6 为
`2+ credits`，Gemini 3.5 Flash 为 `3+ credits`。2026-07-22 复核到的真实参数 ID 分别是
`gemini-3.1-flash-lite`、`deepseek`、`grok-4.20`、`kimi-k2.5`、`gpt-5.4`、
`gemini-3-flash`、`claude-sonnet-4.6`、`gemini-3.5-flash`；中文字体参数应为 `noto`，不是示例默认的
`wildwords`。公开契约没有机器可读的模型目录端点，因此 NextE 只能保存带复核日期的官方目录快照，
请求失效时明确报错并通过应用更新目录，不能抓取 HTML 或让普通用户手填模型名。其更新记录还说明跨页 context 可能按
所选模型额外增加约 1～2 credits/页。按公开单位价，Torii 代付模式的量级可读成：

| Torii 代付场景 | credits/页 | 平台与模型合并扣费/页 |
|---|---:|---:|
| 快速模型、普通单页 | 官方称通常约 1 | $0.00192～$0.00240 |
| 启用 context，增加约 1 credit | 约 2 | $0.00384～$0.00480 |
| 启用 context，增加约 2 credits | 约 3 | $0.00576～$0.00720 |

这不是上限保证；premium/推理模型的 token 行为可能显著增加 credits。接入时必须让模型名与账单模式独立
存储，并在请求前显示 Torii 返回或估算的费用，不能把“非 BYOK”误解为没有模型选择。

按上述单位价，仅计算 Torii 平台部分：

| 页数 | 整图 BYOK 的 Torii 平台费 |
|---:|---:|
| 20 页 | $0.038～$0.048 |
| 40 页 | $0.077～$0.096 |
| 100 页 | $0.192～$0.240 |
| 1,000 页 | $1.92～$2.40 |

BYOK 的真实单页公式是 `Torii 平台费 + 输入 tokens × 模型输入单价 + 输出 tokens × 模型输出单价`。
例如仅用于敏感度估算的 3,000 input + 500 output tokens：若模型每百万 token 输入/输出分别为
$0.10/$0.40、$1/$5、$5/$25，则 LLM 部分分别约 $0.0005、$0.0055、$0.0275/页；真实值取决于 OCR
字数、custom prompt、滚动摘要和厂商是否附加隐藏提示。Torii 的相同图片+设置结果在缓存存在时不重复扣费，
但价格页说明默认约一周后自动删除；这不能代替 NextE 自己的请求去重、artifact 缓存和失败重放约束。

NextE 在 2026-07-22 用设备 `237`、两页 `nexte-original-manga-eval-v1`、managed billing 与
`gemini-3.1-flash-lite` 完成真实验证：一次新鲜两页运行耗时 13.0 秒、返回产物合计 3.8 MiB、扣除
2.42 credits；第二页继续使用“优”，与第一页姓名一致。官方示例把 `image` 写成 PNG data URL，但真实
响应为 JPEG data URL，因此接入方不能只匹配字符串前缀；必须同时校验声明 MIME、文件签名、可解码尺寸，
再归一化到自身稳定产物格式。NextE 的稳定 fixture identity 与本地 artifact 缓存使杀进程后的同配置复跑
降到 25–28 ms，复跑前后余额均为 6016.71。整轮接入诊断从 6030.00 降到 6016.71；其中 13.29 credits
包含修复前被客户端错误拒绝的成功 JPEG 响应和重复定位请求，不能把该总额当作正常两页价格。

Torii 的 `translator` 模型选择与 BYOK 是两个正交参数：不启用 BYOK 时同样由用户选择具体模型，只是模型费
由 Torii 代付并扣 credits；启用 BYOK 后仍选择模型，但模型费改由用户自己的供应商账户承担。因此 BYOK 对
快速廉价模型未必带来显著绝对节省，因为 1 credit 扫描费本来就是主要下限；它更大的价值是账单归属、使用
自有额度和固定 Torii 费用，而不是获得模型选择权。NextE 不据此拆接 Torii 的子阶段：这样会把云端服务的
区域、mask、字体和重试语义混入自有端侧路线，模糊两条路线的质量与责任边界。Torii 只验证一键整图；
端侧路线继续使用共享 LLM 源、Codex OAuth、术语上下文和自有视觉处理。

#### ImageTranslate.ai、PixLab 与 ImgText

| 服务 | 最低 API 门槛与公开额度 | 满额使用时的名义单页成本 | 费用风险 |
|---|---|---:|---|
| [ImageTranslate.ai](https://imagetranslate.ai/pricing) Professional | $19.9/月，或年付折算 $16.6/月；12,000 advanced credits，API 每页 10 credits，即 1,200 页/月 | $0.0166，或年付 $0.0138 | Starter 没有 API；不用完额度时实际单页成本会快速上升 |
| ImageTranslate.ai Enterprise | $99.9/月，或年付折算 $83.3/月；80,000 credits，即 8,000 页/月 | $0.0125，或年付 $0.0104 | 仍有固定月费；多目标语言按调用次数重复计费 |
| ImageTranslate.ai top-up | 3,000/$6.9、10,000/$19.9、50,000/$89.9 credits | $0.023、$0.0199、$0.0180/页 | 仅付费订阅者可买，top-up 一个月失效，不能当长期低频预付包 |
| [PixLab](https://pixlab.io/pricing) | Starter $20/月；页面列出统一 Media Analysis/Processing 调用额度 | **无法可靠计算** | `IMG-TRANSLATE` 没有公开每次消耗哪类额度/多少单位；价格页对超额单价还同时出现 $0.07/1,000 与 $0.009/1,000 两种说法，需售前书面确认或控制台实扣 |
| [ImgText](https://imgtext.io/) | 官网称免费 50 图/月，API 文档称额度随 plan 扩展 | **付费价格未公开** | 价格页/稳定付费契约不可公开复核，且 API 语言表与营销页冲突，暂不进入采购比较 |

在低频 Reader 场景中，ImageTranslate.ai 的固定月费远高于 Torii 按量 credits：例如一个月只翻 100 页，
Professional 的实际成本是 $0.166～$0.199/页；只有接近用完 1,200 页额度时才下降到约 $0.014～$0.017/页。
PixLab 的套餐表面便宜，但在 endpoint 计量没有确认前不能把 350K Media Processing calls 直接等同于 350K
漫画页，否则会形成虚假的低价结论。

[MangaTranslate](https://www.mangatranslate.com/) 和 [MangaTrans](https://www.mangatrans.org/) 提供网页端漫画
OCR/翻译/回填或 overlay，但本次没有找到可公开复现的 API reference、认证和响应契约，因此不能当作
NextE provider。`manga-translator-ui` 则是已经验证的自托管 API，不属于第三方托管服务。

### 托管 API 的边界

托管服务不等同于“一个通用 LLM 直接修改图片”。Torii、PixLab 等仍在云端组合 detector、OCR、翻译、
inpaint 和 renderer，只是把整条流水线封装成 API。NextE 对这类服务只采用**整图后端**接法：上传原图、
目标语言、术语/上下文，直接保存返回图片。厂商独占 OCR、翻译和排版，局部修订通常整页重跑。

Torii 虽然另有 OCR/inpaint/typeset 子端点，但这些端点不进入 NextE 产品路线。把它们拆入现有管线会让
“端侧能力由 NextE 负责”与“云端服务对最终成图负责”的边界再次混合，还会引入第二套 region/mask/排版
协议。因此 Torii 永远作为独立一键整图 provider；托管代付与 BYOK 只是同一路线的两种账单/凭据模式，
不是两种处理管线。Torii 与端侧路线最终都发布同一种 `ComicRenderedPage`，Reader 不感知内部差异。

任何真实接入都必须先固定 provider profile，并验证：源图/结果大小和 MIME、请求超时、取消与幂等扣费、
服务端缓存/删除、第三方模型转发、长图限制、逐页上下文、非文字区域保真以及失败时原图回退。网页宣传的
准确率和延迟不能替代两页原创 fixture 与真实 Reader 链路证据。

### 可复用的服务端阶段边界

2026-07-21 复核 `manga-translator-ui` 的公开文档和服务端源码后，可以确认它不只提供“一键翻译”，还暴露
适合 NextE 分阶段编排的 Web API：`/translate/export/original` 执行检测与 OCR 并返回包含
`translation.json` / `original.txt` 的 ZIP，`/translate/import/json` 或 TXT 导入端点再接收原图、区域文档
和外部译文，执行修复与渲染并返回 PNG。官方手动工作流本身也是“导出原文 -> 外部修改译文 -> 导入并渲染”。

但“公开端点存在”不代表任意上游 revision 都兼容。当前 `main`（复核 commit
[`b311816e`](https://github.com/hgmzhn/manga-translator-ui/commit/b311816edddc8f3c61b3edd66cc064da96762011)）
及已检查的 v2.x 中，[响应模型](https://github.com/hgmzhn/manga-translator-ui/blob/b311816edddc8f3c61b3edd66cc064da96762011/manga_translator/server/to_json.py)
仍要求 `default_stroke_width` / `adjust_bg_color`，而
[`TextBlock.to_dict()`](https://github.com/hgmzhn/manga-translator-ui/blob/b311816edddc8f3c61b3edd66cc064da96762011/manga_translator/utils/textblock.py)
输出 `stroke_width` 且不再给出 `adjust_bg_color`；按静态调用路径会在生成导出 ZIP 前发生 Pydantic 字段校验失败。
因此 NextE 首个上游基线固定到 [v1.9.9 commit `696dc63b`](https://github.com/hgmzhn/manga-translator-ui/commit/696dc63bd0b4803f96cc3d4f844322cef4910f8e)：
该版本的 [response model](https://github.com/hgmzhn/manga-translator-ui/blob/696dc63bd0b4803f96cc3d4f844322cef4910f8e/manga_translator/server/to_json.py)
与 [region serializer](https://github.com/hgmzhn/manga-translator-ui/blob/696dc63bd0b4803f96cc3d4f844322cef4910f8e/manga_translator/utils/textblock.py)
字段一致，且同时包含 [export/import routes](https://github.com/hgmzhn/manga-translator-ui/blob/696dc63bd0b4803f96cc3d4f844322cef4910f8e/manga_translator/server/routes/translation.py)。
但真实链路进一步证明“路由存在、字段一致、返回 HTTP 200”仍不是回填能力证明：v1.9.9 的 vanilla
`/translate/import/json` 没有把 `prepare_translator_params()` 返回的 `load_text` 工作流参数应用到共享
translator，会重新执行检测/OCR和已配置 translator，而不是加载提交 JSON 的 `translation` 字段。
NextE 因此用独立 sidecar 补丁提供 `/translate/import/json/nexte-load-text-v1`，协议能力检查明确要求该
专用路由；未打补丁的服务被视为不兼容。补丁和固定版本构建器位于 `sidecar/manga-translator-ui-v1.9.9/`
与 `scripts/build_manga_translator_ui_sidecar.sh`，上游 GPL 程序和模型仍作为独立服务，不进入 HAP。

2026-07-21 的设备 `237` 合法样页验收中，export 产生五个日文区域，NextE 选中的 Codex provider 返回
五个按 blockId 对齐的中文译文，专用 import 路由直接完成消字、排版和渲染；服务日志没有第二次 OCR 或
sidecar translator。Reader 原/译图切换、译图缩放/平移、切页返回与持久缓存恢复均通过。这证明当前固定
profile 的真实衔接成立，但不能外推为广泛语料、字体排版或长图/双页质量已经完成。

后续同画廊页面给出了混合路线的实际必要性：专用 OCR 对一个已定位长句产生了高影响错字，仅附整页图并
提示多模态模型纠错仍然失败；为 blockId 附加放大的区域裁图后，同一模型才给出与画面一致的中文。另一个
小气泡则被检测阶段完全漏掉，后续文本模型没有可回填的区域。前者应由“geometry 权威、OCR 可纠正、必要时
提供可读裁图”的多模态翻译协议处理，后者必须由检测覆盖或残留文字检查处理。只核对已返回 block 的翻译
完整性，不能证明漫画页不存在漏字。

同一固定版本的认证实现使用 `POST /auth/login` 签发 `X-Session-Token`，`GET /auth/check` 校验会话，空闲
超时为 60 分钟。因此成熟接法不是把短期 token 当长期配置：NextE 保存账号凭据、把会话限制在内存，
并发登录合流，并在 401 后只自动重新登录和重放一次。账号轮换不应使已生成的视觉译图缓存失效，但必须
让持有旧会话的运行时 backend 立即重建。历史 token 只作为升级兼容路径保留。

这给 NextE 一个不重写整套 Python/模型栈的首条质量路线：把该类服务当作可替换的区域/修复/渲染
sidecar，NextE 继续用自己的 API/Codex provider 负责带画廊上下文的翻译。客户端只实现窄的版本化协议
适配器，不复制 GPL 实现；sidecar 原始 JSON 属于可再生成的适配器缓存，内部长期语义仍由
`ComicPageDocument` 和独立 render identity 承担。该路线需要用户配置可达服务，不是移动端离线能力；
未来 on-device 检测器或其他兼容服务可以实现同一内部接口。

## 研究与模型证据

- [The Manga Whisperer / MAGI（CVPR 2024）](https://openaccess.thecvf.com/content/CVPR2024/papers/Sachdeva_The_Manga_Whisperer_Automatically_Generating_Transcriptions_for_Comics_CVPR_2024_paper.pdf)
  把面板、文字、人物、阅读顺序和说话人关联视为不同任务。它说明更完整的漫画理解可以提供说话人
  和顺序信息，但仍存在失败案例，适合作为后续能力参考，不是现成产品后端。
- [Longer Context for Better Comic Translation（LREC-COLING 2024）](https://aclanthology.org/2024.lrec-main.1505/)
  支持把场景、前文和作品级信息引入漫画翻译。
- [Context-Informed Machine Translation of Manga（COLING 2025）](https://aclanthology.org/2025.coling-main.232.pdf)
  表明短前情摘要可以比简单堆入更长的整卷多模态内容更有效；上下文设计应追求相关性而不是无限长度。
- [OCRBench v2（NeurIPS 2025）](https://proceedings.neurips.cc/paper_files/paper/2025/file/8c2e6bb15be1894b8fb4e0f9bcad1739-Paper-Datasets_and_Benchmarks_Track.pdf)
  覆盖定位、细粒度文字和版面等视觉文字能力，说明通用多模态模型的“OCR 能力”不能等同于稳定的
  精确定位和版面还原。
- [manga-ocr](https://github.com/kha-white/manga-ocr) 是日文漫画专用 OCR 的重要参考，但项目文档同样
  提醒模型可能产生幻觉，且长文本更容易出错。

## 路线比较

| 路线 | 优势 | 主要缺口 | 适合场景 |
|---|---|---|---|
| 整页多模态文本输出 | 接入快，能结合画面理解语气、顺序和指代，可同时给出原文与译文 | 精确坐标、蒙版和逐字可核对性不稳定；模型可能漏字或补字 | 分析检查点、快速文本辅助；不能单独作为 NextE 的视觉翻译结果 |
| 整图输入、译制图片输出 | 接入链短，不要求客户端掌握坐标/蒙版，可直接形成 Reader 视觉页 | 可能改动画面；逐框校对、术语修订和重排困难，改少量文本也可能整页重跑 | 声明 image-output 能力且通过画面保真/身份校验的完整 Reader 路线 |
| 检测 + 专用 OCR + 文本翻译 | 原文和位置可分别检查，便于覆盖层、消字和重排 | 模型组合多，对竖排、拟声词、艺术字仍需人工修订 | 精确原文、气泡对应、制图 |
| 混合路线 | 可让多模态负责语境、OCR 负责原文和坐标，并用差异触发复核 | 编排、成本和质量判定更复杂 | 对准确性和后续排版都有要求的阶段 |

不存在对所有页面都稳定最优的单一路线。系统应先统一输出文档，再按页面、用户动作和目标能力选择
处理器；不应把某个模型的私有响应结构暴露给 Reader。

## Codex OAuth 兼容性调研（2026-07-20）

官方资料把 ChatGPT 登录和 API Key 作为 Codex 客户端的两种认证方式，并说明 device-code 登录仍是
beta；凭据由 Codex 客户端保存并自动刷新，自动化环境优先使用 API Key。公开平台的图片调用则使用
[Responses API](https://developers.openai.com/api/reference/resources/responses/methods/create) 和
[图片输入](https://developers.openai.com/api/docs/guides/images-vision)。这些资料没有给第三方移动应用承诺
可长期复用 ChatGPT/Codex OAuth 和私有 backend 的公共集成契约。

[Hermes Agent 的认证实现](https://github.com/NousResearch/hermes-agent/blob/main/hermes_cli/auth.py) 复刻了
Codex device-code 流程：请求 user code、让用户在 OpenAI 页面确认、轮询 authorization code、交换
access/refresh/id token，并在过期前刷新。其
[Codex runtime](https://github.com/NousResearch/hermes-agent/blob/main/agent/codex_runtime.py) 再把 bearer token
用于 SSE Responses 调用；[辅助客户端](https://github.com/NousResearch/hermes-agent/blob/main/agent/auxiliary_client.py)
从 JWT 读取 `chatgpt_account_id` 并发送 Codex 兼容请求头。

OpenAI Codex 开源客户端可以交叉验证几个传输细节：

- [Bearer provider](https://github.com/openai/codex/blob/main/codex-rs/model-provider/src/bearer_auth_provider.rs)
  同时发送 bearer token 与 `ChatGPT-Account-ID`；
- [默认客户端](https://github.com/openai/codex/blob/main/codex-rs/core/src/default_client.rs) 使用
  `originator=codex_cli_rs`；
- [Responses endpoint](https://github.com/openai/codex/blob/main/codex-rs/codex-api/src/endpoint/responses.rs)
  请求 SSE。

当前 [Codex backend client](https://github.com/openai/codex/blob/main/codex-rs/backend-client/src/client.rs)
还实现了账号级 rate-limit 查询：ChatGPT backend 使用 `/wham/...` 路径，API backend 使用
`/api/codex/...` 路径，并在有账号标识时带 `ChatGPT-Account-Id`。Hermes 的
[account usage helper](https://github.com/NousResearch/hermes-agent/blob/main/agent/account_usage.py) 也读取
usage 响应中的 `rate_limit.primary_window` 与 `secondary_window`，分别展示为会话窗口和周窗口，包括
`used_percent` 与重置时间。OpenAI 官方的
[Codex rate card](https://help.openai.com/en/articles/20001106) 说明用户可在 Codex Settings > Usage 查看
当前限额，但没有把 ChatGPT 私有 usage URL 定义为第三方稳定 API。

这条路线可以用于兼容性实验，但不应与公开 OpenAI API 混称为同一稳定能力：它依赖专用 client id、
认证路径、ChatGPT backend、账号 claim、请求头和可能变化的模型目录。Hermes 当前实现会先调用账号级
[Codex model catalog](https://github.com/NousResearch/hermes-agent/blob/main/hermes_cli/codex_models.py)，过滤
`supported_in_api=false` 和隐藏项，再按 priority 展示；只有在线查询不可用时才退回 Codex 配置、缓存或
内置默认值。公开 Platform API 同样提供标准的
[GET /models](https://developers.openai.com/api/reference/resources/models/methods/list)。NextE 因此让两条
provider 都优先查询模型目录：Codex 登录后从账号目录选择；API 从配置端点查询，同时保留手动 model
作为兼容端点兜底。当前 spike 不内置 Codex 回退列表，查询失败时保留既有选择并明确报错。token 只留
本机，401 最多刷新重试一次。NextE 同样只读查询 primary/secondary 用量窗口，在设置页把
`used_percent` 换算为剩余百分比并显示重置倒计时；页面进入时查询一次，也允许手动刷新，不建立后台
轮询。窗口名称按响应时长识别，不假定 primary 永远是 5 小时或 secondary 永远是周限额；UI 合并为
一条 `5H`/`7D` 用量项，缺失窗口直接省略，整行点击刷新且不显示独立刷新按钮。真实登录或用量查询成功只证明
当时兼容，不能升级为长期可用性承诺。

## 对 NextE 的调研结论

1. NextE 当前产品目标是低操作成本的 Reader 阅读翻译，但结果必须是可直接阅读的视觉译制页；结构化
   原文/译文只是中间文档，不能替代结果。“轻量”不能被解释成文字面板。
2. 整页多模态可以承担转录、草译和上下文理解，但不稳定的 geometry/mask 意味着它不能单独完成制图闭环；
   必须与具备文字区域能力的分析阶段衔接，或使用经评估能够输出可靠区域的 provider。
3. 中间文档仍应保存原文、译文、阅读顺序、geometry、质量信号和人工修订；非渲染用途字段可以可选，
   但进入 Reader 翻译页的文本块必须具备渲染所需区域信息。
4. 术语和跨页摘要属于画廊项目，不能只放在一次模型请求中。
5. 视觉分析结果、文本翻译结果和渲染结果必须分别缓存，避免改一个人名就重新上传图片。
6. 低质量结果应进入翻译页的可见待复核状态；原文/译文详情是次级工具，人工结果不得被模型静默覆盖。
7. 不要求把完整桌面技术栈原样移植到应用内，但第一条产品闭环必须覆盖检测/定位、翻译、原文视觉处理、
   排版渲染和 Reader 展示；这些阶段可以由应用内、网关或自托管后端组合承担。
8. 公开 API 与 Codex OAuth 可以共享页面协议和上下文装配，但认证、端点、凭据生命周期、错误提示和
   稳定性声明必须分开；不得在失败时静默互相回退。
9. AI 辅助漫画制作可以复用上述文档和渲染管线，但应在视觉草稿后进入独立的编辑、质检和导出分支；
   不应把制作级复杂度塞进 Reader V1，也不应借“阅读辅助”之名省略视觉回填。
10. 整图出图 provider 可以与分阶段 sidecar 并存：前者直接交付视觉产物，后者提供可检查、可重渲染的
    中间结构。不能把“整图文本响应”误称为“整图译制图片响应”。

## 维护方式

- 上游项目、模型能力或许可证变化时更新“最近复核”及对应条目，不追加流水账。
- 外部事实只保留在本文件；NextE 已采用的数据语义和阶段边界进入领域设计文档。
- 开始具体实现前重新检查相关上游 README、许可证、模型条款和 NextE 当前源码。
- 本文件不产生实现优先级、设备操作、远端请求或发布授权。
