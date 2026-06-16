你正在为 HarmonyOS NEXT 应用 **NextE** 开发功能。以下规则违反将无法编译,或在 Dart→ArkTS 移植 eros_fe 时埋下隐患,务必遵循。

## ArkTS / ets 语法硬约束(违反将无法编译)

ArkTS 是 TypeScript 的受限方言,许多 TS 写法**编译不通过**。下列为高频踩坑项(完整列表见 [HarmonyOS 官方 ArkTS 约束](https://developer.huawei.com/consumer/cn/doc/),与 V2Next `docs/agent-guides/harmonyos-default.md` 同源):

- 不支持 `any` / `unknown`。请显式指定类型;`catch` 子句**省略**类型标注(不能写 `catch (e: unknown)`)。
- 不支持解构(参数 / 赋值 / 声明):`const { a, b } = obj`、`function f({x})`、`[a, b] = arr` 全部禁止。改用临时变量逐字段取值。**移植 eros_fe 的每个 model 时,必须逐字段手写,不能解构/展开。**
- 展开运算符仅支持 `数组 → rest 参数 / 数组字面量`;对象展开 `{...o}` 禁止。手动逐字段拷贝(在 model 上写 `copy()` / `merge()` 方法)。
- 不支持动态/索引字段访问 `obj['field']`。类型化数组(`Int32Array` 等)除外。请用 `obj.field`,字段在类中预先声明。
- 不支持 `for..in`。对象遍历用预声明字段;数组用常规 `for` 或 `forEach`。
- 不支持函数表达式与嵌套函数。用箭头函数;独立函数/静态方法中**禁止 `this`**。
- 不支持 `Function.bind/call/apply`。遵循传统 OOP。
- 不支持 `globalThis` / 全局作用域共享。用显式 `export`/`import`。
- 不支持索引签名 / 映射类型 / 条件类型 / 交叉类型 / `infer` / `as const`。用 class、interface、继承重写。
- 对象字面量必须能推断到一个具体的 class 或 interface;不能用于 `any`/`Object`、带方法的类、带参构造的类、带 `readonly` 字段的类的初始化。**请为每个数据结构显式声明 class / interface。**
- 工具类型仅 `Partial` / `Required` / `Readonly` / `Record` 可用;`Record<K,V>` 的 `rec[k]` 类型为 `V | undefined`。
- `var` 禁止,用 `let` / `const`;`enum` 成员只能用同类型编译期常量初始化。
- 所有 `import` 必须位于文件顶部、其它语句之前。
- 删除属性无意义(对象布局编译期固定);用可空类型 + 赋 `null` 表达"缺失"。

## HarmonyOS API 使用规范(必读)

- **遇到不确定的 ArkTS / ArkUI / NDK API,先用 `harmony-next` skill 或官方文档确认,不要猜 API 形状。** 这是 NextE 的硬规定(与 V2Next 一致)。
- 调 API 前确认:入参/返回值/API Level/设备支持;是否需要 `import`;是否需要在该模块 `module.json5` 声明权限;是否需要在 `oh-package.json5` 加依赖。
- 状态管理只用 V2(见 always-loaded-rules):`@ComponentV2` / `@ObservedV2` / `@Trace` / `@Local` / `@Param` / `@Monitor` + AppStorageV2 holder。**禁止任何 V1 装饰器。**
- UI 中的尺寸/颜色/字号常量统一走 `ThemeConstants`(`shared/theme`),不写字面值;颜色优先用 `$r('sys.color.*')` 系统令牌,自定义色必须同时覆盖浅色 + 深色。
- 用户可见字符串走 i18n 资源(entry/ + AppScope/,语言 base + zh_CN + en_US + ja_JP),新增 key 必须四个语言同步,保持 key 集一致(`scripts/check_i18n_duplicates.py` 校验)。注意:EH 标签翻译是**独立的 TagTranslationService**,不是平台 i18n。

## EH 移植专项约束

- **解析器**:不引入任何外部 HTML 库,用内置正则/DOM 遍历(与 V2Next parser 一致)。重解析放到 **TaskPool worker**(ArkTS 版 `compute()`);worker 不能共享类实例,只能传可序列化数据。
- **图片内存**:整图多 MB,**绝不**在内存缓冲或走 webview/base64;用 `@ohos.net.http` 流式落盘,`@ohos.multimedia.image` 按 `sampleSize/desiredSize` 解码限制位图内存。
- **CSS sprite 魔法常量**:评分 `(80-x)/16 - (y==21?0.5:0)`、favcat `(pos-2)/19` 等绑定 EH 实时页面结构,移植后必须用真实 fixture 验证再依赖。
- **509 / 429**:整图每 IP 一次性 token,509(配额耗尽)需走 `nl=` 换源重取,与 429(限流)区别处理。

## ArkUI 动画规范

- 优先用原生动画 API;用状态变化(`@Local`/`@Trace` 改值)驱动动画。
- 复杂子树设 `renderGroup(true)` 降渲染批次。
- **动画过程中不要频繁改 `width`/`height`/`padding`/`margin`** 等布局属性,严重掉帧——这正是 eros_fe 在 Flutter 上的滑动掉帧痛点,原生重写时不要重蹈覆辙。
