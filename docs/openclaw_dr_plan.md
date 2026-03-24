# OpenClaw 跨账号半自动灾备方案（适用于二进制 / 脚本直接运行）

## 目标

A 账号有一台运行中的 EC2 A，机器上跑 OpenClaw。  
希望做到：

- OpenClaw 以 **二进制 / 脚本** 方式直接运行
- 一旦 A 账号里的 EC2 A 故障
- 可以在 **B 账号** 启动一台 EC2 B 接管
- **最多丢失 1 小时数据**
- **只讨论半自动**：平时自动备份；故障时人工触发恢复

---

## 核心设计

采用下面这套结构：

- **基础 AMI**：只负责把 Linux 机器启动起来
- **独立 EBS 数据卷**：保存 OpenClaw 程序、配置、状态、缓存、日志、认证文件
- **每小时对数据卷做 snapshot**
- **每小时把 snapshot 从 A 账号复制到 B 账号**
- 故障时，在 B 账号：
  - 用基础 AMI 启动 EC2 B
  - 从最近的 snapshot 恢复出数据卷
  - 挂载数据卷
  - 启动 OpenClaw

---

## 为什么这样设计

### 1. AMI 不高频变动
AMI 只保留最小运行环境：

- Linux OS
- SSM Agent
- systemd
- 挂载脚本
- OpenClaw 的 service 定义

这样 AMI 很少变化，只需要第一次复制到 B，或者极少数情况下更新。

### 2. 程序和状态都放在数据卷
把下面这些都放到单独的 EBS 数据卷中：

- OpenClaw 可执行文件
- 启动脚本
- 配置文件
- OAuth / auth 文件
- state
- cache
- logs

这样程序升级、配置修改、状态变更都会随 snapshot 一起进入 B 账号。

### 3. 最适合“最多丢 1 小时数据”
只要每小时做一次数据卷 snapshot，并复制到 B，就能把数据丢失控制在约 1 小时以内。

---

## 总体架构图

```text
Account A（生产）
  EC2 A
   ├─ Root Volume -> 基础 AMI A（低频更新）
   └─ Data Volume -> 每小时 Snapshot A -> 自动复制到 Account B

Account B（灾备）
  基础 AMI B
  Snapshot B（由 A 每小时复制而来）

故障时（手动触发一次）：
  1. 选 B 账号最近一份 Snapshot B
  2. 恢复为新的 EBS Data Volume
  3. 用 AMI B 启动 EC2 B
  4. Attach 恢复出的 Data Volume
  5. 挂载卷并启动 OpenClaw
```

---

## 推荐目录布局

建议把 OpenClaw 的所有运行内容都集中到一个挂载点，例如：

```bash
/opt/openclaw-base
/opt/openclaw-base/bootstrap-openclaw.sh

/mnt/openclaw
/mnt/openclaw/bin
/mnt/openclaw/config
/mnt/openclaw/state
/mnt/openclaw/cache
/mnt/openclaw/logs
/mnt/openclaw/auth
```

### 各目录含义

```text
/opt/openclaw-base
  放在基础 AMI 中，只保存极少变化的引导内容

/mnt/openclaw/bin
  OpenClaw 二进制、shell 启动脚本

/mnt/openclaw/config
  配置文件

/mnt/openclaw/state
  运行状态、任务状态

/mnt/openclaw/cache
  缓存

/mnt/openclaw/logs
  日志

/mnt/openclaw/auth
  OAuth / 认证文件
```

---

## 推荐 systemd service

建议在基础 AMI 中放一个固定的 systemd service。

文件路径：

```bash
/etc/systemd/system/openclaw.service
```

内容如下：

```ini
[Unit]
Description=OpenClaw
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/mnt/openclaw
ExecStart=/mnt/openclaw/bin/openclaw --config /mnt/openclaw/config/config.yaml
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

如果你不是直接执行二进制，而是走 shell 脚本，也可以改成：

```ini
[Unit]
Description=OpenClaw
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/mnt/openclaw
ExecStart=/bin/bash /mnt/openclaw/bin/start-openclaw.sh
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

---

## 推荐 bootstrap 脚本

建议在基础 AMI 中保留一个固定脚本：

```bash
/opt/openclaw-base/bootstrap-openclaw.sh
```

示例内容：

```bash
#!/usr/bin/env bash
set -euo pipefail

DEVICE="${1:-/dev/xvdf}"
MOUNT_POINT="/mnt/openclaw"

mkdir -p "$MOUNT_POINT"

if ! mount | grep -q "on ${MOUNT_POINT} "; then
  mount "$DEVICE" "$MOUNT_POINT"
fi

if [ ! -x "${MOUNT_POINT}/bin/openclaw" ] && [ ! -f "${MOUNT_POINT}/bin/start-openclaw.sh" ]; then
  echo "OpenClaw binary/script not found under ${MOUNT_POINT}/bin"
  exit 1
fi

systemctl daemon-reload
systemctl enable openclaw
systemctl restart openclaw
systemctl status openclaw --no-pager || true
```

如果你的卷文件系统不是现成的，恢复脚本里只需要在首次格式化时处理；从 snapshot 恢复出来的卷通常不需要重新格式化。

---

## 平时自动化做什么

### 自动部分
平时自动完成这些动作：

1. A 账号对 OpenClaw 数据卷每小时做一次 snapshot
2. 每小时把 snapshot 复制到 B 账号
3. 保留最近若干份 snapshot
4. AMI 只在基础环境变化时更新到 B

### 手动部分
故障时只保留一个人工动作：

- 你确认 A 的 EC2 A 确实不可用
- 手动触发 B 账号恢复脚本

这就是“半自动”。

---

## 恢复流程

故障时，B 账号执行以下步骤：

1. 找最近一份可用 snapshot
2. 从 snapshot 创建新的 EBS volume
3. 用基础 AMI 启动 EC2 B
4. 把恢复出的 volume attach 到 EC2 B
5. 挂载到 `/mnt/openclaw`
6. 启动 OpenClaw
7. 检查服务状态

---

## 恢复脚本骨架

下面是一版可直接改造的恢复脚本骨架。

文件名建议：

```bash
restore-openclaw-dr.sh
```

内容：

```bash
#!/usr/bin/env bash
set -euo pipefail

REGION="us-east-1"
AZ="us-east-1a"
AMI_ID="ami-xxxxxxxx"
INSTANCE_TYPE="t3.large"
SUBNET_ID="subnet-xxxxxxxx"
SG_ID="sg-xxxxxxxx"
IAM_INSTANCE_PROFILE="OpenClawEc2Role"
KEY_NAME="your-keypair"
DEVICE_NAME="/dev/sdf"
TAG_KEY="App"
TAG_VALUE="OpenClawData"

echo "==> Step 1: find latest snapshot"
SNAPSHOT_ID=$(aws ec2 describe-snapshots   --region "$REGION"   --owner-ids self   --filters "Name=tag:${TAG_KEY},Values=${TAG_VALUE}" "Name=status,Values=completed"   --query 'Snapshots | sort_by(@, &StartTime) | [-1].SnapshotId'   --output text)

if [ -z "$SNAPSHOT_ID" ] || [ "$SNAPSHOT_ID" = "None" ]; then
  echo "No completed snapshot found"
  exit 1
fi

echo "Latest snapshot: $SNAPSHOT_ID"

echo "==> Step 2: create volume from snapshot"
VOLUME_ID=$(aws ec2 create-volume   --region "$REGION"   --availability-zone "$AZ"   --snapshot-id "$SNAPSHOT_ID"   --tag-specifications 'ResourceType=volume,Tags=[{Key=Name,Value=OpenClaw-Restored-Data}]'   --query 'VolumeId'   --output text)

echo "Created volume: $VOLUME_ID"

aws ec2 wait volume-available   --region "$REGION"   --volume-ids "$VOLUME_ID"

echo "==> Step 3: launch EC2 B"
INSTANCE_ID=$(aws ec2 run-instances   --region "$REGION"   --image-id "$AMI_ID"   --instance-type "$INSTANCE_TYPE"   --subnet-id "$SUBNET_ID"   --security-group-ids "$SG_ID"   --iam-instance-profile Name="$IAM_INSTANCE_PROFILE"   --key-name "$KEY_NAME"   --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=OpenClaw-DR}]'   --query 'Instances[0].InstanceId'   --output text)

echo "Created instance: $INSTANCE_ID"

aws ec2 wait instance-running   --region "$REGION"   --instance-ids "$INSTANCE_ID"

echo "==> Step 4: attach restored volume"
aws ec2 attach-volume   --region "$REGION"   --volume-id "$VOLUME_ID"   --instance-id "$INSTANCE_ID"   --device "$DEVICE_NAME"

echo "==> Step 5: wait for instance status ok"
aws ec2 wait instance-status-ok   --region "$REGION"   --instance-ids "$INSTANCE_ID"

echo "==> Step 6: bootstrap openclaw via SSM"
aws ssm send-command   --region "$REGION"   --instance-ids "$INSTANCE_ID"   --document-name "AWS-RunShellScript"   --comment "Mount OpenClaw volume and start service"   --parameters 'commands=[
    "set -euo pipefail",
    "mkdir -p /mnt/openclaw",
    "lsblk",
    "mount | grep /mnt/openclaw || mount /dev/nvme1n1 /mnt/openclaw || mount /dev/xvdf /mnt/openclaw",
    "systemctl daemon-reload",
    "systemctl enable openclaw",
    "systemctl restart openclaw",
    "systemctl --no-pager --full status openclaw"
  ]'

echo "Recovery flow triggered successfully"
echo "Instance: $INSTANCE_ID"
echo "Volume:   $VOLUME_ID"
echo "Snapshot: $SNAPSHOT_ID"
```

---

## 这个脚本需要你替换的参数

把下面这些值改成你自己的：

```text
REGION
AZ
AMI_ID
INSTANCE_TYPE
SUBNET_ID
SG_ID
IAM_INSTANCE_PROFILE
KEY_NAME
TAG_KEY / TAG_VALUE
DEVICE_NAME
```

---

## 设备名注意事项

在 Nitro 实例上，EBS 卷在系统里经常显示为 `/dev/nvme*n*`，即使 attach 时 API 里填的是 `/dev/sdf`。  
所以恢复后，挂载脚本里最好同时兼容：

- `/dev/nvme1n1`
- `/dev/xvdf`

更稳的做法是用：

- UUID
- 文件系统 label

来挂载，而不是写死块设备名。

可以提前在 A 机器上对数据卷设置 label，例如：

```bash
e2label /dev/nvme1n1 OPENCLAW_DATA
```

然后恢复时用：

```bash
mount LABEL=OPENCLAW_DATA /mnt/openclaw
```

---

## 推荐的 /etc/fstab 写法

如果你想让实例重启后自动挂载，可以在基础 AMI 中预留一条 fstab 规则：

```fstab
LABEL=OPENCLAW_DATA /mnt/openclaw ext4 defaults,nofail 0 2
```

注意：
- 只有在你确认文件系统 label 一致时才这样做
- 否则建议仍然由恢复脚本显式挂载

---

## 认证文件建议

如果 OpenClaw 的 OAuth / auth 文件也要随灾备恢复，建议统一放到：

```bash
/mnt/openclaw/auth
```

然后通过环境变量或启动参数让 OpenClaw 指向这里。

例如：

```bash
export OPENCLAW_STATE_DIR=/mnt/openclaw
```

或者：

```bash
export OPENCLAW_AUTH_DIR=/mnt/openclaw/auth
```

具体变量名按你的 OpenClaw 实际配置来。

---

## 推荐的标签策略

为了让恢复脚本能稳定找到“正确的数据卷快照”，建议 A 账号给数据卷和 snapshot 都打标签。

例如：

```text
App=OpenClawData
Env=Prod
Role=DisasterRecoverySource
```

这样恢复脚本就能按标签筛选，而不是人工找 snapshot。

---

## 半自动操作手册

### 日常
- OpenClaw 正常运行在 A 账号 EC2 A
- 数据卷每小时自动 snapshot 并复制到 B
- AMI 长期不动，除非基础系统环境变化

### 发生故障时
1. 确认 A 账号 EC2 A 确实不可恢复
2. 在 B 账号执行恢复脚本
3. 等待脚本创建卷、启动机器、挂载数据
4. 检查 OpenClaw 服务状态
5. 必要时切换 DNS / 流量 / 上游调用

---

## 推荐的最小原则

### 应该做
- 把 OpenClaw 程序和状态统一放进独立 EBS 数据卷
- 用最小基础 AMI 启动 EC2
- 每小时复制 snapshot 到 B
- 恢复时用脚本自动化

### 不建议做
- 把所有东西都留在 root volume 里
- 每小时重新制作并复制 AMI
- 手工登录到 B 账号逐步恢复

---

## 一句话总结

这套方案的本质是：

**AMI 负责把机器启动起来，snapshot 负责把 OpenClaw 的完整运行目录带到 B 账号。**

对于你当前的半自动目标，这是最简单、最稳、最符合“一小时 RPO”的做法。
