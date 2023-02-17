#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <cstrike>
#include <multicolors>
#include <clientprefs>
#include <KnifeBan>

#define PLUGIN_PREFIX "{deeppink}[KnifeBan]{indianred}"

int g_iClientTargets[MAXPLAYERS+1] = { -1, ... };
int g_iClientTargetsLength[MAXPLAYERS+1] = { -1, ... };

KeyValues Kv;

ArrayList g_aSteamIDs;

bool g_bIsClientKnifeBanned[MAXPLAYERS+1];
bool g_bIsClientTypingReason[MAXPLAYERS + 1] = { false, ... };
bool g_bKnifeModeEnabled;

Handle g_hKnifeBanExpireTime[MAXPLAYERS+1] = {null, ...};

char sPath[PLATFORM_MAX_PATH];

ConVar g_cvDefaultLength;
ConVar g_cvAddBanLength;

public Plugin myinfo = 
{
	name = "KnifeBan",
	author = "Dolly, .Rushaway",
	description = "Block knife damage of the knife banned player",
	version = "2.3",
	url = "https://nide.gg"
}

public void OnPluginStart()
{
	RegAdminCmd("sm_knifeban", Command_KnifeBan, ADMFLAG_BAN);
	RegAdminCmd("sm_kban", Command_KnifeBan, ADMFLAG_BAN);
	
	RegAdminCmd("sm_knifeunban", Command_KnifeUnBan, ADMFLAG_BAN);
	RegAdminCmd("sm_kunban", Command_KnifeUnBan, ADMFLAG_BAN);
	
	RegAdminCmd("sm_knifebans", Command_KnifeBans, ADMFLAG_BAN);
	RegAdminCmd("sm_kbans", Command_KnifeBans, ADMFLAG_BAN);
		
	RegAdminCmd("sm_addknifeban", Command_AddKnifeBan, ADMFLAG_BAN);
	RegAdminCmd("sm_addkban", Command_AddKnifeBan, ADMFLAG_BAN);
	RegAdminCmd("sm_koban", Command_AddKnifeBan, ADMFLAG_BAN);

	RegConsoleCmd("sm_kstatus", Command_CheckKnifeBan);
	RegConsoleCmd("sm_kbanstatus", Command_CheckKnifeBan);
	
	g_cvDefaultLength = CreateConVar("sm_knifeban_length", "30", "The Default length of time will be given incase no length found");
	g_cvAddBanLength = CreateConVar("sm_knifeban_addban_length", "240", "The Maximume length for add knife ban command");
	
	LoadTranslations("knifeban.phrases");
	LoadTranslations("common.phrases");
	
	BuildPath(Path_SM, sPath, sizeof(sPath), "configs/knifeban/knifeban.cfg");

	if(!FileExists(sPath))
		SetFailState("File %s is missing", sPath);
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if(IsValidClient(i))
		{
			OnClientPutInServer(i);

			if(IsClientAuthorized(i))
				OnClientPostAdminCheck(i);
		}
	}
	
	AutoExecConfig(true);
}

//---------------------------------------------------------//
//--------------------------------------------------------//
//-----------------------FORWARDS------------------------//
//------------------------------------------------------//
//-----------------------------------------------------//

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	RegPluginLibrary("KnifeBan");

	CreateNative("KB_BanClient", Native_KB_BanClient);
	CreateNative("KB_UnBanClient", Native_KB_UnBanClient);
	CreateNative("KB_ClientStatus", Native_KB_ClientStatus);
	
	return APLRes_Success;
}

public int Native_KB_BanClient(Handle plugin, int params)
{
	char sReason[128];
		
	int admin = GetNativeCell(1);
	int client = GetNativeCell(2);
	int time = GetNativeCell(3);
	GetNativeString(4, sReason, sizeof(sReason));

	if(g_bIsClientKnifeBanned[client])
		return 0;
		
	if(!IsClientAuthorized(client))
		return 0;
	
	KnifeBanClient(admin, client, time, sReason);
	return 1;
}

public int Native_KB_UnBanClient(Handle plugin, int params)
{
	char sReason[128];
		
	int admin = GetNativeCell(1);
	int client = GetNativeCell(2);
	GetNativeString(3, sReason, sizeof(sReason));

	if(!g_bIsClientKnifeBanned[client])
		return 0;
		
	KnifeUnBanClient(admin, client, sReason);
	return 1;
}

public int Native_KB_ClientStatus(Handle plugin, int params)
{
	int client = GetNativeCell(1);
	
	return g_bIsClientKnifeBanned[client];
}

public void OnAllPluginsLoaded()
{
	g_bKnifeModeEnabled = LibraryExists("KnifeMode");
}

public void OnMapStart()
{
	g_aSteamIDs = new ArrayList(ByteCountToCells(32));
}

public void OnMapEnd()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if(IsValidClient(i))
			delete g_hKnifeBanExpireTime[i];		
	}
	
	g_aSteamIDs.Clear();
	delete g_aSteamIDs;
	delete Kv;
}

public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
}

public void OnClientPostAdminCheck(int client)
{
	ApplyKnifeBan(client);
}

stock void ApplyKnifeBan(int client)
{
	if(IsValidClient(client))
	{
		char SteamID[32];
		GetClientAuthId(client, AuthId_Steam2, SteamID, sizeof(SteamID));
		CreateKv();
		if(Kv.JumpToKey(SteamID))
		{
			char sName[MAX_NAME_LENGTH];
			Kv.GetString("Name", sName, sizeof(sName));
			if(StrEqual(sName, "UnKnown"))
			{
				char PlayerName[MAX_NAME_LENGTH];
				GetClientName(client, PlayerName, sizeof(PlayerName));
				Kv.SetString("Name", PlayerName);
				Kv.Rewind();
				Kv.ExportToFile(sPath);
			}
			
			if(Kv.GetNum("Length") != 0)
			{
				int length = Kv.GetNum("Length");
				int time = Kv.GetNum("TimeStamp");
				int lefttime = ((length * 60) + time);
				
				if(lefttime > GetTime())
				{
					g_bIsClientKnifeBanned[client] = true;
					
					DataPack datapack = new DataPack();
					g_hKnifeBanExpireTime[client] = CreateDataTimer(1.0 * (lefttime - GetTime()), KnifeBan_ExpireTimer, datapack);
					
					datapack.WriteCell(client);
					datapack.WriteString(SteamID);
				}
				else if(lefttime <= GetTime())
				{
					g_bIsClientKnifeBanned[client] = false;
					Kv.DeleteThis();
					Kv.Rewind();
					Kv.ExportToFile(sPath);
				}
			}
			else if(Kv.GetNum("Length") == 0)
				g_bIsClientKnifeBanned[client] = true;
		}
		delete Kv;
	}
}

public Action KnifeBan_ExpireTimer(Handle timer, DataPack datapack)
{
	char SteamID[32];
	datapack.Reset();
	int client = datapack.ReadCell();
	datapack.ReadString(SteamID, sizeof(SteamID));
	
	g_hKnifeBanExpireTime[client] = null;
	g_bIsClientKnifeBanned[client] = false;
	
	if(IsValidClient(client))
	{
		CPrintToChat(client, "%s {white}Your Knife ban has {green}expired.", PLUGIN_PREFIX);
		DeletePlayerFromCFG(SteamID);
	}
	
	return Plugin_Continue;
}

public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype)
{
	if(!g_bKnifeModeEnabled)
	{
		if(IsValidClient(victim) && IsValidClient(attacker) && attacker != victim)
		{
			if(IsPlayerAlive(attacker) && GetClientTeam(attacker) == 3 && g_bIsClientKnifeBanned[attacker])
			{
				char sWeapon[32];
				GetClientWeapon(attacker, sWeapon, 32);
				if(StrEqual(sWeapon, "weapon_knife"))
				{
					damage *= 0.0;
					return Plugin_Changed;
				}
			}
		}
	}
	
	return Plugin_Continue;
} 

//---------------------------------------------------------//
//--------------------------------------------------------//
//-----------------------COMMANDS------------------------//
//------------------------------------------------------//
//-----------------------------------------------------//

public Action Command_KnifeBan(int client, int args)
{
	if(args < 1)
	{
		DisplayKnifeBansListMenu(client);
		CReplyToCommand(client, "%s Usage: sm_kban/sm_knifeban <player> <duration> <reason>", PLUGIN_PREFIX);
		return Plugin_Handled;
	}
	
	char Arguments[256], arg[50], s_time[20];
	GetCmdArgString(Arguments, sizeof(Arguments));
	
	int len, next_len;
	len = BreakString(Arguments, arg, sizeof(arg));
	if(len == -1)
    {
        len = 0;
        Arguments[0] = '\0';
    }
	
	if((next_len = BreakString(Arguments[len], s_time, sizeof(s_time))) != -1)
        len += next_len;
	else
    {
        len = 0;
        Arguments[0] = '\0';
    }

	int time = StringToInt(s_time);
	int target = FindTarget(client, arg, false, false);
	char SteamID[32];
	
	if(IsValidClient(target))
	{	
		if(!g_bIsClientKnifeBanned[target])
		{
			if(!GetClientAuthId(target, AuthId_Steam2, SteamID, sizeof(SteamID)))
			{
				g_bIsClientKnifeBanned[target] = true;
				CPrintToChatAll("%s {white}%N {red}Knife banned {white}%N {red}temporarily.", PLUGIN_PREFIX, client, target);
				return Plugin_Handled;
			}
			else if(args < 2)
			{
				KnifeBanClient(client, target, g_cvDefaultLength.IntValue);
				return Plugin_Handled;
			}
			else if(args < 3)
			{
				if(!CheckCommandAccess(client, "sm_somalia", ADMFLAG_RCON, true) && time == 0)
				{	
					KnifeBanClient(client, target, g_cvDefaultLength.IntValue);			
					return Plugin_Handled;
				}
				
				KnifeBanClient(client, target, time, "No Reason");
				return Plugin_Handled;
			}
			
			if(!CheckCommandAccess(client, "sm_somalia", ADMFLAG_RCON, true) && time == 0)
			{	
				KnifeBanClient(client, target, g_cvDefaultLength.IntValue, Arguments[len]);
				return Plugin_Handled;
			}
			
			KnifeBanClient(client, target, time, Arguments[len]);
			return Plugin_Handled;
		}
		else
		{
			CReplyToCommand(client, "%s {white}%N {indianred}is already knife banned.", PLUGIN_PREFIX, target);
			return Plugin_Handled;
		}
	}
	
	return Plugin_Handled;
}

public Action Command_KnifeUnBan(int client, int args)
{
	if(args < 1)
	{
		DisplayKnifeBansListMenu(client);
		CReplyToCommand(client, "%s Usage: sm_kunban/sm_knifeunban <player> <reason>.", PLUGIN_PREFIX);
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
	char SteamID[32], AdminSteamID[32];
	
	if(IsValidClient(target))
	{
		GetClientAuthId(target, AuthId_Steam2, SteamID, sizeof(SteamID));
		GetClientAuthId(client, AuthId_Steam2, AdminSteamID, sizeof(AdminSteamID));
		
		if(g_bIsClientKnifeBanned[target])
		{
			if(!GetClientAuthId(target, AuthId_Steam2, SteamID, sizeof(SteamID)))
			{
				g_bIsClientKnifeBanned[target] = false;
				CPrintToChatAll("%s {white}%N {green}Knife unbanned {white}%N.", PLUGIN_PREFIX, client, target);
				return Plugin_Handled;
			}
			
			else if(!CheckKnifeBanAuthor(client, SteamID, AdminSteamID))
			{
				CReplyToCommand(client, "%s You cannot unban other admins KBans.", PLUGIN_PREFIX);
				return Plugin_Handled;
			}
			
			else if(args < 2)
			{
				KnifeUnBanClient(client, target);
				CPrintToChatAll("%s {white}%N {green}Knife unbanned {white}%N. \n%s Reason: No Reason.", PLUGIN_PREFIX, client, target, PLUGIN_PREFIX);
				return Plugin_Handled;
			}
			else if(args >= 2)
			{
				KnifeUnBanClient(client, target, Arguments[len]);
				CPrintToChatAll("%s {white}%N {green}Knife unbanned {white}%N. \n%s Reason: %s.", PLUGIN_PREFIX, client, target, PLUGIN_PREFIX, Arguments[len]);
				return Plugin_Handled;
			}
		}
		else
		{
			CReplyToCommand(client, "%s The specified player doesn't have any current knife ban progress.", PLUGIN_PREFIX);
			return Plugin_Handled;
		}
	}
	
	return Plugin_Handled;
}

public Action Command_KnifeBans(int client, int args)
{
	if(!client)
	{
		ReplyToCommand(client, "You cannot use this command from server rcon.");
		return Plugin_Handled;
	}
	
	DisplayKnifeBansListMenu(client);
	return Plugin_Handled;
}

public Action Command_CheckKnifeBan(int client, int args)
{
	if(!client)
	{
		ReplyToCommand(client, "You cannot use this command from server rcon.");
		return Plugin_Handled;
	}
	
	char SteamID[32];
	GetClientAuthId(client, AuthId_Steam2, SteamID, sizeof(SteamID));
	
	if(!g_bIsClientKnifeBanned[client])
	{
		CReplyToCommand(client, "%s {green}You are currently not Knife banned.", PLUGIN_PREFIX);
		return Plugin_Handled;
	}
	else if(g_bIsClientKnifeBanned[client])
	{
		CreateKv();
		if(Kv.JumpToKey(SteamID))
		{
			int time = Kv.GetNum("TimeStamp");
			int length = Kv.GetNum("Length");
			int totaltime = ((length * 60) + time);
			int lefttime = totaltime - GetTime();
			
			char TimeLeft[32];
			CheckPlayerExpireTime(lefttime, TimeLeft, sizeof(TimeLeft));				
			
			DisplayCheckKnifeBanMenu(client);
			CReplyToCommand(client, "%s Your Knife Ban expires {green}in %s.", PLUGIN_PREFIX, TimeLeft);
		}
		else
		{
			//DisplayCheckKnifeBanMenu(client);
			CReplyToCommand(client, "%s You are currently knife banned temporarily until this map end.", PLUGIN_PREFIX);
		}
		
		delete Kv;
		return Plugin_Handled;
	}
	
	return Plugin_Handled;
}

public Action Command_AddKnifeBan(int client, int args)
{
	if(args < 3)
	{
		CReplyToCommand(client, "%s Usage: sm_koban/sm_addknifeban/sm_addkban \"<steamid>\" <time> <reason>", PLUGIN_PREFIX);
		return Plugin_Handled;
	}

	char AdminSteamID[32];
	GetClientAuthId(client, AuthId_Steam2, AdminSteamID, sizeof(AdminSteamID));
	
	char Arguments[256], arg[50], s_time[20];
	GetCmdArgString(Arguments, sizeof(Arguments));
	
	int len, next_len;
	len = BreakString(Arguments, arg, sizeof(arg));
	if(len == -1)
    {
        len = 0;
        Arguments[0] = '\0';
    }
	
	if((next_len = BreakString(Arguments[len], s_time, sizeof(s_time))) != -1)
        len += next_len;
	else
    {
        len = 0;
        Arguments[0] = '\0';
    }
	
	int time = StringToInt(s_time);
	
	if(arg[7] != ':')
	{
		CReplyToCommand(client, "%s Please type the SteamID between quotes.", PLUGIN_PREFIX);
		return Plugin_Handled;
	}
	
	CreateKv();
	if(Kv.JumpToKey(arg))
	{
		CReplyToCommand(client, "%s The specified steamid is already knife banned", PLUGIN_PREFIX);
		return Plugin_Handled;
	}
	else
	{
		if(time <= g_cvAddBanLength.IntValue)
		{
			if(!IsSteamIDInGame(arg))
			{
				char sAdminName[64], date[32], sCurrentMap[64];
				GetClientName(client, sAdminName, 64);
				FormatTime(date, 32, "%d/%m/%y @ %r", GetTime());
				GetCurrentMap(sCurrentMap, 64);
				
				AddPlayerToCFG(arg, AdminSteamID, "UnKnown", sAdminName, Arguments[len], date, sCurrentMap, time);
				CReplyToCommand(client, "%s {green}Successfully added knife ban for {white}%s{indianred} for {red}%d minutes", PLUGIN_PREFIX, arg, time);
				LogAction(client, -1, "\"%L\" has added a knife ban to CFG for \"%s\" for \"%d\" minutes.", client, arg, time);
				return Plugin_Handled;
			}
			else
			{
				CReplyToCommand(client, "%s The specified steamid is alraedy online on the server, please use {green}sm_knifeban {indianred}instead.", PLUGIN_PREFIX);
				return Plugin_Handled;
			}
		}
		else if(time > g_cvAddBanLength.IntValue)
		{
			CReplyToCommand(client, "%s Maximume length for adding knife ban is {green}%d", PLUGIN_PREFIX, g_cvAddBanLength.IntValue);
			return Plugin_Handled;
		}
	}
	delete Kv;
	
	return Plugin_Handled;
}
	
public Action OnClientSayCommand(int client, const char[] command, const char[] sArgs)
{
	if(!client)
		return Plugin_Continue;

	
	if(StrEqual(command, "say") || StrEqual(command, "say_team"))
	{
		if(g_bIsClientTypingReason[client])
		{	
			if(IsValidClient(GetClientOfUserId(g_iClientTargets[client])))
			{
				if(!g_bIsClientKnifeBanned[GetClientOfUserId(g_iClientTargets[client])])
				{
					char buffer[128];
					strcopy(buffer, sizeof(buffer), sArgs);
					KnifeBanClient(client, GetClientOfUserId(g_iClientTargets[client]), g_iClientTargetsLength[client], buffer);
				}
				else
					CPrintToChat(client, "%s Player is already knife banned.", PLUGIN_PREFIX);
			}
			else
				CPrintToChat(client, "%s Player has left the game.", PLUGIN_PREFIX);
			
			g_bIsClientTypingReason[client] = false;
			return Plugin_Stop;
		}
	}
	
	return Plugin_Continue;
}

//---------------------------------------------------------//
//--------------------------------------------------------//
//-----------------------MENUS---------------------------//
//------------------------------------------------------//
//-----------------------------------------------------//

public int Menu_KnifeBansList(Menu menu, MenuAction action, int param1, int param2)
{
	switch(action)
	{
		case MenuAction_End:
			delete menu;
		
		case MenuAction_Select:
		{
			switch(param2)
			{
				case 0:
					DisplayKnifeBanClientsMenu(param1);
				case 2:
					DisplayCurrentKnifeBansMenu(param1);
				case 3:
					DisplayOwnKnifeBansMenu(param1);
				case 4:
					DisplayAllKnifeBansMenu(param1);
			}
		}
	}
	
	return 0;
}
	
public int Menu_KnifeBanClients(Menu menu, MenuAction action, int param1, int param2)
{
	switch(action)
	{
		case MenuAction_End:
			delete menu;
		
		case MenuAction_Cancel:
		{
			if(param2 == MenuCancel_ExitBack)
				DisplayKnifeBansListMenu(param1);
		}
		
		case MenuAction_Select:
		{
			char buffer[64];
			menu.GetItem(param2, buffer, sizeof(buffer));
			int userid = StringToInt(buffer);
			int target = GetClientOfUserId(userid);
			
			if(IsValidClient(target) && !IsFakeClient(target) && IsClientAuthorized(target))
			{
				if(!g_bIsClientKnifeBanned[target])
				{
					DisplayLengthsMenu(param1);
					g_iClientTargets[param1] = userid;
				}
				else
				{
					CPrintToChat(param1, "%s Player is already knife banned", PLUGIN_PREFIX);
					DisplayKnifeBanClientsMenu(param1);
				}
			}
			else
			{
				DisplayKnifeBanClientsMenu(param1);
				CPrintToChat(param1, "%s Player either has invalid steamid or left the game.", PLUGIN_PREFIX);
			}
		}
	}
	
	return 0;
}

public int Menu_KnifeBanLengths(Menu menu, MenuAction action, int param1, int param2)
{
	switch(action)
	{
		case MenuAction_End:
			delete menu;
			
		case MenuAction_Cancel:
		{
			if(param2 == MenuCancel_ExitBack)
				DisplayKnifeBanClientsMenu(param1);
		}
		
		case MenuAction_Select:
		{		
			char buffer[64];
			menu.GetItem(param2, buffer, sizeof(buffer));
			int time = StringToInt(buffer);
			
			if(IsValidClient(GetClientOfUserId(g_iClientTargets[param1])))
			{
				g_iClientTargetsLength[param1] = time;
				DisplayReasonsMenu(param1);
			}
		}
	}
	
	return 0;
}

public int Menu_Reasons(Menu menu, MenuAction action, int param1, int param2)
{
	switch(action)
	{
		case MenuAction_End:
		{
			g_bIsClientTypingReason[param1] = false;
			delete menu;
		}
		
		case MenuAction_Cancel:
		{		
			if(param2 == MenuCancel_ExitBack)
			{
				g_bIsClientTypingReason[param1] = false;
				
				if(IsValidClient(GetClientOfUserId(g_iClientTargets[param1])))
					DisplayLengthsMenu(param1);
			}
		}
		
		case MenuAction_Select:
		{
			if(param2 == 4)
			{
				if(IsValidClient(GetClientOfUserId(g_iClientTargets[param1])))
				{
					if(!g_bIsClientKnifeBanned[GetClientOfUserId(g_iClientTargets[param1])])
					{
						CPrintToChat(param1, "%s Please type the reason in chat.", PLUGIN_PREFIX);
						g_bIsClientTypingReason[param1] = true;
					}
					else
						CPrintToChat(param1, "%s Player is already knife banned.", PLUGIN_PREFIX);
				}
				else
					CPrintToChat(param1, "%s Player has left the game.", PLUGIN_PREFIX);
			}
			else
			{
			
				char buffer[128];
				menu.GetItem(param2, buffer, sizeof(buffer));
				
				if(IsValidClient(GetClientOfUserId(g_iClientTargets[param1])))
				{	
					KnifeBanClient(param1, GetClientOfUserId(g_iClientTargets[param1]), g_iClientTargetsLength[param1], buffer);
				}
			}
		}
	}
	
	return 0;
}
						
public int Menu_CurrentBans(Menu menu, MenuAction action, int param1, int param2)
{
	switch(action)
	{
		case MenuAction_Cancel:
		{
			if(param2 == MenuCancel_ExitBack)
				DisplayKnifeBansListMenu(param1);
		}
		
		case MenuAction_End:
			delete menu;
		
		case MenuAction_Select:
		{
			char buffer[32];
			menu.GetItem(param2, buffer, sizeof(buffer));
			int userid = StringToInt(buffer);
			int target = GetClientOfUserId(userid);
			
			if(IsValidClient(target))
			{
				char SteamID[32];	
				GetClientAuthId(target, AuthId_Steam2, SteamID, sizeof(SteamID));
				
				ShowActionsAndDetailsForCurrent(param1, target, SteamID);
			}
		}
	}
	
	return 0;
}
				
public int Menu_AllKnifeBans(Menu menu, MenuAction action, int param1, int param2)
{
	switch(action)
	{
		case MenuAction_Cancel:
		{
			if(param2 == MenuCancel_ExitBack)
				DisplayKnifeBansListMenu(param1);
		}
		
		case MenuAction_End:
			delete menu;
		
		case MenuAction_Select:
		{			
			char buffer[32];
			menu.GetItem(param2, buffer, sizeof(buffer));
			
			ShowActionsAndDetailsForAll(param1, buffer);
		}
	}
	
	return 0;
}

public int Menu_ActionsAndDetailsAll(Menu menu, MenuAction action, int param1, int param2)
{
	switch(action)
	{
		case MenuAction_End:
			delete menu;
		
		case MenuAction_Cancel:
		{
			if(param2 == MenuCancel_ExitBack)
				DisplayAllKnifeBansMenu(param1);
		}
		
		case MenuAction_Select:
		{
			char buffer[32];
			menu.GetItem(param2, buffer, sizeof(buffer));
			
			DeletePlayerFromCFG(buffer);
			CPrintToChat(param1, "%s {green}Successfully removed knife ban for {white}%s.", PLUGIN_PREFIX, buffer);
			if(!IsSteamIDInGame(buffer))
			{
				LogAction(param1, -1, "[Knife Ban] \"%L\" has knife unbanned player with (\"%s\") (reason No Reason)", param1, buffer);
			}
			else
			{
				int target = GetPlayerFromSteamID(buffer);
				if(g_bIsClientKnifeBanned[target])
				{
					LogAction(param1, -1, "[Knife Ban] \"%L\" has knife unbanned player with (\"%s\") (PLAYER IS IN GAME)(reason No Reason)", param1, buffer);
					CPrintToChatAll("%s {white}%N {green}Knife unbanned {white}%N. \n%s Reason: No Reason.", PLUGIN_PREFIX, param1, target, PLUGIN_PREFIX);
					g_bIsClientKnifeBanned[target] = false;
					g_hKnifeBanExpireTime[target] = null;
				}
			}
				
			
			DisplayAllKnifeBansMenu(param1);
		}
	}
	
	return 0;
}

public int Menu_ActionsAndDetailsCurrent(Menu menu, MenuAction action, int param1, int param2)
{
	switch(action)
	{
		case MenuAction_End:
			delete menu;
		
		case MenuAction_Cancel:
		{
			if(param2 == MenuCancel_ExitBack)
				DisplayCurrentKnifeBansMenu(param1);
		}
		
		case MenuAction_Select:
		{
			char buffer[32];
			menu.GetItem(param2, buffer, sizeof(buffer));
			
			int userid = StringToInt(buffer);
			int target = GetClientOfUserId(userid);
			
			char SteamID[32];
			GetClientAuthId(target, AuthId_Steam2, SteamID, sizeof(SteamID));
			
			if(g_bIsClientKnifeBanned[target])
			{
				DeletePlayerFromCFG(SteamID);
				
				g_bIsClientKnifeBanned[target] = false;
				
				CPrintToChat(param1, "%s {green}Successfully removed knife ban for {white}%s.", PLUGIN_PREFIX, SteamID);
				CPrintToChatAll("%s {white}%N {green}Knife unbanned {white}%N. \n%s Reason: No Reason.", PLUGIN_PREFIX, param1, target, PLUGIN_PREFIX);
				LogAction(param1, target, "[Knife Ban] \"%L\" has knife unbanned \"%L\" (reason: No Reason)", param1, target);
			}
				
			DisplayCurrentKnifeBansMenu(param1);
		}
	}
	
	return 0;
}

public int Menu_OwnKnifeBans(Menu menu, MenuAction action, int param1, int param2)
{
	switch(action)
	{
		case MenuAction_End:
			delete menu;
		
		case MenuAction_Cancel:
		{
			if(param2 == MenuCancel_ExitBack)
				DisplayKnifeBansListMenu(param1);
		}
		
		case MenuAction_Select:
		{
			char buffer[32];
			menu.GetItem(param2, buffer, sizeof(buffer));
			
			DisplayOwnKnifeBansActions(param1, buffer);
		}
	}
	
	return 0;
}

public int Menu_OwnKnifeBansActions(Menu menu, MenuAction action, int param1, int param2)
{
	switch(action)
	{
		case MenuAction_End:
			delete menu;
		
		case MenuAction_Cancel:
		{
			if(param2 == MenuCancel_ExitBack)
				DisplayOwnKnifeBansMenu(param1);
		}
		
		case MenuAction_Select:
		{
			char buffer[32];
			menu.GetItem(param2, buffer, sizeof(buffer));
			
			if(IsSteamIDInGame(buffer))
			{
				int target = GetPlayerFromSteamID(buffer);
				if(IsValidClient(target))
				{
					KnifeUnBanClient(param1, target, "No Reason");
					CPrintToChatAll("%s {white}%N {green}Knife unbanned {white}%N. \n%s Reason: No Reason.", PLUGIN_PREFIX, param1, target, PLUGIN_PREFIX);
				}
			}
			else
			{
				DeletePlayerFromCFG(buffer);
				CPrintToChat(param1, "%s {green}Successfully removed knife ban for {white}%s.", PLUGIN_PREFIX, buffer);
			}
			
			DisplayOwnKnifeBansMenu(param1);
		}
	}
	
	return 0;
}

public int Menu_CheckKnifeBan(Menu menu, MenuAction action, int param1, int param2)
{
	switch(action)
	{
		case MenuAction_End:
			delete menu;
	}
	
	return 0;
}
			
stock void DisplayKnifeBansListMenu(int client)
{
	Menu menu = new Menu(Menu_KnifeBansList);
	menu.SetTitle("[KnifeBan] Commands");
	
	menu.AddItem("0", "KBan a Player");
	menu.AddItem("1", "", ITEMDRAW_SPACER);
	menu.AddItem("2", "Online KBanned");
	menu.AddItem("3", "KBans you made");
	menu.AddItem("4", "Full KBan BanList", CheckCommandAccess(client, "sm_koban", ADMFLAG_RCON, true) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

stock void DisplayKnifeBanClientsMenu(int client)
{
	Menu menu = new Menu(Menu_KnifeBanClients);
	menu.SetTitle("[KnifeBan] Knife Ban Clients");
	
	menu.ExitBackButton = true;
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if(IsValidClient(i) && IsClientAuthorized(i) && !g_bIsClientKnifeBanned[i])
		{
			char buffer[32], text[MAX_NAME_LENGTH];
			int userid = GetClientUserId(i);
			IntToString(userid, buffer, sizeof(buffer));
			Format(text, sizeof(text), "%N", i);
			
			menu.AddItem(buffer, text);
		}
	}
			
	menu.Display(client, MENU_TIME_FOREVER);
}

stock void DisplayLengthsMenu(int client)
{
	Menu menu = new Menu(Menu_KnifeBanLengths);
	menu.SetTitle("[KnifeBan] KBan Duration");
	
	menu.AddItem("0", "Permanent", CheckCommandAccess(client, "sm_koban", ADMFLAG_RCON, true) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	menu.AddItem("-1", "Session");
	
	for(int i = 15; i >= 15 && i < 241920; i++)
	{
		if(i == 15 || i == 30 || i == 45)
		{
			char buffer[32], text[32];
			IntToString(i, buffer, sizeof(buffer));
			Format(text, sizeof(text), "%d Minutes", i);
			menu.AddItem(buffer, text);
		}
		else if(i == 60 || i == 120 || i == 240 || i == 480 || i == 720)
		{
			char buffer[32], text[32];
			IntToString(i, buffer, sizeof(buffer));
			int hour = (i / 60);
			Format(text, sizeof(text), "%d Hours", hour);
			menu.AddItem(buffer, text);
		}	
		else if(i == 1440 || i == 2880 || i == 4320 || i == 5760 || i == 7200 || i == 8640)
		{
			char buffer[32], text[32];
			IntToString(i, buffer, sizeof(buffer));
			int day = (i / 1440);
			Format(text, sizeof(text), "%d Days", day);
			menu.AddItem(buffer, text);
		}
		else if(i == 10080 || i == 20160 || i == 30240)
		{
			char buffer[32], text[32];
			IntToString(i, buffer, sizeof(buffer));
			int week = (i / 10080);
			Format(text, sizeof(text), "%d Weeks", week);
			menu.AddItem(buffer, text);
		}
		else if(i == 40320 || i == 80640 || i == 120960 || i == 241920)
		{
			char buffer[32], text[32];
			IntToString(i, buffer, sizeof(buffer));
			int month = (i / 40320);
			Format(text, sizeof(text), "%d Months", month);
			menu.AddItem(buffer, text);
		}
	}
	
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

stock void DisplayReasonsMenu(int client)
{
	Menu menu = new Menu(Menu_Reasons);
	menu.SetTitle("[KnifeBan] KBan Reason");
	
	char sBuffer[128];
	
	FormatEx(sBuffer, sizeof(sBuffer), "%T", "Boosting", client);
	menu.AddItem(sBuffer, sBuffer);
	
	FormatEx(sBuffer, sizeof(sBuffer), "%T", "TryingToBoost", client);
	menu.AddItem(sBuffer, sBuffer);
	
	FormatEx(sBuffer, sizeof(sBuffer), "%T", "Suspicious", client);
	menu.AddItem(sBuffer, sBuffer);
	
	FormatEx(sBuffer, sizeof(sBuffer), "%T", "No Reason", client);
	menu.AddItem(sBuffer, sBuffer);
	
	menu.AddItem("4", "Custom Reason");
	
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

stock void DisplayCurrentKnifeBansMenu(int client)
{
	Menu menu = new Menu(Menu_CurrentBans);
	menu.SetTitle("[KnifeBan] Online players KBanned:");
	
	if(GetCurrentKnifeBannedPlayers() >= 1)
	{
		for (int player = 1; player <= MaxClients; player++)
		{
			if(IsValidClient(player) && g_bIsClientKnifeBanned[player] && IsClientAuthorized(player))
			{
				char info[32], buffer[32];
				int userid = GetClientUserId(player);
				
				IntToString(userid, info, 32);
				Format(buffer, 32, "%N", player);
				
				menu.AddItem(info, buffer);
			}
		}
	}
	else if(GetCurrentKnifeBannedPlayers() <= 0)
		menu.AddItem("", "No KBan", ITEMDRAW_DISABLED);
	
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

stock void DisplayAllKnifeBansMenu(int client)
{
	Menu menu = new Menu(Menu_AllKnifeBans);
	menu.SetTitle("[KnifeBan] Full KBan BanList");
	
	CreateKv();
	if(!Kv.GotoFirstSubKey())
	{
		menu.AddItem("empty", "No KBan", ITEMDRAW_DISABLED);
	}
	else
	{
		do
		{
			char sName[64], buffer[128], SteamID[32];
			Kv.GetSectionName(SteamID, sizeof(SteamID));
			Kv.GetString("Name", sName, sizeof(sName));
			
			Format(buffer, sizeof(buffer), "%s  %s", sName, SteamID);
			menu.AddItem(SteamID, buffer);
		}
		while(Kv.GotoNextKey());
	}
	
	delete Kv;
	
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}
	
stock void DisplayOwnKnifeBansMenu(int client)
{
	char sSteamID[32];
	GetClientAuthId(client, AuthId_Steam2, sSteamID, sizeof(sSteamID));
	
	Menu menu = new Menu(Menu_OwnKnifeBans);
	menu.SetTitle("[KnifeBan] Your Own active KBans List");
	
	if(GetAdminOwnKnifeBans(client, sSteamID) >= 1)
	{
		CreateKv();
		if(Kv.GotoFirstSubKey())
		{
			do
			{
				char sName[64], buffer[128], SteamID[32], AdminSteamID[32];
				Kv.GetSectionName(SteamID, sizeof(SteamID));
				Kv.GetString("Name", sName, sizeof(sName));
				Kv.GetString("AdminSteamID", AdminSteamID, sizeof(AdminSteamID));
				if(StrEqual(AdminSteamID, sSteamID))
				{
					if(IsSteamIDInGame(SteamID))
						Format(buffer, sizeof(buffer), "%s (ONLINE)", sName);
					else
						Format(buffer, sizeof(buffer), "%s  [%s] (OFFLINE)", sName, SteamID);
						
					menu.AddItem(SteamID, buffer);
				}
			}
			while(Kv.GotoNextKey());
		}
		
		delete Kv;
	}
	else if(GetAdminOwnKnifeBans(client, sSteamID) <= 0)
		menu.AddItem("", "No KBan", ITEMDRAW_DISABLED);
	
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

stock void DisplayOwnKnifeBansActions(int client, const char[] SteamID)
{
	Menu menu = new Menu(Menu_OwnKnifeBansActions);
	char title[65];
	Format(title, sizeof(title), "[KnifeBan] KBan Info: %s", SteamID);
	menu.SetTitle(title);
	
	CreateKv();
	char sName[MAX_NAME_LENGTH], sReason[128], date[128], sCurrentMap[PLATFORM_MAX_PATH];
	char NameBuffer[MAX_NAME_LENGTH+64], ReasonBuffer[150], LengthBuffer[64], DateBuffer[160], MapBuffer[PLATFORM_MAX_PATH+64], TimeLeftBuffer[64], sLengthEx[64];

	int ilength;
	
	Kv.JumpToKey(SteamID, true);
	Kv.GetString("Name", sName, sizeof(sName));
	Kv.GetString("Reason", sReason, sizeof(sReason));
	Kv.GetString("Date", date, sizeof(date));
	Kv.GetString("Map", sCurrentMap, sizeof(sCurrentMap));
	Kv.GetString("LengthEx", sLengthEx, sizeof(sLengthEx));
	if(StrEqual(sLengthEx, "Permanent"))
		Format(LengthBuffer, sizeof(LengthBuffer), "Duration : Permanent");
	else
	{
		ilength = Kv.GetNum("Length");
		Format(LengthBuffer, sizeof(LengthBuffer), "Duration : %d Minutes", ilength);
	}

	int time = Kv.GetNum("TimeStamp");
	int length = Kv.GetNum("Length");
	int totaltime = ((length * 60) + time);
	int lefttime = totaltime - GetTime();

	char TimeLeft[32];
	CheckPlayerExpireTime(lefttime, TimeLeft, sizeof(TimeLeft));
			
	Format(NameBuffer, sizeof(NameBuffer), "Player : %s", sName);
	Format(ReasonBuffer, sizeof(ReasonBuffer), "Reason : %s", sReason);
	Format(DateBuffer, sizeof(DateBuffer), "Issued : %s", date);
	Format(MapBuffer, sizeof(MapBuffer), "Map : %s", sCurrentMap);
	if(StrEqual(sLengthEx, "Permanent"))
		Format(TimeLeftBuffer, sizeof(TimeLeftBuffer), "Expire : Never");
	else
		Format(TimeLeftBuffer, sizeof(TimeLeftBuffer), "Expire in: %s", TimeLeft);
			
	menu.AddItem("", NameBuffer, ITEMDRAW_DISABLED);
	menu.AddItem("", LengthBuffer, ITEMDRAW_DISABLED);
	menu.AddItem("", DateBuffer, ITEMDRAW_DISABLED);
	menu.AddItem("", TimeLeftBuffer, ITEMDRAW_DISABLED);
	menu.AddItem("", ReasonBuffer, ITEMDRAW_DISABLED);
	menu.AddItem("", MapBuffer, ITEMDRAW_DISABLED);
	menu.AddItem(SteamID, "Knife UnBan");

	delete Kv;
	
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

stock void ShowActionsAndDetailsForAll(int client, const char[] sSteamID)
{
	Menu menu = new Menu(Menu_ActionsAndDetailsAll);
	
	char sTitle[64];
	Format(sTitle, sizeof(sTitle), "[KnifeBan] Actions And Details for %s", sSteamID); 
	menu.SetTitle(sTitle);
	
	CreateKv();
	char sName[MAX_NAME_LENGTH], sAdminName[MAX_NAME_LENGTH], AdminSteamID[32], sReason[128], date[128], sCurrentMap[PLATFORM_MAX_PATH];
	char NameBuffer[MAX_NAME_LENGTH+64], AdminNameBuffer[MAX_NAME_LENGTH+64], ReasonBuffer[150], LengthBuffer[64], DateBuffer[160], MapBuffer[PLATFORM_MAX_PATH+64], TimeLeftBuffer[64], sLengthEx[64];

	int ilength;
	
	if(Kv.JumpToKey(sSteamID))
	{
		Kv.GetString("Name", sName, sizeof(sName));
		Kv.GetString("Admin Name", sAdminName, sizeof(sAdminName));
		Kv.GetString("AdminSteamID", AdminSteamID, sizeof(AdminSteamID));
		Kv.GetString("Reason", sReason, sizeof(sReason));
		Kv.GetString("Date", date, sizeof(date));
		Kv.GetString("Map", sCurrentMap, sizeof(sCurrentMap));

		Kv.GetString("LengthEx", sLengthEx, sizeof(sLengthEx));
		if(StrEqual(sLengthEx, "Permanent"))
			Format(LengthBuffer, sizeof(LengthBuffer), "Duration : Permanent");
		else
		{
			ilength = Kv.GetNum("Length");
			Format(LengthBuffer, sizeof(LengthBuffer), "Duration : %d Minutes", ilength);
		}
		
		int time = Kv.GetNum("TimeStamp");
		int length = Kv.GetNum("Length");
		int totaltime = ((length * 60) + time);
		int lefttime = totaltime - GetTime();
		
		char TimeLeft[32];
		CheckPlayerExpireTime(lefttime, TimeLeft, sizeof(TimeLeft));

		Format(NameBuffer, sizeof(NameBuffer), "Player : %s", sName);
		Format(AdminNameBuffer, sizeof(AdminNameBuffer), "Admin : %s (%s)", sAdminName, AdminSteamID);
		Format(ReasonBuffer, sizeof(ReasonBuffer), "Reason : %s", sReason);
		Format(DateBuffer, sizeof(DateBuffer), "Issued : %s", date);
		Format(MapBuffer, sizeof(MapBuffer), "Map : %s", sCurrentMap);
		if(StrEqual(sLengthEx, "Permanent"))
			Format(TimeLeftBuffer, sizeof(TimeLeftBuffer), "Expire : Never");
		else
			Format(TimeLeftBuffer, sizeof(TimeLeftBuffer), "Expire in: %s", TimeLeft);
				
		menu.AddItem("", NameBuffer, ITEMDRAW_DISABLED);
		menu.AddItem("", AdminNameBuffer, ITEMDRAW_DISABLED);
		menu.AddItem("", LengthBuffer, ITEMDRAW_DISABLED);
		menu.AddItem("", DateBuffer, ITEMDRAW_DISABLED);
		menu.AddItem("", TimeLeftBuffer, ITEMDRAW_DISABLED);
		menu.AddItem("", ReasonBuffer, ITEMDRAW_DISABLED);
		menu.AddItem("", MapBuffer, ITEMDRAW_DISABLED);
		menu.AddItem(sSteamID, "Knife UnBan");
	}
	
	delete Kv;
	
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

stock void ShowActionsAndDetailsForCurrent(int client, int target, const char[] sSteamID)
{
	char SteamID[32];
	GetClientAuthId(client, AuthId_Steam2, SteamID, sizeof(SteamID));
	
	Menu menu = new Menu(Menu_ActionsAndDetailsCurrent);
	
	char sTitle[64];
	Format(sTitle, sizeof(sTitle), "[KnifeBan] Actions And Details for %s", sSteamID); 
	menu.SetTitle(sTitle);
	
	CreateKv();
	char sBuffer[32], sName[MAX_NAME_LENGTH], sAdminName[MAX_NAME_LENGTH], AdminSteamID[32], sReason[128], date[128], sCurrentMap[PLATFORM_MAX_PATH];
	char NameBuffer[MAX_NAME_LENGTH+64], AdminNameBuffer[MAX_NAME_LENGTH+64], ReasonBuffer[150], LengthBuffer[64], DateBuffer[160], MapBuffer[PLATFORM_MAX_PATH+64], TimeLeftBuffer[64], sLengthEx[64];
	
	int userid = GetClientUserId(target);
	IntToString(userid, sBuffer, 32);
	
	int ilength;
	
	if(Kv.JumpToKey(sSteamID))
	{
		Kv.GetString("Name", sName, sizeof(sName));
		Kv.GetString("Admin Name", sAdminName, sizeof(sAdminName));
		Kv.GetString("AdminSteamID", AdminSteamID, sizeof(AdminSteamID));
		Kv.GetString("Reason", sReason, sizeof(sReason));
		Kv.GetString("Date", date, sizeof(date));
		Kv.GetString("Map", sCurrentMap, sizeof(sCurrentMap));
		Kv.GetString("LengthEx", sLengthEx, sizeof(sLengthEx));
		if(StrEqual(sLengthEx, "Permanent"))
			Format(LengthBuffer, sizeof(LengthBuffer), "Duration : Permanent");
		else
		{
			ilength = Kv.GetNum("Length");
			Format(LengthBuffer, sizeof(LengthBuffer), "Duration : %d Minutes", ilength);
		}
		
		int time = Kv.GetNum("TimeStamp");
		int length = Kv.GetNum("Length");
		int totaltime = ((length * 60) + time);
		int lefttime = totaltime - GetTime();
		
		char TimeLeft[32];
		CheckPlayerExpireTime(lefttime, TimeLeft, sizeof(TimeLeft));
				
		Format(NameBuffer, sizeof(NameBuffer), "Player : %s", sName);
		Format(AdminNameBuffer, sizeof(AdminNameBuffer), "Admin : %s (%s)", sAdminName, AdminSteamID);
		Format(ReasonBuffer, sizeof(ReasonBuffer), "Reason : %s", sReason);
		Format(DateBuffer, sizeof(DateBuffer), "Issued : %s", date);
		Format(MapBuffer, sizeof(MapBuffer), "Map : %s", sCurrentMap);
		if(StrEqual(sLengthEx, "Permanent"))
			Format(TimeLeftBuffer, sizeof(TimeLeftBuffer), "Expire : Never");
		else
			Format(TimeLeftBuffer, sizeof(TimeLeftBuffer), "Expire in: %s", TimeLeft);
				
		menu.AddItem("", NameBuffer, ITEMDRAW_DISABLED);
		menu.AddItem("", AdminNameBuffer, ITEMDRAW_DISABLED);
		menu.AddItem("", LengthBuffer, ITEMDRAW_DISABLED);
		menu.AddItem("", DateBuffer, ITEMDRAW_DISABLED);
		menu.AddItem("", TimeLeftBuffer, ITEMDRAW_DISABLED);
		menu.AddItem("", ReasonBuffer, ITEMDRAW_DISABLED);
		menu.AddItem("", MapBuffer, ITEMDRAW_DISABLED);
		menu.AddItem(sBuffer, "Knife UnBan", CheckKnifeBanAuthor(client, sSteamID, SteamID) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	}
	else
	{
		//menu.AddItem("", NameBuffer, ITEMDRAW_DISABLED);
		//menu.AddItem("", AdminNameBuffer, ITEMDRAW_DISABLED);
		menu.AddItem("", "Duration : Session", ITEMDRAW_DISABLED);
		menu.AddItem("", "Map : Current Map", ITEMDRAW_DISABLED);
		//menu.AddItem("", DateBuffer, ITEMDRAW_DISABLED);
		//menu.AddItem("", ReasonBuffer, ITEMDRAW_DISABLED);
		//menu.AddItem("", MapBuffer, ITEMDRAW_DISABLED);
		menu.AddItem(sBuffer, "Knife UnBan");
	}
	
	delete Kv;
	
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

stock void DisplayCheckKnifeBanMenu(int client)
{
	Menu menu = new Menu(Menu_CheckKnifeBan);
	menu.SetTitle("[KnifeBan] Your KBan details");
	
	char SteamID[32];
	GetClientAuthId(client, AuthId_Steam2, SteamID, sizeof(SteamID));
	
	char sName[MAX_NAME_LENGTH], sAdminName[MAX_NAME_LENGTH], AdminSteamID[32], sReason[128], date[128], sCurrentMap[PLATFORM_MAX_PATH], sLengthEx[64];
	char NameBuffer[MAX_NAME_LENGTH+64], AdminNameBuffer[MAX_NAME_LENGTH+64], ReasonBuffer[150], LengthBuffer[64], DateBuffer[160], MapBuffer[PLATFORM_MAX_PATH+64], TimeLeftBuffer[64];
		
	int ilength;
	
	CreateKv();
	if(Kv.JumpToKey(SteamID))
	{
		Kv.GetString("Name", sName, sizeof(sName));
		Kv.GetString("Admin Name", sAdminName, sizeof(sAdminName));
		Kv.GetString("AdminSteamID", AdminSteamID, sizeof(AdminSteamID));
		Kv.GetString("Reason", sReason, sizeof(sReason));
		Kv.GetString("Date", date, sizeof(date));
		Kv.GetString("Map", sCurrentMap, sizeof(sCurrentMap));
		Kv.GetString("LengthEx", sLengthEx, sizeof(sLengthEx));
		if(StrEqual(sLengthEx, "Permanent"))
			Format(LengthBuffer, sizeof(LengthBuffer), "Duration : Permanent");
		else
		{
			ilength = Kv.GetNum("Length");
			Format(LengthBuffer, sizeof(LengthBuffer), "Duration : %d Minutes", ilength);
		}

		int time = Kv.GetNum("TimeStamp");
		int length = Kv.GetNum("Length");
		int totaltime = ((length * 60) + time);
		int lefttime = totaltime - GetTime();
		
		char TimeLeft[32];
		CheckPlayerExpireTime(lefttime, TimeLeft, sizeof(TimeLeft));

		Format(NameBuffer, sizeof(NameBuffer), "Player : %s", sName);
		Format(AdminNameBuffer, sizeof(AdminNameBuffer), "Admin : %s (%s)", sAdminName, AdminSteamID);
		Format(ReasonBuffer, sizeof(ReasonBuffer), "Reason : %s", sReason);
		Format(DateBuffer, sizeof(DateBuffer), "Issued : %s", date);
		Format(MapBuffer, sizeof(MapBuffer), "Map : %s", sCurrentMap);
		if(StrEqual(sLengthEx, "Permanent"))
			Format(TimeLeftBuffer, sizeof(TimeLeftBuffer), "Expire : Never");
		else
			Format(TimeLeftBuffer, sizeof(TimeLeftBuffer), "Expire in: %s", TimeLeft);
		
		menu.AddItem("", NameBuffer, ITEMDRAW_DISABLED);
		menu.AddItem("", AdminNameBuffer, ITEMDRAW_DISABLED);
		menu.AddItem("", LengthBuffer, ITEMDRAW_DISABLED);
		menu.AddItem("", DateBuffer, ITEMDRAW_DISABLED);
		menu.AddItem("", TimeLeftBuffer, ITEMDRAW_DISABLED);
		menu.AddItem("", ReasonBuffer, ITEMDRAW_DISABLED);
		menu.AddItem("", MapBuffer, ITEMDRAW_DISABLED);
	}
	
	menu.ExitButton = true;
	menu.Display(client, 32);
}

//--------------------------------------------------------//
//-----------------------CUSTOM--------------------------//
//-----------------------Natives------------------------//
//-----------------------------------------------------//

stock void KnifeBanClient(int client, int target, int time = 0, const char[] reason = "No Reason")
{
	char sName[MAX_NAME_LENGTH], sAdminName[MAX_NAME_LENGTH], date[128], sCurrentMap[PLATFORM_MAX_PATH], SteamID[32];
	GetClientAuthId(target, AuthId_Steam2, SteamID, sizeof(SteamID));
	
	char AdminSteamID[32];
	if(client != 0)
	{
		GetClientAuthId(client, AuthId_Steam2, AdminSteamID, sizeof(AdminSteamID));
	}
				
	if(time >= 1)
	{
		CPrintToChatAll("%s{white}%N {red}Knife banned {white}%N {red}%d minutes. \n%s Reason: %s.", PLUGIN_PREFIX, client, target, time, PLUGIN_PREFIX, reason);
		LogAction(client, target, "[Knife Ban] \"%L\" has knife banned \"%L\" for \"%d\" minutes (reason: \"%s\")", client, target, time, reason);
		DataPack datapack = new DataPack();
		g_hKnifeBanExpireTime[target] = CreateDataTimer((1.0 * time * 60), KnifeBan_ExpireTimerOnline, datapack);
		datapack.WriteCell(target);
		datapack.WriteString(SteamID);
	}
	else if(time < 0)
	{
		CPrintToChatAll("%s {white}%N {red}Temporarily knife banned {white}%N. \n%s Reason: %s.", PLUGIN_PREFIX, client, target, PLUGIN_PREFIX, reason);
		g_bIsClientKnifeBanned[target] = true;
		LogAction(client, target, "[Knife Ban] \"%L\" has temporarily knife banned \"%L\" (reason: \"%s\")", client, target, reason);
		return;
	}
	else if(time == 0)
	{
		CPrintToChatAll("%s {white}%N {red}Permanently knife banned {white}%N. \n%s Reason: %s.", PLUGIN_PREFIX, client, target, PLUGIN_PREFIX, reason);
		LogAction(client, target, "[Knife Ban] \"%L\" has Permanently knife banned \"%L\" (reason: \"%s\")", client, target, reason);
	}
	
	g_bIsClientKnifeBanned[target] = true;
	GetClientAuthId(target, AuthId_Steam2, SteamID, sizeof(SteamID));
	GetClientName(target, sName, sizeof(sName));
	GetClientName(client, sAdminName, sizeof(sAdminName));
	FormatTime(date, sizeof(date), "%d/%m/%y @ %r", GetTime());
	GetCurrentMap(sCurrentMap, sizeof(sCurrentMap));

	AddPlayerToCFG(SteamID, AdminSteamID, sName, sAdminName, reason, date, sCurrentMap, time);
}

public Action KnifeBan_ExpireTimerOnline(Handle timer, DataPack datapack)
{
	char SteamID[32];
	datapack.Reset();
	int client = datapack.ReadCell();
	datapack.ReadString(SteamID, sizeof(SteamID));
	
	if(IsValidClient(client))
	{
		g_bIsClientKnifeBanned[client] = false;
		g_hKnifeBanExpireTime[client] = null;
		DeletePlayerFromCFG(SteamID);
		CPrintToChat(client, "%s {white}Your Knife ban has {green}expired.", PLUGIN_PREFIX);
	}
	
	return Plugin_Continue;
}
		
stock void KnifeUnBanClient(int client, int target, const char[] reason = "No Reason")
{
	g_bIsClientKnifeBanned[target] = false;
	delete g_hKnifeBanExpireTime[target];
	
	char SteamID[32];
	GetClientAuthId(target, AuthId_Steam2, SteamID, sizeof(SteamID));
	
	DeletePlayerFromCFG(SteamID);
	
	LogAction(client, target, "[Knife Ban] \"%L\" has knife unbanned \"%L\" (reason \"%s\")", client, target, reason);
}

stock void AddPlayerToCFG(const char[] sSteamID, const char[] AdminSteamID = "", const char[] sName, const char[] sAdminName, const char[] reason, const char[] date, const char[] sCurrentMap, int time)
{
	CreateKv();

	Kv.JumpToKey(sSteamID, true);
	Kv.SetString("Name", sName);
	Kv.SetString("Admin Name", sAdminName);
	Kv.SetString("AdminSteamID", AdminSteamID);
	Kv.SetString("Reason", reason);
	if(time <= 0)
	{
		Kv.SetString("LengthEx", "Permanent");
	}
	else if(time >= 1)
	{
		Kv.SetNum("Length", time);
	}
	Kv.SetString("Date", date);
	Kv.SetNum("TimeStamp", GetTime());
	Kv.SetString("Map", sCurrentMap);
	Kv.Rewind();
	Kv.ExportToFile(sPath);
	delete Kv;
}

stock void DeletePlayerFromCFG(const char[] sSteamID)
{
	CreateKv();
	if(Kv.JumpToKey(sSteamID))
	{
		Kv.DeleteThis();
		Kv.Rewind();
		Kv.ExportToFile(sPath);
	}
	
	delete Kv;
}

stock void CreateKv()
{
	Kv = new KeyValues("KnifeBan");
	Kv.ImportFromFile(sPath);
}

stock void CheckPlayerExpireTime(int lefttime, char[] TimeLeft, int maxlength)
{
	if(lefttime > -1)
	{
		if(lefttime < 60) // 60 secs
			Format(TimeLeft, maxlength, "%02i Seconds", lefttime);
		else if(lefttime > 3600 && lefttime <= 3660) // 1 Hour
			Format(TimeLeft, maxlength, "%i Hour %02i Minutes", lefttime / 3600, (lefttime / 60) % 60);
		else if(lefttime > 3660 && lefttime < 86400) // 2 Hours or more
			Format(TimeLeft, maxlength, "%i Hours %02i Minutes", lefttime / 3600, (lefttime / 60) % 60);
		else if(lefttime > 86400 && lefttime <= 172800) // 1 Day
			Format(TimeLeft, maxlength, "%i Day and %02i Hours", lefttime / 86400, (lefttime / 3600) % 24);
		else if(lefttime > 172800) // 2 Days or more
			Format(TimeLeft, maxlength, "%i Days and %02i Hours", lefttime / 86400, (lefttime / 3600) % 24);
		else // Less than 1 Hour
			Format(TimeLeft, maxlength, "%i Minutes and %02i Seconds", lefttime / 60, lefttime % 60);
	}
}

stock int GetCurrentKnifeBannedPlayers()
{
	int count = 0;
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if(IsValidClient(i) && g_bIsClientKnifeBanned[i])
			count++;
	}
	
	return count;
}

stock int GetPlayerFromSteamID(const char[] sSteamID)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if(IsValidClient(i) && IsClientAuthorized(i))
		{
			char SteamID[32];
			GetClientAuthId(i, AuthId_Steam2, SteamID, sizeof(SteamID));
			if(StrEqual(sSteamID, SteamID))
				return i;
		}
	}
	
	return -1;
}

stock int GetAdminOwnKnifeBans(int client, const char[] sSteamID)
{
	int count = 0;
	
	CreateKv();
	if(Kv.GotoFirstSubKey())
	{
		do
		{
			char AdminSteamID[32];
			Kv.GetString("AdminSteamID", AdminSteamID, sizeof(AdminSteamID));
			if(StrEqual(sSteamID, AdminSteamID))
			{
				count++;
			}
		}
		while(Kv.GotoNextKey());
	}
	delete Kv;
	
	return count;
}

stock bool CheckKnifeBanAuthor(int client, const char[] buffer, const char[] sSteamID)
{
	if(CheckCommandAccess(client, "sm_koban", ADMFLAG_RCON, true))
		return true;
	
	char AdminSteamID[32];
	
	CreateKv();
	if(Kv.JumpToKey(buffer))
	{
		Kv.GetString("AdminSteamID", AdminSteamID, sizeof(AdminSteamID));
		if(StrEqual(sSteamID, AdminSteamID))
			return true;
	}
	delete Kv;
	
	return false;
}

stock bool IsSteamIDInGame(const char[] sSteamID)
{
	g_aSteamIDs.Clear();
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if(IsValidClient(i) && IsClientAuthorized(i))
		{
			char SteamID[32];
			GetClientAuthId(i, AuthId_Steam2, SteamID, sizeof(SteamID));
			
			g_aSteamIDs.PushString(SteamID);
		}
	}
	
	if((g_aSteamIDs.FindString(sSteamID) == -1))
		return false;
	
	return true;
}
	
stock bool IsValidClient(int client)
{
	return (1 <= client <= MaxClients && IsClientInGame(client) && !IsClientSourceTV(client));
}
