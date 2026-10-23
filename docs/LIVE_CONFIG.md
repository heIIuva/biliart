# Live config

Changes some game settings without a new release. Stored as a JSON string in DataStore
`LiveConfig`, key `current`. Servers read it on start, every 5 minutes, and right away when a
message is published to the MessagingService topic `LiveConfigUpdated`.

Each field is checked on its own (`src/shared/Game/LiveConfig.luau`, tests in
`tests/liveconfig.spec.luau`). An invalid field is skipped with a `[LiveConfig]` warning in the
server log; the other fields still apply. A missing field uses the value from `Config`.

## Fields (all optional)

| Field | Format | Effect |
|---|---|---|
| `disabledTitles` | `["TIGER", …]` known title ids | the classifier never gives these titles |
| `titleNames` | `{ "TIGER": { "en": "…", "ru": "…" } }`, en ≤ 40 chars | renames a title for clients |
| `codes` | `{ "NEWYEAR": { "coins": 500, "gems": 5 } }`, UPPERCASE ≤ 24 chars, coins ≤ 1e6, gems ≤ 1e4 | replaces the code list (one redemption per player per code) |
| `miniOrder` | `["GoldenHour", "TigerNight", "LanternRain"]` | order of the 30-minute mini events |
| `holidays` | `[{ "id": "X", "nameKey": "HOLIDAY_LANTERNS", "from": "MM-DD", "to": "MM-DD" }]` UTC, `nameKey` must exist in Strings | replaces the holiday list (x2 XP) |
| `flags` | `{ "Ads": false, "Chaos": true, "Speed": …, "Trick": …, "Sandbox": …, "Ranked": … }` | turns modes or rewarded ads off; anything not listed stays on |
| `news` | `{ "en": "…", "ru": "…" }`, en ≤ 160 chars | a news line under the event banner |

Example:

```json
{
  "disabledTitles": ["QUANTUM"],
  "titleNames": { "TIGER": { "en": "Tiger King", "ru": "Король тигров" } },
  "codes": { "HUHU": { "coins": 300 } },
  "flags": { "Speed": false },
  "news": { "en": "Lunar New Year starts on Friday!", "ru": "Китайский Новый год — с пятницы!" }
}
```

## Changing it from Studio

Needs "Enable Studio Access to API Services" (Game Settings → Security) on the published place.
Paste into the Command Bar:

```lua
local json = [[{ "flags": { "Speed": false } }]]
game:GetService("HttpService"):JSONDecode(json) -- fails here if the JSON is broken
game:GetService("DataStoreService"):GetDataStore("LiveConfig"):SetAsync("current", json)
pcall(function() game:GetService("MessagingService"):PublishAsync("LiveConfigUpdated", "") end)
```

If the publish fails (Studio edit mode may not reach live servers), servers pick the change up
within 5 minutes. To reset everything, set `"{}"`.
