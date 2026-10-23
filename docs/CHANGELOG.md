# Changelog

## Phase 0 — environment and skeleton
- Toolchain via Rokit (`rokit.toml`): rojo 7.7.1, lune 0.11.1, selene 0.32.0, StyLua 2.6.0, luau-lsp 1.70.1.
- Rojo project: `src/shared` → ReplicatedStorage.Shared, `src/server` → ServerScriptService.Server,
  `src/client` → StarterPlayerScripts.Client.
- `Util/Loader` (Init all → Start all), `Util/Signal`, `Util/Trove`, `Util/RateLimiter` (token bucket, Lune-tested).
- `Net/Remotes`: single remote registry (`Shot`, `ShotResult`), `ShotParams` type.
- `Config/*` stubs; `Config/Physics` filled with GDD 4.1 starting values.
- Lune test runner `tests/run.luau`; `scripts/check.sh` runs stylua, selene, luau-lsp strict analysis and tests.
