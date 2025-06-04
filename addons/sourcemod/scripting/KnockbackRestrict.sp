#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <multicolors>
#include <adminmenu>
#include <cstrike>
#include <KnockbackRestrict>

#define DB_CHARSET "utf8mb4"
#define DB_COLLATION "utf8mb4_unicode_ci"
#define KR_Tag "{aqua}[Kb-Restrict]{white}"
#define NOSTEAMID "NO STEAMID"
#define MAX_IP_LENGTH 16
#define MAX_QUERIE_LENGTH 2000
#define REASON_MAX_LENGTH 128

GlobalForward g_hKbanForward;
GlobalForward g_hKunbanForward;

TopMenu g_hAdminMenu;

int g_iClientPreviousMenu[MAXPLAYERS + 1] = {0, ...},
	g_iClientTarget[MAXPLAYERS + 1] = {0, ...}, g_iClientTargetLength[MAXPLAYERS + 1] = {0, ...},
	g_iClientKbansNumber[MAXPLAYERS + 1] = { 0, ... },
	g_iDefaultLength;
	
bool g_bKnifeModeEnabled,
	g_bUserVerified[MAXPLAYERS + 1] = { false, ... },
	g_bIsClientRestricted[MAXPLAYERS + 1] = { false, ... },
	g_bIsClientTypingReason[MAXPLAYERS + 1] = { false, ... },
	g_bLate = false,
	g_bSaveTempBans = true,
	g_bConnectingToDB = false;

char g_sMapName[PLATFORM_MAX_PATH],
	g_sName[MAXPLAYERS+1][MAX_NAME_LENGTH],
	g_sSteamIDs[MAXPLAYERS+1][MAX_AUTHID_LENGTH],
	g_sIPs[MAXPLAYERS+1][MAX_IP_LENGTH];

float g_fReduceKnife, g_fReduceKnifeMod, g_fReducePistol, g_fReduceSMG, g_fReduceRifle, g_fReduceShotgun, g_fReduceSniper, g_fReduceSemiAutoSniper, g_fReduceGrenade;

Database g_hDB;

ArrayList g_allKbans;
ArrayList g_OfflinePlayers;

ConVar g_cvDefaultLength,
	g_cvMaxBanTimeBanFlag, g_cvMaxBanTimeKickFlag, g_cvMaxBanTimeRconFlag,
	g_cvDisplayConnectMsg, g_cvGetRealKbanNumber, g_cvSaveTempBans,
	g_cvReduceKnife, g_cvReduceKnifeMod, g_cvReducePistol, g_cvReduceSMG, g_cvReduceRifle, g_cvReduceShotgun, g_cvReduceSniper, g_cvReduceSemiAutoSniper, g_cvReduceGrenade;

enum KbanGetType {
	KBAN_GET_TYPE_ID = 0,
	KBAN_GET_TYPE_STEAMID = 1,
	KBAN_GET_TYPE_IP = 2
};

enum ErrorType {
	ERROR_TYPE_SELECT = 0,
	ERROR_TYPE_UPDATE = 1,
	ERROR_TYPE_CREATE = 2,
	ERROR_TYPE_INSERT = 3
};

enum SuccessType {
	SUCCESS_TYPE_SELECT = 0,
	SUCCESS_TYPE_UPDATE = 1,
	SUCCESS_TYPE_CREATE = 2,
	SUCCESS_TYPE_INSERT = 3
};

enum KbanType {
	KBAN_TYPE_STEAMID 		= 0,
	KBAN_TYPE_IP			= 1,
	KBAN_TYPE_NOTKBANNED	= 2
};

enum struct Kban {
	int id;
	char clientName[MAX_NAME_LENGTH];
	char clientSteamID[MAX_AUTHID_LENGTH];
	char clientIP[MAX_IP_LENGTH];
	char adminName[MAX_NAME_LENGTH];
	char adminSteamID[MAX_AUTHID_LENGTH];

	char reason[REASON_MAX_LENGTH];
	char map[PLATFORM_MAX_PATH];

	int time_stamp_start;
	int time_stamp_end;
	int length;
}

enum struct OfflinePlayer {
	int userid;
	char name[MAX_NAME_LENGTH];
	char steamID[MAX_AUTHID_LENGTH];
	char ip[MAX_IP_LENGTH];
}

public Plugin myinfo = {
	name 		= "KnockbackRestrict",
	author		= "Dolly, Rushaway",
	description = "Adjust knockback of certain weapons for the kbanned players",
	version 	= KR_VERSION,
	url			= "https://github.com/srcdslab/sm-plugin-KnockbackRestrict"
};

#include "helpers/menus.sp"
#include "helpers/upgrade.sp"

public void OnPluginStart() {
	/* TRANSLATIONS */
	LoadTranslations("knockbackrestrict.phrases");
	LoadTranslations("common.phrases");

	/* COMMANDS */
	RegAdminCmd("sm_kban", 			Command_KbRestrict, 		ADMFLAG_KICK, "sm_kban <#userid|name> <minutes|0> [reason]");
	RegAdminCmd("sm_kunban", 		Command_KbUnRestrict, 		ADMFLAG_KICK, "sm_kunban <#userid|name> [reason]");
	RegAdminCmd("sm_koban", 		Command_OfflineKbRestrict, 	ADMFLAG_KICK, "sm_koban <#userid|name> <minutes|0> [reason]");
	RegAdminCmd("sm_kbanlist",		Command_KbanList,			ADMFLAG_KICK, "Shows the Kban List.");

	RegConsoleCmd("sm_kstatus", 	Command_CheckKbStatus, "Shows current player Kb-Restrict status");
	RegConsoleCmd("sm_kbstatus", 	Command_CheckKbStatus, "Shows current player Kb-Restrict status");
	RegConsoleCmd("sm_kbanstatus", 	Command_CheckKbStatus, "Shows current player Kb-Restrict status");

	/* CVARS */
	g_cvDefaultLength 			= CreateConVar("sm_kbrestrict_length", "30", "Default length when no length is specified");
	g_cvMaxBanTimeBanFlag		= CreateConVar("sm_kbrestrict_max_bantime_banflag", "20160", "Maximum ban time allowed for Ban-Flag accessible admins(0-518400)", _, true, 0.0, true, 518400.0);
	g_cvMaxBanTimeKickFlag		= CreateConVar("sm_kbrestrict_max_bantime_kickflag", "720", "Maximum ban time allowed for Kick-Flag accessible admins(0-518400)", _, true, 0.0, true, 518400.0);
	g_cvMaxBanTimeRconFlag		= CreateConVar("sm_kbrestrict_max_bantime_rconflag", "40320", "Maximum ban time allowed for Rcon-Flag accessible admins(0-518400)", _, true, 0.0, true, 518400.0);

	g_cvDisplayConnectMsg		= CreateConVar("sm_kbrestrict_display_connect_msg", "1", "Display a message to the player when he connects", _, true, 0.0, true, 1.0);
	g_cvGetRealKbanNumber		= CreateConVar("sm_kbrestrict_get_real_kban_number", "1", "Get the real number of kbans a player has (Do not include removed one)", _, true, 0.0, true, 1.0);
	g_cvSaveTempBans			= CreateConVar("sm_kbrestrict_save_tempbans", "1", "Save temporary bans to the database", _, true, 0.0, true, 1.0);

	g_cvReduceKnife				= CreateConVar("sm_kbrestrict_reduce_knife", "0.98", "Reduce knockback for knife", _, true, 0.0, true, 1.0);
	g_cvReduceKnifeMod			= CreateConVar("sm_kbrestrict_reduce_knife_mod", "0.83", "Reduce knockback for knife in knife mode", _, true, 0.0, true, 1.0);
	g_cvReducePistol			= CreateConVar("sm_kbrestrict_reduce_pistol", "0.50", "Reduce knockback for pistols", _, true, 0.0, true, 1.0);
	g_cvReduceSMG				= CreateConVar("sm_kbrestrict_reduce_smg", "0.30", "Reduce knockback for SMG's", _, true, 0.0, true, 1.0);
	g_cvReduceRifle				= CreateConVar("sm_kbrestrict_reduce_rifle", "0.50", "Reduce knockback for rifles", _, true, 0.0, true, 1.0);
	g_cvReduceShotgun			= CreateConVar("sm_kbrestrict_reduce_shotgun", "0.85", "Reduce knockback for shotguns", _, true, 0.0, true, 1.0);
	g_cvReduceSniper			= CreateConVar("sm_kbrestrict_reduce_sniper", "0.80", "Reduce knockback for snipers", _, true, 0.0, true, 1.0);
	g_cvReduceSemiAutoSniper	= CreateConVar("sm_kbrestrict_reduce_semiautosniper", "0.70", "Reduce knockback for semi-auto snipers", _, true, 0.0, true, 1.0);
	g_cvReduceGrenade			= CreateConVar("sm_kbrestrict_reduce_grenade", "0.95", "Reduce knockback for grenades", _, true, 0.0, true, 1.0);

	// Hook CVARs
	HookConVarChange(g_cvDefaultLength, OnConVarChanged);
	HookConVarChange(g_cvSaveTempBans, OnConVarChanged);
	HookConVarChange(g_cvReduceKnife, OnConVarChanged);
	HookConVarChange(g_cvReduceKnifeMod, OnConVarChanged);
	HookConVarChange(g_cvReducePistol, OnConVarChanged);
	HookConVarChange(g_cvReduceSMG, OnConVarChanged);
	HookConVarChange(g_cvReduceRifle, OnConVarChanged);
	HookConVarChange(g_cvReduceShotgun, OnConVarChanged);
	HookConVarChange(g_cvReduceSniper, OnConVarChanged);
	HookConVarChange(g_cvReduceSemiAutoSniper, OnConVarChanged);
	HookConVarChange(g_cvReduceGrenade, OnConVarChanged);
	
	// Initialize values
	g_iDefaultLength = g_cvDefaultLength.IntValue;
	g_bSaveTempBans = g_cvSaveTempBans.BoolValue;
	g_fReduceKnife = g_cvReduceKnife.FloatValue;
	g_fReduceKnifeMod = g_cvReduceKnifeMod.FloatValue;
	g_fReducePistol = g_cvReducePistol.FloatValue;
	g_fReduceSMG = g_cvReduceSMG.FloatValue;
	g_fReduceRifle = g_cvReduceRifle.FloatValue;
	g_fReduceShotgun = g_cvReduceShotgun.FloatValue;
	g_fReduceSniper = g_cvReduceSniper.FloatValue;
	g_fReduceSemiAutoSniper = g_cvReduceSemiAutoSniper.FloatValue;
	g_fReduceGrenade = g_cvReduceGrenade.FloatValue;

	AutoExecConfig();

	/* HOOK EVENTS */
	HookEvent("player_changename", Event_OnPlayerName, EventHookMode_Post);

	/* CONNECT TO DB */
	g_bConnectingToDB = false;
	ConnectToDB();

	/* Admin Menu */
	TopMenu topmenu;
	if(LibraryExists("adminmenu") && ((topmenu = GetAdminTopMenu()) != null))
		OnAdminMenuReady(topmenu);

	/* Prefix */
	CSetPrefix(KR_Tag);

	/* Incase of a late load */
	if(g_bLate) {
		for(int i = 1; i <= MaxClients; i++) {
			if(!IsClientInGame(i)) {
				continue;
			}

			if(IsFakeClient(i) || IsClientSourceTV(i)) {
				continue;
			}

			OnClientPutInServer(i);
		}
	}

	// Root cmd for upgrade sql structure from 3.3.x to 3.4+ (Fix buffer size)
	OnPluginStart_Upgrade();
}

/***********************************/
public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	g_bLate = late;

	RegPluginLibrary("KnockbackRestrict");

	CreateNative("KR_BanClient", Native_KR_BanClient);
	CreateNative("KR_UnBanClient", Native_KR_UnBanClient);
	CreateNative("KR_ClientStatus", Native_KR_ClientStatus);
	CreateNative("KR_GetClientKbansNumber", Native_KR_GetClientKbansNumber);

	/* Forward */
	g_hKbanForward 		= new GlobalForward("KR_OnClientKbanned", ET_Ignore, Param_Cell, Param_Cell, Param_Cell, Param_String, Param_Cell);
	g_hKunbanForward 	= new GlobalForward("KR_OnClientKunbanned", ET_Ignore, Param_Cell, Param_Cell, Param_String, Param_Cell);

	return APLRes_Success;
}

int Native_KR_BanClient(Handle plugin, int params) {
	char reason[REASON_MAX_LENGTH];

	int admin = GetNativeCell(1);
	int client = GetNativeCell(2);
	int time = GetNativeCell(3);
	GetNativeString(4, reason, sizeof(reason));

	if(g_bIsClientRestricted[client])
		return 0;

	Kban_AddBan(client, admin, time, reason);
	return 1;
}

int Native_KR_UnBanClient(Handle plugin, int params) {
	char reason[REASON_MAX_LENGTH];

	int admin = GetNativeCell(1);
	int client = GetNativeCell(2);
	GetNativeString(3, reason, sizeof(reason));

	if(!g_bIsClientRestricted[client])
		return 0;

	Kban_RemoveBan(client, admin, reason);
	return 1;
}

int Native_KR_ClientStatus(Handle plugin, int params) {
	int client = GetNativeCell(1);

	return g_bIsClientRestricted[client];
}

int Native_KR_GetClientKbansNumber(Handle plugin, int params) {
	int client = GetNativeCell(1);

	if(client < 1 || client > MaxClients || !IsClientInGame(client)) {
		return 0;
	}

	return g_iClientKbansNumber[client];
}

/********************************/
public void OnMapStart() {
	/* ARRAYLIST */
	delete g_allKbans;
	g_allKbans = new ArrayList(ByteCountToCells(2048));

	delete g_OfflinePlayers;
	g_OfflinePlayers = new ArrayList(ByteCountToCells(512));

	/* MAP NAME */
	GetCurrentMap(g_sMapName, sizeof(g_sMapName));

	/* Check all kbans by a timer */
	CreateTimer(5.0, CheckAllKbans_Timer, _, TIMER_FLAG_NO_MAPCHANGE | TIMER_REPEAT);
}

public void OnMapEnd() {
	for(int i = 0; i < g_allKbans.Length; i++) {
		Kban info;
		g_allKbans.GetArray(i, info, sizeof(info));
		if(info.time_stamp_end < 0 || info.length < 0) {
			char query[MAX_QUERIE_LENGTH];
			g_hDB.Format(query, sizeof(query), "UPDATE `KbRestrict_CurrentBans` SET `is_expired`=1 WHERE `id`=%d", info.id);
			g_hDB.Query(OnKbanRemove, query);
		}
	}
}

public void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue) {
	if (convar == g_cvDefaultLength)
		g_iDefaultLength = g_cvDefaultLength.IntValue;
	else if (convar == g_cvSaveTempBans)
		g_bSaveTempBans = g_cvSaveTempBans.BoolValue;
	else if (convar == g_cvReduceKnife)
		g_fReduceKnife = g_cvReduceKnife.FloatValue;
	else if (convar == g_cvReduceKnifeMod)
		g_fReduceKnifeMod = g_cvReduceKnifeMod.FloatValue;
	else if (convar == g_cvReducePistol)
		g_fReducePistol = g_cvReducePistol.FloatValue;
	else if (convar == g_cvReduceSMG)
		g_fReduceSMG = g_cvReduceSMG.FloatValue;
	else if (convar == g_cvReduceRifle)
		g_fReduceRifle = g_cvReduceRifle.FloatValue;
	else if (convar == g_cvReduceShotgun)
		g_fReduceShotgun = g_cvReduceShotgun.FloatValue;
	else if (convar == g_cvReduceSniper)
		g_fReduceSniper = g_cvReduceSniper.FloatValue;
	else if (convar == g_cvReduceSemiAutoSniper)
		g_fReduceSemiAutoSniper = g_cvReduceSemiAutoSniper.FloatValue;
	else if (convar == g_cvReduceGrenade)
		g_fReduceGrenade = g_cvReduceGrenade.FloatValue;
}

public void OnClientPutInServer(int client) {
	SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
}

public void OnClientPostAdminCheck(int client) {
	if(g_bUserVerified[client] || g_allKbans == null || g_OfflinePlayers == null || !IsDBConnected()) {
		return;
	}
	
	// We need to get last only last ban
	char queryEx[MAX_QUERIE_LENGTH];
	g_hDB.Format(queryEx, sizeof(queryEx), 
		"SELECT id, client_name, client_steamid, client_ip, admin_name, admin_steamid, reason, map, length, time_stamp_start, time_stamp_end, is_expired, is_removed \
		FROM `KbRestrict_CurrentBans` \
		WHERE `client_steamid`='%s' OR `client_ip`='%s' \
		ORDER BY id DESC LIMIT 1", 
		g_sSteamIDs[client], g_sIPs[client]
	);
	g_hDB.Query(OnClientPostAdminCheck_Query, queryEx, GetClientUserId(client));
	
	for(int i = 0; i < g_OfflinePlayers.Length; i++) {
		OfflinePlayer player;
		g_OfflinePlayers.GetArray(i, player, sizeof(player));
		if(strcmp(player.steamID, g_sSteamIDs[client], false) == 0) {
			g_OfflinePlayers.Erase(i);
			break;
		}
	}
	
	/* check if this dude got kbanned with steamid pending, we want to update the steamid */
	for(int i = 0; i < g_allKbans.Length; i++) {
		Kban info;
		g_allKbans.GetArray(i, info, sizeof(info));
		if(strcmp(info.clientIP, g_sIPs[client], false) == 0) {
			if(strcmp(info.clientSteamID, NOSTEAMID, false) == 0) {

				FormatEx(info.clientSteamID, sizeof(info.clientSteamID), g_sSteamIDs[client]);
				g_allKbans.SetArray(i, info, sizeof(info));

				char query[MAX_QUERIE_LENGTH];
				g_hDB.Format(query, sizeof(query), "UPDATE `KbRestrict_CurrentBans` SET `client_steamid`='%s' WHERE `id`=%d", g_sSteamIDs[client], info.id);
				g_hDB.Query(OnKbanAdded, query);
			}

			break;
		}
	}

	/* let's tell how many kbans this dude has */
	Kban_CallGetKbansNumber(client);
}

void OnClientPostAdminCheck_Query(Database db, DBResultSet results, const char[] error, int userid) {
	if(!IsDBConnected() || results == null || error[0]) {
		Kban_GiveError(ERROR_TYPE_SELECT, error);
		return;
	}

	int client = GetClientOfUserId(userid);
	if(client < 1) {
		return;
	}

	bool isKbanned = false;
	Kban tempInfo;
	int currentTime = GetTime();

	while(results.FetchRow()) {
		bool isExpired = (results.FetchInt(11) == 0) ? false : true;
		bool isRemoved = (results.FetchInt(12) == 0) ? false : true;

		// Store all data results we need
		Kban info;
		for(int i = 0; i <= 10; i++) {
			Kban_GetRowResults(i, results, info);
		}

		// Skip if kban is expired or manually removed
		if (isExpired || isRemoved) {
			continue;
		}

		// Time validation only if kban is not expired
		bool isTimeValid = false;
		
		if (info.time_stamp_end == 0) { // Permanent kban
			isTimeValid = true;
		} else if (info.time_stamp_end > 0) { // Temporary kban
			isTimeValid = (info.time_stamp_start <= currentTime && info.time_stamp_end > currentTime);
		} else if (info.time_stamp_end == -1) { // Session kban
			isTimeValid = true;
		}

		// Kban conditions check
		if (isTimeValid) {
			// Additional check for IP-based kbans
			if (strcmp(info.clientIP, g_sIPs[client], false) == 0) {
				// If kban is by IP, verify that steamid is not already kbanned
				if (strcmp(info.clientSteamID, NOSTEAMID, false) == 0 || 
					strcmp(info.clientSteamID, g_sSteamIDs[client], false) == 0) {
					isKbanned = true;
					tempInfo = info;
				}
			} else if (strcmp(info.clientSteamID, g_sSteamIDs[client], false) == 0) {
				// SteamID kban
				isKbanned = true;
				tempInfo = info;
			}

			if (isKbanned) {
				/* Check if IP is not known */
				if(strcmp(tempInfo.clientIP, "Unknown", false) == 0) {
					/* Update IP in DB */
					char query[MAX_QUERIE_LENGTH];
					g_hDB.Format(query, sizeof(query), "UPDATE `KbRestrict_CurrentBans` SET `client_ip`='%s' WHERE `id`=%d", g_sIPs[client], tempInfo.id);
					g_hDB.Query(OnUpdateClientIP, query);

					FormatEx(tempInfo.clientIP, sizeof(tempInfo.clientIP), "%s", g_sIPs[client]);
					for(int i = 0; i < g_allKbans.Length; i++) {
						Kban exInfo;
						g_allKbans.GetArray(i, exInfo, sizeof(exInfo));
						if(exInfo.id == tempInfo.id) {
							FormatEx(exInfo.clientIP, sizeof(exInfo.clientIP), "%s", tempInfo.clientIP);
							g_allKbans.SetArray(i, exInfo, sizeof(exInfo));
							break;
						}
					}
				}
				break;
			}
		}
	}

	g_bUserVerified[client] = true;
	
	if(isKbanned) {
		g_bIsClientRestricted[client] = true;

		KbanType type = Kban_GetClientKbanType(client);
		if(type != KBAN_TYPE_NOTKBANNED) {
			return;
		}

		g_allKbans.PushArray(tempInfo, sizeof(tempInfo));
	} else {
		g_bIsClientRestricted[client] = false;

		KbanType type = Kban_GetClientKbanType(client);
		if(type == KBAN_TYPE_NOTKBANNED) {
			return;
		} 

		Kban kbanInfo;
		if(type == KBAN_TYPE_IP) {
			if(!Kban_GetKban(KBAN_GET_TYPE_IP, kbanInfo, _, _, g_sIPs[client])) {
				return;
			}
		} else {
			if(!Kban_GetKban(KBAN_GET_TYPE_STEAMID, kbanInfo, _, g_sSteamIDs[client])) {
				return;
			}
		}

		for(int i = 0; i < g_allKbans.Length; i++) {
			Kban exInfo;
			g_allKbans.GetArray(i, exInfo, sizeof(exInfo));
			if(exInfo.id == kbanInfo.id) {
				g_allKbans.Erase(i);
				break;
			}
		}
	}
}

void OnUpdateClientIP(Database db, DBResultSet results, const char[] error, int userid) {
	if(!IsDBConnected() || results == null || error[0]) {
		Kban_GiveError(ERROR_TYPE_UPDATE, error);
		return;
	}
}

void Kban_CallGetKbansNumber(int client) {
	char query[MAX_QUERIE_LENGTH];
	if (!g_cvGetRealKbanNumber.BoolValue) {
		g_hDB.Format(query, sizeof(query), "SELECT client_steamid FROM `KbRestrict_CurrentBans` WHERE `client_steamid`='%s'", g_sSteamIDs[client]);
	} else {
		g_hDB.Format(query, sizeof(query), "SELECT client_steamid FROM `KbRestrict_CurrentBans` WHERE `client_steamid`='%s' AND `is_removed`=0", g_sSteamIDs[client]);
	}
	g_hDB.Query(OnGetKbansNumber, query, GetClientUserId(client));
}

void OnGetKbansNumber(Database db, DBResultSet results, const char[] error, int userid) {
	if(!IsDBConnected() || results == null || error[0]) {
		Kban_GiveError(ERROR_TYPE_SELECT, error);
		return;
	} 

	int count = 0;
	while(results.FetchRow()) {
		count++;
	}

	if(count == 0) {
		return;
	}

	int client = GetClientOfUserId(userid);
	if(client < 1) {
		return;
	}

	g_iClientKbansNumber[client] = count;

	if (!g_cvDisplayConnectMsg.BoolValue)
		return;

	for(int i = 1; i <= MaxClients; i++) {
		if(!IsClientInGame(i)) {
			continue;
		}

		if(CheckCommandAccess(i, "sm_admin", ADMFLAG_KICK, true)) {
			CPrintToChat(i, "%t", "PlayerConnect", client, count);
		}
	}
}

public Action Event_OnPlayerName(Handle event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	if (client <= MaxClients && client > 0 && IsClientInGame(client) && !IsFakeClient(client) && !IsClientSourceTV(client))
		GetEventString(event, "newname", g_sName[client], sizeof(g_sName[]));
	return Plugin_Continue;
}

public void OnClientConnected(int client) {
	bool bError = false;
	char sIP[MAX_IP_LENGTH], sSteamID[MAX_AUTHID_LENGTH], sName[MAX_NAME_LENGTH];
	// Can't get client data, restrict him by default.
	if (!GetClientIP(client, sIP, sizeof(sIP)) || !GetClientAuthId(client, AuthId_Steam2, sSteamID, sizeof(sSteamID), false) || !GetClientName(client, sName, sizeof(sName))) {
		LogMessage("Failed to get client data for client %L, applying temporary Kban", client);
		strcopy(sSteamID, sizeof(sSteamID), NOSTEAMID);
		strcopy(sName, sizeof(sName), "Unknown");
		bError = true;
	}

	// Initialize client data
	g_bUserVerified[client] = false;
	g_bIsClientRestricted[client] = false;
	FormatEx(g_sIPs[client], sizeof(g_sIPs[]), sIP);
	FormatEx(g_sSteamIDs[client], sizeof(g_sSteamIDs[]), sSteamID);
	FormatEx(g_sName[client], sizeof(g_sName[]), sName);

	if(bError || IsIPBanned(g_sIPs[client])) {
		g_bIsClientRestricted[client] = true;
	}

	// Avoid useless queries
	if (IsFakeClient(client) || IsClientSourceTV(client)) {
		g_bUserVerified[client] = true;
	}
}

public void OnClientDisconnect(int client) {
	if(IsFakeClient(client) || IsClientSourceTV(client)) {
		return;
	}

	OfflinePlayer player;
	player.userid = GetClientUserId(client);
	FormatEx(player.steamID, sizeof(player.steamID), g_sSteamIDs[client]);
	FormatEx(player.ip, sizeof(player.ip), g_sIPs[client]);
	FormatEx(player.name, sizeof(player.name), g_sName[client]);

	g_OfflinePlayers.PushArray(player, sizeof(player));

	FormatEx(g_sSteamIDs[client], sizeof(g_sSteamIDs[]), "");
	FormatEx(g_sName[client], sizeof(g_sName[]), "");
	FormatEx(g_sIPs[client], sizeof(g_sIPs[]), "");
	g_bIsClientRestricted[client] = false;
	g_bUserVerified[client] = false;
	g_iClientKbansNumber[client] = 0;
}

public void OnLibraryAdded(const char[] name) {
	if (strcmp(name, "KnifeMode", false) == 0) {
		g_bKnifeModeEnabled = true;
	}
}

public void OnLibraryRemoved(const char[] name) {
	if (strcmp(name, "KnifeMode", false) == 0) {
		g_bKnifeModeEnabled = false;
	}

	if (strcmp(name, "adminmenu", false) == 0) {
		g_hAdminMenu = null;
	}
}

public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype)
{
	if(victim < 1 || victim > MaxClients || !IsClientInGame(victim) || attacker < 1 || attacker > MaxClients || !IsClientInGame(attacker)) {
		return Plugin_Continue;
	}

	if(!g_bIsClientRestricted[attacker]) {
		return Plugin_Continue;
	}

	if(GetClientTeam(attacker) != CS_TEAM_CT) {
		return Plugin_Continue;
	}

	char sWeapon[32];
	GetClientWeapon(attacker, sWeapon, 32);

	/* Knife */
	if (strcmp(sWeapon, "weapon_knife", false) == 0) {
		if (!g_bKnifeModeEnabled)
			damage -= (damage * g_fReduceKnife);
		else
			damage -= (damage * g_fReduceKnifeMod);
	}

	/* Pistols */
	if (strcmp(sWeapon, "weapon_deagle", false) == 0)
		damage -= (damage * g_fReducePistol);

	/* SMG's */
	if ((strcmp(sWeapon, "weapon_mac10", false) == 0) || (strcmp(sWeapon, "weapon_tmp", false) == 0) || (strcmp(sWeapon, "weapon_mp5navy", false) == 0)
		|| (strcmp(sWeapon, "weapon_ump45", false) == 0) || (strcmp(sWeapon, "weapon_p90", false) == 0))
		damage -= (damage * g_fReduceSMG);

	/* Rifles */
	if ((strcmp(sWeapon, "weapon_galil", false) == 0) || (strcmp(sWeapon, "weapon_famas", false) == 0) || (strcmp(sWeapon, "weapon_ak47", false) == 0)
		|| (strcmp(sWeapon, "weapon_m4a1", false) == 0) || (strcmp(sWeapon, "weapon_sg552", false) == 0) || (strcmp(sWeapon, "weapon_aug", false) == 0)
		|| (strcmp(sWeapon, "weapon_m249", false) == 0))
		damage -= (damage * g_fReduceRifle);

	/* ShotGuns */
	if ((strcmp(sWeapon, "weapon_m3", false) == 0) || (strcmp(sWeapon, "weapon_xm1014", false) == 0))
		damage -= (damage * g_fReduceShotgun);

	/* Snipers */
	if ((strcmp(sWeapon, "weapon_awp", false) == 0) || (strcmp(sWeapon, "weapon_scout", false) == 0))
		damage -= (damage * g_fReduceSniper);

	/* Semi-Auto Snipers */
	if ((strcmp(sWeapon, "weapon_sg550", false) == 0) || (strcmp(sWeapon, "weapon_g3sg1", false) == 0))
		damage -= (damage * g_fReduceSemiAutoSniper);
	
	/* Grenades */
	if (strcmp(sWeapon, "weapon_hegrenade", false) == 0)
		damage -= (damage * g_fReduceGrenade);

	return Plugin_Changed;
}

Action CheckAllKbans_Timer(Handle timer) {
	if(g_allKbans == null || !g_allKbans.Length) {
		return Plugin_Handled;
	}

	// Player was not verified yet, force the verification
	for(int i = 1; i <= MaxClients; i++) {
		if(!IsClientInGame(i))
			continue;

		if (g_bUserVerified[i])
			continue;

		if (IsFakeClient(i) || IsClientSourceTV(i))
			continue;

		OnClientConnected(i);
		OnClientPostAdminCheck(i);
	}

	for(int i = 0; i < g_allKbans.Length; i++) {
		Kban info;
		g_allKbans.GetArray(i, info, sizeof(info));
		if(info.time_stamp_end > 0 && info.time_stamp_end < GetTime()) {
			/* We want to unban this dude, check if the player is in game first by either steamid or ip */
			char query[MAX_QUERIE_LENGTH];
			g_hDB.Format(query, sizeof(query), "SELECT `time_stamp_end` FROM `KbRestrict_CurrentBans` WHERE `id`=%d", info.id);
			g_hDB.Query(OnKbanExpired, query, info.id);
		}
	}

	return Plugin_Continue;
}

void OnKbanExpired(Database db, DBResultSet results, const char[] error, int id) {
	if(!IsDBConnected() || results == null || error[0]) {
		Kban_GiveError(ERROR_TYPE_UPDATE, error);
		return;
	}

	Kban info;
	if(!Kban_GetKban(KBAN_GET_TYPE_ID, info, id)) {
		return;
	}

	if(results.FetchRow()) {
		int time_stamp_end = results.FetchInt(0);
		if(time_stamp_end < 1) {
			return;
		}

		if(time_stamp_end < GetTime()) {
			char query[MAX_QUERIE_LENGTH];
			g_hDB.Format(query, sizeof(query), "UPDATE `KbRestrict_CurrentBans` SET `is_expired`=1 WHERE `id`=%d", info.id);
			g_hDB.Query(OnKbanRemove, query);

			for(int i = 0; i < g_allKbans.Length; i++) {
				Kban exInfo;
				g_allKbans.GetArray(i, exInfo, sizeof(exInfo));
				if(exInfo.id == info.id) {
					g_allKbans.Erase(i);
				}
			}
			if(strcmp(info.clientSteamID, NOSTEAMID, false) == 0) {
				int client = Kban_GetClientByIP(info.clientIP);
				if(client != -1) {
					g_bIsClientRestricted[client] = false;
					CPrintToChatAll("%t", "UnRestricted", 0, client, KR_Tag, "KBan Expired");
				}
			} else {
				int client = Kban_GetClientBySteamID(info.clientSteamID);
				if(client != -1) {
					g_bIsClientRestricted[client] = false;
					CPrintToChatAll("%t", "UnRestricted", 0, client, KR_Tag, "KBan Expired");
				}
			}
		} else {
			for(int i = 0; i < g_allKbans.Length; i++) {
				Kban exInfo;
				g_allKbans.GetArray(i, exInfo, sizeof(exInfo));
				if(exInfo.id == info.id) {
					info.time_stamp_end = time_stamp_end;
					g_allKbans.SetArray(i, info, sizeof(info));
				}
			}
		}
	}
}

//----------------------------------------------------------------------------------------------------
// Commands
//----------------------------------------------------------------------------------------------------
Action Command_KbanList(int client, int args) {
	if(!client) {
		return Plugin_Handled;
	}

	Kban_OpenMainMenu(client);
	return Plugin_Handled;
}

Action Command_KbRestrict(int client, int args) {

	if(args < 1) {
		CReplyToCommand(client, "Usage: sm_kban <player> <duration> <reason>");
		Kban_OpenMainMenu(client);
		return Plugin_Handled;
	}

	int time;
	int len, next_len;
	char Arguments[256], arg[50], s_time[20];

	GetCmdArgString(Arguments, sizeof(Arguments));

	len = BreakString(Arguments, arg, sizeof(arg));
	if(len == -1)
	{
		len = 0;
		Arguments[0] = '\0';
	}

	if((next_len = BreakString(Arguments[len], s_time, sizeof(s_time))) != -1)
		len += next_len;
	else {
		len = 0;
		Arguments[0] = '\0';
	}

	if(!s_time[0] || !StringToIntEx(s_time, time)) {
		time = g_iDefaultLength;
	}

	char reason[REASON_MAX_LENGTH];
	FormatEx(reason, sizeof(reason), Arguments[len]);

	int target = FindTarget(client, arg, false, false);
	if(target < 1) {
		return Plugin_Handled;
	}

	if(g_bIsClientRestricted[target])
	{
		CReplyToCommand(client, "%t", "AlreadyKBanned");
		return Plugin_Handled;
	}

	/* Check if admin has access to perma ban or a long ban */
	if(client > 0 && !CheckCommandAccess(client, "sm_admin", ADMFLAG_ROOT, true)) {
		if(time == 0) {
			time = g_iDefaultLength;
		}
		
		/* Check Admin Access */
		time = Kban_CheckKbanAdminAccess(client, time);
	}

	StripQuotes(reason);
	if(!reason[0] || strlen(reason) <= 3) {
		if(client >= 1) {	
			g_iClientTarget[client] = GetClientUserId(target);
			g_iClientTargetLength[client] = time;
			DisplayReasons_Menu(client);
			return Plugin_Handled;
		}
	}

	Kban_AddBan(target, client, time, reason);
	return Plugin_Handled;
}

Action Command_KbUnRestrict(int client, int args) {
	if(args < 1)
	{
		CReplyToCommand(client, "Usage: sm_kunban <player> <reason>.");
		Kban_OpenMainMenu(client);
		return Plugin_Handled;
	}

	char Arguments[256], arg[50];
	GetCmdArgString(Arguments, sizeof(Arguments));

	int len;
	len = BreakString(Arguments, arg, sizeof(arg));
	if(len == -1)
	{
		len = 0;
		Arguments[0] = '\0';
	}

	int target = FindTarget(client, arg, false, false);
	if(target < 1) {
		return Plugin_Handled;
	}

	if(!g_bIsClientRestricted[target]) {
		CReplyToCommand(client, "%t", "AlreadyKUnbanned");
		return Plugin_Handled;
	}

	char reason[REASON_MAX_LENGTH];
	FormatEx(reason, sizeof(reason), Arguments[len]);

	char adminSteamID[MAX_AUTHID_LENGTH];
	if(!client) {
		adminSteamID = "Console";
	} else {
		adminSteamID = g_sSteamIDs[client];
	}

	Kban info;

	KbanType type = Kban_GetClientKbanType(target);
	if(type == KBAN_TYPE_STEAMID) {
		Kban_GetKban(KBAN_GET_TYPE_STEAMID, info, _, g_sSteamIDs[target]);
	} else {
		Kban_GetKban(KBAN_GET_TYPE_IP, info, _, _, g_sIPs[target]);
	}

	bool canUnban = false;
	if (strcmp(adminSteamID, "Console", false) == 0 || CheckCommandAccess(client, "sm_admin", ADMFLAG_RCON, true)) {
		canUnban = true;
	}

	if (!canUnban && strcmp(info.adminSteamID, adminSteamID, false) == 0) {
		canUnban = true;
	}

	if(canUnban) {
		Kban_RemoveBan(target, client, reason);
		return Plugin_Handled;
	} else {
		CReplyToCommand(client, "%t", "NotOwnBan");
		return Plugin_Handled;
	}
}

Action Command_OfflineKbRestrict(int client, int args) {
	if(args < 1) {
		if(!client) {
			return Plugin_Handled;
		}

		Kban_OpenOfflineKbanMenu(client);
		CReplyToCommand(client, "Usage: sm_koban <player> <time> <reason>");
		return Plugin_Handled;
	}

	int time;
	int len, next_len;
	char Arguments[256], arg[50], s_time[20];

	GetCmdArgString(Arguments, sizeof(Arguments));

	len = BreakString(Arguments, arg, sizeof(arg));
	if(len == -1)
	{
		len = 0;
		Arguments[0] = '\0';
	}

	if((next_len = BreakString(Arguments[len], s_time, sizeof(s_time))) != -1)
		len += next_len;
	else {
		len = 0;
		Arguments[0] = '\0';
	}

	if(!s_time[0] || !StringToIntEx(s_time, time)) {
		time = g_iDefaultLength;
	}

	char reason[REASON_MAX_LENGTH];
	FormatEx(reason, sizeof(reason), Arguments[len]);
	
	/* Check if admin has access to perma ban or a long ban */
	if(client > 0 && !CheckCommandAccess(client, "sm_admin", ADMFLAG_ROOT, true)) {
		if(time == 0) {
			time = g_iDefaultLength;
		}

		/* Check Admin Access */
		time = Kban_CheckKbanAdminAccess(client, time);
	}

	int arrays = Kban_GetOfflineBanResults(arg);
	if(arrays > 1) {
		Kban_OpenOfflineKbanMenu(client, arg);
		return Plugin_Handled;
	} else if(arrays <= 0) {
		CReplyToCommand(client, "No matched client was found.");
		return Plugin_Handled;
	}

	int arrayIndex = Kban_GetOfflinePlayerArray(arg);
	if(arrayIndex == -1) {
		CReplyToCommand(client, "%t", "PlayerNotValid");
		return Plugin_Handled;
	}

	OfflinePlayer player;
	g_OfflinePlayers.GetArray(arrayIndex, player, sizeof(player));
	
	for(int i = 0; i < g_allKbans.Length; i++) {
		Kban info;
		g_allKbans.GetArray(i, info, sizeof(info));
		if(strcmp(info.clientSteamID, player.steamID, false) == 0 || strcmp(info.clientIP, player.ip, false) == 0) {
			CReplyToCommand(client, "%t", "AlreadyKBanned");
			return Plugin_Handled;
		}
	}
	
	Kban_AddOfflineBan(player, client, time, reason);
	return Plugin_Handled;
}

void Kban_AddOfflineBan(OfflinePlayer player, int admin, int length, char[] reason) {
	Kban info;
	if (length < 0) {
		length = g_iDefaultLength;
	}

	if(!reason[0]) {
		FormatEx(reason, REASON_MAX_LENGTH, "Trying To Boost");
	}

	char steamID[MAX_AUTHID_LENGTH], adminName[MAX_NAME_LENGTH];
	FormatEx(steamID, sizeof(steamID), admin < 1 ? "Console" : g_sSteamIDs[admin]);
	FormatEx(adminName, sizeof(adminName), admin < 1 ? "Console" : g_sName[admin]);

	FormatEx(info.clientName, sizeof(info.clientName), player.name);
	FormatEx(info.clientSteamID, sizeof(info.clientSteamID), player.steamID);
	FormatEx(info.clientIP, sizeof(info.clientIP), player.ip);
	FormatEx(info.adminName, sizeof(info.adminName), adminName);
	FormatEx(info.adminSteamID, sizeof(info.adminSteamID), steamID);
	FormatEx(info.reason, sizeof(info.reason), reason);
	FormatEx(info.map, sizeof(info.map), g_sMapName);

	info.length = length;
	info.time_stamp_start = GetTime();
	if(length > 0) {
		info.time_stamp_end = (GetTime() + (length * 60)); // Duration in minutes
	} else if(length == 0) {
		info.time_stamp_end = 0; // Permanent
	}

	// Edit ID purpose
	int arrayIndex = g_allKbans.PushArray(info, sizeof(info));
	
	char escapedTargetName[MAX_NAME_LENGTH * 2 + 1], escapedAdminName[MAX_NAME_LENGTH * 2 + 1], escapedReason[REASON_MAX_LENGTH * 2 + 1];
	if(!g_hDB.Escape(adminName, escapedAdminName, sizeof(escapedAdminName))
		|| !g_hDB.Escape(player.name, escapedTargetName, sizeof(escapedTargetName))
		|| !g_hDB.Escape(reason, escapedReason, sizeof(escapedReason))) {
		return;
	}

	char query[MAX_QUERIE_LENGTH];
	g_hDB.Format(query, sizeof(query), 		"INSERT INTO `KbRestrict_CurrentBans` ("
										... "`client_name`, `client_steamid`, `client_ip`,"
										... "`admin_name`, `admin_steamid`, `reason`,"
										... "`map`, `length`, `time_stamp_start`,"
										... "`time_stamp_end`, `is_expired`, `is_removed`,"
										... "`admin_name_removed`, `admin_steamid_removed`, `time_stamp_removed`,"
										... "`reason_removed`)"
										... "VALUES ('%s', '%s', '%s', '%s', '%s', '%s', '%s',"
										... "'%d', '%d', '%d', '%d', '%d', '%s', '%s', '%d', '%s')",
										escapedTargetName, info.clientSteamID, info.clientIP,
										escapedAdminName, info.adminSteamID, escapedReason,
										info.map, info.length, info.time_stamp_start,
										info.time_stamp_end, 0, 0,
										"null", "null", 0, "null");
										
	g_hDB.Query(OnKbanAdded, query, arrayIndex);

	PublishKban(info, admin, _, reason);
}

int Kban_GetOfflinePlayerArray(const char[] arg) {
	for(int i = 0; i < g_OfflinePlayers.Length; i++) {
		OfflinePlayer player;
		g_OfflinePlayers.GetArray(i, player, sizeof(player));
		if(StrContains(player.name, arg, false) != -1) {
			return i;
		}
	}

	return -1;
}

int Kban_GetOfflineBanResults(const char[] arg) {
	int ret = 0;

	for(int i = 0; i < g_OfflinePlayers.Length; i++) {
		OfflinePlayer player;
		g_OfflinePlayers.GetArray(i, player, sizeof(player));
		if(StrContains(player.name, arg, false) != -1) {
			ret++;
		}
	}

	return ret;
}

Action Command_CheckKbStatus(int client, int args) {
	int target = -1;

	if(args < 1 || !CheckCommandAccess(client, "sm_kban", ADMFLAG_KICK, true)) {
		target = client;
	} else {
		char sArg[MAX_NAME_LENGTH];
		GetCmdArg(1, sArg, sizeof(sArg));
		target = FindTarget(client, sArg, false, true);
	}

	SetGlobalTransTarget(client);

	if(target == -1) {
		CReplyToCommand(client, "%t", "Player no longer available");
		return Plugin_Handled;
	}

	if(!g_bIsClientRestricted[target]) {
		CReplyToCommand(client, "%t", "PlayerNotRestricted", g_sName[target]);
		return Plugin_Handled;
	}

	Kban info;
	KbanType type = Kban_GetClientKbanType(target);
	if(type == KBAN_TYPE_STEAMID) {
		Kban_GetKban(KBAN_GET_TYPE_STEAMID, info, _, g_sSteamIDs[target]);
	} else {
		Kban_GetKban(KBAN_GET_TYPE_IP, info, _, _, g_sIPs[target]);
	}

	switch(info.length) {
		case 0: {
			CReplyToCommand(target, "%t", "PlayerRestrictedPerma", g_sName[target]);
		}

		case -1: {
			CReplyToCommand(target, "%t", "PlayerRestrcitedTemp", g_sName[target]);
		}

		default: {
			char sTimeLeft[32];
			CheckPlayerExpireTime(info.time_stamp_end - GetTime(), sTimeLeft, sizeof(sTimeLeft));
			CReplyToCommand(target, "%t", "RestrictTimeLeft", g_sName[target], sTimeLeft);
		}
	}

	CReplyToCommand(target, "{white}%t", "Reason", info.reason);

	return Plugin_Handled;
}

stock void CheckPlayerExpireTime(int lefttime, char[] TimeLeft, int maxlength) {
	if(lefttime > -1)
	{
		if(lefttime < 60) // 60 secs
			FormatEx(TimeLeft, maxlength, "%02i %s", lefttime, "Seconds");
		else if(lefttime > 3600 && lefttime <= 3660) // 1 Hour
			FormatEx(TimeLeft, maxlength, "%i %s %02i %s", lefttime / 3600, "Hour", (lefttime / 60) % 60, "Minutes");
		else if(lefttime > 3660 && lefttime < 86400) // 2 Hours or more
			FormatEx(TimeLeft, maxlength, "%i %s %02i %s", lefttime / 3600, "Hours", (lefttime / 60) % 60, "Minutes");
		else if(lefttime > 86400 && lefttime <= 172800) // 1 Day
			FormatEx(TimeLeft, maxlength, "%i %s %02i %s", lefttime / 86400, "Day", (lefttime / 3600) % 24, "Hours");
		else if(lefttime > 172800) // 2 Days or more
			FormatEx(TimeLeft, maxlength, "%i %s %02i %s", lefttime / 86400, "Days", (lefttime / 3600) % 24, "Hours");
		else // Less than 1 Hour
			FormatEx(TimeLeft, maxlength, "%i %s %02i %s", lefttime / 60, "Minutes", lefttime % 60, "Seconds");
	}
}

//----------------------------------------------------------------------------------------------------
// Database stuffs
//----------------------------------------------------------------------------------------------------
void Kban_GetRowResults(int num, DBResultSet results, Kban info) {
	switch(num) {
		case 0: {
			info.id = results.FetchInt(num);
		}
		case 1: {
			results.FetchString(num, info.clientName, sizeof(info.clientName));
		}
		case 2: {
			results.FetchString(num, info.clientSteamID, sizeof(info.clientSteamID));
		}
		case 3: {
			results.FetchString(num, info.clientIP, sizeof(info.clientIP));
		}
		case 4: {
			results.FetchString(num, info.adminName, sizeof(info.adminName));
		}
		case 5: {
			results.FetchString(num, info.adminSteamID, sizeof(info.adminSteamID));
		}
		case 6: {
			results.FetchString(num, info.reason, sizeof(info.reason));
		}
		case 7: {
			results.FetchString(num, info.map, sizeof(info.map));
		}
		case 8: {
			info.length = results.FetchInt(num);
		}
		case 9: {
			info.time_stamp_start = results.FetchInt(num);
		}
		case 10: {
			info.time_stamp_end = results.FetchInt(num);
		}
	}
}

void ConnectToDB()
{
	Database.Connect(DB_OnConnect, "KbRestrict");
}

//----------------------------------------------------------------------------------------------------
// Database Connection Status :
//----------------------------------------------------------------------------------------------------
void DB_OnConnect(Database db, const char[] error, any data)
{
	if(db == null || error[0])
	{
		/* Failure happen. Do retry with delay */
		if (!g_bConnectingToDB)
		{
			g_bConnectingToDB = true;
			CreateTimer(15.0, DB_RetryConnection);
			LogError("[Kb-Restrict] Couldn't connect to database `KbRestrict`, retrying in 15 seconds. \nError: %s", error);
		}

		return;
	}

	LogMessage("[Kb-Restrict] Successfully connected to database!");
	g_bConnectingToDB = false;
	g_hDB = db;
	g_hDB.SetCharset(DB_CHARSET);
	DB_CreateTables();
}

bool IsDBConnected()
{
	if(g_hDB == null)
	{
		if (!g_bConnectingToDB)
			LogError("[Kb-Restrict] Database connection is lost, attempting to reconnect...");
		ConnectToDB();
		return false;
	}

	return true;
}

//----------------------------------------------------------------------------------------------------
// Database Attempting Reconnect :
//----------------------------------------------------------------------------------------------------
Action DB_RetryConnection(Handle timer)
{
	g_bConnectingToDB = false;
	IsDBConnected();

	return Plugin_Continue;
}

void DB_CreateTables() {
	if(g_hDB == null) {
		return;
	}

	char driver[10];
	g_hDB.Driver.GetIdentifier(driver, sizeof(driver));
	if(strcmp(driver, "mysql", false) != 0) {
		LogError("[Kb-Restrict] drivers other than mysql are not supported.");
		return;
	}

	char query[MAX_QUERIE_LENGTH];
	Transaction T_Tables = SQL_CreateTransaction();

	g_hDB.Format(query, sizeof(query), "CREATE TABLE IF NOT EXISTS `KbRestrict_CurrentBans` ( \
										`id` int(11) unsigned NOT NULL AUTO_INCREMENT, \
										`client_name` varchar(%d) NOT NULL, \
										`client_steamid` varchar(%d) NOT NULL, \
										`client_ip` varchar(%d) NOT NULL, \
										`admin_name` varchar(%d) NOT NULL, \
										`admin_steamid` varchar(%d) NOT NULL, \
										`reason` varchar(%d) NOT NULL, \
										`map` varchar(%d) NOT NULL, \
										`length` int(11) NOT NULL, \
										`time_stamp_start` int(11) NOT NULL, \
										`time_stamp_end` int(11) NOT NULL, \
										`is_expired` int(11) NOT NULL, \
										`is_removed` int(11) NOT NULL, \
										`time_stamp_removed` int(20) NOT NULL, \
										`admin_name_removed` varchar(%d) NOT NULL, \
										`admin_steamid_removed` varchar(%d) NOT NULL, \
										`reason_removed` varchar(%d) NOT NULL, \
										PRIMARY KEY(`id`)) CHARACTER SET %s COLLATE %s;",
										MAX_NAME_LENGTH, MAX_AUTHID_LENGTH, MAX_IP_LENGTH, // Client
										MAX_NAME_LENGTH, MAX_AUTHID_LENGTH, // Admin
										REASON_MAX_LENGTH, PLATFORM_MAX_PATH, // Reason + Map
										MAX_NAME_LENGTH, MAX_AUTHID_LENGTH, REASON_MAX_LENGTH, // Admin + Remove reason
										DB_CHARSET, DB_COLLATION
	);

	T_Tables.AddQuery(query);

	g_hDB.Format(query, sizeof(query), "CREATE TABLE IF NOT EXISTS `KbRestrict_srvlogs` ( \
										`id` int(10) unsigned NOT NULL AUTO_INCREMENT, \
										`message` varchar(200) NOT NULL, \
										`admin_name` varchar(%d) NOT NULL, \
										`admin_steamid` varchar(%d) NOT NULL, \
										`client_name` varchar(%d) NOT NULL, \
										`client_steamid` varchar(%d) NOT NULL, \
										`time_stamp` int(20) NOT NULL, \
										PRIMARY KEY(`id`)) CHARACTER SET %s COLLATE %s;",
										MAX_NAME_LENGTH, MAX_AUTHID_LENGTH, MAX_NAME_LENGTH, MAX_AUTHID_LENGTH, DB_CHARSET, DB_COLLATION
	);
		
	T_Tables.AddQuery(query);

	g_hDB.Format(query, sizeof(query), "CREATE TABLE IF NOT EXISTS `KbRestrict_weblogs` ( \
										`id` int(10) unsigned NOT NULL AUTO_INCREMENT, \
										`message` varchar(200) NOT NULL, \
										`admin_name` varchar(%d) NOT NULL, \
										`admin_steamid` varchar(%d) NOT NULL, \
										`client_name` varchar(%d) NOT NULL, \
										`client_steamid` varchar(%d) NOT NULL, \
										`time_stamp` int(20) NOT NULL, \
										PRIMARY KEY(`id`)) CHARACTER SET %s COLLATE %s;",
										MAX_NAME_LENGTH, MAX_AUTHID_LENGTH, MAX_NAME_LENGTH, MAX_AUTHID_LENGTH, DB_CHARSET, DB_COLLATION
	);

	T_Tables.AddQuery(query);

	g_hDB.Execute(T_Tables, OnCreateTablesSuccess, OnCreateTablesError);
}

void OnCreateTablesSuccess(Database db, any data, int numQueries, DBResultSet[] results, any[] queryData) {
	Kban_GiveSuccess(SUCCESS_TYPE_CREATE);
}

void OnCreateTablesError(Database db, any data, int numQueries, const char[] error, int failIndex, any[] queryData) {
	Kban_GiveError(ERROR_TYPE_CREATE, error);
}

void Kban_RemoveBan(int target, int admin, char[] reason) {
	g_bIsClientRestricted[target] = false;

	if(!reason[0]) {
		FormatEx(reason, REASON_MAX_LENGTH, "Giving another chance");
	}

	if(!IsIPBanned(g_sIPs[target])) {
		return;
	}

	char adminName[MAX_NAME_LENGTH], adminSteamID[MAX_AUTHID_LENGTH];
	FormatEx(adminName, sizeof(adminName), admin < 1 ? "Console" : g_sName[admin]);
	FormatEx(adminSteamID, sizeof(adminSteamID), admin < 1 ? "Console" : g_sSteamIDs[admin]);

	char adminNameEscaped[MAX_NAME_LENGTH * 2 + 1], reasonEscaped[REASON_MAX_LENGTH * 2 + 1];
	if(!g_hDB.Escape(adminName, adminNameEscaped, sizeof(adminNameEscaped)) || !g_hDB.Escape(reason, reasonEscaped, sizeof(reasonEscaped))) {
		return;
	}

	Kban info;
	for(int i = 0; i < g_allKbans.Length; i++) {
		g_allKbans.GetArray(i, info, sizeof(info));
		if(strcmp(info.clientIP, g_sIPs[target], false) == 0 || (strcmp(g_sSteamIDs[target], NOSTEAMID, false) != 0 && strcmp(info.clientSteamID, g_sSteamIDs[target], false) == 0)) {
			g_allKbans.Erase(i);
			break;
		}
	}

	char query[MAX_QUERIE_LENGTH];
	g_hDB.Format(query, sizeof(query), 		"UPDATE `KbRestrict_CurrentBans` SET `is_expired`=1, `is_removed`=1,"
										... "`admin_name_removed`='%s', `admin_steamid_removed`='%s',"
										... "`time_stamp_removed`=%d, `reason_removed`='%s' WHERE `id`=%d",
											adminNameEscaped, adminSteamID,
											GetTime(), reasonEscaped, info.id);
	g_hDB.Query(OnKbanRemove, query);

	Kban_PublishKunban(target, admin, reason);

	Call_StartForward(g_hKunbanForward);
	Call_PushCell(target);
	Call_PushCell(admin);
	Call_PushString(reason);
	Call_PushCell(g_iClientKbansNumber[target]);
	Call_Finish();
}

void Kban_PublishKunban(int target, int admin, const char[] reason) {
	CPrintToChatAll("%t", "UnRestricted", admin, target, KR_Tag, reason);
	LogAction(admin, target, "[Kb-Restrict] \"%L\" has Kb-UnRestricted \"%L\". \nReason: %s", admin, target, reason);

	if(g_hDB == null) {
		return;
	}

	char adminSteamID[MAX_AUTHID_LENGTH], targetName[MAX_NAME_LENGTH], adminName[MAX_NAME_LENGTH];
	FormatEx(adminSteamID, sizeof(adminSteamID), admin < 1 ? "Console" : g_sSteamIDs[admin]);
	FormatEx(adminName, sizeof(adminName), admin < 1 ? "Console" : g_sName[admin]);
	FormatEx(targetName, sizeof(targetName), g_sName[target]);

	char targetNameEscaped[MAX_NAME_LENGTH * 2 + 1], adminNameEscaped[MAX_NAME_LENGTH * 2 + 1], reasonEscaped[REASON_MAX_LENGTH * 2 + 1];

	if(!g_hDB.Escape(targetName, targetNameEscaped, sizeof(targetNameEscaped))
		|| !g_hDB.Escape(adminName, adminNameEscaped, sizeof(adminNameEscaped))
		|| !g_hDB.Escape(reason, reasonEscaped, sizeof(reasonEscaped))) {
		return;
	}

	char query[MAX_QUERIE_LENGTH];
	g_hDB.Format(query, sizeof(query), 	"INSERT INTO `KbRestrict_srvlogs` ("
									... "`client_name`, `client_steamid`,"
									... "`admin_name`, `admin_steamid`,"
									... "`message`, `time_stamp`)"
									... "VALUES ('%s', '%s', '%s', '%s', '%s', '%d')",
										targetNameEscaped, g_sSteamIDs[target],
										adminName, adminSteamID,
										"Removed Kban", GetTime());
	g_hDB.Query(OnKbanRemove, query);
}

void OnKbanRemove(Database db, DBResultSet results, const char[] error, any data) {
	if(!IsDBConnected() || results == null || error[0]) {
		Kban_GiveError(ERROR_TYPE_UPDATE, error);
		return;
	}
}

void Kban_AddBan(int target, int admin, int length, char[] reason) {
	Kban info;
	if(length < 0) {
		length = -1;
	}

	if(!reason[0]) {
		FormatEx(reason, REASON_MAX_LENGTH, "Trying To Boost");
	}

	FormatEx(info.clientName, sizeof(info.clientName), g_sName[target]);
	FormatEx(info.adminName, sizeof(info.adminName), (admin < 1) ? "Console" : g_sName[admin]);
	FormatEx(info.clientSteamID, sizeof(info.clientSteamID), g_sSteamIDs[target]);
	FormatEx(info.adminSteamID, sizeof(info.adminSteamID), (admin < 1) ? "Console" : g_sSteamIDs[admin]);
	FormatEx(info.clientIP, sizeof(info.clientIP), g_sIPs[target]);

	if((strcmp(info.clientSteamID, NOSTEAMID, false) != 0 && IsSteamIDBanned(info.clientSteamID)) || IsIPBanned(info.clientIP)) {
		CReplyToCommand(admin, "%t", "AlreadyKBanned");
		return;
	}

	FormatEx(info.map, sizeof(info.map), g_sMapName);
	FormatEx(info.reason, sizeof(info.reason), reason);
	info.length = length;
	info.time_stamp_start = GetTime();

	if(length > 0) {
		info.time_stamp_end = (GetTime() + (length * 60)); // Duration in minutes
	} else if(length == 0) {
		info.time_stamp_end = 0; // Permanent
	} else {
		info.time_stamp_end = -1; // Session
	}

	// for editing id purpose
	int arrayIndex = g_allKbans.PushArray(info, sizeof(info));

	char escapedTargetName[MAX_NAME_LENGTH * 2 + 1], escapedAdminName[MAX_NAME_LENGTH * 2 + 1], escapedReason[REASON_MAX_LENGTH * 2 + 1];
	
	if(!g_hDB.Escape(info.clientName, escapedTargetName, sizeof(escapedTargetName))
		|| !g_hDB.Escape(info.adminName, escapedAdminName, sizeof(escapedAdminName))
		|| !g_hDB.Escape(info.reason, escapedReason, sizeof(escapedReason))) {
			return;
	}

	char query[MAX_QUERIE_LENGTH];
	g_hDB.Format(query, sizeof(query), 		"INSERT INTO `KbRestrict_CurrentBans` ("
										... "`client_name`, `client_steamid`, `client_ip`,"
										... "`admin_name`, `admin_steamid`, `reason`,"
										... "`map`, `length`, `time_stamp_start`,"
										... "`time_stamp_end`, `is_expired`, `is_removed`,"
										... "`admin_name_removed`, `admin_steamid_removed`, `time_stamp_removed`,"
										... "`reason_removed`)"
										... "VALUES ('%s', '%s', '%s', '%s', '%s', '%s', '%s',"
										... "'%d', '%d', '%d', '%d', '%d', '%s', '%s', '%d', '%s')",
										escapedTargetName, info.clientSteamID, info.clientIP,
										escapedAdminName, info.adminSteamID, escapedReason,
										info.map, info.length, info.time_stamp_start,
										info.time_stamp_end, 0, 0,
										"null", "null", 0, "null");

	if (!g_bSaveTempBans && length != -1)
		g_hDB.Query(OnKbanAdded, query, arrayIndex);
	else if (g_bSaveTempBans)
		g_hDB.Query(OnKbanAdded, query, arrayIndex);

	g_bIsClientRestricted[target] = true;
	g_iClientKbansNumber[target]++;

	PublishKban(info, admin, target, reason);

	Call_StartForward(g_hKbanForward);
	Call_PushCell(target);
	Call_PushCell(admin);
	Call_PushCell(length);
	Call_PushString(reason);
	Call_PushCell(g_iClientKbansNumber[target]);
	Call_Finish();
}

void PublishKban(Kban info, int admin, int target = -1, const char[] reason) {
	char message[REASON_MAX_LENGTH];

	switch(info.length) {
		case 0: {
			if(target != -1) {
				CPrintToChatAll("%t", "RestrictedPerma", admin, target, KR_Tag, reason);
				LogAction(admin, target, "\"%L\" has Kb-Restricted \"%L\" Permanently. \nReason: %s", admin, target, reason);
			} else {
				CPrintToChatAll("%t", "RestrictedPermaOffline", admin, info.clientName, KR_Tag, reason);
				LogAction(admin, -1, "\"%L\" has Offline Kb-Restricted \"%s\" Permanently. \nReason: %s", admin, info.clientName, reason);
			}

			FormatEx(message, sizeof(message), "Kban Added (Permanent)");
		}

		case -1: {
			if(target != -1) {
				CPrintToChatAll("%t", "RestrictedTemp", admin, target, KR_Tag, reason);
				LogAction(admin, target, "\"%L\" has Kb-Restricted \"%L\" Temporarily. \nReason: %s", admin, target, reason);
			} else {
				CPrintToChatAll("%t", "RestrictedTempOffline", admin, info.clientName, KR_Tag, reason);
				LogAction(admin, -1, "\"%L\" has Offline Kb-Restricted \"%s\" Temporarily. \nReason: %s", admin, info.clientName, reason);
			}

			FormatEx(message, sizeof(message), "Kban Added (Session)");
		}

		default: {
			if(target != -1) {
				CPrintToChatAll("%t", "Restricted", admin, target, info.length, KR_Tag, reason);
				LogAction(admin, target, "\"%L\" has Kb-Restricted \"%L\" for \"%d\" minutes. \nReason: %s", admin, target, info.length, reason);
			} else {
				CPrintToChatAll("%t", "RestrictedOffline", admin, info.clientName, info.length, KR_Tag, reason);
				LogAction(admin, -1, "\"%L\" has Offline Kb-Restricted \"%s\" for %d minutes. \nReason: %s", admin, info.clientName, info.length, reason);
			}

			FormatEx(message, sizeof(message), "Kban Added (%d Minutes - %s)", info.length, reason);
		}
	}

	char targetNameEscaped[MAX_NAME_LENGTH * 2 + 1], adminNameEscaped[MAX_NAME_LENGTH * 2 + 1], reasonEscaped[REASON_MAX_LENGTH * 2 + 1];
	if(!g_hDB.Escape(info.clientName, targetNameEscaped, sizeof(targetNameEscaped))
		|| !g_hDB.Escape(info.adminName, adminNameEscaped, sizeof(adminNameEscaped))
		|| !g_hDB.Escape(reason, reasonEscaped, sizeof(reasonEscaped))) {
			LogError("[Kb-Restrict] Couldn't escape the message.");
			return;
	}

	// -1 because the index was increase due to PushArray.
	int arrayIndex = (g_allKbans.Length - 1);

	char query[MAX_QUERIE_LENGTH];
	g_hDB.Format(query, sizeof(query), 	"INSERT INTO `KbRestrict_srvlogs` ("
									... "`client_name`, `client_steamid`,"
									... "`admin_name`, `admin_steamid`,"
									... "`message`, `time_stamp`)"
									... "VALUES ('%s', '%s', '%s', '%s', '%s', '%d')",
										targetNameEscaped, info.clientSteamID,
										adminNameEscaped, info.adminSteamID,
										message, GetTime());

	g_hDB.Query(OnKbanPublished, query, arrayIndex);
}

void OnKbanPublished(Database db, DBResultSet results, const char[] error, int arrayIndex) {
	if (arrayIndex < 0 || arrayIndex >= g_allKbans.Length) {
		LogError("Invalid arrayIndex %d. g_allKbans has length %d.", arrayIndex, g_allKbans.Length);
	}

	if(!IsDBConnected() || results == null || error[0]) {
		Kban_GiveError(ERROR_TYPE_INSERT, error);
	}
}

void OnKbanAdded(Database db, DBResultSet results, const char[] error, int arrayIndex) {
	if(!IsDBConnected() || results == null || error[0]) {
		Kban_GiveError(ERROR_TYPE_INSERT, error);
		return;
	}

	Kban info;
	// g_allKbans.GetArray(arrayIndex, info, sizeof(info));
	if (!g_allKbans.GetArray(arrayIndex, info, sizeof(info))) {
		LogError("Failed to retrieve element at index %d from g_allKbans.", arrayIndex);
		return;
	}

	char query[MAX_QUERIE_LENGTH];
	g_hDB.Format(query, sizeof(query), 		"SELECT `id` FROM `KbRestrict_CurrentBans` WHERE"
										... "`client_steamid`='%s' AND `client_ip`='%s' AND `is_expired`=0 AND `is_removed`=0",
										info.clientSteamID, info.clientIP);

	g_hDB.Query(OnGetKbanID, query, arrayIndex);
}

int Kban_CheckKbanAdminAccess(int client, int time) {
	bool hasRootFlag	= (CheckCommandAccess(client, "sm_root", ADMFLAG_ROOT, true));
	if(hasRootFlag)
		return 0;

	bool hasKickFlag 	= (CheckCommandAccess(client, "sm_kick", ADMFLAG_KICK, true));
	bool hasBanFlag 	= (CheckCommandAccess(client, "sm_ban", ADMFLAG_BAN, true));
	bool hasRconFlag 	= (CheckCommandAccess(client, "sm_rcon", ADMFLAG_RCON, true));

	ConVar cvar;
	if(hasKickFlag && !hasBanFlag && !hasRconFlag)
		cvar = g_cvMaxBanTimeKickFlag;
	else if(hasBanFlag && !hasRconFlag)
		cvar = g_cvMaxBanTimeBanFlag;
	else if(hasRconFlag)
		cvar = g_cvMaxBanTimeRconFlag;

	if(cvar == null) // Should never happen
		return g_iDefaultLength;

	if(time < 0 || time > cvar.IntValue)
		time = cvar.IntValue;

	return time;
}

void OnGetKbanID(Database db, DBResultSet results, const char[] error, int arrayIndex) {
	if(!IsDBConnected() || results == null || error[0]) {
		Kban_GiveError(ERROR_TYPE_SELECT, error);
		return;
	}

	Kban info;
	g_allKbans.GetArray(arrayIndex, info, sizeof(info));

	if(results.FetchRow()) {
		info.id = results.FetchInt(0);
	}

	g_allKbans.SetArray(arrayIndex, info, sizeof(info));
}

bool Kban_GetKban(KbanGetType type, Kban info, int id = -1, const char[] steamID = "", const char[] ip = "") {
	for(int i = 0; i < g_allKbans.Length; i++) {
		Kban exInfo;
		g_allKbans.GetArray(i, exInfo, sizeof(exInfo));
		if(type == KBAN_GET_TYPE_ID) {
			if(id != -1 && exInfo.id == id) {
				CloneKban(info, exInfo);
				return true;
			}
		} else if(type == KBAN_GET_TYPE_STEAMID) {
			if(steamID[0] && (strcmp(steamID, exInfo.clientSteamID, false) == 0)) {
				CloneKban(info, exInfo);
				return true;
			}
		} else {
			if(ip[0] && (strcmp(ip, exInfo.clientIP, false) == 0)) {
				CloneKban(info, exInfo);
				return true;
			}
		}
	}

	return false;
}

void CloneKban(Kban info, Kban exInfo) {
	FormatEx(info.clientName, sizeof(info.clientName), exInfo.clientName);
	FormatEx(info.clientSteamID, sizeof(info.clientSteamID), exInfo.clientSteamID);
	FormatEx(info.clientIP, sizeof(info.clientIP), exInfo.clientIP);
	FormatEx(info.adminName, sizeof(info.adminName), exInfo.adminName);
	FormatEx(info.adminSteamID, sizeof(info.adminSteamID), exInfo.adminSteamID);
	FormatEx(info.map, sizeof(info.map), exInfo.map);
	FormatEx(info.reason, sizeof(info.reason), exInfo.reason);

	info.length = exInfo.length;
	info.time_stamp_start = exInfo.time_stamp_start;
	info.time_stamp_end = exInfo.time_stamp_end;
	info.id = exInfo.id;
}

int Kban_GetClientByIP(const char[] sIP) {
	for(int i = 1; i <= MaxClients; i++) {
		if(!IsClientInGame(i) || IsFakeClient(i) || IsClientSourceTV(i)) {
			continue;
		}

		if(strcmp(g_sIPs[i], sIP, false) == 0) {
			return i;
		}
	}

	return -1;
}

int Kban_GetClientBySteamID(const char[] sSteamID) {
	for(int i = 1; i <= MaxClients; i++) {
		if(!IsClientInGame(i) || IsFakeClient(i) || IsClientSourceTV(i)) {
			continue;
		}

		if(strcmp(g_sSteamIDs[i], sSteamID, false) == 0) {
			return i;
		}
	}

	return -1;
}

bool IsIPBanned(const char[] ip) {
	if(g_allKbans == null) {
		return false;
	}

	for(int i = 0; i < g_allKbans.Length; i++) {
		Kban info;
		g_allKbans.GetArray(i, info, sizeof(info));
		if(strcmp(info.clientIP, ip, false) == 0) {
			return true;
		}
	}

	return false;
}

bool IsSteamIDBanned(const char[] steamID) {
	if(g_allKbans == null) {
		return false;
	}

	for(int i = 0; i < g_allKbans.Length; i++) {
		Kban info;
		g_allKbans.GetArray(i, info, sizeof(info));
		if(strcmp(info.clientSteamID, steamID, false) == 0) {
			return true;
		}
	}

	return false;
}

KbanType Kban_GetClientKbanType(int client, char[] steamID = "", char[] ip = "") {
	if(client != -1) {
		if(IsSteamIDBanned(g_sSteamIDs[client])) {
			return KBAN_TYPE_STEAMID;
		}

		if(IsIPBanned(g_sIPs[client])) {
			return KBAN_TYPE_IP;
		}
	} else {
		if(ip[0] && IsIPBanned(ip)) {
			return KBAN_TYPE_IP;
		}

		if(StrContains(steamID, "STEAM_", false) != -1 && IsSteamIDBanned(steamID)) {
			return KBAN_TYPE_STEAMID;
		}
	}

	return KBAN_TYPE_NOTKBANNED;
}

void Kban_GiveError(ErrorType type, const char[] error) {
	char tag[] = "[Kb-Restrict]";
	char messageStarter[40];
	FormatEx(messageStarter, sizeof(messageStarter), "%s Could not", tag);

	if(type == ERROR_TYPE_SELECT) {
		LogError("%s get data from database\nError: %s", messageStarter, error);
	} else if(type == ERROR_TYPE_UPDATE) {
		LogError("%s update data to database\nError: %s", messageStarter, error);
	} else if(type == ERROR_TYPE_CREATE) {
		LogError("%s create tables for database\nError: %s", messageStarter, error);
	} else {
		LogError("%s insert data to database\nError: %s", messageStarter, error);
	}
}

void Kban_GiveSuccess(SuccessType type) {
	char tag[] = "[Kb-Restrict]";
	char messageStarter[40];
	FormatEx(messageStarter, sizeof(messageStarter), "%s Successfully", tag);

	if(type == SUCCESS_TYPE_SELECT) {
		LogMessage("%s got data from database", messageStarter);
	} else if(type == SUCCESS_TYPE_UPDATE) {
		LogMessage("%s updated data to database", messageStarter);
	} else if(type == SUCCESS_TYPE_CREATE) {
		LogMessage("%s DB is now ready!", tag);
	} else {
		LogMessage("%s inserted data to database", messageStarter);
	}
}

bool IsValidClient(int client) {
	return (1 <= client <= MaxClients && IsClientInGame(client) && !IsClientSourceTV(client));
}

char[] GetTimeString(int timestamp) {
	char buffer[64];
	FormatTime(buffer, sizeof(buffer), "%Y-%m-%d %H:%M:%S", timestamp);
	return buffer;
}
