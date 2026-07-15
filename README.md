# sm34.cssdm — CS:S DM для Counter-Strike: Source v34

Сборка [CS:S Deathmatch](https://github.com/alliedmodders/cssdm) (CSS:DM) под **CS:S v34** и SourceMod 1.10 с бинарниками для css34.

Исходники берутся из сабмодуля [`alliedmodders/cssdm`](https://github.com/alliedmodders/cssdm), затем на них накладываются патчи из `builder/patches/` (SDK Episode One / Engine v34, API ConVar/CCommand эпохи ep1, gamedata, отключение CS:GO-таргетов).

## Нужен ли этот проект для sourcemod-css34?

**Нет.** Этот репозиторий **не является частью** [sourcemod-css34](https://github.com/rom4s/sourcemod-css34) и **не нужен**, чтобы собрать или запустить сам SourceMod под CS:S v34.

| Вопрос | Ответ |
|--------|--------|
| Нужен ли cssdm, чтобы работал sourcemod-css34? | Нет |
| Нужен ли sourcemod-css34, чтобы работал cssdm? | Да |
| Когда ставить этот проект? | Только если на сервере нужен режим **Deathmatch** (респавн, FFA, слоты оружия, спавны и т.д.) |

Связь односторонняя: **cssdm зависит от SM css34**, а не наоборот.

Типичный стек для DM на v34:

1. CS:S dedicated (v34)
2. Metamod:Source
3. [sourcemod-css34](https://github.com/rom4s/sourcemod-css34) (или совместимые бинарники SM 1.10 css34)
4. **Этот пакет CSS:DM** — по желанию

## Что делает CSS:DM

- Режим deathmatch поверх обычного `cstrike`
- Быстрый респавн, экипировка, спавны
- Free-for-all (FFA) через gamedata/патчи
- Конфиг: `cfg/cssdm/`, расширения `cssdm.ext.*.ep1`, плагины SourceMod

Оригинал: [bailopan.net/cssdm](http://bailopan.net/cssdm/), исходники: [alliedmodders/cssdm](https://github.com/alliedmodders/cssdm).

## Сборка

Сабмодуль `cssdm` должен быть инициализирован:

```bash
git submodule update --init --recursive
```

Сборка рассчитана на CI (`.travis.yml`):

- **Linux / Windows**
- HL2SDK `episode1`
- Metamod:Source `1.10-dev`
- SourceMod `1.10-dev` + пребилды `sourcemod-*-css34-*`
- AMBuild, Clang 9 (Linux)

Локально (Linux, после подготовки зависимостей как в CI):

```bash
builder/run/linux.sh
```

Скрипт применяет патч из `builder/run/config.json` (ветка `2.1` → `1.patch`), конфигурирует и собирает пакет вида:

`cssdm-<version>-git<N>-css34-linux.tar.gz` / `…-windows.zip`

В пакет подставляется gamedata из `builder/patches/2.1/gamedata/` (сигнатуры/оффсеты под v34).

## Структура репозитория

```
builder/
  patches/2.1/     # патчи и gamedata под ep1 / css34
  run/             # build.py, config.json, linux.sh, windows.bat
cssdm/             # сабмодуль upstream CSS:DM
```

## Связанные проекты

- [rom4s/sourcemod-css34](https://github.com/rom4s/sourcemod-css34) — SourceMod под CS:S v34 (нужен для работы cssdm)
- [alliedmodders/cssdm](https://github.com/alliedmodders/cssdm) — исходный CSS:DM
- Upstream этого builder-репозитория: [rom4s/sm34.cssdm](https://github.com/rom4s/sm34.cssdm)

## Лицензия

GPL-2.0 (см. `LICENSE`). Upstream CSS:DM © AlliedModders LLC.
