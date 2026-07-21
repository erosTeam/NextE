# 共享 LLM 源管理

- **status**: active prerequisite for manga visual Reader V1
- **created**: 2026-07-21
- **source**: user requested replacing duplicated comment/comic LLM settings with reusable multi-source profiles
- **consumers**: comment translation and manga translation

## 目标

设置中提供一个独立的“LLM 源”管理入口，可以添加多个 OpenAI-compatible API 或实验性 Codex OAuth
源。评论翻译与漫画翻译不再各自保存 URL、Key、登录和模型目录，而是分别选择已添加的
`sourceProfileId + modelId`。

统一的是连接基础设施，不是业务设置：评论翻译继续拥有启用、自动翻译、显示方式和明确的 Google
回退策略；漫画翻译继续拥有目标语言、上下文/质量策略和制图服务。标签翻译若不调用 LLM，不为了界面
整齐而强行接入。

## 领域边界

`LlmSourceProfile` 至少包含：

```text
schemaVersion
sourceProfileId
displayName
sourceType                // openai_compatible | codex_oauth_experimental
baseUrl?
sourceRevision
capabilities              // chat/responses/image-input/image-output/model-catalog/usage
accountIdentityHash?
createdAt / updatedAt
```

凭据不嵌入 profile JSON：API Key 与 Codex token 通过 `sourceProfileId` 引用独立 secret record。模型目录和
用量快照是账号作用域的可再生成缓存。consumer binding 至少包含 `sourceProfileId + modelId`；模型属于
业务选择，不锁死为源的全局唯一模型，因此评论与漫画可以共用认证但选择不同模型。

源 ID 是稳定用户配置身份。修改显示名或轮换同一账号凭据不提高 `sourceRevision`；更改 source type、
base URL、账号身份或协议语义提高 revision。请求/cache identity 包含 profile ID、source revision、模型
和业务 prompt revision，但不包含明文凭据。

## UI 结构

- 设置首页保留评论翻译、标签翻译、漫画翻译三个独立业务入口；
- 新增同级“LLM 源”入口，列表展示已添加源、类型和连接状态；进入一项后编辑连接/认证，查询模型目录，
  Codex 源在此显示账号用量；
- 评论翻译页删除 URL/Key/模型目录管理，只显示翻译策略、LLM 源选择和该消费方的模型选择；
- 漫画翻译页删除 API/Codex provider 卡片和登录/用量，只显示 LLM 源、模型、漫画策略和独立制图服务；
- 添加/编辑/删除/连接检查属于源详情动作，不在业务页复制按钮；
- 删除被引用的源前明确列出消费者并确认；删除后消费者显示“未配置”，绝不静默选择另一源。

## 迁移

迁移必须幂等并先写新数据再切 consumer binding：

1. 读取旧评论 `apiUrl/apiKey/model` 和漫画 API/Codex 设置；
2. 对完全相同的 API endpoint + credential 只创建一个源；不同配置分别命名为“评论翻译（迁移）”和
   “漫画翻译（迁移）”；比较只在本机内存完成，不记录 Key；
3. 旧漫画 Codex token/账号迁移为一个实验性 Codex 源，保留所选模型与用量缓存作用域；
4. 写入所有 profile/secret 后，再写评论和漫画 binding；任一步失败都保留旧设置可用；
5. 新服务读取 binding，旧键只作为一次性迁移输入，不再双写；稳定一版后另行删除遗留键。

现有评论 `useGoogleOnly` 继续表达业务策略。选择 LLM 源不自动取消 Google-only；LLM 失败后的 Google
回退也只能按现有显式策略执行，不能切换到另一个 LLM 源。

## 数据、安全与备份

- profile 元数据、consumer binding、secret、Codex token、模型目录和用量缓存分别进入持久化 inventory；
- API Key 继续遵循加密备份边界；Codex rotating token 继续完全排除备份/同步；账号用量和模型目录不备份；
- 日志只记录 sourceProfileId/type/revision/model 与脱敏错误，不记录 URL 查询参数、Key、token、账号原文；
- profile/secret 数量、JSON、字段、模型目录和远端响应均保持现有或更严格的大小上限；
- 删除 profile 同时清除其 secret 和可再生成账号缓存，但不删除评论/漫画翻译结果；消费者 binding 变为
  未配置并保留明确缺失状态。

## 实施阶段

### A. 模型与仓库

- [x] 定义有界 profile、capability、secret reference、consumer binding 与 source revision；
- [x] 建立 profile repository 和独立 secret store，补齐 persistence/backup/secret inventory；
- [x] 覆盖多源、稳定 ID、copy isolation、边界输入、删除引用和无静默 fallback 测试。

### B. 传输复用

- [ ] 把 API model catalog、Codex OAuth/token refresh/model catalog/usage 从漫画设置类中抽到 source service；
- [ ] 为 chat-completions、Responses、image input/output 声明能力，不凭 source type 猜模型能力；
- [ ] 评论与漫画通过 source resolution 获取一次性运行配置，服务层不读取彼此 settings。

### C. 幂等迁移

- [x] 用旧设置 fixture 覆盖仅评论、仅漫画 API、两者相同、两者不同、Codex、部分损坏和重入；
- [ ] 先持久新源/secret，再发布 binding；失败保留旧路径，成功后停止旧键双写；
- [x] 不在诊断、fixture 或测试输出中泄露真实 Key/token。

### D. 设置页面

- [ ] 新增同级 LLM 源列表/详情；源详情承载添加、编辑、认证、模型目录、用量和删除；
- [ ] 评论翻译页收敛为策略 + source/model binding；
- [ ] 漫画翻译页收敛为 source/model binding + 漫画业务/制图服务；
- [ ] 保持三个翻译入口层级，不新增“翻译总入口”嵌套。

### E. 验证与清理

- [ ] 评论普通 API、漫画 API、漫画 Codex 和同源双消费者均通过 fake transport；
- [ ] 真机迁移保留设备 `237` 的现有 Codex 登录与模型选择，评论现有设置不丢失；
- [ ] 构建、Hypium、V2、i18n、persistence、secret、backup/sync 门禁通过；
- [ ] 旧专用设置类不再被运行服务读取后，单独提交删除/兼容清理。

## 提交边界

该重构不与 Reader 视觉 UI、sidecar 网络适配或模型真实调用混在同一提交。顺序为：模型/仓库 -> 传输
抽取 -> 迁移 -> UI 消费绑定 -> 旧代码清理。每步都必须保持现有评论翻译和漫画 provider 能回滚验证。
