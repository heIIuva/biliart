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

## Phases 3–6 — not verified in Studio (2026-10-23)
Rojo disconnected from Studio when Play started; phases 4–6 were built and checked offline only
(Lune tests, strict types, lint). Phase 3 was checked in Studio (match vs bot, ball in hand, timer).
- [ ] Reconnect Rojo and run a full Studio pass: tutorial offer → rigged TIGER break → splash;
      debug panel (DBG) replays each title; clip mode (vertical frame, safe zones, close-up, screenshot);
      currency bar, spirits/daily/quests/cues menus; leaderboards; data survives a rejoin.
- [ ] Phase 3 in Studio: called pocket on the 8, match end and result screen, leaving mid-match.
- [ ] Verify APIs flagged `TODO(verify-api)`: AnalyticsService:LogProgressionEvent argument order;
      also CaptureService:CaptureScreenshot / PromptSaveCapturesToGallery, Humanoid:PlayEmote with
      default emotes, AnalyticsService:LogOnboardingFunnelStepEvent / LogEconomyEvent / LogCustomEvent.
- [ ] Enable "Studio Access to API Services" to test DataStore/MemoryStore (otherwise ProfileStore
      uses its mock and rarity % stays hidden).
- [ ] Hanzi and title names are placeholders: native speaker check.

## Not started (stopped after phase 6 at the user's request)
- Phase 7: PvP, queue, ranked (Elo), King of the table, spectators/big screen, quick chat, emotes,
  friends bonus, invites, group bonus.
- Phase 8: dojo (plots, tables, NPC students, till, offline income, upgrades, rebirth).
- Phase 9: ShopService (game passes, products, single ProcessReceipt, gifts, server hype, starter pack),
  shop UI, AdRewardService and the four ad placements.
- Phase 10: chaos mode, glitch titles, trick of the week, sandbox, speed pool.
- Phase 11: EventService, admin commands, LiveConfigService, LocalizationTable generation, sound/quality
  settings, low-end optimisation, publishing checklist.
