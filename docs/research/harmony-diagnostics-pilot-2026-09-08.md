# 鸿蒙设备诊断技能试点：2026-09-08

本轮已更新本机 `harmony-run-device-diagnostics` 技能，并在用户指定的设备上完成默认 Reader
打开/返回路径的功能、布局和连续录屏取证试点。最主要的发现是：减少成功截图能减少采集命令，
但本样本中全量 `dumpLayout` 比截图更慢；下一类重复功能检查应优先复用 UiTest 的控件属性读取。

## 已落地的能力

- 技能入口新增证据分流，按功能、布局、状态/网络、性能、动画选择证据。
- `references/evidence-strategy.md` 说明条件等待、失败取证、业务断言与视觉验收的边界。
- `scripts/inspect_layout.py` 离线读取布局，支持应用/父容器范围、精确 ID/类型查询及前后差异。
  默认不返回页面文本，重复 ID 不按序号配对，未知属性不当作 false，空或无效布局不当作节点缺失。
- 协议 runner 支持 `measurement.actions: []`。唤醒检查、纯观察和清理不再需要填入无意义手势；
  其余 target、argv、trace、lease 规则沿用原实现。

技能安装位置：`~/.codex/skills/harmony-run-device-diagnostics/`。
本轮未改 NextE 业务代码、已有 native tests 或其他任务的 WIP，未构建或安装应用。

## 设备与样本

- 用户选择：237；完整连接信息保存在当次协议内。
- 实时识别：Pura X / VDE-AL00，展开，纵向 1320×2120。
- 安装包回读：NextE 1.3.3，versionCode 38；共享阅读器任务另外报告为 main12b/native12，
  这是协调方提供的构建身份，本轮没有独立证明它对应某一源码提交，也没有当作 main13。
- 路径：当前 Gallery 卡片 → 同一画廊 Detail → 默认“阅读”入口 → 返回 Detail。
- 新建试点租约前确认原任务已释放；完成后本轮租约已释放，并通知共享阅读器任务。
- 最终保持在同一 Detail；持续亮屏回读跨越设备原 120 秒超时，仍为 AWAKE 和
  OverrideTimeout=86400000ms。本轮设备临时导出和录屏媒体已清理，本地证据保留。

## 功能与布局结果

带截图与精简回放均确认：

1. Reader 打开后，目标应用内唯一的 `reader-overlay-navigation` 节点存在且可见。
2. 返回后，该节点消失，`gallery-detail-pane` 及同一画廊封面节点存在。
3. 返回后的 Detail 容器和封面 bounds 与本轮进入前一致。

Reader 最终截图已查看，画面包含内容和页码；返回后的整页截图也已查看。
本试点只断言上述导航/几何事实，不代表全部 Reader 功能或可选 shared-reader 路径通过。

为避开并行开发中的原生用例和未安装实验包，本轮复跑的是已安装默认入口。没有把已有
ReaderThumbnailRetry/ReaderThumbnailRail 的源码检查算作它们的真机测试通过。
这次回放仍使用相同的短暂停顿及最终布局断言，没有验证新增的设备端条件等待实现。

## 采集成本对照

两轮使用同一安装包、画廊、方向和阅读/返回动作，停顿分别保持 900ms、700ms。

| 项目 | 带最终截图 | 精简功能回放 |
| --- | ---: | ---: |
| 协议内 HDC 命令 | 10 | 6 |
| 全量布局采集 | 2 | 2 |
| 成功截图采集 | 2 | 0 |
| 两个协议运行耗时之和 | 12.812 秒 | 11.610 秒 |

命令数排除校验和 target 枚举。时间排除两协议之间的工具/人工处理间隔。两轮顺序执行，缓存状态
可能不同，样本各一次；因此这不是性能基准，也不能据此承诺整体调试提速百分比。

原始命令时间显示，`dumpLayout` 分别约 3.0 秒和 5.7–5.8 秒，`screenCap` 约 0.46–0.48 秒。
减少的四条命令来自两次截图及其文件传输。定向布局摘要缩小 Agent 读取量，但不会加速设备上已经
发生的全量 dump。后续同类功能问题应先评估已有 UiTest 会话的属性读取，而不是逐步截图改成逐步 dump。

## 动画证据

另录制一段正常速度的相同往返过程，保留原始时间戳，解码得到 99 帧、4 张联系表。
已查看全部联系表，并展开查看第 34、37、76、80 帧；源页面、Reader、中间侧向移动、系统状态栏
变化及返回后的稳定页面均包含在同一连续记录中。录屏后布局再次确认回到同一 Detail。

这证明录屏渠道覆盖了端点断言看不到的过渡状态；未与固定视觉参考比较，动画视觉验收仍未验证。
录屏中的系统录制指示器也说明，采集本身可能影响屏幕显示，应与应用内容分开判断。

## 验证与复用

- 布局工具 9 项测试通过：真实嵌套结构、容器/应用范围、文本选择、缺失属性、重复 ID、
  出现/消失、空/无效布局、尺寸变化及输出截断。
- 技能 `quick_validate.py` 通过。
- 空输入协议完成实际唤醒检查、最终回读及清理；普通点击/返回协议仍可运行。
- malformed actions 仍被校验拒绝。

本地证据根目录：`.hvigor/outputs/diagnostics-pilot-20260908/`，受忽略，不随本文进入版本控制。

| 文件 | 内容 |
| --- | --- |
| `capture-comparison.json` | 两轮协议逐命令计时与成本口径 |
| `pilot-state-layout-results.json` | 首轮导航与几何断言 |
| `pura-x__VDE-AL00/unfolded/portrait-1320x2120/03-reader/` | Reader 最终布局和截图 |
| `pura-x__VDE-AL00/unfolded/portrait-1320x2120/04-return/` | 返回后的整页证据 |
| `pura-x__VDE-AL00/unfolded/portrait-1320x2120/05-reader-compact/` | 精简回放 Reader 布局 |
| `pura-x__VDE-AL00/unfolded/portrait-1320x2120/06-return-compact/` | 精简回放返回布局 |
| `pura-x__VDE-AL00/unfolded/portrait-1320x2120/07-motion/` | 连续视频、命令账本、原始帧与时间戳 |
| `pura-x__VDE-AL00/unfolded/portrait-1320x2120/08-final/` | 最终页面及持续亮屏回读 |
| `skill-before/` | 本轮修改前的技能入口、runner 和 manifest 文档副本 |

执行方法由已安装技能维护；业务 selector 和本次坐标留在项目协议中，不写进通用技能。
后续优先按实际任务复用已有 UiTest 条件等待和断言；只有实测出现主机控制能力缺口时，再评估
hmdriver2，避免为减少截图而引入第二套完整框架。

## 第二轮：直接语义查询与连续执行

用户要求继续提高效率后，已实测并启用 hmdriver2 1.4.4 的可选语义会话。
它适合已安装应用的稳定功能路径：一次连接完成定位、操作、条件等待和断言，成功步骤只返回
精简结果。原协议 runner 继续负责亮屏门禁、CLI 布局/日志与 trace；已有原生 UiTest 测试仍优先复用。

本轮独立建立相同构建/内容的对照：Pura X VDE-AL00、展开、竖屏 1320×2120，Detail4176682
进入默认 Reader 后返回。安装任务报告 main15/native16；本轮未重新安装或构建。第一轮旧构建和
不同画廊的计时不参与本轮百分比计算。先确认当前页面，再在独占租约内完成两组三轮执行。

| 计时口径 | 全量布局协议 | 连续语义会话 | 变化 |
| --- | ---: | ---: | ---: |
| 单轮耗时，三次样本 | 11.309 / 11.042 / 11.353 s | 4.316 / 4.392 / 4.337 s | 中位耗时减少 61.6% |
| 三轮完整执行 | 33.704 s | 20.120 s | 减少 40.3% |
| 三轮成功检查点的全量布局 | 6 | 0 | 省去 6 次完整树采集 |
| 三轮截图 | 0 | 0 | 收益来自执行层 |

单轮语义计时从查找阅读入口开始，包含点击、Reader出现、返回、Reader消失和原详情锚点查询；
返回锚点几何复核在单轮计时外。完整执行计时包含它以及驱动启动、初始前置检查、清理，语义组还
包含一次负向等待测试。语义驱动启动约 2.884 s。两组均保留 0.6 s 输入节奏，期间未发生模型往返；
布局组另包含协议验证/进程启动及文件传输。因此这是两种工作流的小样本比较，不是仅替换采集函数
的严格微基准，也不能泛化成所有调试任务的提速率。

正式脚本安装后的一轮冷启动复跑总耗时 9.930 s，核心路径 4.458 s。单次任务的收益小于批量任务，
不要为每个普通点击重新初始化驱动。稳定页面后连续 ID 查询曾测到约 0.13–0.15 s，导航后的首次
条件查询仍约 1.1 s；离线摘要不能代替这种执行层优化。

所有完成样本确认 Reader overlay 出现、返回后消失，且恢复同一 Detail 封面锚点及其几何。
这些断言不证明图片解码、动画质量或整个 Reader 的功能验收。

### 实测失败与执行限制

- 初次点击部分可见封面未进入详情，被 4 s 条件等待拦截；保留失败布局后，使用完整可见卡片容器
  成功进入。点击返回成功不能代替目的页面断言。
- 在语义会话中混用 CLI `uitest dumpLayout` 导致连接失效，后续 RPC 报 JSONDecodeError。
  因而两组改为分开执行；失败采集也放在语义会话关闭后，未将该错误吞成“节点不存在”。
- 发布版的多关键字 selector 不能可靠组合，适配器只接受一个唯一 selector；`current_app()`
  曾误报 Settings，前台事实使用窗口和应用专属锚点确认。
- 缺失节点的 0.4 s 轮询预算在 0.515 s 返回；预算不打断进行中的 RPC，其 socket timeout 为 20 s。
- 驱动会替换通用 agent 并管理 singleness 服务。适配器保存原 agent、拒绝已有通用会话、只清理本次
  资源。最终回读确认旧文件内容/权限恢复，通用 daemon、本次转发及备份无残留，既有其他转发保留。

### 已交付入口

- 项目脚本：`scripts/diagnostics/reader_roundtrip.py`，参数化当前 target、上下文 manifest、Detail
  封面 ID、阅读文字和新输出目录；一个进程运行完整路径，失败停止后续输入并写 `result.json`。
- 已安装技能新增 `scripts/semantic_session.py` 和 `references/semantic-session.md`；普通路径可选
  该入口，视觉和动画问题继续使用原截图/录屏流程。
- 专用运行环境：`~/.codex/runtimes/harmony-semantic/bin/python`，固定 hmdriver2 1.4.4，未修改应用依赖。
- 共 16 项测试通过（本轮新增 7 项）；技能校验、正式安装后的真机入口复跑通过。

示例命令中的 target 必须来自当前解析，lease 必须由本任务持有；manifest、锚点和输出目录必须
对应当前场景，不能把本文的历史内容当成当前前置状态：

```bash
scripts/device-lease --device "$TARGET" run --lease "$LEASE_ID" -- \
  ~/.codex/runtimes/harmony-semantic/bin/python scripts/diagnostics/reader_roundtrip.py \
  --target "$TARGET" --hdc "$HDC" --manifest "$CURRENT_MANIFEST" \
  --anchor-id "$CURRENT_DETAIL_COVER_ID" --runs 3 --output-dir "$NEW_OUTPUT_DIR"
```

本轮证据位于 `.hvigor/outputs/semantic-efficiency-20260908/`。其中状态分区
`pura-x__VDE-AL00/unfolded/portrait-1320x2120/` 保存 `semantic-benchmark.json`、
`baseline-benchmark.json`、六个基线检查点、`installed-smoke/result.json` 及 `final/run-metadata.json`。
设备租约已释放并通知共享阅读器任务；终点为 Detail4176682，保持实验设备亮屏设置。

审阅源码：[hmdriver2 项目](https://github.com/codematrixer/hmdriver2)及下载的 1.4.4 wheel。
上述兼容性结论来自当前发布版源码和本机实测，升级版本后需重新验证。

## 第三轮：减少重复定位，明确下一步瓶颈

`unique()` 原先调用 `count` 后再次 `find_component`，会执行两次组件查询。
现在从一次查询返回的列表检查唯一性，并直接绑定该结果；减少两个 RPC，同时避免第二次查询
选到与第一次唯一性检查不同的组件集合。适配器使用已固定版本的内部结果接口，测试通过真实
hmdriver2 `UiObject` 与模拟 RPC 验证查询次数、句柄一致性、缺失和重复匹配处理。

项目脚本新增启动、前置条件、入口定位、点击、返回、条件等待、几何复核及清理的分段计时。
原 `elapsedMs` 保持核心路径口径；`totalRoundMs` 包含几何复核，`totalMs` 包含整个会话。

237 同一前台应用、Detail4176682、展开竖屏 1320×2120，旧/新实现各三轮：

| 指标 | 旧实现 | 新实现 |
| --- | ---: | ---: |
| 阅读入口定位，中位 | 271.5 ms | 117.3 ms |
| 返回后的几何查询，中位 | 321.5 ms | 211.6 ms |
| 三轮完整耗时 | 19.358 s | 18.466 s |

三轮总耗时减少约 4.6%，属于小幅改善。六轮均通过相同导航与几何断言；不把样本波动当作精确的
普遍提速率。18 项测试通过，新适配器已安装；设备资源清理回读通过，短租约已释放。
证据在 `.hvigor/outputs/semantic-refine-20260908/`，包括 `before/after` 结果和适配器版本快照。

后续优先级按本次分段计时排列：

1. **核实重复同步等待。** 新实现每轮两次导航后查询合计中位 2.257 s，动作另外各有 0.6 s
   固定节奏。上游 `FindWidgets` 会调用 `WaitForUiSteady`，默认阈值 1000 ms、最长 3000 ms；
   这支持“底层空闲同步可能占主要开销”的推断，但未确认商业设备使用相同实现或开放调参入口。
   下一次应验证支持的同步方式与慢加载/过渡场景，再决定能否减少额外等待；缩短 Python 轮询间隔
   不会缩短一次进行中的 RPC。
2. **同一租约内组合不同功能场景。** 初始化仍约 2.90 s，初始前置条件约 1.50 s，清理约 0.55 s。
   让连续的功能检查共享会话可以摊薄这些成本；换任务、释放租约或开始 CLI 布局/录屏前仍结束会话。
3. **失败后的一次性取证。** 当前失败会保存检查点和错误，布局采集由调用方在会话关闭后执行。
   可把已验证的失败采集协议接入调用方，减少一次人工/模型决策；保留原始失败，避免自动重启应用。
4. **精简仍然必要的布局采集。** 当前 `device_ui_action.py` 和本次全量布局基线都带 `-a`，会额外
   保存背景、字体、extraAttrs 等数据；上游实现还会通过 hidumper 补充属性。只需要 ID、层级和
   bounds 时可对照基础 dump，并用 `-b` 或 `-w` 缩小范围。此前 3–5.8 s 样本属于带 `-a` 的采集，
   尚未实测基础/限定范围 dump 的耗时和字段完整性，不据此承诺提速或直接更改视觉诊断默认项。

上游依据：[FindWidgets](https://github.com/openharmony/testfwk_arkxtest/blob/master/uitest/core/ui_driver.cpp)、
[UiOpArgs 默认参数](https://github.com/openharmony/testfwk_arkxtest/blob/master/uitest/core/ui_action.h)、
[控件树参数](https://github.com/openharmony/docs/blob/master/zh-cn/application-dev/application-test/uitest-guidelines.md#获取控件树)。

## 第四轮：基础布局默认值与等待验证

在相同 Detail4176682、Pura X 展开竖屏 1320×2120 上，以交错顺序采集三种配置，各三次；
无 UI 输入，应用前台和页面保持一致。计时覆盖单条 `uitest dumpLayout`，不包含文件传输。

| 配置 | 中位采集耗时 | 文件大小 | 应用节点核心字段/层级 |
| --- | ---: | ---: | --- |
| 全量属性 `-a` | 5.613 s | 161,308 B | 154 节点一致 |
| 基础布局 | 1.102 s | 144,701 B | 154 节点一致 |
| 基础布局 + `-b com.erosteam.nexte` | 1.025 s | 107,701 B | 154 节点一致 |

去掉 `-a` 后本场景采集耗时减少约 80.4%。对应用完整子树逐节点比较 ID、type、text、bounds、
visible、enabled、clickable、scrollable 及子节点层级，九份结果一致；基础布局不再携带样式扩展
数据。包名过滤主要进一步减少其他窗口节点和文件体积，不能据此判断被过滤掉的系统窗口状态。

已修改现有 `harmony-next/scripts/device_ui_action.py`：

- 普通操作默认 `--layout-profile basic`，保持核心布局、前后截图和日志采集。
- 样式诊断显式使用 `--layout-profile styled`，恢复 `-a` 属性。
- 可选 `--layout-bundle <bundle>` 只限制布局范围，截图仍为整屏。
- 输出的 before/after 记录实际 layoutProfile 和 layoutBundle，避免误把精简结果当成样式证据。

已有工具的四项假 HDC 集成测试通过，覆盖默认配置、样式/包名选项传递、定位执行和失败清理。
正式安装后的真实工具入口也完成了“阅读 → Reader 出现 → 返回 → 原详情锚点/几何恢复”，
确认新默认配置和包名过滤均在前后采集中生效。

### 去掉固定等待没有收益

另用相同语义路径对照上游节奏与仅省去主机两个 0.6 s sleep 的试验版，各三轮；
保留原生操作、平台同步和原有条件断言。

| 指标 | 上游节奏 | 省去主机 sleep |
| --- | ---: | ---: |
| 每轮导航后两次查询，中位合计 | 2.161 s | 3.429 s |
| 单轮核心路径，中位 | 4.109 s | 4.171 s |
| 三轮完整执行 | 17.405 s | 17.797 s |

没有观察到提速：省去的等待基本转移进了后续查询。六轮断言均通过，但生产脚本已撤回该试验选项，
保留原来的等待行为；试验脚本仅留在忽略的证据目录中。后续不再将“直接删除固定 sleep”作为已知
优化方案，除非新的同步方式和端到端计时提供不同证据。

证据根目录：`.hvigor/outputs/capture-pacing-20260908/`。状态分区下 `layouts/comparison.json`
保存采集耗时、字节数和树比较结果，`pacing-upstream/`、`pacing-condition/` 保存等待对照，
`installed-helper/verification.json` 保存正式入口验证。有效改进已写入两个技能的使用说明。
