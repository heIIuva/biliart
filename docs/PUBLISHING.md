# Publishing checklist

Everything a release needs that the code cannot do by itself.

## Place and access
- [ ] Publish the place; Game Settings → Security: **Enable Studio Access to API Services** (DataStore,
      MessagingService, MemoryStore) for testing; leave HTTP off (not used).
- [ ] Complete the **Experience Questionnaire** (maturity / content labels). The game has no free text
      chat of its own (quick chat phrases only) and no wagering.
- [ ] Supported devices: Phone, Tablet, Computer, Console (gamepad is not tuned yet — consider leaving
      Console off). Orientation: landscape (set in the project file).
- [ ] Icon (512×512) and thumbnails/video. No "8 Ball Pool" / Miniclip names or look-alike art.
- [ ] Description and genre; social links if any.

## IDs (every `id = 0` is a placeholder)
- [ ] `Config/Monetization`: create every game pass and developer product, paste the ids. Product
      prices are the GDD ones. Rewarded-ad products also need the ad option enabled.
- [ ] `Config/Ads`: rewarded ads enabled for the experience (eligibility rules apply).
- [ ] `Config/Social`: `GroupId` of the community group.
- [ ] `Config/Admins`: `UserIds` of the admins (admin panel + event commands).
- [ ] `Config/Assets`: replace temporary sounds (Pro Sound Effects library, see `docs/ASSETS.md`) and
      add images/meshes; every asset must be owned by the experience owner or be public.
- [ ] `Config/Tables` big screen and lobby art.

## Data and live ops
- [ ] Check DataStore budgets: ProfileStore autosave + LiveConfig reads (1 per server per 5 min).
- [ ] Write the initial live config (`docs/LIVE_CONFIG.md`), at least `"{}"`.
- [ ] Analytics: confirm funnel / economy / progression events show up in the Creator Dashboard.

## Before going public
- [ ] Full pass in Studio and on a phone (see `docs/TECH_DEBT.md`, phases 2–11 checks).
- [ ] Hanzi and title names checked by a native speaker; Chinese theme reviewed for respect.
- [ ] Paid random items: none. If ever added — odds before purchase + `PolicyService`.
- [ ] Private server price (optional) and a test run with 6+ players on a live server.
