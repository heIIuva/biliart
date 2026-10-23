# Фаза 0 HU HU POOL: тулчейн и каркас (сделано)
Тикет: — (ТЗ docs/GDD.md, раздел 21, фаза 0) · Коммиты: b90fd1f (ветка phase-0, без push) · Дата: 2026-10-23

## Симптомы — что наблюдалось, дословно
- Репозиторий: только LICENSE (MIT, heIIuva), README, .gitignore; один коммит `1a55edc Initial commit`.
- Тулчейна не было: `rokit/rojo/lune/selene/stylua/wally/luau-lsp: none`.
- `brew info rokit` → `Error: No available formula with the name "rokit"` — через brew не ставится.
- `rokit add rojo-rbx/rojo` → `ERROR The following tool has not been marked as trusted: rojo-rbx/rojo`
  (без TTY не спрашивает доверие) → лечится `rokit trust <tools...>` перед `rokit add`.
- `rokit add --global=false` → ошибка разбора аргументов (флаг булев, просто не передавать).
- selene (std roblox): `standard library function assert requires 2 parameters, 1 passed` в тестах →
  добавлены сообщения в assert, правило не отключали.
- luau-lsp: `Loader.luau(30,4): TypeError: Value of type '((any) -> ())?' could be nil` на `if module.Init then module:Init()` —
  уточнение типа поля не работает при вызове через `:`; лечится `local init = module.Init; if init then init(module) end`.

## Зачем — какую проблему решали, кто попросил
Пользователь дал полное ТЗ мемного бильярда для Roblox (HU HU POOL) — фаза 0: окружение, каркас, доки, раннер тестов.
Решения пользователя (AskUserQuestion, сохранены в памяти проекта `hu-hu-pool-decisions`):
тулчейн ставлю сам; Studio MCP (Place1) можно читать и править; ветка на фазу (`phase-N`), коммит без push;
ретро-предложение про pre-push хук — «позже».

## Что сделано — и почему так
- Rokit 1.2.0: официальный install.sh (прочитан перед запуском) → `~/.rokit`, PATH через `~/.zshenv` (`. "$HOME/.rokit/env"`).
  `rokit.toml`: rojo 7.7.1, lune 0.11.1, selene 0.32.0, StyLua 2.6.0, luau-lsp 1.70.1.
- `default.project.json`: src/shared → ReplicatedStorage.Shared, src/server → ServerScriptService.Server,
  src/client → StarterPlayer.StarterPlayerScripts.Client. `selene.toml` (std roblox), `stylua.toml` (Luau, tabs, 120).
- **Ключевое решение: require по строке.** Проверено в Studio через MCP execute_luau (временные ModuleScript в ServerStorage,
  удалены): `require("./B")` и `require("../Config/C")` → `true 11`. Значит модули shared подключают друг друга
  относительными путями — один код в Lune и в Roblox. Entry-скрипты (Main.server/client) — через instance-пути.
- `Util/Loader` (все Init, затем Start в task.spawn, порядок — сортировка по имени), `Signal`, `Trove`,
  `RateLimiter` (token bucket, инжектируемые часы → тестируется в Lune; методы Allow/Forget).
- `Net/Remotes`: реестр DEFINITIONS (`Shot`, `ShotResult`), тип `ShotParams`, `Remotes.Setup()` на сервере,
  `Remotes.Event/Function(name)` через WaitForChild.
- `Config/*` заглушки (Game, Physics, Titles, Spirits, Economy, Dojo, Monetization с напоминанием про paid random items,
  Ads, Events, QuickChat, Assets, Strings). Physics заполнен значениями из GDD 4.1; `StudsPerMeter = 6` — временно, тюнинг в фазе 2.
- `Main.server.luau` / `Main.client.luau` печатают `[HU HU POOL] Server|Client: Services started`.
- `tests/run.luau`: находит `tests/*.spec.luau` (динамический require в Lune работает), spec возвращает `{[name]: fn}`,
  exit 1 при падении или 0 файлов. Specs: smoke, rateLimiter.
- `scripts/check.sh`: stylua --check, selene, luau-lsp analyze (качает globalTypes.d.luau, `rojo sourcemap`), lune tests.
- Доки: `CLAUDE.md` (правила из разд. 0 и 2 + команды), `docs/GDD.md` (ТЗ целиком), `docs/ASSETS.md`, `docs/CHANGELOG.md`, README (установка).
- `.gitignore`: *.rbxl(x), lock-файлы, sourcemap.json, globalTypes.d.luau.
- Отброшено: пустые стабы 16 сервисов/9 контроллеров (YAGNI — появятся в своих фазах, Loader терпит отсутствие папки);
  `Util/Types.luau` (типы живут в модулях); Wally/ProfileStore — фаза 6; StreamingEnabled — позже.
- Опечатка в ТЗ: раздел 0 ссылается на «фазы — раздел 15», фазы на самом деле в разделе 21.

## Как проверял — команды, замеры, цифры
- `PATH="$HOME/.rokit/bin:$PATH" scripts/check.sh` → selene 0 errors, luau-lsp без ошибок, `3 passed, 0 failed (2 files)`, exit 0.
- Мутация: временный `tests/zz_tmp.spec.luau` с `assert(false)` → `FAIL ... 3 passed, 1 failed`, exit 1; `lune run tests/run nomatch` → exit 1.
- `rojo build -o <scratchpad>/build.rbxl` → `Built project`.
- `rojo plugin install` → `~/Documents/Roblox/Plugins/RojoManagedPlugin.rbxm`; `rojo serve` в фоне → localhost:34872.
- Studio MCP: `list_roblox_studios` → Place1 (id 4bfb1cdf-…); в Place1 нет ни одного LuaSourceContainer (синк ничего не затрёт).

## Почему так проверял
- check.sh ловит формат, lint, strict-типы против Roblox-определений и логику RateLimiter. Мутация доказывает, что раннер не «всегда зелёный».
- НЕ ловит: реальный запуск в Studio (порядок репликации, WaitForChild на клиенте, работу Loader/Remotes в рантайме).

## Итог и грабли
- Открыто: пользователь должен (перезапустить Studio, если нет вкладки Rojo) нажать Plugins → Rojo → Connect;
  затем через MCP: дерево → Play → get_console_output, ждать оба «Services started»; затем коммит в `phase-0`
  явными путями (без push) и стоп до подтверждения фазы 1.
- Грабли: rokit без TTY требует `rokit trust`; brew-формулы rokit нет; luau-lsp не сужает optional-поле при вызове через `:`.
- Ретро-предложение (pre-push хук по cwd) — отложено пользователем.

## Проверка в Studio (закрыто 2026-10-23)
- После перезапуска Studio id инстанса сменился (4bfb1cdf-… → 5ecc373e-…) — всегда заново `list_roblox_studios`.
- Rojo Connect → в дереве 19 скриптов (Server.Main, Client.Main, 17 ModuleScript в Shared).
- Play → консоль: `[HU HU POOL] Server: Services started`, `[HU HU POOL] Client: Services started`.
  Клиент видит `ReplicatedStorage.Remotes`: `Shot:RemoteEvent, ShotResult:RemoteEvent`.
- Шум в консоли `ContentId: rbxassetid://203785492 failed due to: Asset type does not match requested type` — не наш
  (в src нет ни одного asset id, grep пуст); вероятно, Studio/дефолтный персонаж.
- CLAUDE.md проекта НЕ закоммичен: глобальный `~/.config/git/ignore:2` его игнорит; пользователь решил оставить локальным.
  Ссылку на CLAUDE.md из README убрал.
