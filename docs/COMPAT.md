# CSS:DM: какая сборка на каком SourceMod работает

Проверено 2026-11-03/04. В каждой клетке на чистый CS:S v34 (build 4044) ставятся Metamod + SourceMod и один вариант CSS:DM, сервер стартует на `de_dust2` и проверяется:

- какие бинарники реально загружены (`sourcemod.N.ep1.so`, `cssdm.ext.N.ep1.so`, из `/proc/<pid>/maps`);
- `sm exts list`: загрузился ли `CS:S DM`, а если нет, то с какой ошибкой;
- `sm plugins list`: сколько из 5 DM-плагинов работает;
- 60–90 с игры 8 ботов: убийства в логе, `CS:S DM` всё ещё в списке, сервер не упал.

«yes» — всё выполнено. Клетки с пометкой **(FEX)** запускались на ARM-хосте под FEX-Emu (a1, отдельная копия сервера). Остальные — в GitHub Actions (x86, workflow `Compat`).

## Коротко: что ставить

| SourceMod | Рабочий CSS:DM |
|---|---|
| fmu1337/sourcemod-css34 **1.13** r5 | артефакт `cssdm-css34-sm13-linux` (линия **sm13**) |
| fmu1337/sourcemod-css34 **1.12** r4 | артефакт `cssdm-css34-sm12-linux` (линия **sm12**) или `cssdm.ext` + gamedata из MyArena SM 1.11 |
| fmu1337/sourcemod-css34 1.11 dual-r3 + MM 1.12 (ядро `2.ep1`) | только `cssdm.ext` + gamedata из MyArena SM 1.11 |
| MyArena SM 1.11.0.6541 | только его собственный `cssdm.ext` + gamedata |
| MyArena SM 1.9.0.6189 | полностью — ничего: его `cssdm.ext` (2018) грузится, но наши плагины собраны новым spcomp и на SM 1.9 не стартуют |
| ядро `1.ep1`: rom4s 1.11 / 1.10 / 1.9 (MM 1.10.6), наш 1.11 + MM 1.10.7 | ничего |
| rom4s SM 1.6.4 | ничего, сервер падает |

## Что выяснилось

1. **Артефакт `cssdm-css34-linux` (линия sm11) не работает нигде.** И `cssdm.ext.1.ep1.so`, и `cssdm.ext.2.ep1.so` дают `Failed to get API` на всех сборках. Это ошибка загрузчика Metamod (расширение не отдаёт интерфейс `ISmmPlugin`), а не проверка версии API в SourceMod. Старый Test Server её не ловил: он искал `cssdm.ext.*<FAILED>`, а SM печатает `<FAILED> file "cssdm.ext…"`. С PR #3 проверка исправлена.
2. **Под ядро `1.ep1` рабочего CSS:DM нет.** Сборки sm12/sm13 и обе сборки MyArena есть только для `2.ep1`, SM ищет `cssdm.ext.1.ep1.so` или `cssdm.ext.so` и не находит их. Наш `1.ep1` из линии sm11 падает с `Failed to get API`.
3. **`cssdm.ext` из MyArena SM 1.9 (2018) роняет сервер** (SIGSEGV сразу после смены карты) на SM 1.11/1.12 с MM 1.12 и на MyArena SM 1.11.
4. **`cssdm.ext` из MyArena SM 1.11 (2022)** работает на всех сборках с ядром `2.ep1` и API ≤ 8 (наш 1.12, наш 1.11 + MM 1.12, MyArena 1.11), но только со своим `cssdm.games.txt`. Его gamedata отличается от нашего (другие оффсеты, лишний патч `TakeDmgPatch2`).
5. Сборки с API 8 (sm11, sm12, обе MyArena) на SM 1.13 не грузятся (`too old to load (8, max is 9)`), sm13 (API 11) — на SM ≤ 1.12 (`too new`). Это ожидаемо.
6. sm12 на SM 1.11 даёт `Could not find interface: IPlayerManager`, на SM 1.9 — `ISourceMod`: собранное под 1.12 расширение просит версии интерфейсов, которых в старом SM нет.

## Полная таблица

<!-- compat-table:begin -->
<!-- compat-table:end -->

## Как перезапустить

- **GitHub Actions:** workflow `Compat` (Actions → Compat → Run workflow). Он берёт пакеты CSS:DM из последнего успешного Build на `master` (или из run id, указанного вручную), прогоняет все сборки из `testing/compat/sm-builds.json`, кроме локальных, и выводит таблицу в summary и в артефакт `compat-table`.
- **Локально / FEX:** `testing/scripts/compat-local.sh`. Нужен готовый сервер (`SERVER_DIR`) и каталог `PKG_DIR` с пакетами `sm11/sm12/sm13.tar.gz`, архивами MyArena и `myarena19-cssdm.ext.2.ep1.so`, `myarena111-cssdm.ext.2.ep1.so`, `myarena111-cssdm.games.txt`. Под FEX нужны ещё `SRCDS_PREFIX=FEX`, переменные `FEX_*` и `COMPAT_RUNNER=fex`.

Архивы MyArena не публикуются, поэтому в Actions их нет, только локально.
