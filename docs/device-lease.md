# 实机占用声明与 Agent 协作约束

## 没有默认设备：选择意图与完整 target 是两个条件

NextE 不设默认真机。用户当前指令必须先明确选择哪台设备，但选择不要求用户手写完整 HDC
target。以下两种形式都有效：

- 完整 target，例如 `192.168.50.237:12345`；
- 能通过当前在线设备唯一解析的短名，例如 `237`、设备标签或模拟器名称。

短名代表明确的设备选择意图。Agent 必须自行用实时、只读的 `hdc list targets -v` 将它解析为
完整 target；只要唯一匹配，就回显解析结果并继续，不得要求用户重复提供 IP 和端口。

历史地址、脚本默认值、交接文档、旧 artifact、其他任务和 lease 记录不能参与当前解析，也不能
替代用户的设备选择。用户完全没有选择设备，或实时解析得到零个/多个候选时，才停止并询问。

lease 是 agent 间的协作锁，不是设备授权。获取 lease 不构成用户对任意设备操作的许可，
也不会扩大用户授权的操作范围。

## 实时选择设备，增量复用场景

设备连接状态与测试场景不是同一种状态：

- 每个连续设备操作阶段开始时实时解析 target 并确认 `Connected`；这是易漂移事实。解析结果在该
  阶段的有效 lease 内复用，不得在每条命令前重复枚举；lease 失效、连接中断或目标发生变化后再刷新。
- 已经证明的页面入口、测试数据、分辨率/方向、稳定节点、动作序列、最后有效检查点和验收条件属于
  当前场景；重复验证时继续复用，不得从首页重新发现或逐步截图计算。
- 执行重复 UI 动作、日志或 trace 前，先搜索当前任务产物和机器记忆中的已验证协议。存在 manifest
  时复用它；没有正式 manifest 但已有可靠产物时，也应复用其中已证明的入口、几何和动作，而不是
  从模型记忆重建。
- 用户纠正某个手势、截图或结论时，只废弃受影响的样本和派生结论。设备、入口和其他前置条件不会
  因此自动失效；按 `harmony-run-device-diagnostics` skill 在原场景上记录并验证增量。
- 默认只在建立前置状态和最终验收点采集必要证据。除非中间动作本身就是诊断对象，不要给每次普通
  导航点击都包一轮完整截图、布局树和日志采集。
- 重启或重新安装由用户目标决定；需要重启时使用已经证明的深链、稳定 selector 或动作序列恢复到
  最后有效检查点，不重新分析同一条入口路径。

## 短名解析规则

1. 先取得用户当前指令中明确选择的设备 selector；历史计划只能提供背景，不能创建授权。
2. 完整 target 可直接作为解析结果；连接前仍应核对实际状态。
3. 短名必须对 `hdc list targets -v` 的当前 `Connected` 结果做精确、可解释的匹配。
4. `1` 到 `3` 位纯数字按 IPv4 最后一段匹配，例如 `237` 可匹配
   `192.168.50.237:12345`；不得做任意子串匹配。
5. 唯一匹配时，把完整 target 写入当前执行计划并回显，例如：
   `设备 237 已实时解析为 192.168.50.237:12345，本轮只操作该 target。`
6. 零匹配或多匹配时停止，列出匹配结果并请用户澄清。不得因为“只有一台在线”就替用户选择。

`hdc list targets -v` 只用于发现和解析，不改变设备状态，不需要 lease。它不能在用户未选择设备
时充当自动选设备机制。

## 工具

```bash
scripts/device-lease
scripts/device_lease.py
```

`scripts/device-lease` 故意没有默认 target；所有 lease 命令都必须显式提供解析后的完整目标：

```bash
scripts/device-lease --device "$TARGET" status
```

## 设备操作前的顺序

1. 取得用户指定的完整 target 或短名。
2. 如为短名，使用 `hdc list targets -v` 实时唯一解析。
3. 回显本轮将使用的完整 target；唯一匹配时无需等待用户再次确认。
4. 申请该 target 的 lease。
5. 检查 `hdc -t "$TARGET" shell echo ok` 明确返回 `ok`。
6. 只在用户已授权的范围内执行设备命令。
7. 完成或失败后释放 lease。

示例：

```bash
HDC=/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc
TARGET=<完整且已回显的target>

LEASE_ID=$(scripts/device-lease --device "$TARGET" acquire \
  --owner "codex:nexte-device-verify" \
  --project "NextE" \
  --ttl 30m \
  --reason "用户已授权的设备验证")

scripts/device-lease --device "$TARGET" run --lease "$LEASE_ID" -- \
  "$HDC" -t "$TARGET" shell echo ok

scripts/device-lease --device "$TARGET" release --lease "$LEASE_ID"
```

## 哪些命令需要 lease

- `hdc tconn` / `hdc install` / 卸载 / 清应用数据；
- `aa start` / 停止应用 / 切换前台应用；
- `uitest` / `uinput` 点击、滑动、按键；
- 截图、录屏、依赖前台状态的布局或日志采集；
- 其他会改变设备、应用、账号或页面状态的命令。

本地文件、git 状态、构建和 `hdc list targets -v` 不需要 lease。不依赖前台状态的只读设备探针
可不加锁；一旦验证依赖当前 UI/前台状态，就先获取 lease。

## 释放与抢占

```bash
scripts/device-lease --device "$TARGET" renew --lease "$LEASE_ID" --ttl 15m
scripts/device-lease --device "$TARGET" release --lease "$LEASE_ID"
```

`--force` 仅能在用户明确批准后使用。

## Agent 提示必带规则

```text
设备操作前，用户必须先选择设备。完整 target 和可实时唯一解析的短名都有效；
短名先用 hdc list targets -v 在当前 Connected 设备中解析，唯一匹配后回显完整 target 并直接
继续，只有零匹配或多匹配才询问。禁止从历史地址、默认值、交接或 lease 记录选择/解析设备。
所有设备控制使用 scripts/device-lease --device "$TARGET" 协调占用；lease 不扩大用户授权。
重复设备场景先使用 harmony-run-device-diagnostics skill，并复用当前任务已有 manifest、产物和
最后有效检查点；用户纠正只修改受影响的协议增量，不从首页重新发现，不为普通导航逐步全量取证。
```
