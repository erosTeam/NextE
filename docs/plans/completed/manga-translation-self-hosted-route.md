# 漫画翻译自部署路线

- **状态**：已完成；代理维护的隔离服务和设备 `237` 已完成真实 Reader 两页闭环
- **建立日期**：2026-07-28
- **完成日期**：2026-07-28
- **范围**：把现有 patched `manga-translator-ui v1.9.9` sidecar 产品化为与端侧、Torii 并列的显式视觉路线

## 目标

用户可以在漫画翻译设置中选择“自部署”，配置自己的 NextE-compatible
`manga-translator-ui` 服务，并继续使用漫画翻译已选择的共享 LLM 源。Reader 的结果仍是完整译图：
自部署服务负责检测、OCR、消除原文和排版，NextE 负责画廊上下文、术语一致性、翻译和缓存。

自部署不是端侧能力的内部阶段，也不是 Torii BYOK。三条路线只在 `ComicRenderedPage` 发布边界汇合：

- 端侧：设备上的 YSGYolo / CTD / PP-OCRv5 / AOT 与系统渲染；
- 自部署：用户运行的 patched `manga-translator-ui` 分阶段 export/import；
- Torii：Torii 对完整云端译图负责，不复用共享 LLM 源。

## 首版参数边界

上游还支持检测器、检测尺寸、OCR 引擎、OCR 阈值、mask 膨胀、排版模式、字体、描边、方向和超分等参数。
首版不提供任意 JSON，也不把这些内部耦合项全部暴露给普通设置。只提供两个有稳定语义、能进入缓存身份的
选项：

| 设置 | 选项 | 固定含义 |
| --- | --- | --- |
| 检测灵敏度 | 高召回 / 平衡 | 高召回保留现有 `box_threshold=0.5`、零最小面积；平衡使用较严格阈值减少噪声 |
| 修复方式 | LaMa 高质量 / AOT 快速 | 使用 pinned v1.9.9 已有的 LaMa Large 或 AOT inpainter |

OCR 语种路由继续由 NextE 固定：日文/自动允许 MangaOCR hybrid，明确非日文只用通用 48px OCR。排版、
字体、描边和 mask 参数暂时保持 pinned profile；只有真实页面 A/B 能证明稳定收益时才增加新的产品选项。

## 安全与兼容边界

- 只接受 pinned profile 生成的有限配置组合，拒绝任意 sidecar translator 或任意 JSON；
- export 固定 `translator=original`，不得把共享 LLM 凭据转交给 sidecar；
- 必须存在 `/translate/import/json/nexte-load-text-v2`，vanilla v1.9.9 在上传图片前失败；
- 私网可以显式使用 HTTP；公网端点必须 HTTPS；
- 用户名/密码只进入加密备份，会话令牌只驻内存；
- 路线未被用户选择时，不读取凭据、不连接服务、不上传页面。

## 2026-07-28 实现与设备证据

- [x] 设置页显示端侧 / 自部署 / Torii 三条同级路线；
- [x] 自部署设置可保存服务地址、账号、检测灵敏度和修复方式，并可无图片检查连接；
- [x] Reader 自部署路线实现 export -> 共享 LLM -> import，缓存身份包含 profile、URL、LLM 与译文；
- [x] 端侧与自部署共用 API/Codex 漫画来源筛选：仅文本模式可使用文本 Responses 源，多模态模式才要求
  图片输入能力；
- [x] LLM 源详情返回前完成持久化，来源列表即时显示新名称与最新能力，不要求退出列表后重新进入；
- [x] 任意配置 JSON、未打补丁服务、公网 HTTP、无效凭据均本地失败并保留原图；
- [x] 本地 CI preflight、V2/i18n 门禁、设备 314 项测试与签名构建通过；
- [x] 代理自行构建 `nexte/manga-translator-ui:v1.9.9-nexte2`，创建隔离 QA 容器与专用测试账号；这不是
  用户既有部署，也没有修改旧容器的账号或数据；
- [x] 设备 `237` 真实访问 QA 服务，OpenAPI、登录、`/auth/check` 和 NextE v2 export/import 能力检查通过；
- [x] 用户提供的真实画廊第 21、22 页均在 Reader 内完成译图，不使用合成图片；
- [x] 新增无图片模型准备脚本和模型/账号持久卷部署约束，避免首次 Reader 请求承担模型安装。

上游参数已完成审计。NextE 首版只暴露检测灵敏度与修复方式；OCR 阈值、mask 膨胀、字体、描边、方向、
超分和任意 JSON 继续固定在版本化 profile 中，避免设置项互相组合后产生无法复现的质量结果。

## 真实 Reader 结果

隔离 QA 服务运行在 `manga-translator-ui v1.9.9-nexte2`，设备 `237` 使用高召回、LaMa 高质量、
Codex `gpt-5.6-luna` 与“上传图片辅助翻译”，在用户指定的真实画廊
`https://e-hentai.org/g/4068247/2590fe92e3/` 完成以下验证：

| 页面 | 结果 | 实测时间 |
| --- | --- | --- |
| P21 | 冷容器首次请求下载模型并超过客户端 5 分钟上限；模型就绪后同页重试成功 | 冷启动从 20:40:20 开始，10 分钟后仍在服务侧准备；不作为暖态性能 |
| P22 | export、共享 LLM、v2 import 全部成功，Reader 显示完整衍生页 | 触发到 export 约 44.36 秒，export 到 import 约 72.38 秒，总计约 116.74 秒 |

两页都保留了原图纵向排版方向，并按区域保留紫、蓝、绿等源文字颜色与白色描边；真实结果仍存在局部
拥挤、边缘裁切和文字压缩，不能据此宣称印刷质量或所有页面通用可用。该验收只证明自部署路线的产品衔接、
缓存身份和 Reader 发布边界成立。

本地验收截图留在 `.hvigor/outputs/manga-self-hosted-reader-237-20260728/`，P21 与 P22 的 SHA-256 分别为
`eab3102255dc9576a5438e5d5d2d85c1951e9023df1548d158b1bae126e2d768` 和
`16b652453ba4a99041b374c9279790fcb9c8e3875f1cc0e12aa25bdb23f5db9c`；原图和截图均不提交到仓库。

冷启动不是通过继续放宽 Reader 超时解决。全新容器实测约生成 1.3 GiB 模型目录且准备超过十分钟，因此
部署流程固定为持久化 `/app/models` 与 `/app/manga_translator/server/data`，再运行
`scripts/prepare_manga_translator_ui_sidecar.sh`。脚本直接调用 pinned 上游下载器并校验默认 detector、
YSGYolo、48px OCR、MangaOCR、LaMa Large 和 AOT 文件，不需要测试图片；Reader 请求继续保持有界失败。

本计划不扩展 Torii BYOK，不把 sidecar 打包进 HAP，不新增专业制作台，也不授权继续穷举上游参数。
