/**
 * CS:S DM core as a SourcePawn plugin (replaces cssdm.ext), CS:S v34 / Linux.
 * 1:1 port of cssdm_*.cpp (upstream git325 + builder/patches/2.1/2.patch).
 * Same natives, forwards, cvars and gamedata (cssdm.games) as the extension.
 */
#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

#define CS_TEAM_T	2
#define CS_TEAM_CT	3

public Plugin myinfo =
{
	name = "CS:S DM",
	author = "AlliedModders LLC",
	description = "CS:S Deathmatch core",
	version = "2.1.6-sp",
	url = "https://github.com/alliedmodders/cssdm"
};

/* cssdm_config.cpp */
ConVar cssdm_ragdoll_time;
ConVar cssdm_respawn_wait;
ConVar cssdm_enabled;
ConVar cssdm_ffa_enabled;
ConVar cssdm_spawn_method;

/* cssdm_ctrl.cpp */
bool g_IsRunning;
bool g_IsMapStarted;
bool g_HasConfigRan;

/* cssdm_events.cpp */
bool g_InRoundRestart;
ArrayList g_RagdollTimers;

/* cssdm_players.cpp (dm_player_t) */
bool g_IsSpawned[MAXPLAYERS + 1];
bool g_WillRespawnOnClass[MAXPLAYERS + 1];
Handle g_RespawnTimer[MAXPLAYERS + 1];

/* cssdm_weapons.cpp */
enum struct DmWeapon
{
	char classname[64];
	char display[64];
	int type;
}
ArrayList g_Weapons;
StringMap g_WeaponLookup;

/* cssdm_utils.cpp */
GameData g_Conf;
Handle g_RoundRespawn;
Handle g_RemoveAllItems;

/* cssdm_callbacks.cpp */
GlobalForward g_OnClientDeath;
GlobalForward g_OnClientSpawned;
GlobalForward g_OnClientPostSpawned;
GlobalForward g_OnSetSpawnMethod;
GlobalForward g_OnStartup;
GlobalForward g_OnShutdown;

/* cssdm_ffa.cpp: a byte patch, like DM_ApplyPatch */
enum struct DmPatch
{
	Address addr;
	int len;
	int bytes[16];
	int restore[16];
}
DmPatch g_LagCompPatch;
DmPatch g_TakeDmgPatch;
DmPatch g_PointsPatch;
int g_PointsVtblIndex;
bool g_FFA_Prepared;
bool g_FFA_Patched;
bool g_FFA_PointsPatched;

/******************************************************************************
 * Load / unload (cssdm_main.cpp)
 ******************************************************************************/

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("DM_GetSpawnMethod", Native_GetSpawnMethod);
	CreateNative("DM_GetWeaponID", Native_GetWeaponID);
	CreateNative("DM_GetWeaponType", Native_GetWeaponType);
	CreateNative("DM_StripBotItems", Native_StripBotItems);
	CreateNative("DM_GetWeaponClassname", Native_GetWeaponClassname);
	CreateNative("DM_GetWeaponName", Native_GetWeaponName);
	CreateNative("DM_IsRunning", Native_IsRunning);
	CreateNative("DM_GetSpawnWaitTime", Native_GetSpawnWaitTime);
	CreateNative("DM_RespawnClient", Native_RespawnClient);
	CreateNative("DM_IsClientAlive", Native_IsClientAlive);
	RegPluginLibrary("cssdm");
	return APLRes_Success;
}

public void OnPluginStart()
{
	g_Conf = new GameData("cssdm.games");
	if (g_Conf == null)
	{
		SetFailState("Could not load gamedata cssdm.games");
	}

	StartPrepSDKCall(SDKCall_Player);
	if (!PrepSDKCall_SetFromConf(g_Conf, SDKConf_Signature, "RoundRespawn"))
	{
		SetFailState("Could not find signature \"RoundRespawn\"");
	}
	g_RoundRespawn = EndPrepSDKCall();

	StartPrepSDKCall(SDKCall_Player);
	if (!PrepSDKCall_SetFromConf(g_Conf, SDKConf_Virtual, "RemoveAllItems"))
	{
		SetFailState("Could not find offset \"RemoveAllItems\"");
	}
	PrepSDKCall_AddParameter(SDKType_Bool, SDKPass_Plain);
	g_RemoveAllItems = EndPrepSDKCall();

	char error[256];
	if (!ParseWeapons(error, sizeof(error)))
	{
		SetFailState("%s", error);
	}

	cssdm_ragdoll_time = CreateConVar("cssdm_ragdoll_time", "2", "Sets ragdoll stay time", 0, true, 0.0, true, 20.0);
	cssdm_respawn_wait = CreateConVar("cssdm_respawn_wait", "0.75", "Sets respawn wait time");
	CreateConVar("cssdm_version", "2.1.6-sp", "CS:S DM Version", FCVAR_NOTIFY);
	cssdm_enabled = CreateConVar("cssdm_enabled", "1", "Sets whether CS:S DM is enabled", FCVAR_NOTIFY);
	cssdm_ffa_enabled = CreateConVar("cssdm_ffa_enabled", "0", "Sets whether Free-For-All mode is enabled", FCVAR_NOTIFY);
	cssdm_spawn_method = CreateConVar("cssdm_spawn_method", "preset", "Sets how and where players are spawned");
	cssdm_enabled.AddChangeHook(ChangeStatus);
	cssdm_ffa_enabled.AddChangeHook(ChangeFFAStatus);
	cssdm_spawn_method.AddChangeHook(ChangeSpawnStatus);

	g_OnClientDeath = new GlobalForward("DM_OnClientDeath", ET_Hook, Param_Cell);
	g_OnClientSpawned = new GlobalForward("DM_OnClientSpawned", ET_Ignore, Param_Cell);
	g_OnClientPostSpawned = new GlobalForward("DM_OnClientPostSpawned", ET_Ignore, Param_Cell);
	g_OnSetSpawnMethod = new GlobalForward("DM_OnSetSpawnMethod", ET_Hook, Param_String);
	g_OnStartup = new GlobalForward("DM_OnStartup", ET_Ignore);
	g_OnShutdown = new GlobalForward("DM_OnShutdown", ET_Ignore);

	g_RagdollTimers = new ArrayList();

	HookEvent("player_death", Event_PlayerDeath);
	HookEvent("player_spawn", Event_PlayerSpawn);
	HookEvent("player_team", Event_PlayerTeam);
	HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
	HookEvent("round_end", Event_RoundEnd, EventHookMode_PostNoCopy);
	AddCommandListener(Command_JoinClass, "joinclass");

	if (!PrepareFFA(error, sizeof(error)))
	{
		LogError("FFA will not work: %s", error);
	}
}

public void OnPluginEnd()
{
	DM_Disable();
}

/******************************************************************************
 * Map start / end, enable / disable (cssdm_ctrl.cpp)
 ******************************************************************************/

public void OnMapStart()
{
	g_IsMapStarted = true;
	ServerCommand("exec cssdm/cssdm.cfg");

	char map[PLATFORM_MAX_PATH];
	GetCurrentMap(map, sizeof(map));
	ServerCommand("exec cssdm/maps/%s.cssdm.cfg", map);

	DM_StartEverything();
}

public void OnMapEnd()
{
	ClearRagdollTimers();
	if (g_IsRunning)
	{
		DM_Disable();
	}

	g_IsMapStarted = false;
	g_HasConfigRan = false;
}

void DM_StartEverything()
{
	if (!g_IsMapStarted || g_HasConfigRan)
	{
		return;
	}

	g_HasConfigRan = true;

	if (!g_IsRunning && cssdm_enabled.IntValue == 1)
	{
		DM_Enable();
	}
}

bool DM_Enable()
{
	if (g_IsRunning || !g_IsMapStarted || !g_HasConfigRan)
	{
		return false;
	}

	g_IsRunning = true;

	Call_StartForward(g_OnStartup);
	Call_Finish();

	if (cssdm_ffa_enabled.IntValue != 0 && g_FFA_Prepared && !g_FFA_Patched)
	{
		PatchFFA();
	}

	return true;
}

bool DM_Disable()
{
	if (!g_IsRunning)
	{
		return false;
	}

	g_IsRunning = false;

	if (g_FFA_Patched)
	{
		UnpatchFFA();
	}

	Call_StartForward(g_OnShutdown);
	Call_Finish();

	return true;
}

/******************************************************************************
 * ConVar callbacks (cssdm_config.cpp)
 ******************************************************************************/

void ChangeStatus(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if (cssdm_enabled.IntValue)
	{
		DM_Enable();
	}
	else
	{
		DM_Disable();
	}
}

void ChangeFFAStatus(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if (cssdm_ffa_enabled.IntValue && !g_FFA_Patched && g_FFA_Prepared)
	{
		PatchFFA();
	}
	else if (!cssdm_ffa_enabled.IntValue && g_FFA_Patched)
	{
		UnpatchFFA();
	}
}

void ChangeSpawnStatus(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if (StrEqual(oldValue, newValue))
	{
		return;
	}

	Call_StartForward(g_OnSetSpawnMethod);
	Call_PushString(newValue);
	Call_Finish();
}

/******************************************************************************
 * Players (cssdm_players.cpp)
 ******************************************************************************/

public void OnClientConnected(int client)
{
	ResetPlayer(client);
}

public void OnClientDisconnect(int client)
{
	delete g_RespawnTimer[client];
	ResetPlayer(client);
}

void ResetPlayer(int client)
{
	g_IsSpawned[client] = false;
	g_WillRespawnOnClass[client] = false;
	g_RespawnTimer[client] = null;
}

/* DM_IsPlayerAlive: m_lifeState == LIFE_ALIVE */
bool IsAlive(int client)
{
	return GetEntProp(client, Prop_Send, "m_lifeState") == 0;
}

void RespawnPlayer(int client)
{
	delete g_RespawnTimer[client];
	SDKCall(g_RoundRespawn, client);
}

/******************************************************************************
 * Events (cssdm_events.cpp)
 ******************************************************************************/

void SchedRespawn(int client)
{
	delete g_RespawnTimer[client];
	g_RespawnTimer[client] = CreateTimer(cssdm_respawn_wait.FloatValue, Timer_Respawn, client);
}

Action Timer_Respawn(Handle timer, int client)
{
	g_RespawnTimer[client] = null;

	if (!g_IsRunning)
	{
		return Plugin_Stop;
	}

	int team = GetClientTeam(client);
	if (team != CS_TEAM_T && team != CS_TEAM_CT)
	{
		return Plugin_Stop;
	}

	if (IsAlive(client))
	{
		return Plugin_Stop;
	}

	RespawnPlayer(client);

	return Plugin_Stop;
}

Action Timer_RemoveRagdoll(Handle timer, int ref)
{
	if (g_IsRunning)
	{
		int ragdoll = EntRefToEntIndex(ref);
		if (ragdoll != INVALID_ENT_REFERENCE)
		{
			AcceptEntityInput(ragdoll, "Kill");
		}
	}

	int idx = g_RagdollTimers.FindValue(timer);
	if (idx != -1)
	{
		g_RagdollTimers.Erase(idx);
	}

	return Plugin_Stop;
}

void ClearRagdollTimers()
{
	for (int i = 0; i < g_RagdollTimers.Length; i++)
	{
		KillTimer(g_RagdollTimers.Get(i));
	}
	g_RagdollTimers.Clear();
}

/* ClientCommand post hook: the listener is pre, so check one frame later. */
Action Command_JoinClass(int client, const char[] command, int argc)
{
	if (g_IsRunning && client > 0)
	{
		RequestFrame(Frame_JoinClass, GetClientUserId(client));
	}
	return Plugin_Continue;
}

void Frame_JoinClass(int userid)
{
	int client = GetClientOfUserId(userid);
	if (!g_IsRunning || !client || !IsClientInGame(client))
	{
		return;
	}

	if (IsAlive(client) || !g_WillRespawnOnClass[client])
	{
		return;
	}

	g_WillRespawnOnClass[client] = false;

	SchedRespawn(client);
}

void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_IsRunning)
	{
		return;
	}

	int client = GetClientOfUserId(event.GetInt("userid"));
	if (!client || !IsClientInGame(client))
	{
		return;
	}

	g_IsSpawned[client] = false;

	/* Remove ragdoll */
	int ragdollTime = cssdm_ragdoll_time.IntValue;
	if (ragdollTime <= 20 && !g_InRoundRestart)
	{
		int ragdoll = GetEntPropEnt(client, Prop_Send, "m_hRagdoll");
		SetEntPropEnt(client, Prop_Send, "m_hRagdoll", -1);
		if (ragdoll != -1)
		{
			if (ragdollTime == 0)
			{
				AcceptEntityInput(ragdoll, "Kill");
			}
			else
			{
				g_RagdollTimers.Push(CreateTimer(float(ragdollTime), Timer_RemoveRagdoll, EntIndexToEntRef(ragdoll)));
			}
		}
	}

	Action result = Plugin_Continue;
	Call_StartForward(g_OnClientDeath);
	Call_PushCell(client);
	Call_Finish(result);
	if (result != Plugin_Continue)
	{
		return;
	}

	SchedRespawn(client);
}

void Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_IsRunning)
	{
		return;
	}

	int client = GetClientOfUserId(event.GetInt("userid"));
	if (!client || !IsClientInGame(client))
	{
		return;
	}

	if (IsAlive(client) || event.GetBool("disconnect"))
	{
		return;
	}

	int oldTeam = event.GetInt("oldteam");
	if (oldTeam == CS_TEAM_T || oldTeam == CS_TEAM_CT)
	{
		return;
	}

	int newTeam = event.GetInt("team");
	if (newTeam != CS_TEAM_T && newTeam != CS_TEAM_CT)
	{
		return;
	}

	if (IsFakeClient(client))
	{
		SchedRespawn(client);
	}
	else
	{
		g_WillRespawnOnClass[client] = true;
	}
}

void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_IsRunning)
	{
		return;
	}

	int client = GetClientOfUserId(event.GetInt("userid"));
	if (!client || !IsClientInGame(client) || (g_IsSpawned[client] && !g_InRoundRestart))
	{
		return;
	}

	/* This can be fired before a player gets a team! */
	int team = GetClientTeam(client);
	if (team != CS_TEAM_T && team != CS_TEAM_CT)
	{
		return;
	}

	g_IsSpawned[client] = true;

	/* If we were waiting to respawn, cancel the timer */
	if (!IsFakeClient(client))
	{
		delete g_RespawnTimer[client];
	}

	Call_StartForward(g_OnClientSpawned);
	Call_PushCell(client);
	Call_Finish();
	Call_StartForward(g_OnClientPostSpawned);
	Call_PushCell(client);
	Call_Finish();
}

void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	g_InRoundRestart = false;
}

void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	g_InRoundRestart = true;

	ClearRagdollTimers();

	for (int i = 1; i <= MaxClients; i++)
	{
		g_IsSpawned[i] = false;
	}
}

/******************************************************************************
 * Weapons (cssdm_weapons.cpp)
 ******************************************************************************/

bool ParseWeapons(char[] error, int maxlength)
{
	g_Weapons = new ArrayList(sizeof(DmWeapon));
	g_WeaponLookup = new StringMap();

	char path[] = "cfg/cssdm/cssdm.weapons.txt";
	KeyValues kv = new KeyValues("Weapons");
	if (!kv.ImportFromFile(path))
	{
		delete kv;
		FormatEx(error, maxlength, "Could not load weapons file \"%s\"", path);
		return false;
	}

	char game[64];
	GetGameFolderName(game, sizeof(game));
	if (!kv.JumpToKey(game) || !kv.GotoFirstSubKey())
	{
		delete kv;
		FormatEx(error, maxlength, "Could not find \"%s\" section in weapons file", game);
		return false;
	}

	do
	{
		DmWeapon wp;
		char name[64], type[16];

		kv.GetSectionName(name, sizeof(name));
		for (int i = 0; name[i]; i++)
		{
			name[i] = CharToLower(name[i]);
		}
		FormatEx(wp.classname, sizeof(wp.classname), "weapon_%s", name);
		kv.GetString("name", wp.display, sizeof(wp.display), name);

		kv.GetString("type", type, sizeof(type));
		if (StrEqual(type, "primary"))
		{
			wp.type = 0;
		}
		else if (StrEqual(type, "secondary"))
		{
			wp.type = 1;
		}
		else if (StrEqual(type, "grenade"))
		{
			wp.type = 3;
		}
		else if (StrEqual(type, "c4"))
		{
			wp.type = 4;
		}
		else
		{
			continue;
		}

		/* std::unordered_map::insert keeps the first entry for a name */
		if (g_WeaponLookup.SetValue(name, g_Weapons.Length, false))
		{
			g_Weapons.PushArray(wp);
		}
	} while (kv.GotoNextKey());

	delete kv;
	return true;
}

/******************************************************************************
 * FFA (cssdm_ffa.cpp)
 ******************************************************************************/

/* DM_StringToBytes: gamedata Keys hold "\x90\x90..." as text */
int StringToBytes(const char[] str, int[] buffer, int maxlength)
{
	int count = 0;
	int length = strlen(str);
	for (int i = 0; i < length && count < maxlength; i++)
	{
		if (str[i] == '\\' && str[i + 1] == 'x' && i + 3 < length)
		{
			char hex[3];
			hex[0] = str[i + 2];
			hex[1] = str[i + 3];
			buffer[count++] = StringToInt(hex, 16);
			i += 3;
		}
		else
		{
			buffer[count++] = str[i];
		}
	}
	return count;
}

bool LoadPatch(DmPatch patch, const char[] sig, const char[] name, char[] error, int maxlength)
{
	patch.addr = g_Conf.GetMemSig(sig);
	if (patch.addr == Address_Null)
	{
		FormatEx(error, maxlength, "Could not find \"%s\" signature!", sig);
		return false;
	}

	int offset = g_Conf.GetOffset(name);
	if (offset <= 0)
	{
		FormatEx(error, maxlength, "Could not find %s offset", name);
		return false;
	}
	patch.addr += view_as<Address>(offset);

	char key[64], value[128];
	FormatEx(key, sizeof(key), "%s_Linux", name);
	if (!g_Conf.GetKeyValue(key, value, sizeof(value)))
	{
		FormatEx(error, maxlength, "Could not find signature value for \"%s\"", key);
		return false;
	}

	patch.len = StringToBytes(value, patch.bytes, sizeof(patch.bytes));
	if (!patch.len)
	{
		FormatEx(error, maxlength, "Invalid signature detected for \"%s\"", key);
		return false;
	}

	return true;
}

bool PrepareFFA(char[] error, int maxlength)
{
	if (!LoadPatch(g_TakeDmgPatch, "OnTakeDamage", "TakeDmgPatch1", error, maxlength)
		|| !LoadPatch(g_LagCompPatch, "WantsLagComp", "LagCompPatch", error, maxlength))
	{
		return false;
	}

	g_PointsVtblIndex = g_Conf.GetOffset("IPointsForKill");
	if (g_PointsVtblIndex <= 0)
	{
		FormatEx(error, maxlength, "Could not find IPointsForKills offset");
		return false;
	}

	/* IPointsForKill always returns 1: mov eax, 1; ret */
	static const int ret1[] = {0xB8, 0x01, 0x00, 0x00, 0x00, 0xC3};
	for (int i = 0; i < sizeof(ret1); i++)
	{
		g_PointsPatch.bytes[i] = ret1[i];
	}
	g_PointsPatch.len = sizeof(ret1);

	g_FFA_Prepared = true;
	return true;
}

void ApplyPatch(DmPatch patch)
{
	for (int i = 0; i < patch.len; i++)
	{
		Address addr = patch.addr + view_as<Address>(i);
		patch.restore[i] = LoadFromAddress(addr, NumberType_Int8);
		StoreToAddress(addr, patch.bytes[i], NumberType_Int8);
	}
}

void RestorePatch(DmPatch patch)
{
	for (int i = 0; i < patch.len; i++)
	{
		StoreToAddress(patch.addr + view_as<Address>(i), patch.restore[i], NumberType_Int8);
	}
}

/* Instead of the SourceHook hook on the gamerules vtable slot, patch the
 * function that slot points to. g_pGameRules is only set once a map runs. */
bool LoadPointsAddress()
{
	Address gamerules = g_Conf.GetAddress("GameRules");
	if (gamerules == Address_Null)
	{
		LogError("Could not find GameRules address. FFA points hook will not work.");
		return false;
	}

	Address vtable = view_as<Address>(LoadFromAddress(gamerules, NumberType_Int32));
	g_PointsPatch.addr = view_as<Address>(LoadFromAddress(vtable + view_as<Address>(g_PointsVtblIndex * 4), NumberType_Int32));
	return true;
}

void PatchFFA()
{
	if (g_FFA_Patched || !g_FFA_Prepared)
	{
		return;
	}

	ApplyPatch(g_LagCompPatch);
	ApplyPatch(g_TakeDmgPatch);

	if (!g_FFA_PointsPatched && LoadPointsAddress())
	{
		ApplyPatch(g_PointsPatch);
		g_FFA_PointsPatched = true;
	}

	g_FFA_Patched = true;
}

void UnpatchFFA()
{
	if (!g_FFA_Patched)
	{
		return;
	}

	if (g_FFA_PointsPatched)
	{
		RestorePatch(g_PointsPatch);
		g_FFA_PointsPatched = false;
	}

	RestorePatch(g_LagCompPatch);
	RestorePatch(g_TakeDmgPatch);

	g_FFA_Patched = false;
}

/******************************************************************************
 * Natives (cssdm_callbacks.cpp)
 ******************************************************************************/

any Native_GetSpawnMethod(Handle plugin, int numParams)
{
	char method[64];
	cssdm_spawn_method.GetString(method, sizeof(method));
	SetNativeString(1, method, GetNativeCell(2));
	return 1;
}

any Native_GetWeaponID(Handle plugin, int numParams)
{
	char name[64];
	GetNativeString(1, name, sizeof(name));

	int id;
	if (!g_WeaponLookup.GetValue(name, id))
	{
		return -1;
	}
	return id;
}

bool GetWeapon(int id, DmWeapon wp)
{
	if (id < 0 || id >= g_Weapons.Length)
	{
		ThrowNativeError(SP_ERROR_NATIVE, "Invalid CS:S DM weapon id (%d)", id);
		return false;
	}
	g_Weapons.GetArray(id, wp);
	return true;
}

any Native_GetWeaponType(Handle plugin, int numParams)
{
	DmWeapon wp;
	GetWeapon(GetNativeCell(1), wp);
	return wp.type;
}

any Native_GetWeaponClassname(Handle plugin, int numParams)
{
	DmWeapon wp;
	GetWeapon(GetNativeCell(1), wp);
	SetNativeString(2, wp.classname, GetNativeCell(3));
	return 1;
}

any Native_GetWeaponName(Handle plugin, int numParams)
{
	DmWeapon wp;
	GetWeapon(GetNativeCell(1), wp);
	SetNativeString(2, wp.display, GetNativeCell(3));
	return 1;
}

void CheckClient(int client)
{
	if (client < 1 || client > MaxClients)
	{
		ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index %d", client);
	}
	if (!IsClientInGame(client))
	{
		ThrowNativeError(SP_ERROR_NATIVE, "Client %d is not in game", client);
	}
}

any Native_StripBotItems(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	CheckClient(client);
	if (!IsFakeClient(client))
	{
		ThrowNativeError(SP_ERROR_NATIVE, "Client %d is not a bot", client);
	}

	SDKCall(g_RemoveAllItems, client, false);
	return 1;
}

any Native_IsRunning(Handle plugin, int numParams)
{
	return g_IsRunning;
}

any Native_GetSpawnWaitTime(Handle plugin, int numParams)
{
	return cssdm_respawn_wait.FloatValue;
}

any Native_RespawnClient(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	CheckClient(client);

	g_IsSpawned[client] = !GetNativeCell(2);
	RespawnPlayer(client);
	return 1;
}

any Native_IsClientAlive(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	CheckClient(client);
	return IsAlive(client);
}
