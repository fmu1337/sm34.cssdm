# CSS:DM: какая сборка на каком SourceMod работает

Проверено 2026-11-03/04. В каждой клетке на чистый CS:S v34 (build 4044) ставятся Metamod + SourceMod и один вариант CSS:DM, сервер стартует на `de_dust2` и проверяется:

- какие бинарники реально загружены (`sourcemod.N.ep1.so`, `cssdm.ext.N.ep1.so`, из `/proc/<pid>/maps`);
- `sm exts list`: загрузился ли `CS:S DM`, а если нет, то с какой ошибкой;
- `sm plugins list`: сколько из 5 DM-плагинов работает;
- 60–90 с игры 8 ботов: убийства в логе, `CS:S DM` всё ещё в списке, сервер не упал.

«yes» — всё выполнено. Колонка «no cssdm» — та же сборка SM без CSS:DM: все сборки без него работают, так что ошибки в остальных колонках вызывает cssdm. Клетки с пометкой **(FEX)** запускались на ARM-хосте под FEX-Emu (a1, отдельная копия сервера). Остальные — в GitHub Actions (x86, workflow `Compat`).

## Коротко: что ставить

| SourceMod | Рабочий CSS:DM |
|---|---|
| fmu1337/sourcemod-css34 **1.13** r5 | артефакт `cssdm-css34-sm13-linux` (линия **sm13**) |
| fmu1337/sourcemod-css34 **1.12** r4 | `cssdm-css34-sm12-linux` (линия **sm12**) или `cssdm-css34-linux` после PR #8 |
| fmu1337/sourcemod-css34 1.11 dual-r3, с MM 1.12 (ядро `2.ep1`) и с MM 1.10.7 (ядро `1.ep1`) | `cssdm-css34-linux` после PR #8 |
| MyArena SM 1.11.0.6541 | `cssdm-css34-linux` после PR #8 или его собственный `cssdm.ext` + gamedata |
| MyArena SM 1.9.0.6189 | полностью — ничего: его `cssdm.ext` (2018) грузится, но наши плагины собраны новым spcomp и на SM 1.9 не стартуют; наш ext даёт `ISourceMod` |
| rom4s 1.11 / 1.10 (MM 1.10.6, ядро `1.ep1`) | `cssdm-css34-linux` после PR #8 |
| rom4s 1.9 (MM 1.10.6) | ничего: `Could not find interface: ISourceMod` (cssdm собран с заголовками SM 1.10) |
| rom4s SM 1.6.4 | ничего: сам SM работает, но с любым cssdm сервер падает |

## Что выяснилось

1. **Артефакт `cssdm-css34-linux` (линия sm11) в `master` не работает нигде; исправлен в PR #8.** С исправлением он работает на SM 1.10–1.12 с обоими ядрами (наши, rom4s, MyArena 1.11), но не на SM 1.9 и 1.6.4. Без исправления и `cssdm.ext.1.ep1.so`, и `cssdm.ext.2.ep1.so` дают `Failed to get API` на всех сборках. Это ошибка загрузчика Metamod, а не проверка версии API в SourceMod: в заголовках MM 1.10 `SMM_API` получает `visibility("default")` только при `__GNUC__ == 4`, поэтому при сборке GCC 11 с `-fvisibility=hidden` функция `CreateInterface` из cssdm скрыта, и Metamod находит одноимённую функцию из `vstdlib`. Старый Test Server её не ловил: он искал `cssdm.ext.*<FAILED>`, а SM печатает `<FAILED> file "cssdm.ext…"`. С PR #3 проверка исправлена.
2. **Под ядро `1.ep1` есть только `cssdm-css34-linux`** (после PR #8). Сборки sm12/sm13 и обе сборки MyArena есть только для `2.ep1`: SM ищет `cssdm.ext.1.ep1.so` или `cssdm.ext.so` и не находит их.
3. **`cssdm.ext` из MyArena SM 1.9 (2018) роняет сервер** (SIGSEGV сразу после смены карты) на SM 1.11/1.12 с MM 1.12 и на MyArena SM 1.11.
4. **`cssdm.ext` из MyArena SM 1.11 (2022)** работает на всех сборках с ядром `2.ep1` и API ≤ 8 (наш 1.12, наш 1.11 + MM 1.12, MyArena 1.11), но только со своим `cssdm.games.txt`. Его gamedata отличается от нашего (другие оффсеты, лишний патч `TakeDmgPatch2`).
5. Сборки с API 8 (sm11, sm12, обе MyArena) на SM 1.13 не грузятся (`too old to load (8, max is 9)`), sm13 (API 11) — на SM ≤ 1.12 (`too new`). Это ожидаемо.
6. sm12 на SM 1.11 даёт `Could not find interface: IPlayerManager`, на SM 1.9 — `ISourceMod`: собранное под 1.12 расширение просит версии интерфейсов, которых в старом SM нет.

## Полная таблица

<!-- compat-table:begin -->
Пакеты CSS:DM из Build `master` 41588298565; колонка «sm11 fixed» — пакет `cssdm-css34-linux` из Build 41740013517 (PR #8). CI: Compat run 41738474417; FEX: a1, 60 с ботов.

| Source | Build | MM / SM seen | SM core | no cssdm (SM itself) | cssdm sm11 (API 8, 1.ep1+2.ep1) | cssdm sm11 fixed (PR #8, API 8) | cssdm sm12 (API 8, 2.ep1) | cssdm sm13 (API 11, 2.ep1) | cssdm.ext from MyArena SM 1.9 (2018) | cssdm.ext + gamedata from MyArena SM 1.11 (2022) |
|---|---|---|---|---|---|---|---|---|---|---|
| fmu1337/sourcemod-css34 | SM 1.13.0.7478 r5 + MM 1.12.0 | 1.12.0-dev+1229 / 1.13.0.7478 | sourcemod.2.ep1.so | runs, 8 kills | no: `cssdm.ext.2.ep1.so: Extension version is too old to load (8, max is 9)` | no: `cssdm.ext.2.ep1.so: Extension version is too old to load (8, max is 9)` (FEX) | no: `cssdm.ext.2.ep1.so: Extension version is too old to load (8, max is 9)` | yes: cssdm.ext.2.ep1.so, plugins 5/5, 26 kills | no: `cssdm.ext.2.ep1.so: Extension version is too old to load (8, max is 9)` (FEX) | no: `cssdm.ext.2.ep1.so: Extension version is too old to load (8, max is 9)` (FEX) |
| fmu1337/sourcemod-css34 | SM 1.12.0.7257 r4 + MM 1.12.0 | 1.12.0-dev+1229 / 1.12.0.7257 | sourcemod.2.ep1.so | runs, 8 kills | no: `cssdm.ext.2.ep1.so: Failed to get API` | yes: cssdm.ext.2.ep1.so, plugins 5/5, 8 kills (FEX) | yes: cssdm.ext.2.ep1.so, plugins 5/5, 27 kills | no: `cssdm.ext.2.ep1.so: Extension version is too new to load (11, max is 8)` | **crash** (exited after 'meta version' (rc -11)) (FEX) | yes: cssdm.ext.2.ep1.so, plugins 5/5, 12 kills (FEX) |
| fmu1337/sourcemod-css34 | SM 1.11.0.6970 dual-r3 + MM 1.12.0 | 1.12.0-dev+1227 / 1.11.0.6970 | sourcemod.2.ep1.so | runs, 8 kills | no: `cssdm.ext.2.ep1.so: Failed to get API` | yes: cssdm.ext.2.ep1.so, plugins 5/5, 3 kills (FEX) | no: `cssdm.ext.2.ep1.so: Could not find interface: IPlayerManager` | no: `cssdm.ext.2.ep1.so: Extension version is too new to load (11, max is 8)` | **crash** (exited after 'meta version' (rc -11)) (FEX) | yes: cssdm.ext.2.ep1.so, plugins 5/5, 6 kills (FEX) |
| fmu1337/sourcemod-css34 | SM 1.11.0.6970 dual-r3 + MM 1.10.7 | 1.10.7-dev+976 / 1.11.0.6970 | sourcemod.1.ep1.so | runs, 8 kills | no: `cssdm.ext.1.ep1.so: Failed to get API` | yes: cssdm.ext.1.ep1.so, plugins 5/5, 8 kills (FEX) | no: no binary for the 1.ep1 core | no: no binary for the 1.ep1 core | no: no binary for the 1.ep1 core (FEX) | no: no binary for the 1.ep1 core (FEX) |
| MyArena | SM 1.11.0.6541 + MM 1.11.0-dev+1130 (MyArena) | 1.11.0-dev+1130 / 1.11.0.6522 | sourcemod.2.ep1.so | runs, 6 kills (FEX) | no: `cssdm.ext.2.ep1.so: Failed to get API` (FEX) | yes: cssdm.ext.2.ep1.so, plugins 5/5, 8 kills (FEX) | no: `cssdm.ext.2.ep1.so: Could not find interface: IPlayerManager` (FEX) | no: `cssdm.ext.2.ep1.so: Extension version is too new to load (11, max is 8)` (FEX) | **crash** (exited after 'meta version' (rc -11)) (FEX) | yes: cssdm.ext.2.ep1.so, plugins 5/5, 8 kills (FEX) |
| MyArena | SM 1.9.0.6189 + MM (MyArena) | 1.11.0-dev+1099 / 1.9.0.6190 | sourcemod.2.ep1.so | runs, 6 kills (FEX) | no: `cssdm.ext.2.ep1.so: Failed to get API` (FEX) | no: `cssdm.ext.2.ep1.so: Could not find interface: ISourceMod` (FEX) | no: `cssdm.ext.2.ep1.so: Could not find interface: ISourceMod` (FEX) | no: `cssdm.ext.2.ep1.so: Extension version is too new to load (11, max is 8)` (FEX) | partial: cssdm.ext.2.ep1.so, plugins 0/5, 11 kills, `Unable to load plugin (no debug string table)` (FEX) | no: `cssdm.ext.2.ep1.so: Could not find interface: ISourceMod` (FEX) |
| rom4s | SM 1.11.0.6572 + MM 1.10.6 (rom4s) | 1.10.6 / 1.11.0.6572 | sourcemod.1.ep1.so | runs, 8 kills | no: `cssdm.ext.1.ep1.so: Failed to get API` | yes: cssdm.ext.1.ep1.so, plugins 5/5, 9 kills (FEX) | no: no binary for the 1.ep1 core | no: no binary for the 1.ep1 core | no: no binary for the 1.ep1 core (FEX) | no: no binary for the 1.ep1 core (FEX) |
| rom4s | SM 1.10.0.6490 + MM 1.10.6 (rom4s) | 1.10.6 / 1.10.0.6490 | sourcemod.1.ep1.so | runs, 8 kills | no: `cssdm.ext.1.ep1.so: Failed to get API` | yes: cssdm.ext.1.ep1.so, plugins 5/5, 9 kills (FEX) | no: no binary for the 1.ep1 core | no: no binary for the 1.ep1 core | no: no binary for the 1.ep1 core (FEX) | no: no binary for the 1.ep1 core (FEX) |
| rom4s | SM 1.9.0.6224 + MM 1.10.6 (rom4s) | 1.10.6 / 1.9.0.6224 | sourcemod.1.ep1.so | runs, 8 kills | no: `cssdm.ext.1.ep1.so: Failed to get API` | no: `cssdm.ext.1.ep1.so: Could not find interface: ISourceMod` (FEX) | no: no binary for the 1.ep1 core | no: no binary for the 1.ep1 core | no: no binary for the 1.ep1 core (FEX) | no: no binary for the 1.ep1 core (FEX) |
| rom4s | SM 1.6.4 + MM 1.10.6 (rom4s) | 1.10.6 / 1.6.4-stable+4626 | sourcemod.1.ep1.so | runs, 8 kills | **crash** (exited after 'meta version' (rc -11)) | **crash** (exited after 'meta version' (rc -11)) (FEX) | no: no binary for the 1.ep1 core | no: no binary for the 1.ep1 core | **crash** (exited after 'meta version' (rc -11)) (FEX) | **crash** (exited after 'meta version' (rc -11)) (FEX) |
<!-- compat-table:end -->

## Как перезапустить

- **GitHub Actions:** workflow `Compat` (Actions → Compat → Run workflow). Он берёт пакеты CSS:DM из последнего успешного Build на `master` (или из run id, указанного вручную), прогоняет все сборки из `testing/compat/sm-builds.json`, кроме локальных, и выводит таблицу в summary и в артефакт `compat-table`.
- **Локально / FEX:** `testing/scripts/compat-local.sh`. Нужен готовый сервер (`SERVER_DIR`) и каталог `PKG_DIR` с пакетами `sm11/sm12/sm13.tar.gz`, архивами MyArena и `myarena19-cssdm.ext.2.ep1.so`, `myarena111-cssdm.ext.2.ep1.so`, `myarena111-cssdm.games.txt`. Под FEX нужны ещё `SRCDS_PREFIX=FEX`, переменные `FEX_*` и `COMPAT_RUNNER=fex`.

Архивы MyArena не публикуются, поэтому в Actions их нет, только локально.
