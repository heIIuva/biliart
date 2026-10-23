# Assets needed from the author

Every asset is referenced by key from `src/shared/Config/Assets.luau` (or `Monetization.luau` for passes/products).
ID `0` = placeholder: the game falls back to primitives / `print` stubs.
Only original assets — nothing ripped from other games or videos.

| Phase | Key | Type | Description | Status |
|---|---|---|---|---|
| 2 | `Sounds.CueStrike` | Sound | Cue tip hits the cue ball: short leather "tok". Volume scales with power. | needed |
| 2 | `Sounds.BallHit` | Sound | Ball-ball click, crisp and short (< 0.3 s). Played at volume 0.05–1 by impact speed. | needed |
| 2 | `Sounds.CushionHit` | Sound | Dull thud of a ball on a rubber cushion. | needed |
| 2 | `Sounds.JawHit` | Sound | Ball knocking the pocket jaw (rattle): harder, wooden. | needed |
| 2 | `Sounds.Pocket` | Sound | Ball dropping into the pocket and rolling in the gully. | needed |
| 2 | `Sounds.Land` | Sound | Jumped ball landing on the cloth: soft thump. | needed |

Not needed yet: table/cue/ball models (primitives are fine until the art pass), fonts (chosen by the author later).
