# /loop —— NextE 对标 eros_fe 的开发驱动提示词

> 这份文档就是 `/loop` 的提示词本体。每轮开工前从头读一遍,按它执行。
> 它的存在是为了**约束行为**:把反复犯的错写成红线,违反即停。

---

## 0. 一句话目标

把 NextE 的每个页面对标 **eros_fe**(功能 / 架构 / 页面结构 / 精心逻辑全部对齐),
用**原生 HDS + V2Next 经验**呈现,做到与 eros_fe / V2Next **同级**。
**视觉与页面设计的质量,优先级高于后台逻辑。**

参考物三方定位(分工不同,别混用):
- **eros_fe**(`/home/gamer/git/eros_fe`,Flutter)= **规格 / SPEC**:要做什么、功能是否完整、页面结构与交互协调怎么安排、**比例/结构性的安排为什么这么定**。实现与处理的答案在它的源码里(但具体像素尺度按原生来,见 §2.3)。
- **V2Next**(`/home/gamer/git/V2Next`,HarmonyOS)= **怎么用原生做 / HOW**:同一个东西在 ArkUI/HDS 里的原生写法、组件、占位、状态。**抄它,别从零自创。**
- **截图**(eros_fe 真机 + NextE 真机)= **最终视觉确认**,不是实现依据。

---

## 1. 每一轮怎么做(工作循环)

1. **读 `docs/parity-driver.md`**(进度源,是"活的假设")。发现它漏的 / 错的 / 过时的,就改它、补它、重排。
2. **选这轮啃哪块**:自己判断——一整页做透,或一簇相关差距。**别为凑数做原子小补丁;该整页重构就整页重构。**
3. **开工自检**(见 §2 红线 + §8 开工前清单)。
4. **先查源码,再动手**。每个改动都要说得清理由(§2.3),不许拍脑袋/编造源码里没有的东西。
5. **改**。能抄 V2Next 就抄,别自创。
6. **验证闭环**(§4):逻辑→契约测试+构建+装饰器门禁;视觉→真机截图做四源对抗审查。
7. **记录**(§5):进度写回 driver.md;视觉取向 + 对比截图 + 理由写进 `docs/parity-visual-review.md`。
8. **提交**(§5):这一轮验证+记录都做完后,`git commit` 本轮改动。一轮一提交,信息写清楚。
9. 还有可做项就**不许停**;**绝不自报"做完"**——只报"已验证到 X 程度,证据是 Y"。

每轮起一个 workflow 来组织这一轮的工作。

---

## 2. 铁律 / 红线(违反即停,`BLOCKED` 上报)

这些是反复犯、被纠正、又退回去的错。每条都当成硬约束:

1. **源码与截图不是互斥的,必须同时用。**
   - 实现 / 处理 / 数值 / 样式的答案在**源码**里(eros_fe 源码、V2Next 源码、NextE 自己的代码与数据)。
   - **截图只用来做最终视觉确认**,绝不用来推断实现、更不能据截图去改逻辑。
   - 病症:一看截图就不看代码,一看代码就不看截图。**根治:任何视觉/实现结论,先在源码里坐实,再用截图确认。两边都要看。**

2. **先查再说,不先猜后查。** 任何"它应该长这样 / 应该是这个值 / 应该有个描边"——先去源码查证,查到了再写。**不许把脑补当事实。**(描边那次:eros_fe `TagItem` 源码里根本没有 border,我却凭"chip 应该有描边"写了 `borderWidth(1)`。)

3. **不许拍脑袋定值,但也不是照抄 eros_fe 的像素。** 要禁的是**无理由的脑补/近似值**,不是"跟源码不一样"。每个取值二选一,且**说得清为什么**:
   - **(a) 结构/比例性决策——尊重 eros_fe 的*意图*。** 例:封面宽 = 屏短边 / 3(这是个**比例**决策,不是魔数)、封面贴左撑满、两端对齐布局、信息分组与层级、有没有占位/加载。先去源码搞懂它**为什么**这么安排,再用原生方式表达同一意图。这类**别乱改**。
   - **(b) 具体像素量(字号/圆角/padding/间距)——按原生定,够协调就行。** 优先 `ThemeConstants` token + HDS/V2Next 审美;**不必等于 eros_fe 的 14.5 / 4 / 12**。原生有自己的尺度,硬抄 Cupertino 像素反而是另一种像素复刻(违反 §6)。
   - 真正的红线是 §2.2 那种**编造源码里没有的东西**(凭空多个 border);"尺度跟 eros_fe 不同但协调、且说得清理由"是允许的。

4. **禁止用文本符号 / emoji 冒充 UI。** 勾、图标、徽章、指示器、控件一律用原生:`SymbolGlyph($r('sys.symbol.X'))` / `SymbolGlyphModifier` / 原生控件(Radio/Checkbox/Slider/HDS Menu 自带勾)。文本里作为**词义**的符号(如方向标 `左→右`)不算。

5. **列表标签默认中性灰,绝不按命名空间/分类染色。** 真正的 per-tag 颜色只来自用户在「我的标签」里的自定义色值(`SimpleTag.color/backgroundColor`,需 usertag 库)。看到 F1 列表标签有颜色就断定"按分类染色"是反复犯的错——已被真机+源码双重证伪。

6. **不要像素复刻 eros_fe。** 它是 Flutter/Cupertino,我们是原生 HDS。参考它的**功能、功能完整性、UI 协调**,然后用原生做出同级质量。视觉有差异是正常且应该的。

7. **只用中文跟用户交流。** 解释、确认、汇报、提问、道歉一律中文,**一个英文词都不夹**(代码标识符/文件名/commit 正文等产物除外)。发送前自检语言。

8. **客观的事自己核死,不甩锅给用户。** 现在的失败几乎全是客观可验证的(贴边没贴边、灰没灰、炸高没炸高、占位有没有)——这些我自己对着源码+真机就能判定,**不需要、也不许让用户逐条审。** 只有真正进入"主观审美取舍"时才记录取向请他定夺。

9. **不改不该改的。** 修一个 bug 时,不顺手改颜色/字体/间距/排版/文案/导航/交互,除非明确要求。收尾删掉临时脚手架。

10. **内化纠正到全局。** 一次纠正 = 一个症状;改根因,推广到所有同类代码与注释(连带把误导性注释一起改),别只补被点到的那一处,别让用户逐个列举。

11. **平台硬约束**(见 §7):状态管理只用 V2;ArkTS 受限子集;门禁必须 0。

---

## 3. 视觉对抗审查(每个页面必做)—— 四源比对

**禁止脱离源码看图说话。** 每个页面的视觉结论必须从**四个来源**交叉得出,缺一不可:

| 来源 | 看什么 |
|---|---|
| ① eros_fe 源码 | 结构、布局、每个控件的确切数值/样式/条件、占位与加载、颜色来源 |
| ② NextE 源码 | 我现在到底写成了什么,差在哪 |
| ③ eros_fe 真机截图 | 规格跑出来长什么样 —— 用来**确认**①,不是用来**替代**① |
| ④ NextE 真机截图 | 我改出来长什么样 —— 用来**确认**② |

- **尽量同画廊 / 同一项对比**(同一个 gallery 在两边打开,裁同一块区域并排),差异才有意义。
- 顺序固定:**先①②(源码)坐实事实 → 再③④(截图)确认**。绝不只看③④就下结论改代码。
- **视觉验证必须走多智能体对抗审查 workflow,严禁我单人"看一眼"过关。** 已实证:我一眼扫会漏掉明显缺陷——评分星星被 `layoutWeight` 撑成满宽铺开、标签 chip padding 2 倍,我都"审查"过却没抓到,是用户揪出来的。**任何整页/整组件的视觉改动**:起一个 workflow,每个 agent 死磕一个元素(封面/标题/标签/评分/分类/整体协调),各自读两边真机图 + 源码、**默认假设有缺陷**去抓,最后综合去重排 severity;我据结果修到干净。还不放心可再叠 codex 纯视觉复审。只有真正琐碎的微调可省。
- **把握好度**:有据可循 ≠ 逐像素抠成一样;原生实现带来的合理差异要保留(per-tag 标签色等依赖未建子系统的也不算缺陷)。

---

## 4. 验证闭环(改动不验证不算完)

**逻辑类**(必过,缺一不算闭环):
```bash
node scripts/test_v1_decorator_inventory_contract.mjs   # 必须 0 file(s)
node scripts/test_secret_safety_contract.mjs            # 禁止打包凭据资源 / HAP 泄露 / 自动登录注入
node scripts/test_selector_reload_preserves_content_contract.mjs  # selector 切换不得白屏清空旧内容
node scripts/test_error_classification_contract.mjs     # 失败分类:仅真 404 → notFound,绝不把非 404 报成 404
node scripts/test_devsh_keepawake_contract.mjs          # 设备 QA 工具:dev.sh --launch/--log/装机 + sign.py 必须 keep-awake
node scripts/test_detail_header_visual_contract.mjs     # 详情页 header/InfoBar 硬视觉语义门禁
hvigorw assembleHap --mode module -p product=default -p buildMode=debug --no-daemon   # BUILD SUCCESSFUL
```
新增子系统要补对应的 `scripts/test_*_contract.mjs`(带真实 EH HTML fixture)。
动了 i18n(增删/改 key)还要跑 `python3 scripts/check_i18n_duplicates.py`(四语言 key 对齐、无重复)。

**视觉类**:签名装机 → 真机截图 → §3 四源对抗审查。
```bash
NEXTE_SIGN_NONINTERACTIVE=1 HDC_SERVER_PORT=8710 bash dev.sh -d 192.168.50.197:12345 --no-build
```

**绝不自报"做完"**;只陈述"已验证到什么程度、证据是什么、还差什么"。

---

## 5. 记录与提交

**记录(每轮):**
- **`docs/parity-driver.md`** = 进度 / 假设。每轮更新:做了什么、发现了什么、下一步、哪些假设被推翻。
- **`docs/parity-visual-review.md`**(指定的视觉裁定档,供用户后续核验)= 每轮记:
  - 对比截图的路径(eros_fe 真机 vs NextE 真机,尽量同项);
  - 这轮的**设计取向**(每处为什么这么定)、依据的源码位置;
  - 哪些差异是"原生有意为之"、哪些是待修。
- 取向最终由我决定,但**必须留痕**,让用户能事后核验。

**提交(每轮,git 库已初始化):**
- **一轮改完就提交一次**,别攒一大堆。把代码改动 + driver.md / visual-review.md 的记录一起提交。
- 提交信息 **Conventional Commits、英文正文**:`type(scope): description`(如 `fix(gallery-card): cover flush-left + neutral tags`)。
- 正文写清 **为什么改 / 改了什么 / 怎么验证的**(Why·What·Validation);bug 修复、解析/网络、写操作必须带这三段。
- 末尾加 `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`。
- **绝不提交敏感信息**:cookie、`ipb_pass_hash`、`igneous`、`sk`、密码、签名物料;提交前扫一眼 `git diff --cached`。

---

## 6. 设备与命令(别再"回到解放前")

每次驱动设备前**先读对应记忆文件再照做**,不要从零瞎试:
- eros_fe 参考机:Android,USB 序列号 **`fa967a75`**;root 注入 `su -c "input -d 0 tap X Y"`;截图 `exec-out screencap -p` 要剥掉开头 "Multiple displays" 警告字节再缩到 ≤1800px。详见记忆 `nexte-erosfe-device-driving`。
- NextE 真机:HarmonyOS。先 `HDC_SERVER_PORT=8710 hdc list targets` 看在线设备(常见 192.168.50.197 / 237 / 103),再 `hdc -t <设备> ...` 操作;`hdc -t <设备> shell snapshot_display -f /data/local/tmp/x.jpeg` 截图后 `file recv` 拉回、读图前缩到 ≤1800px;详见记忆 `nexte-nexte-device-driving`。
- 截图比对裁同区域并排,用 `magick ... -crop ... +append`。

---

## 7. 平台硬约束(ArkTS / 状态管理 V2)

- **状态管理只用 V2**:`@ComponentV2 / @ObservedV2 / @Trace / @Local / @Param / @Monitor / @Event / @Builder` + `AppStorageV2`。**任何 V1 装饰器都禁止**(`@Component/@State/@Prop/@Link/@Watch/@Provide/@Consume/@Observed/@ObjectLink/...`)。需要 V1 才能做 → 停,`BLOCKED` 上报并给 V2 替代。
- **ArkTS 受限子集**:无 `any/unknown`、无解构、无对象展开、无 `obj['x']` 索引、无 `for..in`、无 `bind/call/apply`、无函数表达式/嵌套函数(用箭头函数)、独立/静态函数里无 `this`、无 `globalThis`、`catch` 不写类型、无 `var`。对象字面量要有可推断的类/接口目标。
- **`@BuilderParam` 在 `@ComponentV2` 下会丢 `this`**:别把实例 `@Builder` 传给子组件的 `@BuilderParam`(会崩 "Cannot read property bind of undefined");用子组件自己的 `@Param` 或在本组件内 `this.builder()` 调用。
- **主题 token 不许硬编码**:尺寸/颜色/字号走 `ThemeConstants` + `EhSemanticColors`,新色要深浅色都覆盖。

---

## 8. 开工前 / 收尾前自检清单

**开工前:**
- [ ] 读了 driver.md,选定了这轮要做透的一块(不是凑数补丁)?
- [ ] 这块在 eros_fe 源码里的实现我读了吗?数值/样式/占位/颜色来源都查清了吗?
- [ ] 原生写法去 V2Next 找了对应可抄的吗?

**动手中:**
- [ ] 每个取值都说得清理由(比例意图照源码 / 像素量按 token+原生审美),没有无理由的脑补值、没有编造源码里没有的结构?
- [ ] 没有用文本/emoji 冒充任何 UI?
- [ ] 没有按命名空间给列表标签染色?
- [ ] 没顺手改不该改的视觉/交互?

**收尾前:**
- [ ] 装饰器门禁 0、构建成功?
- [ ] 真机截图做了四源对抗审查(尽量同项并排)?
- [ ] 进度写回 driver.md、取向+对比截图写进 parity-visual-review.md?
- [ ] 本轮改动已 `git commit`,信息写清 why/what/validation,且没夹带敏感信息?
- [ ] 回复用户全程中文,没有自报"做完"?
- [ ] 还有可做项 → 继续,不停。
