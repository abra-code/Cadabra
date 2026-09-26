# Image recipes

The recipes the Box Manager's New Image window offers. Each folder holds a `recipe.json` for `agent-vm image create --recipe`, plus any files its steps copy into the image.

These are copies of the recipes in agent-vm's `Recipes` folder, from the same agent-vm checkout the bundled agent-vm is built from: `update-cadabra.sh` refreshes them whenever it rebuilds agent-vm. They are copied rather than generated, so a recipe's digest, which agent-vm records in every image built from it, changes only when agent-vm's recipe does.

| Recipe | Installs | Build it from |
|---|---|---|
| `homebrew-node` | Homebrew and Node | an image installed from a restore image |
| `acp-agents` | The ACP adapters Cadabra drives: Claude Agent ACP, Codex ACP and opencode | an image with Homebrew and Node |
| `xcode` | Xcode, from a `.xip` downloaded from Apple | an image installed from a restore image (with a larger disk) |
| `xcode-platforms` | Simulator runtimes and Xcode components | an image with Xcode |
