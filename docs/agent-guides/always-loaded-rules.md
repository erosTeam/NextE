# NextE 始终生效规则

每次涉及 NextE 代码改动都适用。硬约束在前。

## 硬停: 仅用状态管理 V2

State Management V1 在本项目**已废弃**。`entry/`、`feature/`、`shared/` 中禁止引入或恢复任何 V1 组件/状态装饰器:`@Component`、`@State`、`@Prop`、`@Link`、`@Watch`、`@StorageLink`、`@StorageProp`、`@Provide`、`@Consume`、`@ObjectLink`、`@Observed`(裸)、`@Track`、`@LocalStorageLink`、`@LocalStorageProp`。

只用 V2:`@ComponentV2`、`@ObservedV2`、`@Trace`、`@Local`、`@Param`、`@Monitor`,以及项目 state holder(`AppStorageV2.connect` + `@ObservedV2`/`@Trace`,key 为 `'v2:<name>'`)。跨组件信号用**单写者命令总线**(带时间戳的唯一 payload + `@Monitor` 响应),参考 `shared/state/NavStackHolder.ets`、`PendingEhUrlState.ets`。

不得添加 V1 适配器、白名单、临时桥接、key churn 刷新 hack(`Date.now`/随机数/版本号强制重渲染)。若某改动看似必须用 V1,**停下并报告 `BLOCKED`**,给出源码/构建证据和 V2-only 替代方案。

任意 ArkTS/UI/状态改动前后,必须跑通门禁(报 `0 file(s)`):
```bash
node scripts/test_v1_decorator_inventory_contract.mjs
```

## 数据流分层与边界

```
EhHttpClient → EhApiService/EhApiPhpService → parser(正则/DOM) → model
  → feature ViewModel(@ObservedV2) → AppStorageV2 state holder → @ComponentV2 page
```

- feature 模块**互不导入**;跨 feature 交互只经 `shared/` state holder + `entry` 导航。
- `shared` 是零依赖叶子;`feature/*` 只依赖 `shared`;`entry` 编排一切。
- parser 是最脆弱层(EH 页面结构一变就坏)——每个 parser 配 `scripts/test_*_parser_contract.mjs` + 真实 HTML fixture。
- 不在组件里硬编码尺寸/颜色/字号,走 `ThemeConstants`;用户可见字符串走 i18n 资源。

## UI / 产品保真

修 bug 时,未经明确要求**不要**改颜色、字体、间距、布局、文案、导航或交互模型。完成前移除所有临时测试脚手架(假请求、mock、诊断 UI)。新颜色需同时覆盖深色 + 浅色。

## 破坏性写操作(EH)

评分(rategallery)、收藏(addfav)、发表/回复评论、点赞/踩评论(votecomment)、打标签(taggallery/setusertag)、归档下载请求等是**非幂等**写操作。默认验证方式为非破坏性:打开对话框 → 取证 → 取消,不真正提交。真正提交需获授权,且应优先在自己的测试画廊上验证,避免污染他人内容/触发风控。

## 登录 / Cookie 安全

- EH 登录靠 Cookie(`ipb_member_id`/`ipb_pass_hash`,里站另需 `igneous`)。凭据只从本地 `.env.local` 或用户在应用内 WebView 登录获取。
- **绝不**打印、提交、或粘贴到对话中:cookie、`ipb_pass_hash`、`igneous`、`sk`。日志经 `DiagnosticsRedactor` 脱敏。
- 不向用户索要密码/cookie。
- 不把任何凭据放进 `entry/src/main/resources/rawfile/` 等会被 HAP 打包的资源目录；`.gitignore` 不是打包隔离。

## 提交规范

- Conventional Commits,**英文** `type(scope): description`(`feat`/`fix`/`refactor`/`style`/`docs`/`chore`/`perf`)。bug 修复、parser/网络改动、写操作附 Why/What/Validation。
- 提交信息绝不含 cookie、token、密码。
- 未明确要求**不要提交**。
- 注释用英文,解释 *why*(产品约束、平台怪癖、状态不变量),非 *what*。

## 不确定就查

任何拿不准的 ArkTS/ArkUI/NDK API、DevEco/hdc/hilog 操作,用 `harmony-next` skill 或官方文档确认,**不要猜**。
