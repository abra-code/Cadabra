# agent-vm fixtures

Real `--json` answers of agent-vm, which `Tests/helpers/fake_agent_vm.sh` serves to the library tests (`Tests/45-agentvm-library.test.sh`, `Tests/47-agentvm-boxes.test.sh`, `Tests/48-agentvm-jobs.test.sh`).

- `version.json` - `agent-vm version --json`.
- `doctor.json` - `agent-vm doctor --json`. Its "running VMs" check is a `warning` (two virtual machines ran when it was captured), so to the library no slot is free.
- `box-status-stopped.json` - `agent-vm box status <box> --json` for a stopped box.
- `box-status-ready.json` - the same for a running box with a project shared (read-only) and one program running in it, so every status field is present.
- `box-status-unresponsive.json` - made by hand from `box-status-stopped.json` (state `unresponsive`, `running` true, a `statusError`), because a wedged supervisor cannot be produced on request. It follows `BoxStatus.of` in agent-vm's `Sources/AgentVMKit/Boxes/BoxStatus.swift`.
- `image-list.json`, `box-list.json`, `packs.json` - `image list`, `box list` and `box packs`. The boxes were all stopped, so the running fields (`pid`, `project`, `ownerPid`) are absent here; `box-status-ready.json` carries them.
- `execlog.json`, `netlog.json` - `box execlog <box> --last 5` and `box netlog <box> --last 5`.
- `box-create.json` - `box create <box> --image dev --memory-gb 4 --allow pack:npm --allow example.com --disposable`.
- `box-start.json`, `box-start.events`, `box-stop.events` - what `box start` prints on standard output, and the progress events of `box start` and `box stop` on standard error.
- `secret-list.json` - `agent-vm secret list --json` (agent-vm 0.2.12, 2026-09-26), with a second, readable entry added by hand so both states are present.
- `update-guest.events` - made by hand, following the steps agent-vm's `Docs/progress-events.md` lists for `image update-guest` (a guest update boots a VM, which the capture avoided).
- `image-create.events` - made by hand the same way, for `image create --from dev --recipe homebrew-node` (clone, boot, the recipe and its four steps with a line of their output, shutdown).

Captured on 2026-09-24 (agent-vm 0.1.8: version, doctor, status) and 2026-09-25 (agent-vm 0.2.1: the rest) with `Tests/helpers/refresh_agentvm_fixtures.py`, which replaces the home folder with `/Users/you` and re-serializes with sorted keys. When agent-vm's JSON changes, run it again (its usage says how to prepare the boxes; `--lifecycle` starts a virtual machine) and rerun the suite: the drift checks fail when a field the library reads is gone. `--import` sanitizes a capture made by hand.
