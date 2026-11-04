# sm34.cssdm — CS:S DM для Counter-Strike: Source v34

Сборка [CS:S Deathmatch](https://github.com/alliedmodders/cssdm) (CSS:DM) под **CS:S v34** (SDK Episode One). Исходники берутся из сабмодуля `cssdm`, поверх накладываются патчи из `builder/patches/`: Engine v34, ConVar/CCommand эпохи ep1, gamedata, без CS:GO-таргетов.

Нужен только DM-серверу: cssdm зависит от SourceMod, но SourceMod от cssdm не зависит.

## Артефакты

Workflow `Build` собирает по одному пакету на каждую линию SourceMod (артефакты прогона на `master`):

| Артефакт | Для какого SM | Бинарники | Extension API |
|---|---|---|---|
| `cssdm-css34-sm13-linux` | [fmu1337/sourcemod-css34](https://github.com/fmu1337/sourcemod-css34) 1.13 | `cssdm.ext.2.ep1.so` | 11 |
| `cssdm-css34-sm12-linux` | fmu1337/sourcemod-css34 1.12 | `cssdm.ext.2.ep1.so` | 8 |
| `cssdm-css34-linux` | SM 1.10–1.12 (линия sm11, исходники SM/MM 1.10-dev), оба ядра | `cssdm.ext.1.ep1.so` + `cssdm.ext.2.ep1.so` | 8 |

**Какой пакет на каком SM реально работает — см. [docs/COMPAT.md](docs/COMPAT.md).** Коротко:

- SM 1.13 → `sm13`.
- SM 1.10–1.12 (наш форк, rom4s, MyArena 1.11; ядра `1.ep1` и `2.ep1`) → `cssdm-css34-linux`; на SM 1.12 подходит и `sm12`.
- SM 1.9 и старше — рабочего cssdm нет.

## Как устроена сборка

`builder/run/build.py` (через `builder/run/linux.sh`):

1. применяет `builder/patches/2.1/1.patch`;
2. патчи линии: sm11 — `builder/patches/mm110/2.1/*.patch` (`SMM_API` с видимостью `default`: без него Metamod не находит `CreateInterface` и пишет `Failed to get API`); sm12/sm13 — `builder/patches/mm112/2.1/*.patch` (без `1.ep1`, в MM 1.12 нет `core-legacy`; C++17; `-fno-sized-deallocation`);
3. собирает AMBuild-ом и кладёт gamedata из `builder/patches/2.1/gamedata/`.

Зависимости (HL2SDK `episode1`, исходники Metamod/SourceMod и пакет SM ради `spcomp`) ставит `builder/run/checkout-deps.sh`. Для sm12/sm13 всё берётся из релизов-указателей форка `line-sm12-latest` / `line-sm13-latest` (`builder/run/css34_line.py`): коммиты SM/MM и тег релиза — из их `lines.json`, пакеты проверяются по `SHA256SUMS`. Номера релизов форк удаляет, указатели — нет.

```bash
git submodule update --init --recursive
export CSSDM_SM_LINE=sm13 DEPS_DIR=$HOME CC=gcc CXX=g++
bash builder/run/checkout-deps.sh
builder/run/linux.sh   # → OUT/package/cssdm-<ver>-git<N>-css34-sm13-linux.tar.gz
```

## CI

| Workflow | Что делает |
|---|---|
| `Build` | Собирает все линии, проверяет состав пакета, ELF i386 и extension API (читается из `GetExtensionVersion()` в бинарнике) |
| `Test Server` | CS:S v34 + MM/SM нужной линии, smoke: `cssdm.ext` и DM-плагины загружены. Для sm12/sm13 ещё botplay (на sm11 только smoke) |
| `Compat` | Матрица «сборка SourceMod × пакет CSS:DM» → [docs/COMPAT.md](docs/COMPAT.md) |

Тестовые скрипты лежат в `testing/scripts/`; сервер и harness берутся из [fmu1337/sourcemod-css34](https://github.com/fmu1337/sourcemod-css34) (`testing/scripts`).

## Связанные проекты

- [fmu1337/sourcemod-css34](https://github.com/fmu1337/sourcemod-css34) — SourceMod 1.11–1.13 под CS:S v34
- [rom4s/sourcemod-css34](https://github.com/rom4s/sourcemod-css34) — исходный SourceMod css34 (1.10/1.11)
- [alliedmodders/cssdm](https://github.com/alliedmodders/cssdm) — исходный CSS:DM; upstream этого репо — [rom4s/sm34.cssdm](https://github.com/rom4s/sm34.cssdm)

## Лицензия

GPL-2.0 (см. `LICENSE`). CSS:DM © AlliedModders LLC.
