# Ohio EC2 Install Report

## Target

- Region: `us-east-2`
- Availability Zone: `us-east-2b`
- Instance ID: `i-0de4784e26d587fb3`
- Public IP: `52.14.204.187`
- Private IP: `172.31.25.143`
- Base AMI: `ami-0b0b78dcacbab728f`
- Instance profile: `OpenClawEc2Role`
- OpenClaw version: `2026.3.23-2`
- Node.js version: `v22.22.2`

## EBS Layout

- Root volume: `vol-058a3b795f45c08cd`
  - API device: `/dev/xvda`
  - In-guest device family: `nvme0n1`
  - Filesystem: `xfs`
- Data volume: `vol-048224406aaccc60d`
  - API device: `/dev/sdf`
  - In-guest device family: `nvme1n1`
  - Filesystem: `ext4`
  - Label: `OPENCLAW_DATA`
  - Mount point: `/mnt/openclaw`

## Current Service State

- `openclaw.service`: `inactive`
- `openclaw.service`: `disabled`
- `fstab` mount rule present for `LABEL=OPENCLAW_DATA`

## Root Volume Content

```text
/opt/openclaw-base
/opt/openclaw-base/bootstrap-openclaw.sh
/etc/systemd/system/openclaw.service
/etc/fstab -> includes LABEL=OPENCLAW_DATA /mnt/openclaw ext4 defaults,nofail 0 2
/usr/bin/node
/usr/bin/npm
/usr/bin/systemctl
/usr/bin/amazon-ssm-agent
```

## Data Volume Content

```text
/mnt/openclaw
/mnt/openclaw/app
/mnt/openclaw/app/bin
/mnt/openclaw/app/bin/openclaw
/mnt/openclaw/app/lib
/mnt/openclaw/app/lib/node_modules
/mnt/openclaw/app/lib/node_modules/openclaw
/mnt/openclaw/auth
/mnt/openclaw/bin
/mnt/openclaw/bin/openclaw
/mnt/openclaw/bin/start-openclaw.sh
/mnt/openclaw/cache
/mnt/openclaw/config
/mnt/openclaw/config/config.yaml
/mnt/openclaw/logs
/mnt/openclaw/lost+found
/mnt/openclaw/releases
/mnt/openclaw/state
```

## `lsblk -f`

```text
NAME          FSTYPE FSVER LABEL         UUID                                 FSAVAIL FSUSE% MOUNTPOINTS
nvme0n1
├─nvme0n1p1   xfs          /             bb1ad377-aefa-4354-a419-b1d6a31d6d2c   13.9G    13% /
├─nvme0n1p127
└─nvme0n1p128 vfat   FAT16               3D07-5F4A                               8.7M    13% /boot/efi
nvme1n1       ext4   1.0   OPENCLAW_DATA 0b863c96-2fca-4365-aff8-8d3eabfa36d3   45.8G     1% /mnt/openclaw
```

## Notes

- The root volume only keeps low-change system and bootstrap components.
- All OpenClaw-specific binaries, wrappers, config, state, cache, logs, and auth paths are on the data volume.
- The installation intentionally stopped before onboarding and before starting the OpenClaw service.
