# HU HU POOL

Meme 8-ball pool with idle progression for Roblox. Spec: [docs/GDD.md](docs/GDD.md).

## Setup (macOS)
1. Install Rokit: `curl -sSf https://raw.githubusercontent.com/rojo-rbx/rokit/main/scripts/install.sh | bash`,
   then open a new terminal (the installer adds `~/.rokit/bin` to PATH).
2. In the repo: `rokit install` — installs rojo, lune, selene, stylua, luau-lsp from `rokit.toml`.
3. Rojo plugin for Studio: `rojo plugin install`, then restart Roblox Studio.
4. `rojo serve`, open a place in Studio → Plugins → Rojo → **Connect** (localhost:34872).
5. Press Play: Output shows `[HU HU POOL] Server: Services started` and `[HU HU POOL] Client: Services started`.

## Checks
`scripts/check.sh` — format check, lint, strict type analysis, Lune tests.
