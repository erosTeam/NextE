# HarmonyOS / ArkTS / ArkUI 约束

本文件只负责平台和 UI 实现约束。产品语义与验收流程见 [Product work](product-work.md)，本地构建
与工具见 [Local development](local-development.md)。

## ArkTS 受限语法

- 不使用 `any` / `unknown`；`catch` 省略类型标注。
- 不使用参数、声明或赋值解构；移植 model 时逐字段读取和赋值。
- 对象展开 `{...o}` 禁止；model 用显式 `copy()` / `merge()`。
- 不使用动态字段访问 `obj['field']`、`for..in`、索引签名、映射/条件/交叉类型、`infer`、
  `as const`、`globalThis`、`Function.bind/call/apply`。
- 不使用函数表达式或嵌套函数；使用箭头函数。独立函数和静态方法中不使用 `this`。
- 对象字面量必须能推断为明确 class/interface；数据结构预先声明类型。
- `var` 禁止；import 位于文件顶部；对象字段“缺失”用可空类型和 `null` 表达。
- `Record<K,V>` 索引结果按 `V | undefined` 处理；enum 成员只用同类型编译期常量初始化。

## 状态管理 V2

- `entry/`、`feature/`、`shared/` 只使用 `@ComponentV2`、`@ObservedV2`、`@Trace`、`@Local`、
  `@Param`、`@Monitor` 和项目 state holder。
- 禁止 V1 适配器、allowlist、临时桥接和通过时间戳/随机 key 强制重渲染。
- 跨组件信号使用明确所有权的状态 holder 或单写者命令总线，不把 UI 生命周期当数据仓库。
- ArkTS/UI/状态改动必须运行 `node scripts/test_v1_decorator_inventory_contract.mjs` 并得到
  `0 file(s)`。

## API 与模块边界

- 不确定的 ArkTS/ArkUI/NDK/DevEco API 先用 `harmony-next` skill 或华为官方文档确认；核对 API
  Level、设备支持、import、权限、`module.json5` 和依赖声明。
- `shared` 不依赖 feature/entry；feature 之间不互相 import；跨 feature 编排由 `entry` 负责。
- EH 重解析放 TaskPool，worker 只接收可序列化数据。图片下载流式落盘，不经 WebView/base64 或
  长期整图内存缓冲。

## 原生 UI 与设计系统

- 优先使用系统/HDS 控件和项目已有组件。未得到用户针对当前需求的明确授权，不新增自绘控件、
  仿原生控件、额外命中层或自绘轨道；原生能力不足时先给出源码/文档证据和可选方案。
- 尺寸、颜色、字号和圆角使用 `ThemeConstants` / `EhSemanticColors` / 系统资源；新增颜色同时覆盖
  明暗主题。用户可见字符串进入 base、zh_CN、en_US、ja_JP 四套资源。
- 修复功能问题时不顺手改变颜色、字体、间距、布局、文案、导航或交互模型。
- 设置项按用户心智归类，根设置页只放分类入口；半模态、设置页、管理页和选择列表先查项目内
  同类实现，再决定是否需要局部扩展。
- 一个 ArkUI 触发节点只拥有一个 `bindMenu` 或 `bindSheet`；弹层必须绑定到实际触发按钮，不用
  脱离触发节点的代理容器。
- 原生动画由状态变化驱动；复杂子树可用 `renderGroup(true)`。动画期间避免频繁改变 width、
  height、padding、margin 等布局属性。

## 内容与交互状态

- 内容页以“最后一次可展示内容 + 独立加载状态”建模。刷新、筛选、分页和重载不得先无条件清空
  可见数据；terminal empty 只在请求完成且结果确认为空时出现。
- 有 seed/cache 时先展示，再后台补全。分页或刷新失败保留旧内容并给出 inline error/toast/retry。
- 输入、键盘、滚动、弹层和手势必须有单一所有者；不要叠加多套命中层、滚动容器或键盘避让。
- Reader 图片手势、缩放、清晰度和缓存改动必须保留已确认行为，并用真实交互序列验证；构建和
  源码形状不能替代手势证据。

## 平台验证

- 新增 i18n key 后运行 `python3 scripts/check_i18n_duplicates.py`。
- HDC/hilog 命令保持可复现：`hilog -x` 与 `hilog -z` 不组合；远端 shell 过滤符正确转义。
- UI 验收标准和状态标签遵循 [Product work](product-work.md)，设备控制遵循
  [Device lease](../device-lease.md)。
