# 漫画翻译自部署路线

- **状态**：实现与设备设置回归完成；真实页验收待现有自部署账号重新认证
- **建立日期**：2026-07-28
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
- [x] 端侧与自部署共用 API/Codex 漫画来源筛选：OpenAI/兼容源声明支持 Responses 图片输入后即可选择；
- [x] LLM 源详情返回前完成持久化，来源列表即时显示新名称与最新能力，不要求退出列表后重新进入；
- [x] 任意配置 JSON、未打补丁服务、公网 HTTP、无效凭据均本地失败并保留原图；
- [x] 本地 CI preflight、V2/i18n 门禁、设备 314 项测试与签名构建通过；
- [ ] 设备 `237` 的真实 Reader 自部署译图：2026-07-28 已在当前签名构建中重新选择自部署路线，设置仍显示
  已配置；“检查连接”真实返回“旧会话已失效，请填写用户名和密码”。设备此前已成功访问自部署服务的 OpenAPI
  与 `/auth/check`，当前唯一缺口是用现有账号重新认证后完成一次 Reader 译图。不在未取得账号授权时创建新用户、
  提取凭据或重置服务。

上游参数已完成审计。NextE 首版只暴露检测灵敏度与修复方式；OCR 阈值、mask 膨胀、字体、描边、方向、
超分和任意 JSON 继续固定在版本化 profile 中，避免设置项互相组合后产生无法复现的质量结果。

本计划不扩展 Torii BYOK，不把 sidecar 打包进 HAP，不新增专业制作台，也不授权继续穷举上游参数。
