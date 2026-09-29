# Image recipes (test fixtures)

Copies of four recipes from agent-vm's `Recipes` folder, for the Box Manager tests.

Cadabra carries no recipes of its own. It offers the ones in the `Recipes` folder beside the installed agent-vm, which AgentVM's package puts in each version's folder (`~/.local/share/agent-vm/versions/<version>/Recipes`). The library finds that folder by resolving agent-vm's links (`agentvm_real_dir`), and under test agent-vm is `fake_agent_vm.sh` in this folder's parent, so these are the recipes the tests see.

They are copied rather than written for the tests, so the New Image window is tested against real recipes. Refresh them from an agent-vm checkout when its recipe format changes.

| Recipe | Installs | Build it from |
|---|---|---|
| `homebrew-node` | Homebrew and Node | an image installed from a macOS restore file |
| `acp-agents` | The ACP adapters Cadabra drives: Claude Agent ACP, Codex ACP and opencode | an image with Homebrew and Node |
| `xcode` | Xcode, from a `.xip` downloaded from Apple | an image installed from a macOS restore file (with a larger disk) |
| `xcode-platforms` | Simulator runtimes and Xcode components | an image with Xcode |
