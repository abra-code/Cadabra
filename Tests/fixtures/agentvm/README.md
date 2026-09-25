# agent-vm fixtures

Real `--json` answers of agent-vm, which `Tests/helpers/fake_agent_vm.sh` serves to the library tests (`Tests/45-agentvm-library.test.sh`).

- `version.json` - `agent-vm version --json`.
- `doctor.json` - `agent-vm doctor --json`.
- `box-status-stopped.json` - `agent-vm box status <box> --json` for a stopped box.
- `box-status-ready.json` - the same for a running box with a project shared (read-only) and one program running in it, so every status field is present.
- `box-status-unresponsive.json` - made by hand from `box-status-stopped.json` (state `unresponsive`, `running` true, a `statusError`), because a wedged supervisor cannot be produced on request. It follows `BoxStatus.of` in agent-vm's `Sources/AgentVMKit/Boxes/BoxStatus.swift`.

Captured from agent-vm 0.1.8 on 2026-09-24 with `Tests/helpers/refresh_agentvm_fixtures.py`, which replaces the home folder with `/Users/you` and re-serializes with sorted keys. When agent-vm's JSON changes, run it again (its usage says how to prepare the boxes) and rerun the suite: the drift checks fail when a field the library reads is gone.
