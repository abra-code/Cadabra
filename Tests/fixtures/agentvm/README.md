# agent-vm fixtures

Real `--json` answers of agent-vm, which `Tests/helpers/fake_agent_vm.sh` serves to the library tests (`Tests/45-agentvm-library.test.sh`, `Tests/47-agentvm-boxes.test.sh`, `Tests/48-agentvm-jobs.test.sh`).

- `version.json` - `agent-vm version --json`.
- `doctor.json` - `agent-vm doctor --json`. Its "running VMs" check is a `warning` (two virtual machines ran when it was captured), so to the library no slot is free.
- `box-status-stopped.json` - `agent-vm box status <box> --json` for a stopped box.
- `box-status-running.json` - the same for a running box with a project shared (read-only) and one program running in it, so every status field is present. Captured as `box-status-ready.json` with agent-vm 0.1.8; its state was changed by hand to `running`, what agent-vm says for a running box since 0.2.18.
- `box-status-unresponsive.json` - made by hand from `box-status-stopped.json` (state `unresponsive`, `running` true, a `statusError`), because a wedged supervisor cannot be produced on request. It follows `BoxStatus.of` in agent-vm's `Sources/AgentVMKit/Boxes/BoxStatus.swift`.
- `image-list.json`, `box-list.json`, `packs.json` - `image list`, `box list` and `box packs`. The boxes were all stopped, so the running fields (`pid`, `project`, `ownerPid`) are absent here; `box-status-running.json` carries them.
- `execlog.json`, `netlog.json` - `box execlog <box> --last 5` and `box netlog <box> --last 5`.
- `box-create.json` - `box create <box> --image dev --memory-gb 4 --allow pack:npm --allow example.com --disposable`.
- `box-start.json`, `box-start.events`, `box-stop.events` - what `box start` prints on standard output, and the progress events of `box start` and `box stop` on standard error. The state in `box-start.json` and the last step in `box-start.events` were changed by hand from `ready` to `running`, as agent-vm 0.2.18 and later print them.
- `image-info.json`, `box-info.json` - `agent-vm image info dev-agents --json` and `box info try1 --json` (agent-vm 0.2.18, 2026-09-26): the list entry or status plus `diskUsage`, and for a derived image `addedOverBase`. Since 0.2.18 the lists and `box status` carry no `diskUsage`; the older captures above still do.
- `secret-list.json` - `agent-vm secret list --json` (agent-vm 0.2.12, 2026-09-26), with a second, readable entry added by hand so both states are present.
- `session-start.json`, `session-list.json`, `session-report.json` - `agent-vm session start --project P`, `session list` and `session report <id>` (agent-vm 0.4.4, 2026-09-30), on a scratch project in which, after the start, a file was changed and one deleted, a git hook was added, a symbolic link to `~/.ssh` made, a `postinstall` script added to `package.json`, and a new folder made holding a git hook (so the report lists entries covered by their folder's change). Imported with `--import`; read by `Tests/48-project-snapshot.test.sh`, which runs the real agent-vm for everything else about sessions (`fake_agent_vm.sh`'s `session-agent-vm`).
- `update-guest.events` - made by hand, following the steps agent-vm's `Docs/progress-events.md` lists for `image update-guest` (a guest update boots a VM, which the capture avoided).
- `image-create.events` - made by hand the same way, for `image create --from dev --recipe homebrew-node` (clone, boot, the recipe and its four steps with a line of their output, shutdown).

Captured on 2026-09-24 (agent-vm 0.1.8: version, doctor, status) and 2026-09-25 (agent-vm 0.2.1: the rest) with `Tests/helpers/refresh_agentvm_fixtures.py`, which replaces the home folder with `/Users/you` and re-serializes with sorted keys. When agent-vm's JSON changes, run it again (its usage says how to prepare the boxes; `--lifecycle` starts a virtual machine) and rerun the suite: the drift checks fail when a field the library reads is gone. `--import` sanitizes a capture made by hand.

Checked against agent-vm 0.3.8 on 2026-09-28: a fresh capture of the queries (version, doctor, the lists, packs, a stopped box's status and logs) lost no field the library reads, only the `diskUsage` the lists stopped carrying in 0.2.18. The fixtures above were kept rather than replaced, because the tests are written around what they hold (two running VMs in `doctor.json`, the five images of `image-list.json`); a new capture reflects whatever the store holds that day.
