# Фазы 4–6 HU HU POOL: хайп, клип, данные и прогрессия (сделано офлайн; в Studio не проверено)
Тикет: — (docs/GDD.md 7–10, 21) · Коммиты: 3b0ca80 (ф.4), ae50fd6 (ф.5), ф.6 — см. git log · Дата: 2026-10-23

## Симптомы — что наблюдалось, дословно
- Rojo в Studio отваливался при входе в Play: `[Rojo-Warn] Disconnected from an error: WebSocket error: 400 - Failed ws recv`.
  Новые модули в место не попадали → фазы 4–6 проверены только офлайн.
- hype.spec: `tiger conditions hold` падал — в сценарии EIGHT_DOOM у отчёта foul = WrongBallFirst (тест чистит foul).
- Типизация luau-lsp (повторяется): литеральные юнионы в локалах и в for-переменных, `x or {}` в `for … in`
  (нужен `(x or {}) :: T`), сужение после assert (`"Stationary" cannot be compared with "Pocketed"`), инвариантность
  таблиц для `{ [string]: string | number }` (заменено на `{ [string]: any }`), тип-кортеж `{ { Page, string } }` невалиден.
- Python-скрипт правок упал на «пустой» замене с неверным отступом → часть файла не записалась; проверять assert на каждой замене.

## Что сделано
- Ф.4: физика отдаёт travel/cueCurve/cueJumps; ShotReport + ShotClassifier, титулы — данные (Config/Titles);
  TitleScenarios + tools/find_scenarios.luau (перебор нашёл удары для всех 15 титулов за 0.6 с, хранятся с %.17g);
  HypeService (MemoryStore SortedMap + DataStore бэкап, MessagingService для Legendary), HypeController (slow-mo,
  push-in, заставка, тряска от сохранённой позы — иначе дрейф), обучение с подстроенным TIGER, AnalyticsService, DBG-панель.
- Ф.5: ClipController — вертикальная рамка 9:16, безопасные зоны, кнопки вне рамки, финальный план аватара (PlayEmote).
- Ф.6: ProfileStore 1.0.3 завендорен в src/server/Packages (проверен: HttpService только GenerateGUID, без loadstring);
  Game/Progression (чистый, 6 тестов), DataService/SpiritService/QuestService/CueService/LeaderboardService, меню.
  Бот планирует с теми же множителями силы/винта своего кия, что применяются при исполнении.

## Как проверял
- `scripts/check.sh` → 73 passed (10 файлов), strict-типы и selene чистые. Studio — нет (Rojo).

## Итог и грабли
- Пользователь попросил остановиться на ближайшей фазе → остановился после фазы 6. Остаток — docs/TECH_DEBT.md.
