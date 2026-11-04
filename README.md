# sm34.cssdm — CS:S DM для Counter-Strike: Source v34

Сборка [CS:S Deathmatch](https://github.com/alliedmodders/cssdm) (CSS:DM) под **CS:S v34**. Исходники — сабмодуль `cssdm`, поверх накладываются патчи из `builder/patches/`.

## Какой пакет ставить

Пакеты — артефакты workflow `Build` на `master`:

| Пакет | SourceMod |
|---|---|
| `cssdm-css34-linux` | SM 1.10 и новее, до 1.12: наш [sourcemod-css34](https://github.com/fmu1337/sourcemod-css34) 1.11/1.12, SM от [rom4s](https://github.com/rom4s/sourcemod-css34), MyArena 1.11. Оба ядра (`1.ep1` и `2.ep1`) |
| `cssdm-css34-sm13-linux` | отдельная версия для SM 1.13 (наш sourcemod-css34) |

На SM 1.9 и старше cssdm не работает. `cssdm-css34-sm12-linux` тоже собирается, но для SM 1.12 достаточно `cssdm-css34-linux`.

## Сборка

```bash
git submodule update --init --recursive
export CSSDM_SM_LINE=sm13 DEPS_DIR=$HOME CC=gcc CXX=g++   # sm11 / sm12 / sm13
bash builder/run/checkout-deps.sh
builder/run/linux.sh   # → OUT/package/cssdm-<ver>-git<N>-css34-sm13-linux.tar.gz
```

SourceMod/Metamod для sm12/sm13 берутся из релизов-указателей форка `line-sm12-latest` / `line-sm13-latest`.

## CI

`Build` собирает пакеты, `Test Server` поднимает CS:S v34 и проверяет, что `cssdm.ext` и DM-плагины загрузились, `Compat` прогоняет пакеты по разным сборкам SourceMod.

## Лицензия

GPL-2.0 (см. `LICENSE`). CSS:DM © AlliedModders LLC.
