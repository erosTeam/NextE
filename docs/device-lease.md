# 实机占用声明与 Agent 协作约束

## 硬边界：没有默认设备

NextE 不设任何默认真机 target。Agent 只能使用用户当前指令或当前任务计划中明确写出的
target；不得从脚本默认值、历史验证记录、其他任务、交接文档或旧 artifact 推断设备地址。

target 缺失、冲突或不确定时，必须停止并向用户询问。不得连接、安装、启动、卸载、清数据、
点击、滑动、按键或截图。

本机制是 agent 间的协作锁，不是设备授权。获取 lease 不构成用户对任意设备操作的许可。

## 工具

```bash
scripts/device-lease
scripts/device_lease.py
```

所有命令都必须显式提供目标：

```bash
TARGET=<用户或当前任务计划明确指定的target>
scripts/device-lease --device "$TARGET" status
```

`scripts/device-lease` 故意没有默认 target；漏传 `--device` 必须直接失败。

## 实机操作前的顺序

1. 从当前用户指令或当前任务计划取得 target。
2. 将 target 原样回显给用户，确认本次操作目标。
3. 申请该 target 的 lease。
4. 检查 `hdc -t "$TARGET" shell echo ok` 返回 `ok`。
5. 只在用户已授权的范围内执行设备命令。
6. 完成或失败后释放 lease。

示例：

```bash
HDC=/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc
TARGET=<用户或当前任务计划明确指定的target>

LEASE_ID=$(scripts/device-lease --device "$TARGET" acquire \
  --owner "codex:nexte-device-verify" \
  --project "NextE" \
  --ttl 30m \
  --reason "用户已授权的真机验证")

scripts/device-lease --device "$TARGET" run --lease "$LEASE_ID" -- \
  "$HDC" -t "$TARGET" shell echo ok

scripts/device-lease --device "$TARGET" release --lease "$LEASE_ID"
```

## 哪些命令需要 lease 与明确授权

- `hdc tconn` / `hdc install` / 卸载 / 清应用数据
- `aa start` / 停止应用 / 切前台应用
- `uitest` 点击、滑动、按键
- `uinput`、截图、录屏、依赖前台状态的布局或日志采集

只读本地文件与 git 状态不需要 lease。普通 `hdc list targets` 不是设备授权；它不能替代
明确 target 和用户许可。

## 释放与抢占

```bash
scripts/device-lease --device "$TARGET" renew --lease "$LEASE_ID" --ttl 15m
scripts/device-lease --device "$TARGET" release --lease "$LEASE_ID"
```

`--force` 仅能在用户明确批准后使用。

## Agent 提示必带规则

```text
任何会改变设备状态的命令前，必须使用用户当前指令或当前任务计划中明确写出的 target。
禁止使用默认设备、历史地址、其他任务或 lease 记录推断 target。先回显 target，再以
scripts/device-lease --device "$TARGET" 获取对应 lease；target 缺失或不确定时停止并询问。
lease 只协调占用，不构成设备操作授权。
```
