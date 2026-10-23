# Assets needed from the author

Every asset is referenced by key from `src/shared/Config/Assets.luau` (or `Monetization.luau` for passes/products).
ID `0` = placeholder: the game falls back to primitives / `print` stubs.
Only original assets — nothing ripped from other games or videos.

| Phase | Key | Type | Description | Status |
|---|---|---|---|---|
| 2 | `Sounds.CueStrike` | Sound | Cue tip hits the cue ball: short leather "tok". Volume scales with power. | temp: Pro Sound Effects 9113441098 · 0–0.2 s |
| 2 | `Sounds.BallHit` | Sound | Ball-ball click, crisp and short (< 0.3 s). Played at volume 0.05–1 by impact speed. | temp: Pro Sound Effects 9113440232 · 0–0.14 s |
| 2 | `Sounds.CushionHit` | Sound | Dull thud of a ball on a rubber cushion. | temp: Pro Sound Effects 9113440925 · 0.24–0.5 s |
| 2 | `Sounds.JawHit` | Sound | Ball knocking the pocket jaw (rattle): harder, wooden. | temp: Pro Sound Effects 9113440927 · 0.17–0.4 s |
| 2 | `Sounds.Pocket` | Sound | Ball dropping into the pocket and rolling in the gully. | temp: Pro Sound Effects 9113442190 · 0.65–1.5 s |
| 2 | `Sounds.Land` | Sound | Jumped ball landing on the cloth: soft thump. | temp: Pro Sound Effects 9113441345 · 0.23–0.5 s |
| art | `BallTextures[0..15]` | Image | Ball textures `assets/balls/textures/ball_XX.png` on the template mesh `ReplicatedStorage.Assets.BallMesh` (`assets/balls/pool_ball.obj`). 0 = primitive ball. | files ready, not uploaded |
| art | `CueTexture` | Image | Cue texture `assets/cue/cue.png` for `assets/cue/cue.obj`. | files ready, not uploaded, not wired |

Temporary sounds come from the Roblox Creator Store "Pro Sound Effects" library (free to use in
Roblox experiences). Each clip holds several hits, so only a region plays (found from the clip's
peak envelope in Studio). Replace with own recordings when ready: set `id`, `start`, `length`, `gain`.

Not needed yet: table model (primitives are fine until the art pass), fonts (chosen by the author later).
