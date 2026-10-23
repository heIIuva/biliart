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

## Phase 2 — table in the world, aiming, playback
- Two free-play tables (Standard green, Chinese8 red) built from primitives, sized from TableGeometry
  (`server/World/TableBuilder`, `Config/Tables`); ProximityPrompt "Play" seats the player.
- `TableService` (free play, no rules): validates the shot (`Util/Validate`, Lune-tested), simulates,
  sends the encoded trajectory to all clients; respots a scratched cue ball, re-racks when the table is empty.
- `TableViewController`: client-side balls (stripe band / spot so rotation reads), top-down near-orthographic
  camera with tweened enter/leave, interpolated playback with orientation, sound stubs per event.
- `AimController` + `UI/TableHud`: touch (point on the table, power bar, fine wheel) and mouse (point, hold LMB
  and pull back, wheel/arrow keys, RMB cancels); spin and cue-elevation panel; cue stick and aim guide.
- `Pool/AimPredictor`: first contact, ghost ball, object/cue directions; tested against the simulation on 300 scenes.
- `World/TableSpace` maps simulation meters to Roblox CFrames; `Util/Text` resolves en/ru localization keys.
- Landscape orientation is a place setting (`StarterGui.ScreenOrientation` in `default.project.json`).

## Phase 3 — rules, match, bot
- `Pool/PoolRules` (31 scenarios), `Pool/BotPlanner` + `BotService` (3 levels), `MatchService`
  (turns, shrinking timer, ball in hand, called pocket, leaving loses), level picker / status / result UI.

## Phase 4 — hype system and tutorial
- Physics reports per-ball travel, cue curve drift (masse) and cue jumps.
- `Pool/ShotReport` + `Pool/ShotClassifier`: titles and anti-titles are data in `Config/Titles`
  (min/max/equals conditions, priority, secret flag); combo per visit.
- `Pool/TitleScenarios`: a layout + known shot for every title, found by `tools/find_scenarios.luau`
  and checked by tests; Studio-only debug panel replays any of them.
- `HypeService`: global title counters (MemoryStore with batching, DataStore backup), rarity %,
  server-wide announcements for Epic+, cross-server for Legendary (MessagingService, rate-limited).
- `HypeController`: slow motion and camera push-in at the decisive moment, splash (hanzi, name,
  rarity, combo), camera shake, title sound stub, announcement banner.
- Tutorial: offer on join, rigged first break (always TIGER, `Config/Tutorial`), 4 hints;
  `AnalyticsService` wrapper logs the onboarding funnel.

## Phase 5 — clip mode
- `ClipController`: "Clip" button after every shot (gold after a title); vertical 9:16 replay of
  the last shot centered on screen with black side bars, table turned long side up, title and game
  watermark inside the reels safe zones (top 12%, bottom 20%, right 15%, `Config/Clip`); buttons sit
  outside the frame; replay ends on an avatar close-up with an emote; screenshot via CaptureService.
- The avatar plays a reaction emote at the table after the player's own titled shot.

## Phase 6 — data and progression
- `DataService` on ProfileStore 1.0.3 (vendored in `src/server/Packages`, Apache-2.0): session lock,
  reconcile + `Progression.migrate`, batched snapshots to the client, currency/XP with analytics.
- `Game/Progression` (pure, tested): schema v1, levels, 7-day daily streak, spirit levels, quest picks
  and progress, match rewards. Configs: `Economy`, `Spirits`, `Cues`, `Quests`.
- `SpiritService` (unlock by title, levels, equip), `QuestService` (daily reward, daily/weekly quests),
  `CueService` (buy/equip; stats in casual matches, base cue in the tutorial), `LeaderboardService`
  (wins, shot of the day, boards in the lobby). Matches pay fixed coins/XP; leaving records a loss only.
- Client: currency bar, spirit index (silhouettes, "???" for secrets), daily, quests, cues menus,
  toasts, leaderboard boards; tutorial is offered only until done; aim guide length follows the cue.

## Phase 7 — PvP and social
- Two seats per table (head/foot); a third table and the gilded Tiger table for King of the table.
- `MatchService` modes: Bot, Casual and Ranked PvP (server queue, 20 s then "try the bot"), King.
  Ranked: base cue for everyone, Elo (K = 32, tested), rating board. PvP rewards are fixed coins.
- `KingTableService`: queue at the Tiger table, winner stays with a crown, fixed reward per defense,
  big spectator screen with a live top-down map of the balls (`BigScreenController`).
- `SocialService`: friends bonus (+10% per friend, max +30%), invites (LaunchData → reward delivered
  to the inviter's saved data via ProfileStore messages), one-time group bonus (group id to set),
  codes, quick chat phrases and emotes shown above the sender's head.
