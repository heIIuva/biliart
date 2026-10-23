# Changelog

## Phase 0 — environment and skeleton
- Toolchain via Rokit (`rokit.toml`): rojo 7.7.1, lune 0.11.1, selene 0.32.0, StyLua 2.6.0, luau-lsp 1.70.1.
- Rojo project: `src/shared` → ReplicatedStorage.Shared, `src/server` → ServerScriptService.Server,
  `src/client` → StarterPlayerScripts.Client.
- `Util/Loader` (Init all → Start all), `Util/Signal`, `Util/Trove`, `Util/RateLimiter` (token bucket, Lune-tested).
- `Net/Remotes`: single remote registry (`Shot`, `ShotResult`), `ShotParams` type.
- `Config/*` stubs; `Config/Physics` filled with GDD 4.1 starting values.
- Lune test runner `tests/run.luau`; `scripts/check.sh` runs stylua, selene, luau-lsp strict analysis and tests.

## Phase 1 — physics
- `Pool/PoolPhysics.simulateShot`: slide → roll friction model (follow, draw, stun, masse emerge from it),
  vertical-axis spin decay, cushion friction (side spin bends rebounds), jump shots with bounces,
  pockets with jaws/knuckles, rattle and off-table detection. Exact time-of-impact search inside
  240 Hz steps: no tunneling at any speed (tested at 30 Hz). Deterministic; break ≈ 4.5 ms in Lune and Studio.
- Events `{t, kind, a, b, speed}`: CueStrike, BallBall, BallCushion, BallJaw, Pocketed, Airborne, Landed,
  Rattle, OffTable. Frames at 60 Hz with position, height and orientation (quaternion) of moving balls.
- `Pool/TableGeometry`: Standard (pockets 120/130 mm) and Chinese8 (95/100 mm) variants.
- `Pool/Rack.eightBall(geometry, seed)`: seeded sub-millimeter jitter, required for realistic breaks.
- `Pool/TrajectoryCodec`: buffer encoding (0.1 mm positions, int16 quaternions); a break is ~33–38 KB.
- Tests: physics (GDD 4.4 + jump, masse, side spin, Chinese8), codec round trip, break benchmark.
