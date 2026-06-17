# 实机占用声明与 Agent 协作约束

NextE 目前常驻开发验证真机只有一台：`192.168.50.197:12345`。多项目、多 agent 并行开发时，如果多个自动化任务同时执行 `hdc install`、`aa start`、`uitest click/swipe/keyEvent`，真机状态会被交替控制，导致验证结果不可信。

本机制是 **agent 之间的协作锁（advisory lease）**，用于约束 Hermes/Codex/Claude 等自动化任务。它 **不会拦截人工调试**：人仍然可以直接使用 `hdc`、DevEco、屏幕触控等工具；只有交给 agent 的任务必须遵守 lease。

## 原则

1. **人工优先**：人工调试不需要申请 lease，也不会被脚本阻止。
2. **Agent 控制真机前必须申请 lease**：涉及安装、启动、点击、滑动、按键、清数据等会改变设备状态的操作，agent 必须持有有效 lease。
3. **只读观察尽量不加锁**：`hdc list targets`、读取 git 状态、读取本地文件、普通日志查看通常不需要 lease；但若日志/截图/布局依赖当前前台 UI 状态，建议申请 lease。
4. **TTL 防死锁**：lease 有过期时间，agent 卡死后不会永久占用。默认 lease 是 TTL-only，不会把申请命令的短生命周期 PID 当作持有者存活信号。
5. **抢占需用户批准**：除非用户明确要求，否则 agent 不得使用 `--force` 抢占别的 lease。

## 工具位置

```bash
scripts/device-lease
scripts/device_lease.py
```

默认设备：`192.168.50.197:12345`

锁文件目录默认在：

```bash
~/.hermes/device-leases/
```

可用环境变量覆盖：

```bash
export NEXTE_DEVICE_LEASE_DIR=/tmp/nexte-device-leases
```

## 基本用法

### HDC TCP 连接稳定探针

共享设备使用 TCP target `192.168.50.197:12345`。实机 QA 开始前，必须先确认设备 shell 真正可用，而不是只看 `tconn` 或 `list targets`：

```bash
HDC=/home/gamer/devtool/ohos/command-line-tools/sdk/default/openharmony/toolchains/hdc
$HDC tconn 192.168.50.197:12345
sleep 2
$HDC -t 192.168.50.197:12345 shell echo ok
```

只有第三条命令明确输出 `ok`，才可以继续 `hdc install`、`aa start`、截图、点击或 dump。`tconn` 返回 `Connect OK`、`list targets -v` 显示 `Connected` 都不能单独作为设备可控证据；实测中 target 显示 Connected 后，立即执行 `shell echo` 可能无输出，等待约 2 秒后才稳定。

如果探针没有输出 `ok`，记录为设备连接 `BLOCKED`，不要循环重试或继续安装。除非用户明确要求修复设备连接模式，agent 不得执行 `hdc tmode port ...`；`tmode` 会改变设备端 hdc daemon 模式，不属于普通 QA 连接检查。

### 查看当前占用

```bash
scripts/device-lease status
```

无人占用时返回非 0，输出 `no active lease` 或过期 lease 信息。

### 申请占用

```bash
LEASE_ID=$(scripts/device-lease acquire \
  --owner "codex:nexte-device-verify" \
  --project "NextE" \
  --ttl 30m \
  --reason "NextE 真机验证")
```

默认申请的是 **TTL-only lease**：`status` 中的 `acquire_pid` 只是当次 `acquire` 命令进程，不代表后续真正占用设备的 agent 是否仍存活。因此不能仅因为 `acquire_pid` 已退出就判定 lease 可抢占。

如果有明确的长生命周期验证/agent 进程，建议绑定其 PID：

```bash
LEASE_ID=$(scripts/device-lease acquire \
  --owner "codex:nexte-device-verify" \
  --ttl 30m \
  --holder-pid "$$" \
  --reason "长时间真机验证")
```

带 `--holder-pid` 的 lease 是 **process-bound lease**。当 holder PID 位于本机且进程已不存在时，`status` 会显示 `stale: holder pid not running`，后续普通 `acquire` 可在 TTL 到期前替换该 stale lease；TTL-only lease 不会因为 `acquire_pid` 消失而被自动视为 stale。

### Controller wrapper 起 dev.sh 时的陷阱

当 controller 通过 background wrapper 脚本调用 `dev.sh` 之类的长流程时：

1. **不要 `--holder-pid $$`**。wrapper 进程往往很短命，PID 退出后 lease 立即 stale，`scripts/device-lease run --lease $ID -- ...` 会返回 `denied: holder pid not running`，`dev.sh` 实际根本没启起来。改用 TTL-only `acquire`（不传 `--holder-pid`）。
2. **PATH 必须显式包含**：
   - `/home/gamer/devtool/ohos/command-line-tools/bin`（提供 `ohpm`）
   - `/home/gamer/OpenHarmony/20/toolchains`（提供 `hdc`）

   缺 `ohpm` 时 `dev.sh` 第 5 行会以 `未找到 ohpm` 直接 `exit 1`。
3. **wrapper 结尾 release 用 `--force`**，防止 TTL 未过被卡。

### 带 lease 执行强控制命令

```bash
scripts/device-lease run --lease "$LEASE_ID" -- \
  /home/gamer/devtool/ohos/command-line-tools/sdk/default/openharmony/toolchains/hdc \
  -t 192.168.50.197:12345 shell uitest uiInput click 650 1200
```

### 续约

```bash
scripts/device-lease renew --lease "$LEASE_ID" --ttl 15m
```

### 释放

```bash
scripts/device-lease release --lease "$LEASE_ID"
```

建议 agent 使用 `trap` 确保退出时释放：

```bash
LEASE_ID=$(scripts/device-lease acquire --owner "codex:task" --ttl 30m --reason "真机验证")
trap 'scripts/device-lease release --lease "$LEASE_ID" || true' EXIT
```

## Agent Prompt 必带规则

给 Codex/Claude/Hermes 子任务时，涉及真机验证必须加入：

```text
真机设备 192.168.50.197:12345 是 agent 间共享的独占资源。你在执行任何会改变设备状态的命令前，必须先通过 scripts/device-lease acquire 获取 lease，并用 scripts/device-lease run --lease "$LEASE_ID" -- <command> 执行 hdc install、aa start、uitest click/swipe/keyEvent、清数据、卸载等强控制命令。完成或失败退出时必须 release。不要使用 --force，除非用户明确批准。人工调试不受该机制限制。
```

## 哪些命令必须持有 lease

必须：

- `hdc tconn` / `hdc tconn ... -remove`
- `hdc install` / 卸载 / 清应用数据
- `aa start` / 停止应用 / 切前台应用
- `uitest uiInput click`
- `uitest uiInput swipe`
- `uitest uiInput keyEvent`
- 会改变设备、应用、账号、页面状态的脚本

建议：

- `uitest dumpLayout`，如果依赖当前页面不被别人切走
- 截图/录屏，如果依赖当前页面不被别人切走
- hilog 验证，如果需要和某段 UI 操作严格对应

通常不需要：

- `hdc list targets`
- `hdc -t 192.168.50.197:12345 shell echo ok` 这类只读连接探针
- `git status` / `git diff`
- 本地构建，不安装到设备时
- 查看已保存的本地日志文件

## 人工调试如何处理

本机制不阻止人工直接使用设备。如果你要人工调试，建议向 agent 发一句：

```text
我接管实机调试，暂停所有 agent 真机操作。
```

agent 应当停止申请新 lease；如已有 lease，应释放或等待用户确认。

如果需要用户批准抢占：

```bash
scripts/device-lease acquire --force --owner "manual-approved:task" --reason "用户批准抢占"
```

## 故障处理

如果 agent 崩溃但 lease 仍显示 active：

1. 先看 `liveness`：
   - `TTL-only / not process-bound`：只能依据 `expires_at` 或用户批准处理，不能用 `acquire_pid` 是否存在判断。
   - `process-bound holder_pid=...`：如果同机 holder 进程已退出，`status` 会标记 stale，普通 `acquire` 可直接替换。
2. 对 TTL-only lease，先检查 `expires_at`，过期后自动可被新 lease 覆盖。
3. 如确定无人使用且用户批准，可执行：

```bash
scripts/device-lease release --lease <old-lease-id> --force
```

或直接用 `--force` 申请新 lease。

## 设计边界

- 这是 advisory lock，不是系统级 hdc 拦截器。
- 目标是防止 agent 之间互相抢设备，而不是限制人工操作。
- 真正的强制隔离可后续再做，例如封装统一 `hdc-agent` 命令并禁止 agent 直接调用裸 `hdc`。当前先保持低摩擦。
