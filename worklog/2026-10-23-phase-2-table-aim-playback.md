# Фаза 2 HU HU POOL: стол в мире, прицел, проигрывание (сделано, ждёт подтверждения; мобильный тач не проверен)
Тикет: — (docs/GDD.md, разделы 5, 9.3, 21) · Коммиты: 1da95a7 (ветка phase-2, без push) · Дата: 2026-10-23

## Симптомы — что наблюдалось, дословно
- Полосы/пятна шаров не видны: `band 0, 0, 0` при шаре в (3.66, 3.17, -19.8) — WeldConstraint запоминает смещение
  в момент активации, а шар ставился на стол ДО попадания в Workspace → дочерние части остались в начале координат.
- `Infinite yield possible on 'Players.<name>.PlayerScripts:WaitForChild("PlayerModule")'` — PlayerModule в этом
  месте нет (в PlayerScripts только RbxCharacterSounds и Client); из-за yield сигнал посадки не доходил до HUD (`hud enabled=false`).
- `PlayerGui.ScreenOrientation` оставался `Sensor`, хотя Main ставил LandscapeSensor (перезаписывается из StarterGui).
- Кнопки «Встать»/«Расставить заново» в левом верхнем углу не нажимались: UIS `lmb processed=true pos=99, 48`,
  а InputBegan/Activated кнопки молчат — вход съедает окно чата Roblox (оно в левом верхнем углу).
- luau-lsp: литеральные юнионы в локалах расширяются до string (`Expected '"Chinese8" | "Standard"' but got 'string | string'`),
  паттерн `local x = map[k]; if not x then x = new end` сужается в nil; колбэки событий без аннотации = 'a.
- selene падает (exit 1) и на warnings (roblox_manual_fromscale_or_fromoffset, unused_variable).
- Инструмент мыши MCP: координаты = GUI-пространство (сам добавляет inset 58 px); я прибавил inset второй раз → прицел ушёл вниз.

## Что сделано — и почему так
- Сервер: TableBuilder (примитивы по TableGeometry, StudsPerMeter=6, поверхность 3 studs, ModelStreamingMode=Atomic —
  StreamingEnabled в месте уже включён), TableService (free play): ProximityPrompt → посадка (HRP anchored, CFrame у
  изголовья), Shot → Validate.shotParams → simulateShot → TrajectoryCodec → FireAllClients; busyUntil = duration + 0.5 с;
  респот битка у head spot, перерасстановка при пустом столе; RateLimiter на Shot/Leave/Rerack.
- Клиент получает CFrame поверхности в payload (не зависит от стриминга модели), шары строит сам (anchored Part + Weld с C0).
- Проигрывание: треки по шару, «держать» шар на месте до кадра перед первым движением, CFrame:Lerp, события по t → Sfx-заглушки.
- Камера: Scriptable, FOV 12, дистанция под размер стола и аспект экрана, твин входа/выхода; при посадке
  ProximityPromptService.Enabled=false и GuiService.TouchControlsEnabled=false (вместо PlayerModule).
- Прицел: тач — палец указывает точку (а не вращение свайпом — проще и точнее), PC — курсор + ЛКМ с оттягиванием,
  ПКМ отмена, колесо/стрелки доводка. Кнопки HUD внизу по центру (не под чатом).
- Ориентация — свойство места в default.project.json (StarterGui.ScreenOrientation=LandscapeSensor), строка в Main убрана.
- Локализация: Util/Text (ru по LocalizationService.RobloxLocaleId), промпты локализуются на клиенте по атрибутам
  ActionKey/ObjectKey в PromptShown. Генерация LocalizationTable — фаза 11.

## Как проверял — команды, замеры, цифры
- `scripts/check.sh` → 25 passed (aim: 300 случайных сцен, AimPredictor == первое касание физики, угол прицельного < 1°;
  validate: NaN/inf/типы/диапазоны).
- Studio MCP (Play): обе «Services started»; 16+16 шаров; посадка по E → камера сверху, прицел в пирамиду;
  удар мышью (оттяжка ~70 px) → траектория проигралась, `[sfx stub] ...` по событиям, 1 шар забит; отмена ПКМ — биток на месте;
  RerackButton → 15 шаров сдвинулись (новый seed); LeaveButton → hud=false, camera=Custom, rootAnchored=false;
  прыжок 50°, сила 0.6 → подъём битка 0.036 м (расчёт 0.039 м).
- `rojo build` → ScreenOrientation=2 (LandscapeSensor) в собранном месте.

## Почему так проверял
- Синтетический ввод MCP проверяет мышиный путь и кнопки; НЕ проверяет тач (палец, шкала силы, колесо, панель винта) —
  это пользователь в эмуляторе устройства. Звук не проверен (ID = 0).

## Итог и грабли
- Rojo не применяет изменения default.project.json на лету — нужен перезапуск `rojo serve` + Connect; значение в месте
  выставлено через MCP вручную (то же, что выставит Rojo).
- ShotResult рассылается всем клиентам (ponytail-комментарий) — ограничить радиусом в фазе 7.
- Дырки луз — чёрные диски, частично перекрытые рамой; выглядят «квадратно» — косметика до арт-прохода.

## Дополнение: временные звуки (коммит f5b7b78, ветка phase-2-sfx, без push)
- Пользователь попросил найти бесплатные ассеты сам. Через MCP search_asset (Creator Store, Audio, free) нашлась
  библиотека «Pro Sound Effects» (creatorName ProSoundEffects, «Courtesy of Pro Sound Effects») — лицензирована Roblox
  для игр. Пользовательские загрузки («Pool Table SFX» от m6oru, «billiard hit … by aifoon on Freesound» от SwimyGreen)
  отброшены: происхождение/лицензия неизвестны.
- Клипы 0.9–1.8 с с несколькими ударами → играем отрезок: Sound.PlaybackRegionsEnabled + PlaybackRegion (NumberRange).
  Отрезки найдены огибающей пиков: AudioPlayer → Wire → AudioAnalyzer.PeakLevel по Heartbeat на клиенте (Play).
  Онсеты: BallHit 0.04 (пик 0.60), CueStrike 0.02 (0.10), Cushion 0.28, Jaw 0.21, Pocket 0.27/0.74/1.00, Land 0.27–0.34.
- Sfx: клон на каждое событие (Debris), Volume = gain × скорость-громкость, тот же ключ не чаще 30 мс.
- Проверка: разбой → 16 Sound IsPlaying, 5 разных ID, ошибок нет. НЕ проверено на слух (я не слышу) — пользователь.
