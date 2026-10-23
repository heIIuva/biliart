# HU HU POOL — шары и кий

Всё сгенерировано скриптами из `tools/` (Python + numpy + Pillow), чужих ассетов нет.
Перегенерировать (из `assets/`): `python3 tools/make_balls.py balls` и `python3 tools/make_cue.py`.

## Что внутри

| Файл | Что это |
|---|---|
| `balls/pool_ball.obj` | одна UV-сфера на все шары (2976 треугольников, диаметр 1, полюс по оси X) |
| `balls/textures/ball_00..15.png` | текстуры 1024×512: 0 — биток с 6 красными точками (видно вращение и винт), 1–7 сплошные, 8 чёрный, 9–15 полосатые; 6 и 9 подчёркнуты |
| `balls/preview.png` | как это выглядит на сфере |
| `cue/cue.obj`, `cue/cue.png` | кий: длина 1, ось X, наконечник на +X; текстура 1024×128 |

## Как завести в Studio (~3 минуты)

1. **Текстуры:** Window → Asset Manager → Bulk Import → выбрать все 16 `ball_XX.png` и `cue.png`.
2. **Меш шара:** File → Import 3D → `pool_ball.obj`. Переименовать в `BallMesh`, `Anchored = true`,
   `CollisionFidelity = Box`, положить в `ReplicatedStorage.Assets`. Сохранить как `assets/BallMesh.rbxm`
   (правый клик → Save to File) и прописать в `default.project.json`.
3. **Кий:** так же импортировать `cue.obj` → `CueMesh`, `TextureID` = id `cue.png`,
   `Size = (1.47, 0.029, 0.029) × StudsPerMeter`.
4. ID картинок вписать в `Config/Assets.luau` (`BallTextures`, `CueTexture`).

Ориентация совпадает с текущим кодом: при единичном повороте номер смотрит вверх в камеру стола
и читается правильно, полоса идёт вокруг оси X — как была цилиндрическая полоса.
