/**
 * Behaviour test for the CS:S DM core, the same for cssdm.ext and cssdm.smx:
 * it only uses the cssdm natives / forwards and the game state.
 *
 * Writes "RESULT <name> PASS|FAIL <detail>" and "INFO ..." lines to
 * logs/cssdm_selftest.log, then quits the server.
 */
#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <cssdm>

public Plugin myinfo = { name = "cssdm selftest", author = "", description = "", version = "1", url = "" };

char g_Log[PLATFORM_MAX_PATH];
int g_Step;
int g_Fails;

int g_T[3];
int g_CT;

/* forward counters */
int g_Deaths[MAXPLAYERS + 1];
int g_Spawns[MAXPLAYERS + 1];
int g_PostSpawns[MAXPLAYERS + 1];
int g_Startups, g_Shutdowns, g_SpawnMethodCalls;
char g_SpawnMethodArg[64];
int g_BlockClient;

/* memory sites */
Address g_LagComp, g_TakeDmg, g_Points;
char g_BytesOff[256];

int g_FragsBefore;

public void OnPluginStart()
{
	BuildPath(Path_SM, g_Log, sizeof(g_Log), "logs/cssdm_selftest.log");
	DeleteFile(g_Log);
}

void Out(const char[] fmt, any ...)
{
	char buf[512];
	VFormat(buf, sizeof(buf), fmt, 2);
	LogToFileEx(g_Log, "%s", buf);
	PrintToServer("[selftest] %s", buf);
}

void Check(const char[] name, bool ok, const char[] fmt = "", any ...)
{
	char detail[256];
	VFormat(detail, sizeof(detail), fmt, 4);
	Out("RESULT %s %s %s", name, ok ? "PASS" : "FAIL", detail);
	if (!ok)
	{
		g_Fails++;
	}
}

/* forwards */
public Action DM_OnClientDeath(int client)
{
	g_Deaths[client]++;
	return client == g_BlockClient ? Plugin_Handled : Plugin_Continue;
}
public void DM_OnClientSpawned(int client) { g_Spawns[client]++; }
public void DM_OnClientPostSpawned(int client) { g_PostSpawns[client]++; }
public void DM_OnStartup() { g_Startups++; }
public void DM_OnShutdown() { g_Shutdowns++; }
public Action DM_OnSetSpawnMethod(const char[] method)
{
	g_SpawnMethodCalls++;
	strcopy(g_SpawnMethodArg, sizeof(g_SpawnMethodArg), method);
	return Plugin_Continue;
}

/* memory helpers */
void LoadSites()
{
	GameData gd = new GameData("cssdm_selftest.games");
	g_LagComp = gd.GetMemSig("WantsLagComp") + view_as<Address>(gd.GetOffset("LagCompPatch"));
	g_TakeDmg = gd.GetMemSig("OnTakeDamage") + view_as<Address>(gd.GetOffset("TakeDmgPatch1"));
	Address rules = gd.GetAddress("GameRules");
	Address vtable = view_as<Address>(LoadFromAddress(rules, NumberType_Int32));
	g_Points = view_as<Address>(LoadFromAddress(vtable + view_as<Address>(gd.GetOffset("IPointsForKill") * 4), NumberType_Int32));
	delete gd;
}

void Hex(Address addr, int n, char[] out, int maxlen)
{
	out[0] = 0;
	for (int i = 0; i < n; i++)
	{
		Format(out, maxlen, "%s%02X", out, LoadFromAddress(addr + view_as<Address>(i), NumberType_Int8) & 0xFF);
	}
}

void Bytes(char[] out, int maxlen)
{
	char a[32], b[32], c[32];
	Hex(g_LagComp, 6, a, sizeof(a));
	Hex(g_TakeDmg, 6, b, sizeof(b));
	Hex(g_Points, 6, c, sizeof(c));
	FormatEx(out, maxlen, "lagcomp=%s takedmg=%s points=%s", a, b, c);
}

int CountRagdolls()
{
	int n, ent = -1;
	while ((ent = FindEntityByClassname(ent, "cs_ragdoll")) != -1)
	{
		n++;
	}
	return n;
}

/* Health lost by an unarmoured victim. */
int TeamDamage(int victim, int attacker, float amount)
{
	SetEntProp(victim, Prop_Send, "m_ArmorValue", 0);
	SetEntityHealth(victim, 100);
	Damage(victim, attacker, amount);
	return 100 - GetClientHealth(victim);
}

void Damage(int victim, int attacker, float amount)
{
	SDKHooks_TakeDamage(victim, attacker, attacker, amount, DMG_BULLET);
}

/* step machine */
public void OnMapStart()
{
	if (g_Step == 0)
	{
		CreateTimer(5.0, Timer_Step, _, TIMER_FLAG_NO_MAPCHANGE);
		CreateTimer(150.0, Timer_Watchdog);
	}
}

Action Timer_Step(Handle timer)
{
	float next = Step(++g_Step);
	if (next > 0.0)
	{
		CreateTimer(next, Timer_Step, _, TIMER_FLAG_NO_MAPCHANGE);
	}
	return Plugin_Stop;
}

float Step(int step)
{
	char buf[256], buf2[256];
	int a, b, c;
	if (step > 2)
	{
		a = g_T[0];
		b = g_T[1];
		c = g_T[2];
	}

	switch (step)
	{
		case 1:
		{
			ServerCommand("sv_cheats 1; mp_autoteambalance 0; mp_limitteams 0; mp_freezetime 0; mp_roundtime 9; mp_timelimit 0");
			ServerCommand("mp_friendlyfire 0; mp_tkpunish 0; mp_autokick 0; bot_join_after_player 0; bot_quota_mode normal");
			ServerCommand("cssdm_respawn_wait 1; cssdm_ragdoll_time 2; cssdm_ffa_enabled 0");
			ServerCommand("bot_add_t; bot_add_t; bot_add_t; bot_add_ct; bot_add_ct");
			ServerCommand("bot_stop 1; bot_dont_shoot 1; mp_restartgame 1");
			return 10.0;
		}
		case 2:
		{
			int nt;
			for (int i = 1; i <= MaxClients; i++)
			{
				if (!IsClientInGame(i) || !IsFakeClient(i))
				{
					continue;
				}
				if (GetClientTeam(i) == 2 && nt < 3)
				{
					g_T[nt++] = i;
				}
				else if (GetClientTeam(i) == 3)
				{
					g_CT = i;
				}
			}
			Check("setup_bots", nt == 3 && g_CT != 0, "T=%d CT=%d", nt, g_CT);
			if (nt < 3 || !g_CT)
			{
				return Finish();
			}

			a = g_T[0];
			b = g_T[1];
			c = g_T[2];
			Check("native_IsRunning", DM_IsRunning());
			int id = DM_GetWeaponID("ak47");
			Check("native_GetWeaponID", id >= 0, "ak47=%d unknown=%d", id, DM_GetWeaponID("nope"));
			if (id >= 0)
			{
				DM_GetWeaponClassname(id, buf, sizeof(buf));
				DM_GetWeaponName(id, buf2, sizeof(buf2));
				Check("native_GetWeaponInfo", DM_GetWeaponType(id) == DmWeapon_Primary && StrEqual(buf, "weapon_ak47"),
					"type=%d classname=%s name=%s", DM_GetWeaponType(id), buf, buf2);
			}
			Check("native_GetSpawnWaitTime", DM_GetSpawnWaitTime() == 1.0, "%.2f", DM_GetSpawnWaitTime());
			DM_GetSpawnMethod(buf, sizeof(buf));
			Out("INFO spawn_method=%s startups=%d", buf, g_Startups);
			Check("native_IsClientAlive", DM_IsClientAlive(a) == IsPlayerAlive(a));

			LoadSites();
			Bytes(g_BytesOff, sizeof(g_BytesOff));
			Out("INFO bytes_ffa_off %s", g_BytesOff);

			/* death -> ragdoll removed, respawn after cssdm_respawn_wait */
			g_Deaths[a] = 0;
			g_Spawns[a] = 0;
			g_PostSpawns[a] = 0;
			ForcePlayerSuicide(a);
			return 0.3;
		}
		case 3:
		{
			Check("death_forward", g_Deaths[a] == 1, "DM_OnClientDeath=%d", g_Deaths[a]);
			Check("death_ragdoll_cleared", GetEntPropEnt(a, Prop_Send, "m_hRagdoll") == -1, "m_hRagdoll=%d", GetEntPropEnt(a, Prop_Send, "m_hRagdoll"));
			Check("death_dead_before_wait", !IsPlayerAlive(a));
			Out("INFO ragdolls_after_death=%d", CountRagdolls());
			return 1.2;
		}
		case 4:
		{
			Check("respawn_after_wait", IsPlayerAlive(a));
			Check("respawn_forwards", g_Spawns[a] == 1 && g_PostSpawns[a] == 1, "spawned=%d post=%d", g_Spawns[a], g_PostSpawns[a]);
			return 1.2;
		}
		case 5:
		{
			Check("ragdoll_removed", CountRagdolls() == 0, "cs_ragdoll=%d", CountRagdolls());

			/* DM_OnClientDeath returning Plugin_Handled: no respawn */
			g_BlockClient = a;
			g_Deaths[a] = 0;
			g_Spawns[a] = 0;
			/* not ForcePlayerSuicide: the engine has a suicide cooldown right after spawn */
			Damage(a, 0, 500.0);
			return 2.5;
		}
		case 6:
		{
			Check("death_blocked_no_respawn", !IsPlayerAlive(a), "OnClientDeath=%d spawned_forward=%d", g_Deaths[a], g_Spawns[a]);
			g_BlockClient = 0;
			g_Spawns[a] = 0;
			DM_RespawnClient(a);
			Check("native_RespawnClient", IsPlayerAlive(a), "spawned_forward=%d", g_Spawns[a]);
			return 4.0; /* spawn protection on b / c is long gone, a is not used for damage */
		}
		case 7:
		{
			/* FFA needs mp_friendlyfire 1 (cssdm.cfg: "without any damage reduction or
			 * teamkill penalties"). FFA off: teammate damage reduced, teamkill = -1 frag. */
			ServerCommand("mp_friendlyfire 1");
			return 0.5;
		}
		case 8:
		{
			int dmg = TeamDamage(c, b, 10.0);
			Check("ffa_off_team_damage_reduced", dmg > 0 && dmg < 10, "10 dmg -> %d", dmg);

			g_FragsBefore = GetClientFrags(b);
			Damage(c, b, 500.0);
			Check("ffa_off_teamkill_minus_one", !IsPlayerAlive(c) && GetClientFrags(b) - g_FragsBefore == -1,
				"alive=%d frags %d -> %d", IsPlayerAlive(c), g_FragsBefore, GetClientFrags(b));
			ServerCommand("cssdm_ffa_enabled 1");
			return 5.0; /* c respawns, spawn protection (2 s) ends */
		}
		case 9:
		{
			Bytes(buf, sizeof(buf));
			Out("INFO bytes_ffa_on %s", buf);
			Check("ffa_on_bytes_changed", !StrEqual(buf, g_BytesOff));

			int dmg = TeamDamage(c, b, 10.0);
			/* the extension too still reduces SDKHooks_TakeDamage team damage here (10 -> 3) */
			Check("ffa_on_team_damage", dmg > 0, "10 dmg -> %d", dmg);

			g_FragsBefore = GetClientFrags(b);
			Damage(c, b, 500.0);
			Check("ffa_on_teamkill_plus_one", !IsPlayerAlive(c) && GetClientFrags(b) - g_FragsBefore == 1,
				"alive=%d frags %d -> %d", IsPlayerAlive(c), g_FragsBefore, GetClientFrags(b));

			/* enemy kill is still +1 */
			g_FragsBefore = GetClientFrags(g_CT);
			Damage(b, g_CT, 500.0);
			Check("ffa_on_enemy_kill_plus_one", GetClientFrags(g_CT) - g_FragsBefore == 1, "frags %d -> %d", g_FragsBefore, GetClientFrags(g_CT));

			ServerCommand("cssdm_ffa_enabled 0; mp_friendlyfire 0");
			return 0.5;
		}
		case 10:
		{
			Bytes(buf, sizeof(buf));
			Check("ffa_off_bytes_restored", StrEqual(buf, g_BytesOff), "%s", buf);

			/* disable with FFA on: unpatch + shutdown; dead players stay dead */
			ServerCommand("cssdm_ffa_enabled 1");
			ServerCommand("cssdm_enabled 0");
			return 0.5;
		}
		case 11:
		{
			Bytes(buf, sizeof(buf));
			Check("disable_not_running", !DM_IsRunning());
			Check("disable_shutdown_forward", g_Shutdowns == 1, "OnShutdown=%d", g_Shutdowns);
			Check("disable_bytes_restored", StrEqual(buf, g_BytesOff), "%s", buf);
			g_Deaths[a] = 0;
			ForcePlayerSuicide(a);
			return 2.5;
		}
		case 12:
		{
			Check("disable_no_respawn", !IsPlayerAlive(a) && g_Deaths[a] == 0, "alive=%d OnClientDeath=%d", IsPlayerAlive(a), g_Deaths[a]);
			int startups = g_Startups;
			ServerCommand("cssdm_enabled 1");
			ServerExecute();
			Bytes(buf, sizeof(buf));
			Check("enable_running", DM_IsRunning() && g_Startups == startups + 1, "OnStartup %d -> %d", startups, g_Startups);
			Check("enable_ffa_repatched", !StrEqual(buf, g_BytesOff), "%s", buf);
			ServerCommand("cssdm_ffa_enabled 0");
			return 0.5;
		}
		case 13:
		{
			DM_StripBotItems(g_CT);
			int left;
			for (int s = 0; s < 5; s++)
			{
				if (GetPlayerWeaponSlot(g_CT, s) != -1)
				{
					left++;
				}
			}
			Check("native_StripBotItems", left == 0, "weapons left=%d", left);

			g_SpawnMethodCalls = 0;
			ServerCommand("cssdm_spawn_method random");
			ServerExecute();
			Check("spawn_method_forward", g_SpawnMethodCalls == 1 && StrEqual(g_SpawnMethodArg, "random"),
				"calls=%d arg=%s", g_SpawnMethodCalls, g_SpawnMethodArg);
			ServerCommand("cssdm_spawn_method preset");
			return Finish();
		}
	}
	return 0.0;
}

Action Timer_Watchdog(Handle timer)
{
	Check("watchdog", false, "selftest stuck at step %d", g_Step);
	Finish();
	return Plugin_Stop;
}

float Finish()
{
	Out("SUMMARY fails=%d", g_Fails);
	ServerCommand("quit");
	return 0.0;
}
