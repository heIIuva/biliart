# Фазы 7–11 HU HU POOL: PvP, додзё, магазин и реклама, хаос и speed pool, события и live-конфиг (сделано офлайн; в Studio не проверено)
Тикет: — · Коммиты: 5631f60 (7), deaf61a (8), 9827116 (9), bff7d0c + fdf9e0a (10), bc29566 (11) · Дата: 2026-10-23

## Симптомы — что наблюдалось, дословно
- Rojo отваливается при Play: «WebSocket error: 400» → фазы 4–11 в Studio не проверены.
- luau-lsp: «Key 'id' is missing from '{|  |}' in the type '{ [unknown]: unknown } | {|  |}'» —
  `if type(h)=="table" then h :: T else {}` без аннотации локала; лечится `local entry: T = …`.
- luau-lsp: «Expected type table, got 'nil' instead» при `group = Instance.new(...)` в переменную,
  выведенную из `groups[name]` → отдельный `local existing`/`local group`.

## Зачем
Пользователь: «пуш в мастер и делай все оставшиеся фазы и потом выпиши чего не хватает», потом
«продолжай». Ветка на фазу, ff-merge в main, push после каждой фазы.

## Что сделано
- 7: TableService/MatchService (Casual/Ranked/Elo/King), KingTableService, SocialService, QuickChat.
- 8: Game/Dojo + DojoService (участки, доход, офлайн, перерождение), хуки addMultiplierSource.
- 9: ShopService — единственный ProcessReceipt, идемпотентность по PurchaseId; AdRewardService —
  награда за рекламу приходит чеком с каналом AdReward.
- 10: Chaos, Tricks (решения найдены tools/find_tricks.luau), Sandbox, рефактор физики в makeWorld
  (бинарно тот же break-трек 32971 байт), Speed pool (UnreliableRemoteEvent 20 Гц, интерполяция 100 мс).
- 11: Game/Events + EventService (мини-события, неделя, праздники, админ-эффекты), Game/LiveConfig +
  LiveConfigService (DataStore "LiveConfig"/"current", 5 мин + MessagingService "LiveConfigUpdated"),
  Text.override для переименования титулов, SettingsController + SetSettings (Validate.settings),
  SoundGroups и ducking в Sfx, EventController (баннер, новости, админ-панель).
  Отброшено: Localization.csv/LocalizationTable — текст идёт через Util/Text; вместо этого тест
  tests/strings.spec.luau (все литеральные ключи есть в Strings).
- Циклы require: EventService не требует MatchService/DojoService — они сами берут у него множители.

## Как проверял
`PATH="$HOME/.rokit/bin:$PATH" scripts/check.sh` → stylua ok, selene 0 errors/0 warnings, luau-lsp 0
ошибок, «99 passed, 0 failed (15 files)». API (UserGameSettings.SavedQualityLevel, AdService,
ProductPurchaseChannel.AdReward) — по globalTypes.d.luau в корне репо.

## Почему так проверял
Ловит: логику чистых модулей, типы, контракт строк. НЕ ловит: поведение в Studio (UI, сеть, DataStore,
покупки, реклама, мультиплеер) — всё это в docs/TECH_DEBT.md.

## Итог и грабли
- Все id = 0 (пропуски, продукты, группа, админы, ассеты) — список в docs/PUBLISHING.md.
- Не сделано: бонусы хаоса «гигантский биток» и «двойной биток»; Low-качество выключает только тряску.
- Поиск globalTypes через `find ~` висит >2 мин — файл лежит в корне репозитория.

## Проход в Studio (2026-10-23, ветка studio-fixes: af529cd, 8e17bc9)
Симптомы, дословно:
- «You must publish this place to use MemoryStoreService.» + стек `HypeService, Line 47 - function refresh` —
  GetSortedMap бросает в неопубликованном месте и убивал цикл счётчиков → pcall-обёртка sortedMap().
- Монета «▯» в панели валюты — эмодзи 🪙 не рисуется шрифтом Roblox → 💰.
- Кнопки Spirits/Daily не нажимались: колонка из 10 кнопок дошла до окна чата Roblox (ест клики) → 2 колонки.
- Панели Shop/Settings/Dojo открывались друг поверх друга → addButton(..., panel) закрывает остальные.
- Кнопки меню просвечивали поверх панели → ZIndex = 2 у Kit.panel и Codes; Events gui DisplayOrder 6.
- Трюк недели: справа оставались шары прошлой партии → applyBalls прячет шары, которых нет в состоянии.
- Баннер событий и валюта наезжали на панель матча → скрываются за столом.
- Кнопки песочницы лезли под «Встать» → панель режима по центру над ней.
- Золотые шары падали на бильярдные столы → lobbySpot() обходит столы (полуразмер 7.7×4.4 studs).
- «Все удары тигриные» не срабатывали на брейке: pottedOwn = 0 на открытом столе → potted > 0 и без фола.
Ложная тревога: RATTLE вместо TIGER на обучении — истёк таймер хода, брейк сделал бот; через remote TIGER.
Как проверял: Play в Studio через MCP, клики по instance_path (координаты из AbsolutePosition сдвинуты на
inset 58 — надёжнее instance_path), remotes из execute_luau Client, слушатели [chk] в консоли.
Грабли: execute_luau Server получает свежие экземпляры модулей (DataService.get → nil) — состояние смотреть
через remotes на клиенте. Rojo после Stop остаётся подключён: правки подхватываются до следующего Play.
Не проверено: 2 игрока, сохранения/DataStore, покупки — список в docs/TECH_DEBT.md.
