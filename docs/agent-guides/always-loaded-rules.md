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

## 新 worktree 依赖前置

新建或切换到新的 NextE worktree 后,首次构建、签名、运行、Preview、DevEco/Hvigor 验证前,必须先确认 OHPM 依赖已安装。默认执行:

```bash
ohpm install
```

适用场景:

- 新 worktree。
- `oh_modules` 缺失或被移除。
- `oh-package.json5`、模块依赖、hvigor 依赖发生变化。
- 准备排查 module/package resolution 类构建错误。

不要等 Hvigor/DevEco 报错后才发现依赖缺失。如果 `ohpm install` 因网络、权限、registry 或工具缺失失败,明确报告 `BLOCKED`,不要把后续构建失败误判为源码问题。

## UI / 产品保真

修 bug 时,未经明确要求**不要**改颜色、字体、间距、布局、文案、导航或交互模型。完成前移除所有临时测试脚手架(假请求、mock、诊断 UI)。新颜色需同时覆盖深色 + 浅色。

使用原生控件时,先用控件自身 API 表达状态、轨道、选中态、手柄、按钮动作等行为。不要在原生控件外再叠一层自绘背景 / 轨道 / 命中层去“对齐”系统控件;这会制造两套几何和两套状态,导致端点、触控、颜色或动画错位。只有确认原生 API 无法表达需求时,才允许做最小自绘替代,并必须保持单一状态源。

### 设置项归属纪律

新增或移动任何设置项前,必须先按用户心智归类,不要按实现接线位置归类。根设置页不是“最容易看到”的兜底区,也不是所有全局开关的默认位置。

- 阅读相关进 Reader 设置;下载相关进 Download 设置;搜索相关进 Search 设置;EH / 账号 / 站点相关进 EH / 账号设置;列表、网格、瀑布流、底部栏、导航显示等浏览 / 界面行为进 Layout / 界面 / 导航类设置。
- 根设置页优先放分类入口。只有没有更好归属、且确实跨全应用高频的少数项,才允许直接放根页。
- 新设置项写产品代码前,先检查现有 Settings 分类和 `eros_fe` / Next2V 对应入口语义;不能因为状态 holder 在 `Index`、`Home` 或 shared 层,就把开关放到 Settings 根页。
- 不得用 deterministic contract 锁定尚未经过归属审查的设置位置。contract 只能防止已确认正确的信息架构回退。

### 内容页状态: 禁止 empty-list-first

带网络 / 数据加载的内容页必须以“可展示内容优先”建模,不要在进入、刷新、筛选、切换子 tab 或重新加载时先把列表 / 详情 / 评论 / 种子 / 缩略图数据清空成 `[]` / 空对象,再触发请求。这会造成白屏、空状态闪烁、旧内容丢失,是已多次复发的 UX 事故。

- `items` / `data` 表示最后一次可展示成功内容;`isLoading` / `loadState` / `phase` 表示当前请求状态。不要用“数组为空”替代加载状态。
- terminal empty state 只能在“请求已完成且结果确认为空”后出现。条件必须等价于 `hasLoaded && !isLoading && items.length === 0`,而不是初始 `items.length === 0`。
- refresh、filter reapply、favcat/source/subtab 切换、route reseed 时,优先保留 stale content 并显示 in-body loading / skeleton / dimmed stale 状态。除非切到完全不同实体且没有 seed/cache,不得把整个页面打回空白。
- 首次打开没有任何缓存时可以显示 loading/skeleton;有 seed data 的路由页(例如列表进详情携带 title/thumb/basic meta)必须先渲染 seed,再后台补全。
- reload / paging 失败时保留旧内容并显示 inline error / toast / retry,不要清空页面后只剩错误或空白。
- 禁止在 `loadData()` / `reload()` / `select*()` / `applyFilter()` 开头无条件执行 `this.items = []`、`this.gallerys = []`、`this.comments = []`、`this.thumbnails = []`、`this.data = new ...()` 等清空展示面的写法。若确需清空,必须在代码注释和 contract 中说明它不是用户可见内容面,或说明没有 stale/seed 可保留。

涉及列表、搜索、收藏、评论、all-thumbnails、种子 / 磁力链、详情页、Reader 辅助数据、设置子页等内容页改动时,contract 应覆盖“不闪 terminal empty / 不清空 stale content”的关键路径。

### UI / 功能开工前 grounding

任何新增 UI 或用户可见功能,写产品代码前必须先记录 5 行 grounding:

1. `eros_fe` 对应页面 / 组件 / 方法的具体文件位置,不能只写“参考 eros_fe”。
2. 页面或功能的主信息是什么,用户第一眼应该看到什么。
3. 主动作 / 次动作分别是什么,操作权重必须先定清楚。
4. 本轮做到哪个可用闭环,哪些明确不做,避免只做入口或占位。
5. HarmonyOS / Next2V / HDS 用什么表达方式承接(例如 segmented control、title-bar bottomBuilder、toolbar/menu、FAB、settings row)。

这 5 行答不出来,不要开始写 UI。contract、构建、截图只能作为验证,不能代替产品语义 grounding。截图验收要看层级、间距、动作权重,不只是“控件存在”。

如果同一 UI / 功能连续两轮返工仍未接近产品语义,停止补丁式修修补补,先复盘页面类型、状态归属、导航位置和组件选择;必要时重写局部结构,不要在错误形态上继续堆分支。

### UI 组件结构纪律

写任何可见控件前,先把结构说清楚,再写代码。至少明确:

- 本体层:真正承载信息的对象是什么(色块、图片、文本、滑块轨道、列表行等)。
- 状态层:选中、禁用、加载、错误等状态如何附着到本体上。
- 交互层:点击、长按、拖动、输入等命中区域在哪里,是否改变本体尺寸。

规则:

- 先用系统 / HDS / 已有 shared primitive 表达;不要先手搓。
- `Stack` 只用于明确覆盖层,例如 badge、选中描边、loading overlay。禁止用 `Stack` 猜布局、堆假控件、或把本体 / 状态 / 交互混成一团。
- 选中态、滑块、色块、列表行等基础控件必须先对照参考图 / 参考实现拆出层级和尺寸,不能边写边猜。
- 没有经过截图 / 设备 / 用户确认的视觉形态,不要写 deterministic contract。contract 只锁定已经验收正确的结构,不要把猜测制度化。
- 用户指出局部问题时,只修对应结构层;不要滑坡到整页重写、换组件体系、或撤掉已确认的基线。

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
