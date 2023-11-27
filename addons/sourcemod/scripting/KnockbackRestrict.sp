#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <multicolors>
#include <adminmenu>
#include <cstrike>
#include <KnockbackRestrict>

#define KR_Tag "{aqua}[Kb-Restrict]{white}"

GlobalForward g_hKbanForward;
GlobalForward g_hKunbanForward;

TopMenu g_hAdminMenu;

int 
	g_iClientPreviousMenu[MAXPLAYERS + 1] = {0, ...},
	g_iClientTarget[MAXPLAYERS + 1] = {0, ...},
	g_iClientTargetLength[MAXPLAYERS + 1] = {0, ...},
	g_iClientKbansNumber[MAXPLAYERS + 1] = { 0, ... };
	
bool 
	g_bKnifeModeEnabled,
	g_bIsClientRestricted[MAXPLAYERS + 1] = { false, ... },
	g_bIsClientTypingReason[MAXPLAYERS + 1] = { false, ... },
	g_bLate = false;

Database g_hDB;

ArrayList g_allKbans;
ArrayList g_OfflinePlayers;

ConVar	
		g_cvDefaultLength,
		g_cvMaxBanTimeBanFlag,
		g_cvMaxBanTimeKickFlag,
		g_cvMaxBanTimeRconFlag;

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
	char clientName[32];
	char clientSteamID[20];
	char clientIP[20];
	char adminName[32];
	char adminSteamID[20];

	char reason[128];
	char map[120];

	int time_stamp_start;
	int time_stamp_end;
	int length;
}

enum struct OfflinePlayer {
	int userid;
	char name[32];
	char steamID[20];
	char ip[20];
}

public Plugin myinfo = {
	name 		= "KnockbackRestrict",
	author		= "Dolly, Rushaway",
	description = "Adjust knockback of certain weapons for the kbanned players",
	version 	= "3.3.3",
	url			= "https://github.com/srcdslab/sm-plugin-KnockbackRestrict"
};

#include "helpers/menus.sp"

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
	RegConsoleCmd("sm_kbanstatus", Command_CheckKbStatus, "Shows current player Kb-Restrict status");

	/* CVARS */
	g_cvDefaultLength 			= CreateConVar("sm_kbrestrict_length", "30", "Default length when no length is specified");
	g_cvMaxBanTimeBanFlag		= CreateConVar("sm_kbrestrict_max_bantime_banflag", "20160", "Maximum ban time allowed for Ban-Flag accessible admins(0-518400)", _, true, 0.0, true, 518400.0);
	g_cvMaxBanTimeKickFlag		= CreateConVar("sm_kbrestrict_max_bantime_kickflag", "720", "Maximum ban time allowed for Kick-Flag accessible admins(0-518400)", _, true, 0.0, true, 518400.0);
	g_cvMaxBanTimeRconFlag		= CreateConVar("sm_kbrestrict_max_bantime_rconflag", "40320", "Maximum ban time allowed for Rcon-Flag accessible admins(0-518400)", _, true, 0.0, true, 518400.0);

	AutoExecConfig();

	/* CONNECT TO DB */
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
	char reason[128];

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
	char reason[128];

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
	g_allKbans = new ArrayList(ByteCountToCells(512));

	delete g_OfflinePlayers;
	g_OfflinePlayers = new ArrayList(ByteCountToCells(100));

	/* GET ALL KBANS */
	CreateTimer(1.0, GetAllKbans_Timer);

	/* Check all kbans by a timer */
	CreateTimer(2.0, CheckAllKbans_Timer, _, TIMER_FLAG_NO_MAPCHANGE | TIMER_REPEAT);
}

public void OnMapEnd() {
	for(int i = 0; i < g_allKbans.Length; i++) {
		Kban info;
		g_allKbans.GetArray(i, info, sizeof(info));
		if(info.time_stamp_end < 0 || info.length < 0) {
			char query[80];
			g_hDB.Format(query, sizeof(query), "UPDATE `KbRestrict_CurrentBans` SET `is_expired`=1 WHERE `id`=%d", info.id);
			g_hDB.Query(OnKbanRemove, query);
		}
	}
}

public void OnClientPutInServer(int client) {
	SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
}

public void OnClientPostAdminCheck(int client) {
	if(g_allKbans == null) {
		return;
	}

	if(g_OfflinePlayers == null) {
		return;
	}

	if(IsFakeClient(client) || IsClientSourceTV(client)) {
		return;
	}

	char ip[20];
	if(!GetClientIP(client, ip, sizeof(ip))) {
		return;
	}
	
	char steamID[20];
	if(!GetClientAuthId(client, AuthId_Steam2, steamID, sizeof(steamID))) {
		return;
	}
	
	char queryEx[300];
	g_hDB.Format(queryEx, sizeof(queryEx), "SELECT * FROM `KbRestrict_CurrentBans` WHERE `client_steamid`='%s' OR `client_ip`='%s'", steamID, ip);
	g_hDB.Query(OnClientPostAdminCheck_Query, queryEx, GetClientUserId(client));
	
	for(int i = 0; i < g_OfflinePlayers.Length; i++) {
		OfflinePlayer player;
		g_OfflinePlayers.GetArray(i, player, sizeof(player));
		if(StrEqual(player.steamID, steamID)) {
			g_OfflinePlayers.Erase(i);
			break;
		}
	}
	
	/* check if this dude got kbanned with steamid pending, we want to update the steamid */
	for(int i = 0; i < g_allKbans.Length; i++) {
		Kban info;
		g_allKbans.GetArray(i, info, sizeof(info));
		if(StrEqual(info.clientIP, ip)) {
			if(StrEqual(info.clientSteamID, "NO STEAMID", false)) {
				FormatEx(info.clientSteamID, 20, steamID);
				g_allKbans.SetArray(i, info, sizeof(info));

				char query[100];
				g_hDB.Format(query, sizeof(query), "UPDATE `KbRestrict_CurrentBans` SET `client_steamid`='%s' WHERE `id`=%d", steamID, info.id);
				g_hDB.Query(OnKbanAdded, query);
			}

			break;
		}
	}

	/* let's tell how many kbans this dude has */
	Kban_CallGetKbansNumber(client);
}

void OnClientPostAdminCheck_Query(Database db, DBResultSet results, const char[] error, int userid) {
	if(results == null || error[0]) {
		Kban_GiveError(ERROR_TYPE_SELECT, error);
		return;
	}

	int client = GetClientOfUserId(userid);
	if(client < 1) {
		return;
	}

	char steamID[20];
	if(!GetClientAuthId(client, AuthId_Steam2, steamID, sizeof(steamID))) {
		return;
	}

	char clientIP[20];
	if(!GetClientIP(client, clientIP, sizeof(clientIP))) {
		return;
	}

	bool isKbanned = false;
	Kban tempInfo;

	while(results.FetchRow()) {
		bool isExpired = (results.FetchInt(11) == 0) ? false : true;
		bool isRemoved = (results.FetchInt(12) == 0) ? false : true;

		Kban info;
		Kban_GetRowResults(10, results, info);

		if((!isExpired && !isRemoved) || (info.time_stamp_end > GetTime()) && !isRemoved) {
			isKbanned = true;
			for(int i = 0; i <= 10; i++) {
				Kban_GetRowResults(i, results, tempInfo);
			}

			/* Check if ip is not known */
			if(StrEqual(tempInfo.clientIP, "Unknown", false)) {
				/* Update IP to DB */
				char query[120];
				g_hDB.Format(query, sizeof(query), "UPDATE `KbRestrict_CurrentBans` SET `client_ip`='%s' WHERE `id`=%d", clientIP, tempInfo.id);
				g_hDB.Query(OnUpdateClientIP, query);

				FormatEx(tempInfo.clientIP, 20, "%s", clientIP);
				for(int i = 0; i < g_allKbans.Length; i++) {
					Kban exInfo;
					g_allKbans.GetArray(i, exInfo, sizeof(exInfo));
					if(exInfo.id == tempInfo.id) {
						FormatEx(exInfo.clientIP, 20, "%s", tempInfo.clientIP);
						g_allKbans.SetArray(i, exInfo, sizeof(exInfo));
						break;
					}
				}
			}

			break;
		}

		isKbanned = false;
	}
	
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
			if(!Kban_GetKban(KBAN_GET_TYPE_IP, kbanInfo, _, _, clientIP)) {
				return;
			}
		} else {
			if(!Kban_GetKban(KBAN_GET_TYPE_STEAMID, kbanInfo, _, steamID)) {
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
	if(results == null || error[0]) {
		Kban_GiveError(ERROR_TYPE_UPDATE, error);
		return;
	}
}

void Kban_CallGetKbansNumber(int client) {
	char steamID[20];
	if(!GetClientAuthId(client, AuthId_Steam2, steamID, sizeof(steamID))) {
		return;
	}

	char query[150];
	g_hDB.Format(query, sizeof(query), "SELECT * FROM `KbRestrict_CurrentBans` WHERE `client_steamid`='%s'", steamID);
	g_hDB.Query(OnGetKbansNumber, query, GetClientUserId(client));
}

void OnGetKbansNumber(Database db, DBResultSet results, const char[] error, int userid) {
	if(results == null || error[0]) {
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

	for(int i = 1; i <= MaxClients; i++) {
		if(!IsClientInGame(i)) {
			continue;
		}

		if(CheckCommandAccess(i, "sm_admin", ADMFLAG_BAN, true)) {
			CPrintToChat(i, "%t", "PlayerConnect", client, count);
		}
	}

	g_iClientKbansNumber[client] = count;
}

public void OnClientConnected(int client) {
	if(IsFakeClient(client) || IsClientSourceTV(client)) {
		return;
	}

	if(g_bIsClientRestricted[client]) {
		return;
	}

	char ip[20];
	if(!GetClientIP(client, ip, sizeof(ip))) {
		return;
	}

	if(g_allKbans == null) {
		return;
	}

	if(!IsIPBanned(ip)) {
		return;
	}

	g_bIsClientRestricted[client] = true;
}

public void OnClientDisconnect(int client) {
	if(IsFakeClient(client) || IsClientSourceTV(client)) {
		return;
	}

	g_bIsClientRestricted[client] = false;
	g_iClientKbansNumber[client] = 0;

	char steamID[20];
	if(!GetClientAuthId(client, AuthId_Steam2, steamID, sizeof(steamID))) {
		return;
	}

	char name[32];
	if(!GetClientName(client, name, sizeof(name))) {
		return;
	}

	char ip[20];
	if(!GetClientIP(client, ip, sizeof(ip))) {
		return;
	}

	OfflinePlayer player;
	player.userid = GetClientUserId(client);
	FormatEx(player.steamID, sizeof(OfflinePlayer::steamID), steamID);
	FormatEx(player.ip, sizeof(OfflinePlayer::ip), ip);
	FormatEx(player.name, sizeof(OfflinePlayer::name), name);

	g_OfflinePlayers.PushArray(player, sizeof(player));
}

public void OnLibraryAdded(const char[] name) {
	if(StrEqual(name, "KnifeMode")) {
		g_bKnifeModeEnabled = true;
	}
}

public void OnLibraryRemoved(const char[] name) {
	if(StrEqual(name, "KnifeMode")) {
		g_bKnifeModeEnabled = false;
	}

	if(StrEqual(name, "adminmenu")) {
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
			damage -= (damage * 0.98);
		else
			damage -= (damage * 0.83);
	}

	/* Pistols */
	if (strcmp(sWeapon, "weapon_deagle", false) == 0)
		damage -= (damage * 0.50);

	/* SMG's */
	if ((strcmp(sWeapon, "weapon_mac10", false) == 0) || (strcmp(sWeapon, "weapon_tmp", false) == 0) || (strcmp(sWeapon, "weapon_mp5navy", false) == 0)
		|| (strcmp(sWeapon, "weapon_ump45", false) == 0) || (strcmp(sWeapon, "weapon_p90", false) == 0))
		damage -= (damage * 0.30);

	/* Rifles */
	if ((strcmp(sWeapon, "weapon_galil", false) == 0) || (strcmp(sWeapon, "weapon_famas", false) == 0) || (strcmp(sWeapon, "weapon_ak47", false) == 0)
		|| (strcmp(sWeapon, "weapon_m4a1", false) == 0) || (strcmp(sWeapon, "weapon_sg552", false) == 0) || (strcmp(sWeapon, "weapon_aug", false) == 0)
		|| (strcmp(sWeapon, "weapon_m249", false) == 0))
		damage -= (damage * 0.50);

	/* ShotGuns */
	if ((strcmp(sWeapon, "weapon_m3", false) == 0) || (strcmp(sWeapon, "weapon_xm1014", false) == 0))
		damage -= (damage * 0.85);

	/* Snipers */
	if ((strcmp(sWeapon, "weapon_awp", false) == 0) || (strcmp(sWeapon, "weapon_scout", false) == 0))
		damage -= (damage * 0.80);

	/* Semi-Auto Snipers */
	if ((strcmp(sWeapon, "weapon_sg550", false) == 0) || (strcmp(sWeapon, "weapon_g3sg1", false) == 0))
		damage -= (damage * 0.70);
	
	/* Grenades */
	if (strcmp(sWeapon, "weapon_hegrenade", false) == 0)
		damage -= (damage * 0.95);

	return Plugin_Changed;
}

Action CheckAllKbans_Timer(Handle timer) {
	if(g_allKbans == null || !g_allKbans.Length) {
		return Plugin_Handled;
	}

	for(int i = 0; i < g_allKbans.Length; i++) {
		Kban info;
		g_allKbans.GetArray(i, info, sizeof(info));
		if(info.time_stamp_end > 0 && info.time_stamp_end < GetTime()) {
			/* We want to unban this dude, check if the player is in game first by either steamid or ip */
			char query[100];
			g_hDB.Format(query, sizeof(query), "SELECT `time_stamp_end` FROM `KbRestrict_CurrentBans` WHERE `id`=%d", info.id);
			g_hDB.Query(OnKbanExpired, query, info.id);
		}
	}

	return Plugin_Continue;
}

void OnKbanExpired(Database db, DBResultSet results, const char[] error, int id) {
	if(results == null || error[0]) {
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
			char query[100];
			g_hDB.Format(query, sizeof(query), "UPDATE `KbRestrict_CurrentBans` SET `is_expired`=1 WHERE `id`=%d", info.id);
			g_hDB.Query(OnKbanRemove, query);

			for(int i = 0; i < g_allKbans.Length; i++) {
				Kban exInfo;
				g_allKbans.GetArray(i, exInfo, sizeof(exInfo));
				if(exInfo.id == info.id) {
					g_allKbans.Erase(i);
				}
			}

			if(StrEqual(info.clientSteamID, "NO STEAMID")) {
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
		time = g_cvDefaultLength.IntValue;
	}

	char reason[128];
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
			time = g_cvDefaultLength.IntValue;
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

	char reason[128];
	FormatEx(reason, sizeof(reason), Arguments[len]);

	char adminSteamID[20];
	if(!client) {
		adminSteamID = "Console";
	} else {
		if(!GetClientAuthId(client, AuthId_Steam2, adminSteamID, sizeof(adminSteamID))) {
			return Plugin_Handled;
		}
	}

	Kban info;

	KbanType type = Kban_GetClientKbanType(target);
	if(type == KBAN_TYPE_STEAMID) {
		char targetSteamID[20];
		if(GetClientAuthId(target, AuthId_Steam2, targetSteamID, sizeof(targetSteamID))) {
			Kban_GetKban(KBAN_GET_TYPE_STEAMID, info, _, targetSteamID);
		}
	} else {
		char ip[20];
		if(!GetClientIP(target, ip, sizeof(ip))) {
			return Plugin_Handled;
		}
		
		Kban_GetKban(KBAN_GET_TYPE_IP, info, _, _, ip);
	}

	bool canUnban = false;
	if(StrEqual(adminSteamID, "Console") || CheckCommandAccess(client, "sm_admin", ADMFLAG_RCON, true)) {
		canUnban = true;
	}

	if(!canUnban && StrEqual(info.adminSteamID, adminSteamID)) {
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
		time = g_cvDefaultLength.IntValue;
	}

	char reason[128];
	FormatEx(reason, sizeof(reason), Arguments[len]);
	
	/* Check if admin has access to perma ban or a long ban */
	if(client > 0 && !CheckCommandAccess(client, "sm_admin", ADMFLAG_ROOT, true)) {
		if(time == 0) {
			time = g_cvDefaultLength.IntValue;
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
		if(StrEqual(info.clientSteamID, player.steamID) || StrEqual(info.clientIP, player.ip)) {
			CReplyToCommand(client, "%t", "AlreadyKBanned");
			return Plugin_Handled;
		}
	}
	
	Kban_AddOfflineBan(player, client, time, reason);
	return Plugin_Handled;
}

void Kban_AddOfflineBan(OfflinePlayer player, int admin, int length, char[] reason) {
	if(!reason[0]) {
		FormatEx(reason, 128, "Trying To Boost");
	}

	char steamID[20];
	char adminName[32];
	if(admin < 1) {
		steamID = "Console";
		adminName = "Console";
	} else {
		if(!GetClientAuthId(admin, AuthId_Steam2, steamID, sizeof(steamID))) {
			return;
		}

		if(!GetClientName(admin, adminName, sizeof(adminName))) {
			return;
		}
	}

	Kban info;
	info.length = length;
	info.time_stamp_start = GetTime();
	
	if(length > 0) {
		/* Normal */
		info.time_stamp_end = (GetTime() + (length * 60));
	} else if(length == 0) {
		/* Permanent */
		info.time_stamp_end = 0;
	} else {
		/* Session */
		info.time_stamp_end = -1;
	}

	FormatEx(info.clientName, 32, player.name);
	FormatEx(info.clientSteamID, 20, player.steamID);
	FormatEx(info.clientIP, 20, player.ip);
	FormatEx(info.adminName, 32, adminName);
	FormatEx(info.adminSteamID, 20, steamID);
	FormatEx(info.reason, 128, reason);

	if(!GetCurrentMap(info.map, 120)) {
		return;
	}

	int arrayIndex = g_allKbans.Length;
	g_allKbans.PushArray(info, sizeof(info));
	
	char escapedTargetName[32 * 2 + 1];
	char escapedAdminName[32 * 2 + 1];
	char escapedReason[128 * 2 + 1];
	if(!g_hDB.Escape(adminName, escapedAdminName, sizeof(escapedAdminName))) {
		return;
	}

	if(!g_hDB.Escape(player.name, escapedTargetName, sizeof(escapedTargetName))) {
		return;
	}

	if(!g_hDB.Escape(reason, escapedReason, sizeof(escapedReason))) {
		return;
	}

	char query[2000];
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
	if(!client) {
		return Plugin_Handled;
	}

	if(!g_bIsClientRestricted[client]) {
		CReplyToCommand(client, "%t", "PlayerNotRestricted");
		return Plugin_Handled;
	}

	Kban info;
	char steamID[20];

	KbanType type = Kban_GetClientKbanType(client);
	if(type == KBAN_TYPE_STEAMID) {
		if(GetClientAuthId(client, AuthId_Steam2, steamID, sizeof(steamID))) {
			Kban_GetKban(KBAN_GET_TYPE_STEAMID, info, _, steamID);
		}
	} else {
		char ip[20];
		if(GetClientIP(client, ip, sizeof(ip))) {
			Kban_GetKban(KBAN_GET_TYPE_IP, info, _, _, ip);
		}
	}

	switch(info.length) {
		case 0: {
			CReplyToCommand(client, "%t\n%s Reason: {olive}%s.", "PlayerRestrictedPerma", KR_Tag, info.reason);
			return Plugin_Handled;
		}

		case -1: {
			CReplyToCommand(client, "%t\n%s Reason: {olive}%s.", "PlayerRestrcitedTemp", KR_Tag, info.reason);
			return Plugin_Handled;
		}

		default: {
			int timeLeft = (info.time_stamp_end - GetTime());
			char sTimeLeft[32];
			CheckPlayerExpireTime(timeLeft, sTimeLeft, sizeof(sTimeLeft));
			CReplyToCommand(client, "%t\n%s Reason: {olive}%s.", "RestrictTimeLeft", sTimeLeft, KR_Tag, info.reason);
			return Plugin_Handled;
		}
	}
}

stock void CheckPlayerExpireTime(int lefttime, char[] TimeLeft, int maxlength)
{
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
Action GetAllKbans_Timer(Handle timer) {
	if(g_hDB == null) {
		CreateTimer(1.0, GetAllKbans_Timer);
		return Plugin_Stop;
	}

	g_hDB.Query(OnGetAllKbans, "SELECT * FROM `KbRestrict_CurrentBans`");
	return Plugin_Continue;
}

void OnGetAllKbans(Database db, DBResultSet results, const char[] error, any data) {
	if(results == null || error[0]) {
		Kban_GiveError(ERROR_TYPE_SELECT, error);
		return;
	}

	while(results.FetchRow()) {
		bool push = false;
			
		bool isExpired = (results.FetchInt(11) == 0) ? false : true;
		bool isRemoved = (results.FetchInt(12) == 0) ? false : true;

		if(!isExpired && !isRemoved) {
			push = true;
		}

		if(push) {		
			Kban info;
			for(int i = 0; i <= 10; i++) {
				Kban_GetRowResults(i, results, info);
			}

			g_allKbans.PushArray(info, sizeof(info));
		}
 	}

 	/* incase of a late load */
 	if(g_bLate) {
	 	for(int i = 1; i <= MaxClients; i++) {
			if(!IsClientInGame(i)) {
				continue;
			}

			OnClientConnected(i);
			OnClientPostAdminCheck(i);
		}
	}
}

void Kban_GetRowResults(int num, DBResultSet results, Kban info) {
	switch(num) {
		case 0: {
			info.id = results.FetchInt(num);
		}

		case 1: {
			results.FetchString(num, info.clientName, 32);
		}

		case 2: {
			results.FetchString(num, info.clientSteamID, 20);
		}

		case 3: {
			results.FetchString(num, info.clientIP, 20);
		}

		case 4: {
			results.FetchString(num, info.adminName, 32);
		}

		case 5: {
			results.FetchString(num, info.adminSteamID, 20);
		}

		case 6: {
			results.FetchString(num, info.reason, 128);
		}

		case 7: {
			results.FetchString(num, info.map, 120);
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
		CreateTimer(15.0, DB_RetryConnection);
		LogError("[Kb-Restrict] Couldn't connect to database `KbRestrict`, retrying in %15 seconds. \nError: %s", error);

		return;
	}

	LogMessage("[Kb-Restrict] Successfully connected to database!");
	g_hDB = db;
	g_hDB.SetCharset("utf8");
	DB_CreateTables();
}

//----------------------------------------------------------------------------------------------------
// Database Attempting Reconnect :
//----------------------------------------------------------------------------------------------------
Action DB_RetryConnection(Handle timer)
{
    if(g_hDB == null)
        ConnectToDB();
    
    return Plugin_Continue;
}

void DB_CreateTables() {
	if(g_hDB == null) {
		return;
	}

	char driver[10];
	g_hDB.Driver.GetIdentifier(driver, sizeof(driver));
	if(!StrEqual(driver, "mysql")) {
		LogError("[Kb-Restrict] drivers other than mysql are not supported.");
		return;
	}

	char query[1024];
	Transaction T_Tables = SQL_CreateTransaction();

	g_hDB.Format(query, sizeof(query), "  CREATE TABLE IF NOT EXISTS `KbRestrict_CurrentBans` ( \
										  `id` int(11) unsigned NOT NULL AUTO_INCREMENT, \
										  `client_name` varchar(64) NOT NULL, \
										  `client_steamid` varchar(32) NOT NULL, \
										  `client_ip` varchar(32) NOT NULL, \
										  `admin_name` varchar(64) NOT NULL, \
										  `admin_steamid` varchar(32) NOT NULL, \
										  `reason` varchar(128) NOT NULL, \
										  `map` varchar(128) NOT NULL, \
										  `length` int(11) NOT NULL, \
										  `time_stamp_start` int(11) NOT NULL, \
										  `time_stamp_end` int(11) NOT NULL, \
										  `is_expired` int(11) NOT NULL, \
										  `is_removed` int(11) NOT NULL, \
										  `time_stamp_removed` int(20) NOT NULL, \
										  `admin_name_removed` varchar(32) NOT NULL, \
										  `admin_steamid_removed` varchar(20) NOT NULL, \
										  `reason_removed` varchar(128) NOT NULL, \
										  PRIMARY KEY(`id`))");
 
	T_Tables.AddQuery(query);

	g_hDB.Format(query, sizeof(query),    "CREATE TABLE IF NOT EXISTS `KbRestrict_srvlogs` ( \
										  `id` int(10) unsigned NOT NULL AUTO_INCREMENT, \
										  `message` varchar(200) NOT NULL, \
										  `admin_name` varchar(32) NOT NULL, \
										  `admin_steamid` varchar(20) NOT NULL, \
										  `client_name` varchar(32) NOT NULL, \
										  `client_steamid` varchar(20) NOT NULL, \
										  `time_stamp` int(20) NOT NULL, \
										  PRIMARY KEY(`id`))");
		  
	T_Tables.AddQuery(query);

	g_hDB.Format(query, sizeof(query),    "CREATE TABLE IF NOT EXISTS `KbRestrict_weblogs` ( \
										  `id` int(10) unsigned NOT NULL AUTO_INCREMENT, \
										  `message` varchar(200) NOT NULL, \
										  `admin_name` varchar(32) NOT NULL, \
										  `admin_steamid` varchar(20) NOT NULL, \
										  `client_name` varchar(32) NOT NULL, \
										  `client_steamid` varchar(20) NOT NULL, \
										  `time_stamp` int(20) NOT NULL, \
										  PRIMARY KEY(`id`))");

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
		FormatEx(reason, 128, "Giving another chance");
	}

	char ip[20];
	if(!GetClientIP(target, ip, sizeof(ip))) {
		return;
	}

	if(!IsIPBanned(ip)) {
		return;
	}

	char adminName[32];
	if(admin < 1) {
		adminName = "Console";	
	} else {
		if(!GetClientName(admin, adminName, sizeof(adminName))) {
			return;
		}
	}

	char adminSteamID[20];
	if(admin < 1) {
		adminSteamID = "Console";
	} else {
		if(!GetClientAuthId(admin, AuthId_Steam2, adminSteamID, sizeof(adminSteamID))) {
			return;
		}
	}

	char adminNameEscaped[2 * 32 + 1];
	if(!g_hDB.Escape(adminName, adminNameEscaped, sizeof(adminNameEscaped))) {
		return;
	}

	char reasonEscaped[2 * 128 + 1];
	if(!g_hDB.Escape(reason, reasonEscaped, sizeof(reasonEscaped))) {
		return;
	}

	char targetSteamID[20];
	if(!GetClientAuthId(target, AuthId_Steam2, targetSteamID, sizeof(targetSteamID))) {
		strcopy(targetSteamID, sizeof(targetSteamID), "NO STEAMID");
	}

	Kban info;
	for(int i = 0; i < g_allKbans.Length; i++) {
		g_allKbans.GetArray(i, info, sizeof(info));
		if(StrEqual(info.clientIP, ip) || (!StrEqual(targetSteamID, "NO STEAMID", false) && StrEqual(info.clientSteamID, targetSteamID))) {
			g_allKbans.Erase(i);
			break;
		}
	}

	char query[1024];
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

	char adminName[32];
	if(admin < 1) {
		adminName = "Console";
	}
	else {
		if(!GetClientName(admin, adminName, sizeof(adminName))) {
			return;
		}
	}

	char targetName[32];
	if(!GetClientName(target, targetName, sizeof(targetName))) {
		return;
	}

	char targetSteamID[20];
	if(!GetClientAuthId(target, AuthId_Steam2, targetSteamID, sizeof(targetSteamID))) {
		strcopy(targetSteamID, sizeof(targetSteamID), "NO STEAMID");
	}

	char adminSteamID[20];
	if(admin < 1) {
		adminSteamID = "Console";
	} else {
		if(!GetClientAuthId(admin, AuthId_Steam2, adminSteamID, sizeof(adminSteamID))) {
			return;
		}
	} 

	char targetNameEscaped[32 * 2 + 1];
	char adminNameEscaped[32 * 2 + 1];
	char reasonEscaped[128 * 2 + 1];

	if(!g_hDB.Escape(targetName, targetNameEscaped, sizeof(targetNameEscaped))) {
		return;
	}

	if(!g_hDB.Escape(adminName, adminNameEscaped, sizeof(adminNameEscaped))) {
		return;
	}

	if(!g_hDB.Escape(reason, reasonEscaped, sizeof(reasonEscaped))) {
		return;
	}

	char query[1024];
	g_hDB.Format(query, sizeof(query), 	"INSERT INTO `KbRestrict_srvlogs` ("
									... "`client_name`, `client_steamid`,"
									... "`admin_name`, `admin_steamid`,"
									... "`message`, `time_stamp`)"
									... "VALUES ('%s', '%s', '%s', '%s', '%s', '%d')",
										targetNameEscaped, targetSteamID,
										adminName, adminSteamID,
										"Removed Kban", GetTime());
	g_hDB.Query(OnKbanRemove, query);
}

void OnKbanRemove(Database db, DBResultSet results, const char[] error, any data) {
	if(results == null || error[0]) {
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
		FormatEx(reason, 128, "Trying To Boost");
	}

	if(!GetClientName(target, info.clientName, 32)) {
		return;
	}

	if(admin < 1) {
		FormatEx(info.adminName, 32, "Console");
	} else {
		if(!GetClientName(admin, info.adminName, 32)) {
			return;
		}
	}

	char targetSteamID[20];
	if(!GetClientAuthId(target, AuthId_Steam2, targetSteamID, sizeof(targetSteamID))) {
		FormatEx(info.clientSteamID, 20, "NO STEAMID");
	} else {
		FormatEx(info.clientSteamID, 20, targetSteamID);
	}

	if(admin < 1) {
		FormatEx(info.adminSteamID, 20, "Console");
	} else {
		if(!GetClientAuthId(admin, AuthId_Steam2, info.adminSteamID, 20)) {
			return;
		}
	}

	if(!GetClientIP(target, info.clientIP, 20)) {
		return;
	}

	if((!StrEqual(info.clientSteamID, "NO STEAMID") && IsSteamIDBanned(info.clientSteamID)) || IsIPBanned(info.clientIP)) {
		return;
	}

	if(!GetCurrentMap(info.map, sizeof(Kban::map))) {
		return;
	}

	FormatEx(info.reason, sizeof(Kban::reason), reason);

	info.length = length;

	info.time_stamp_start = GetTime();

	if(length > 0) {
		/* Normal */
		info.time_stamp_end = (GetTime() + (length * 60));
	} else if(length == 0) {
		/* Permanent */
		info.time_stamp_end = 0;
	} else {
		/* Session */
		info.time_stamp_end = -1;
	}

	int arrayIndex = g_allKbans.Length; // for editing id purpose
	g_allKbans.PushArray(info, sizeof(info));

	char escapedTargetName[32 * 2 + 1];
	char escapedAdminName[32 * 2 + 1];
	char escapedReason[128 * 2 + 1];
	
	if(!g_hDB.Escape(info.clientName, escapedTargetName, sizeof(escapedTargetName))) {
		return;
	}

	if(!g_hDB.Escape(info.adminName, escapedAdminName, sizeof(escapedAdminName))) {
		return;
	}

	if(!g_hDB.Escape(info.reason, escapedReason, sizeof(escapedReason))) {
		return;
	}

	char query[2000];
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
	char targetNameEscaped[32 * 2 + 1];
	char adminNameEscaped[32 * 2 + 1];
	char reasonEscaped[128 * 2 + 1];

	if(!g_hDB.Escape(info.clientName, targetNameEscaped, sizeof(targetNameEscaped))) {
		return;
	}

	if(!g_hDB.Escape(info.adminName, adminNameEscaped, sizeof(adminNameEscaped))) {
		return;
	}

	if(!g_hDB.Escape(reason, reasonEscaped, sizeof(reasonEscaped))) {
		return;
	}

	char message[128];

	switch(info.length) {
		case 0: {
			if(target != -1) {
				CPrintToChatAll("%t", "RestrictedPerma", admin, target, KR_Tag, reason);
				LogAction(admin, target, "[Kb-Restrict] \"%L\" has Kb-Restricted \"%L\" Permanently. \nReason: %s", admin, target, reason);
			} else {
				CPrintToChatAll("%t", "RestrictedPermaOffline", admin, info.clientName, KR_Tag, reason);
				LogAction(admin, -1, "[Kb-Restrict] \"%L\" has Offline Kb-Restricted \"%s\" Permanently. \nReason: %s", admin, info.clientName, reason);
			}

			FormatEx(message, sizeof(message), "Kban Added (Permanent)");
		}

		case -1: {
			if(target != -1) {
				CPrintToChatAll("%t", "RestrictedTemp", admin, target, KR_Tag, reason);
				LogAction(admin, target, "[Kb-Restrict] \"%L\" has Kb-Restricted \"%L\" Temporarily. \nReason: %s", admin, target, reason);
			} else {
				CPrintToChatAll("%t", "RestrictedTempOffline", admin, info.clientName, KR_Tag, reason);
				LogAction(admin, -1, "[Kb-Restrict] \"%L\" has Offline Kb-Restricted \"%s\" Temporarily. \nReason: %s", admin, info.clientName, reason);
			}

			FormatEx(message, sizeof(message), "Kban Added (Session)");
		}

		default: {
			if(target != -1) {
				CPrintToChatAll("%t", "Restricted", admin, target, info.length, KR_Tag, reason);
				LogAction(admin, target, "[Kb-Restrict] \"%L\" has Kb-Restricted \"%L\" for \"%d\" minutes. \nReason: %s", admin, target, info.length, reason);
			} else {
				CPrintToChatAll("%t", "RestrictedOffline", admin, info.clientName, info.length, KR_Tag, reason);
				LogAction(admin, -1, "[Kb-Restrict] \"%L\" has Offline Kb-Restricted \"%s\" for %d minutes. \nReason: %s", admin, info.clientName, info.length, reason);
			}

			FormatEx(message, sizeof(message), "Kban Added (%d Minutes)", info.length);
		}
	}

	char query[1024];
	g_hDB.Format(query, sizeof(query), 	"INSERT INTO `KbRestrict_srvlogs` ("
									... "`client_name`, `client_steamid`,"
									... "`admin_name`, `admin_steamid`,"
									... "`message`, `time_stamp`)"
									... "VALUES ('%s', '%s', '%s', '%s', '%s', '%d')",
										targetNameEscaped, info.clientSteamID,
										adminNameEscaped, info.adminSteamID,
										message, GetTime());

	g_hDB.Query(OnKbanAdded, query);
}

void OnKbanAdded(Database db, DBResultSet results, const char[] error, int arrayIndex) {
	if(results == null || error[0]) {
		Kban_GiveError(ERROR_TYPE_INSERT, error);
		return;
	}

	Kban info;
	g_allKbans.GetArray(arrayIndex, info, sizeof(info));
	
	char query[1024];
	g_hDB.Format(query, sizeof(query), 		"SELECT `id` FROM `KbRestrict_CurrentBans` WHERE"
										... "`client_steamid`='%s' AND `client_ip`='%s' AND `is_expired`=0 AND `is_removed`=0",
										info.clientSteamID, info.clientIP);

	g_hDB.Query(OnGetKbanID, query, arrayIndex);
}

int Kban_CheckKbanAdminAccess(int client, int time) {
	bool hasKickFlag 	= (CheckCommandAccess(client, "sm_kick", ADMFLAG_KICK, true));
	bool hasBanFlag 	= (CheckCommandAccess(client, "sm_ban", ADMFLAG_BAN, true));
	bool hasRconFlag 	= (CheckCommandAccess(client, "sm_rcon", ADMFLAG_RCON, true));

	ConVar cvar;
	if(hasKickFlag && !hasBanFlag && !hasRconFlag) {
		cvar = g_cvMaxBanTimeKickFlag;
	} else if(hasBanFlag && !hasRconFlag) {
		cvar = g_cvMaxBanTimeBanFlag;
	} else if(hasRconFlag) {
		cvar = g_cvMaxBanTimeRconFlag;
	}

	if(cvar == null) {
		// this should never happen
		return g_cvDefaultLength.IntValue;
	}

	if(time > cvar.IntValue) {
		time = cvar.IntValue;
	}

	return time;
}

bool Kban_CheckKbanMaxLength(int client, int time) {
	bool hasRootFlag	= (CheckCommandAccess(client, "sm_root", ADMFLAG_ROOT, true));

	if(hasRootFlag) {
		return true;
	}

	bool hasKickFlag 	= (CheckCommandAccess(client, "sm_kick", ADMFLAG_KICK, true));
	bool hasBanFlag 	= (CheckCommandAccess(client, "sm_ban", ADMFLAG_BAN, true));
	bool hasRconFlag 	= (CheckCommandAccess(client, "sm_rcon", ADMFLAG_RCON, true));

	ConVar cvar;
	if(hasKickFlag && !hasBanFlag && !hasRconFlag) {
		cvar = g_cvMaxBanTimeKickFlag;
	} else if(hasBanFlag && !hasRconFlag) {
		cvar = g_cvMaxBanTimeBanFlag;
	} else if(hasRconFlag) {
		cvar = g_cvMaxBanTimeRconFlag;
	}

	if(time > cvar.IntValue) {
		return false;
	}

	return true;
}

void OnGetKbanID(Database db, DBResultSet results, const char[] error, int arrayIndex) {
	if(results == null || error[0]) {
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
			if(steamID[0] && StrEqual(steamID, exInfo.clientSteamID)) {
				CloneKban(info, exInfo);
				return true;
			}
		} else {
			if(ip[0] && StrEqual(ip, exInfo.clientIP)) {
				CloneKban(info, exInfo);
				return true;
			}
		}
	}

	return false;
}

void CloneKban(Kban info, Kban exInfo) {
	FormatEx(info.clientName, 32, exInfo.clientName);
	FormatEx(info.clientSteamID, 20, exInfo.clientSteamID);
	FormatEx(info.clientIP, 20, exInfo.clientIP);
	FormatEx(info.adminName, 32, exInfo.adminName);
	FormatEx(info.adminSteamID, 20, exInfo.adminSteamID);
	FormatEx(info.map, sizeof(Kban::map), exInfo.map);
	FormatEx(info.reason, sizeof(Kban::reason), exInfo.reason);

	info.length = exInfo.length;
	info.time_stamp_start = exInfo.time_stamp_start;
	info.time_stamp_end = exInfo.time_stamp_end;
	info.id = exInfo.id;
}

int Kban_GetClientByIP(const char[] sIP) {
	for(int i = 1; i <= MaxClients; i++) {
		if(!IsClientInGame(i)) {
			continue;
		}

		char ip[20];
		if(!GetClientIP(i, ip, 20)) {
			continue;
		}

		if(StrEqual(ip, sIP, false)) {
			return i;
		}
	}

	return -1;
}

int Kban_GetClientBySteamID(const char[] sSteamID) {
	for(int i = 1; i <= MaxClients; i++) {
		if(!IsClientInGame(i)) {
			continue;
		}

		char steamID[20];
		if(!GetClientAuthId(i, AuthId_Steam2, steamID, 20)) {
			continue;
		}

		if(StrEqual(steamID, sSteamID)) {
			return i;
		}
	}
	
	return -1;
}

bool IsIPBanned(const char[] ip) {
	for(int i = 0; i < g_allKbans.Length; i++) {
		Kban info;
		g_allKbans.GetArray(i, info, sizeof(info));
		if(StrEqual(info.clientIP, ip)) {
			return true;
		}
	}

	return false;
}

bool IsSteamIDBanned(const char[] steamID) {
	for(int i = 0; i < g_allKbans.Length; i++) {
		Kban info;
		g_allKbans.GetArray(i, info, sizeof(info));
		if(StrEqual(info.clientSteamID, steamID)) {
			return true;
		}
	}

	return false;
}

KbanType Kban_GetClientKbanType(int client, char[] steamID = "", char[] ip = "") {
	if(client != -1) {
		if(GetClientAuthId(client, AuthId_Steam2, steamID, 20) && IsSteamIDBanned(steamID)) {
			return KBAN_TYPE_STEAMID;
		}

		if(GetClientIP(client, ip, 20) && IsIPBanned(ip)) {
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
