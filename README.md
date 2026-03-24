# OpenClaw Ohio DR Layout

This repository captures:

- The original DR plan from `gs://grafana_data_samples/md-files/openclaw_dr_plan.md`
- The actual Ohio (`us-east-2`) EC2 installation layout
- The `systemd` unit and shell scripts used to keep base components on the root volume and all OpenClaw content on the data volume

## Scope

The installed host was prepared with these goals:

- Root volume only contains OS and low-change bootstrap components
- Data volume contains all OpenClaw runtime content
- OpenClaw is installed but not started

## Repository Layout

- `docs/openclaw_dr_plan.md`: original DR plan
- `docs/ohio-ec2-install-report.md`: actual installation result and directory tree
- `scripts/install-openclaw-layout.sh`: installation script used to finalize the host layout
- `scripts/bootstrap-openclaw.sh`: root-volume bootstrap script
- `scripts/start-openclaw.sh`: data-volume wrapper used by `systemd`
- `systemd/openclaw.service`: service unit installed on the instance
- `config/fstab.openclaw.fragment`: mount fragment used for the data volume
