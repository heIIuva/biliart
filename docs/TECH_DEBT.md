# Tech debt

Open items deferred by decision. Close an item by checking it and noting the commit.

## Phase 2 — table in the world, aiming, playback (deferred 2026-10-23)
- [ ] Mobile check in the Studio device emulator: aim by touch, power bar (pull down / slide back to cancel),
      fine wheel, spin/elevation panel, smooth playback. Only the mouse path was verified (MCP cannot emulate touch).
- [ ] Decide touch aiming: finger points at the target (current) vs. swipe rotates the cue around the cue ball (GDD 5).
- [ ] Listen to the temporary sounds; check that the `Pocket` region (0.65–1.5 s) is really the drop into the pocket.
      Break hits collapse into one click (same sound at most every 30 ms) — revisit if it sounds thin.
- [ ] Seat at the Chinese8 table in Studio (only its geometry is covered by tests).
- [ ] Reconnect Rojo after restarting `rojo serve` and confirm it applies `StarterGui.ScreenOrientation` itself
      (set by hand in the place for now).
- [ ] Measure the ShotResult payload (~35 KB per break) in a multi-player session.
