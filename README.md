# sm34.cssdm — CS:S DM для Counter-Strike: Source v34

Сборка [CS:S Deathmatch](https://github.com/alliedmodders/cssdm) (CSS:DM) под **CS:S v34** и SourceMod 1.10 с бинарниками для css34.

Исходники берутся из сабмодуля [`alliedmodders/cssdm`](https://github.com/alliedmodders/cssdm) (`2.1.6-dev`, tip `master`), затем на них накладываются патчи из `builder/patches/` (SDK Episode One / Engine v34, API ConVar/CCommand эпохи ep1, **v34 gamedata** из `builder/patches/2.1/gamedata/`, отключение CS:GO-таргетов). Upstream FFA-оффсеты для современного CS:S в пакет не попадают.

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

## CI

GitHub Actions (как в [fmu1337/sourcemod-css34](https://github.com/fmu1337/sourcemod-css34)):

| Workflow | Что делает |
|----------|------------|
| `Build` | Собирает `cssdm-*-css34-linux.tar.gz`, проверяет ELF/состав пакета |
| `Test Server` | Поднимает CS:S v34 + rom4s MM/SM, ставит CSS:DM, smoke (`cssdm.ext` + плагины) и короткий **botplay** |

Для bot-теста переиспользуются скрипты из `fmu1337/sourcemod-css34` (`testing/scripts`). Локально:

```bash
# после успешной сборки:
export CSSDM_PACKAGE=$PWD/OUT/package/cssdm-2.1.6-git270-css34-linux.tar.gz
export RECORD_SECS=120 INSTALL_SMAC=0
testing/scripts/cssdm-bot-test.sh
```

## Сборка

Сабмодуль `cssdm` должен быть инициализирован:

```bash
git submodule update --init --recursive
```

Зависимости (Linux):

- HL2SDK `episode1`
- Metamod:Source `1.10-dev` (исходники)
- SourceMod `1.10-dev` (исходники) + пребилд `sourcemod-*-css34-*` (spcomp / bin)
- AMBuild, `g++` multilib (`-m32`)

Пример:

```bash
export DEPS_DIR=$HOME   # hl2sdk-episode1, mmsource, sourcemod, sourcemod-bin
export CC=gcc CXX=g++
builder/run/linux.sh
```

Скрипт применяет патч из `builder/run/config.json` (ветка `2.1` → `1.patch`) и собирает:

`cssdm-<version>-git<N>-css34-linux.tar.gz`

В пакет подставляется gamedata из `builder/patches/2.1/gamedata/`.

## Структура репозитория

```
.github/workflows/ # Build + Test Server (botplay)
builder/
  patches/2.1/     # патчи и gamedata под ep1 / css34
  run/             # build.py, config.json, linux.sh, windows.bat
cssdm/             # сабмодуль upstream CSS:DM
testing/scripts/   # check/install/bot-test (smoke + botplay)
```

## Связанные проекты

- [rom4s/sourcemod-css34](https://github.com/rom4s/sourcemod-css34) — SourceMod под CS:S v34 (нужен для работы cssdm)
- [alliedmodders/cssdm](https://github.com/alliedmodders/cssdm) — исходный CSS:DM
- Upstream этого builder-репозитория: [rom4s/sm34.cssdm](https://github.com/rom4s/sm34.cssdm)

## Лицензия

GPL-2.0 (см. `LICENSE`). Upstream CSS:DM © AlliedModders LLC.
