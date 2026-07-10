# NextE 始终生效规则

每次涉及 NextE 代码改动都适用。硬约束在前。

## 沟通: 禁止口头承诺 / 口头认错替代行动

出现返工、误改、误解或用户指出规则违反时,不要输出空泛道歉、保证、承诺、复述情绪或自我剖析。只给三类信息:已采取的具体动作、对应文件 / 规则依据、验证结果 / 剩余阻塞。需要改变行为时,把规则写入项目文档或代码约束,不要用口头承诺代替。

## 事故账本: 先读已犯错误

处理 NextE 任务时必须把 `docs/agent-guides/incidents/` 视为始终生效的反例账本。用户指出严重误改、假验证、越权设备操作、范围漂移、或反复同类错误时,必须把事实、原因、后果、后续硬要求写入该目录,并在后续同类任务中按账本约束执行。

- [2026-07-06 Search History Verification Failure](incidents/2026-07-06-search-history-verification-failure.md)
- [2026-07-08 Account Asset Balance Accountability Failure](incidents/2026-07-08-account-asset-balance-accountability-failure.md)
- [2026-07-08 Reader Progress Control Capability Failure](incidents/2026-07-08-reader-progress-control-capability-failure.md)
- [2026-07-08 Reader Loading Contract Abuse](incidents/2026-07-08-reader-loading-contract-abuse.md)
- [2026-07-10 Reader Slider Animation Investigation Failure](incidents/2026-07-10-reader-slider-animation-investigation-failure.md)

## 硬停: 未知即阻断

涉及远端页面解析、账号 / 资产 / 配额数据、EH 写操作、用户可见状态、或 UI 信息层级时,未知事实必须先变成证据,不能用实现推进来覆盖。

- 不知道真实页面 DOM / 文案 / 返回结构时,禁止写 parser。先取得真实 HTML、脱敏片段、现有 fixture、参考实现 selector,或设备 / 日志证据;拿不到证据则报告 `BLOCKED`。
- 不知道用户会如何理解信息主次时,禁止写 UI。先明确主信息、同级信息、主次动作和用户第一眼读法;答不出来就停在 grounding,不能套现有组件模板。
- 不知道真实用户路径是否成立时,禁止说完成。构建、静态 contract、代码存在只证明实现候选;用户可见功能必须用截图 / layout / 日志 / fixture / 设备路径证明。
- 不知道 contract 是否保护稳定边界时,禁止新增 contract。不要把未知、猜测、示例数字、视觉偏好或临时 workaround 制度化。
- 对资产、余额、配额、Cookie、写操作等高风险数据,解析不到或证据不足只能显示明确失败 / 不可用,但不能把这种失败包装成已完成。

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

## 非预期逻辑排查: 先静态对比,再上机验收

应用出现非预期逻辑、回归或与 `eros_fe` 行为不一致时,不要先靠反复装机 / 截图 / 滑动来穷举。先做静态逻辑排查,把差异说清楚再改代码。

- 先定位同一行为在 `../eros_fe` 的具体文件 / 方法 / 参数构造 / parser 取值方式,并对照 NextE 当前实现。不能只写“参考 FE”。
- 先回答四个问题:旧逻辑怎么工作;哪次改动改掉了什么;改动当时想解决什么;为什么该差异会导致当前症状。
- 对 EH 请求、分页、parser、收藏 / 标签 / 搜索 / 阅读状态等行为,必须优先比较 URL 参数、游标 / page / from、DOM selector、字段含义、状态推进条件。设备日志只能验证这些静态结论,不能替代结论。
- 找不到静态原因前,不要补丁式改参数、换组件、加 workaround、或扩大重构范围。确需临时诊断 UI / 日志时,必须标记为临时,用完移除。
- 修复后用 contract 锁住已经确认的差异点,例如“完整游标 token 不能被截断”“FE 的 page/from 优先级保持一致”。再用模拟器 / 真机验证用户路径。

### 用户可见功能验收纪律

任何用户可见功能、页面、交互、状态流、网络动作、缓存 / 同步 / 下载 / 搜索 / 阅读 / 设置能力,都不能用“代码已写 / contract 通过 / 页面存在 / 口头解释”替代可用性验收。实现或修复这些能力时,必须先写清楚用户路径,再用静态逻辑、日志、截图 / layout、构建和设备证据证明路径成立。

- 最小验收单位是用户路径,不是文件、函数、组件或 contract。必须说明用户从哪里进入、点什么、看到什么状态变化、最终完成什么结果。
- 有日志点的链路必须先看日志再判断。按钮是否触发、任务是否入队、请求是否发出、状态是否写回、缓存是否命中,以 `DiagnosticLogger` / hilog 为主证据;截图只证明 UI 外观。
- 每次声称“完成”前必须列出已验证的真实路径和证据文件 / 日志事件。缺少黑盒路径证据时,只能说 `implemented candidate / needs QA`,不能说完成。
- 不能因为某一类功能单独列了细则,就把其他用户可见功能排除在验收外。下面的下载 / 归档细则只是高风险例子,不是例外列表或白名单。
- 涉及远端账号写入、资源消耗、不可逆状态或用户数据变更的动作,默认只验证到确认框或本地无害边界;未经用户明确授权不得点击确认。
- 如果连续两轮仍未跑通用户路径,停止继续堆补丁,回到 `eros_fe` 对照、日志链路和当前调度文档,把失败原因和下一条最小验证动作写清楚。

下载 / 归档的具体闭环要求:

- 硬停:禁止使用 ArkUI `DownloadFileButton`。NextE 下载入口必须保留项目现有按钮 / 半模态语义;公共 Download 目录获取只允许走 `DocumentViewPicker.save()` + `DocumentPickerMode.DOWNLOAD` + `fileUri.FileUri(...).path` 的路径。`DocumentPickerMode.DOWNLOAD` 返回的就是系统分配给当前应用的 Download 目录,不得再拼接 `NextE` 等应用名子目录,也不得把该根目录写入 Preferences / 同步 / 备份作为用户设置持久化。
- 普通画廊下载:详情页下载入口可见并可点击 → 日志出现 `detail_download_tap` / `detail_enqueue_request` → 任务进入下载队列 → 日志出现 `gallery_download_start` / `gallery_download_batch_done` 或明确失败原因 → 下载页进度文本和进度条实时更新 → 完成后从下载页进入本地 Reader → Reader 继承同一 `GalleryReadProgressState` 阅读记录。
- 归档下载:详情页 `归档`入口按 `eros_fe` 行为可见 → 点击后日志出现 `detail_archiver_open` → 归档半模态加载报价或明确显示缺少 `or` 参数的错误并记录 `archiver_missing_or_token` → 报价面板展示 Download / H@H 选项 → 真实提交前必须停在确认框,除非用户明确授权消耗账号资源 → 本地归档下载任务进入归档队列并有 `archiver_download_start` / `archiver_download_done` 或失败日志。

### Contract 使用纪律

Contract 只允许用于会造成严重影响的稳定边界。默认不新增,也不得把每个 bug、UI 细节、返工记录、口头例子或临时实现写成 contract。

允许场景仅限以下几类:

- 平台硬红线:状态管理 V1 禁止、ArkTS/架构边界、构建/签名/版本一致性。
- 安全与隐私:凭据泄露、Cookie/session 处理、诊断日志脱敏、会被打包或导出的敏感数据。
- 数据破坏或远端写操作:评分、收藏、评论、标签、归档请求、同步/备份/恢复、RDB/Preferences 持久化与迁移。
- 高风险远端协议/parser:真实 fixture 支撑的 EH HTML/API 字段、分页游标、图片解析、错误分类等,其失败会导致主要链路不可用、错误写入或资源浪费。
- 设备/自动化互斥:会影响真机控制、租约、构建环境的硬约束。

明确禁止:

- UI 视觉、布局、文案、入口位置、按钮样式、间距、圆角、图标选择、loading 文案、截图观感类 contract。
- grounding、产品语义、信息架构、用户路径验收类 contract。它们必须写成文档、截图、日志或设备验证记录,不能做成正则门禁。
- 单次事故的补偿性 contract、临时 workaround contract、为证明自己改过而新增的 contract。
- 无真实 fixture 或无可复现严重后果的 parser 猜测 contract。

新增或扩展 contract 前必须同时满足:能说清严重影响是什么;已有构建、现有测试、日志、截图、人工/设备路径不能覆盖;失败时修复方向明确。任一条件不满足就不能加。用户指出 contract 滥用时,先删减同域低价值 contract,再继续当前任务验证。

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

使用原生控件时,先用控件自身 API 表达状态、轨道、选中态、手柄、按钮动作等行为。不要在原生控件外再叠一层自绘背景 / 轨道 / 命中层去“对齐”系统控件;这会制造两套几何和两套状态,导致端点、触控、颜色或动画错位。

### 硬停: 自绘组件必须由用户明确授权

任何页面、功能和交互场景都禁止主动创建自绘组件、仿原生控件或自绘替代层。只有用户针对当前需求明确说“可以自绘”或给出等价的明确授权后,才允许进入自绘方案;沉默、原生能力暂未查明、现有实现难改、首次修复无效、构建通过或代理认为自绘更灵活,都不构成授权。

- 未获明确授权时,只能继续调查并使用系统 / HDS 控件、项目已有组件或对已有组件做窄参数扩展;这些路径仍无法实现时,报告 `BLOCKED` 和证据,不得自行转向自绘。
- 在方案、实现或评审中发现未授权自绘时,立即停止并移除该候选,回到原生 / 已有组件链路;不得以“已写完”“只是一层轨道 / 命中层 / overlay”作为保留理由。
- 用户只对某一个明确场景授权自绘时,授权不得扩展到其他页面、组件或后续需求。

### 设置项归属纪律

新增或移动任何设置项前,必须先按用户心智归类,不要按实现接线位置归类。根设置页不是“最容易看到”的兜底区,也不是所有全局开关的默认位置。

- 阅读相关进 Reader 设置;下载相关进 Download 设置;搜索相关进 Search 设置;EH / 账号 / 站点相关进 EH / 账号设置;列表、网格、瀑布流、底部栏、导航显示等浏览 / 界面行为进 Layout / 界面 / 导航类设置。
- 根设置页只放分类入口,禁止把单个零散设置项直接放根页。只有用户明确要求根页直放时例外。
- 新设置项写产品代码前,先检查现有 Settings 分类和 `eros_fe` / Next2V 对应入口语义;不能因为状态 holder 在 `Index`、`Home` 或 shared 层,就把开关放到 Settings 根页。
- 不得用 deterministic contract 锁定设置位置。设置归属只能通过产品语义、参考实现、截图 / layout 和用户路径记录验收。

### 内容页状态: 禁止 empty-list-first

带网络 / 数据加载的内容页必须以“可展示内容优先”建模,不要在进入、刷新、筛选、切换子 tab 或重新加载时先把列表 / 详情 / 评论 / 种子 / 缩略图数据清空成 `[]` / 空对象,再触发请求。这会造成白屏、空状态闪烁、旧内容丢失,是已多次复发的 UX 事故。

- `items` / `data` 表示最后一次可展示成功内容;`isLoading` / `loadState` / `phase` 表示当前请求状态。不要用“数组为空”替代加载状态。
- terminal empty state 只能在“请求已完成且结果确认为空”后出现。条件必须等价于 `hasLoaded && !isLoading && items.length === 0`,而不是初始 `items.length === 0`。
- refresh、filter reapply、favcat/source/subtab 切换、route reseed 时,优先保留 stale content 并显示 in-body loading / skeleton / dimmed stale 状态。除非切到完全不同实体且没有 seed/cache,不得把整个页面打回空白。
- 首次打开没有任何缓存时可以显示 loading/skeleton;有 seed data 的路由页(例如列表进详情携带 title/thumb/basic meta)必须先渲染 seed,再后台补全。
- reload / paging 失败时保留旧内容并显示 inline error / toast / retry,不要清空页面后只剩错误或空白。
- 禁止在 `loadData()` / `reload()` / `select*()` / `applyFilter()` 开头无条件执行 `this.items = []`、`this.gallerys = []`、`this.comments = []`、`this.thumbnails = []`、`this.data = new ...()` 等清空展示面的写法。若确需清空,必须在代码注释和验证记录中说明它不是用户可见内容面,或说明没有 stale/seed 可保留。

涉及列表、搜索、收藏、评论、all-thumbnails、种子 / 磁力链、详情页、Reader 辅助数据、设置子页等内容页改动时,优先用用户路径、日志和截图证明“不闪 terminal empty / 不清空 stale content”。只有会造成严重数据丢失、错误写回或主要链路不可用时,才允许用 contract 锁定。

### UI / 功能开工前 grounding

任何新增 UI 或用户可见功能,写产品代码前必须先记录 5 行 grounding:

1. `eros_fe` 对应页面 / 组件 / 方法的具体文件位置,不能只写“参考 eros_fe”。
2. 页面或功能的主信息是什么,用户第一眼应该看到什么。
3. 主动作 / 次动作分别是什么,操作权重必须先定清楚。
4. 本轮做到哪个可用闭环,哪些明确不做,避免只做入口或占位。
5. HarmonyOS / Next2V / HDS 用什么表达方式承接(例如 segmented control、title-bar bottomBuilder、toolbar/menu、FAB、settings row)。

这 5 行答不出来,不要开始写 UI。contract、构建、截图只能作为验证,不能代替产品语义 grounding。截图验收要看层级、间距、动作权重,不只是“控件存在”。

如果同一 UI / 功能连续两轮返工仍未接近产品语义,停止补丁式修修补补,先复盘页面类型、状态归属、导航位置和组件选择;必要时重写局部结构,不要在错误形态上继续堆分支。

### 半模态 / 设置列表 UI 纪律

涉及半模态、设置页、管理页、选择列表、确认 / 编辑面板时,写代码前必须先找项目内同类实现并说明复用关系。这里不是组件黑白名单;约束目标是先理解项目已有表达方式,再决定是否需要新结构。

- 先判断页面类型和信息层级:这是表单、设置列表、选择列表、操作区,还是内容阅读面板。主信息、主动作、次动作必须先定清楚。
- 优先复用项目已经稳定的外壳、列表行、按钮、分组和滚动结构。只有已有结构无法表达当前语义时,才做局部 wrapper 或窄参数扩展。
- 偏离现有实现时必须写清楚原因和证据:参考文件是什么、默认行为哪里不满足、截图 / 设备 / 源码证据是什么。说不清就不要偏离。
- 不要把视觉猜测写成布局参数。高度、padding、字号、颜色、safe-area、键盘避让、动画、press 态等都应来自现有模式或真实问题;不能用“看起来更稳”作为理由。
- 多层半模态、滚动内容、底部操作区等平台已经负责承载的行为,先保留系统 / 项目默认机制。只有复现到具体错误后,才做最小修正。
- 截图验收必须看结构是否像同类页面,不是只看控件是否出现。未经过截图或用户确认的形态,不得写成门禁;已经确认的形态也只能记录为验收证据,不能升级成 UI contract。

禁止把 UI grounding 做成可执行 contract。UI grounding 只能作为开工前的文档记录和收尾时的截图 / layout / 日志验收依据。

### UI / 交互验收 Definition of Done

任何 UI / 交互改动,实现者不能自行用“控件存在”判定完成。写代码前先列用户路径,验收时必须覆盖最容易坏的反例状态。

- 开工前写清楚一条真实用户路径:从哪个页面进入、点什么、焦点 / 键盘 / 滚动 / 弹层 / 返回如何变化、最终用户看到什么。
- 同时列至少 3 个反例状态,例如键盘打开、回复 / 编辑态、长文本、多行输入、小屏 / 折叠屏外屏、加载中、空数据、滚动后、隐藏 chrome、缓存命中。
- 截图 / layout 证据必须覆盖关键状态。输入组件必须有键盘打开截图;浮动组件必须证明位置、避让和遮挡;手势组件必须证明隐藏层不会拦截;列表组件必须证明极端内容不破版。
- 未覆盖关键反例时,只能标记为 `implemented candidate / needs QA`,不能写成 `implemented / pending acceptance`。
- 如果用户截图打回,对应条目必须改成 `reopened / failed QA`,并把失败截图暴露出的静态原因和新的验收条件写回 domain intake / dispatch。

### Reader / 图片手势与清晰度验证纪律

阅读器、图片预览、缩放、清晰度、双击 / 双指 / 拖动手势属于高风险交互面。这里的修复不得靠删动画、删 `renderGroup`、改清晰度参数、换 transform 顺序等猜测式手段推进。

- 先找官方 HarmonyOS 图片手势 / PinchGesture / 图形变换示例,以及项目内当前实现的确切差异;不能把 Next2V / eros_fe 当作天然正确答案。
- 双击缩放动画、清晰度渲染、图片缓存、原图 / 普通图切换等已确认可用行为,未经独立证据不得删除、降级或绕开。
- 任何 reader 手势改动必须覆盖真实用户路径:先双击放大,再双指缩放;先双指缩放,再拖动;缩放后翻页再返回;单页和双页至少说明是否都覆盖。
- 验收必须由实现者自行完成,并产出连拍截图、录屏或等价逐帧证据;只跑静态 contract / 构建不能声明手势已修复。
- 图片清晰度改动必须证明同一张图、同一位置、同一缩放倍率下 reader 与保存到相册 / 源文件的对比结果;不能用旧缓存、错误画廊或无法证明源分辨率的样本代替。
- 如果当前工具不能合成双指手势或无法录屏,只能报告 `implemented candidate / needs manual QA`,不得声称已通过黑盒验证。
- 找不到静态原因、拿不出理论证明、或没有黑盒证据时,结论必须写成 `BLOCKED` / `needs QA` / `not verified`;禁止说“已修复”“没问题”“验证通过”。

### UI 组件结构纪律

写任何可见控件前,先把结构说清楚,再写代码。至少明确:

- 本体层:真正承载信息的对象是什么(色块、图片、文本、滑块轨道、列表行等)。
- 状态层:选中、禁用、加载、错误等状态如何附着到本体上。
- 交互层:点击、长按、拖动、输入等命中区域在哪里,是否改变本体尺寸。

规则:

- 只用系统 / HDS / 已有 shared primitive 表达。没有用户对当前需求的明确授权,禁止手搓或自绘任何替代组件;无法满足时按上方硬停规则报告 `BLOCKED`。
- 组件属性采用最小集。先写“能正确工作的最少属性 / 参数”,再按确切问题逐项增加。每新增一个布局、尺寸、padding、height、lineHeight、align、clip、overlay、state workaround 等属性,必须能说明它解决的具体问题;说不清就不加。
- 不要为了“看起来更稳”预防式堆属性。平台控件、HDS 控件和 shared primitive 的默认测量 / 内边距 / 动画 / 命中区优先保留;只有设备或源码证据证明默认行为不满足需求,才做最小覆盖。
- 修局部问题时先删掉自作的额外属性,验证平台默认是否已经正确。不要在错误属性之上继续补偿式叠加新属性。
- `Stack` 只用于明确覆盖层,例如 badge、选中描边、loading overlay。禁止用 `Stack` 猜布局、堆假控件、或把本体 / 状态 / 交互混成一团。
- 选中态、滑块、色块、列表行等基础控件必须先对照参考图 / 参考实现拆出层级和尺寸,不能边写边猜。
- 没有经过截图 / 设备 / 用户确认的视觉形态,不得写成门禁。已经验收正确的结构记录为证据即可,不要把视觉判断制度化成 contract。
- 用户指出局部问题时,只修对应结构层;不要滑坡到整页重写、换组件体系、或撤掉已确认的基线。

### 输入 / Composer 控件纪律

评论框、回复框、搜索框、备注框等输入控件,默认信任平台 / HDS 的自然文本布局。不要为了“看起来居中”先手算输入高度、行高、滚动高度、placeholder 偏移或键盘偏移。

- 先使用 TextInput / TextArea / HDS 输入控件自身能力和现有成熟实现,再考虑外层布局。改动前先查项目内同类可用实现,例如 Next2V / NextE 已验证输入框。
- 禁止添加不存在或未确认的 ArkUI 属性;不确定先查 SDK / harmony-next skill / 编译,不要猜。
- 禁止用透明背景、额外 Stack、假轨道、假 padding 遮盖错位。背景只用于设计表达,不能用来隐藏文本布局错误。
- 单行输入应由控件自然垂直居中;多行输入应自然扩展到约定最大行数后再滚动。不要用手写 `height = lineCount * lineHeight + padding` 作为第一方案。
- 键盘避让优先使用 ArkUI 原生机制,例如 `KeyboardAvoidMode.RESIZE` 或 sheet 原生 keyboard avoid mode。`keyboardHeight` 只能作为状态信号,不得作为内部大 padding / 大 offset。
- 如果删掉自作的高度 / 行高 / padding 后问题消失,保持删除结果,不要再补一层“修正”逻辑。

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
