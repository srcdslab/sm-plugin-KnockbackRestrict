#pragma semicolon 1
#pragma newdecls required

/* Admin Menu */
public void OnAdminMenuReady(Handle aTopMenu) {
	TopMenu topmenu = TopMenu.FromHandle(aTopMenu);
	
	if(g_hAdminMenu == topmenu)
		return;
	
	g_hAdminMenu = topmenu;
	
	TopMenuObject hMenuObj = g_hAdminMenu.AddCategory("KbRestrictCommands", CategoryHandler, "sm_koban", ADMFLAG_KICK);

	if(hMenuObj == INVALID_TOPMENUOBJECT)
		return;
		
	g_hAdminMenu.AddItem("KbRestrict_RestrictPlayer", ItemHandler_RestrictPlayer, hMenuObj, "sm_kban", ADMFLAG_KICK);
	g_hAdminMenu.AddItem("KbRestrict_ListOfKbans", ItemHandler_ListOfKbans, hMenuObj, "sm_kbanlist", ADMFLAG_RCON);
	g_hAdminMenu.AddItem("KbRestrict_OnlineKBanned", ItemHandler_OnlineKBanned, hMenuObj, "sm_kban", ADMFLAG_KICK);
	g_hAdminMenu.AddItem("KbRestrict_OwnBans", ItemHandler_OwnBans, hMenuObj, "sm_kban", ADMFLAG_KICK);
	g_hAdminMenu.AddItem("KbRestrict_OfflineKban", ItemHandler_OfflineKban, hMenuObj, "sm_koban", ADMFLAG_BAN);
}

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
public void CategoryHandler(TopMenu topmenu, TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength) {
	if(action == TopMenuAction_DisplayTitle)
		FormatEx(buffer, maxlength, "[KbRestrict] %t", "Commands");
	else if(action == TopMenuAction_DisplayOption)
		FormatEx(buffer, maxlength, "KbRestrict %t", "Commands");
}

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
public void ItemHandler_RestrictPlayer(TopMenu topmenu, TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength) {
	if(action == TopMenuAction_DisplayOption) 
		FormatEx(buffer, maxlength, "%t", "KBan a player");
	else if(action == TopMenuAction_SelectOption)
		Kban_OpenKbanMenu(param);
}

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
public void ItemHandler_ListOfKbans(TopMenu topmenu, TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength) {
	if(action == TopMenuAction_DisplayOption)
		FormatEx(buffer, maxlength, "%t", "List of KBans");
	else if(action == TopMenuAction_SelectOption) {
		if(CheckCommandAccess(param, "sm_koban", ADMFLAG_RCON, true))
			Kban_OpenAllKbansMenu(param);
		else
			CPrintToChat(param, "%t", "Not have permission KbList");
	}
}

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
public void ItemHandler_OnlineKBanned(TopMenu topmenu, TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength) {
	if(action == TopMenuAction_DisplayOption)
		FormatEx(buffer, maxlength, "%t", "Online KBanned");
	else if(action == TopMenuAction_SelectOption)
		Kban_OpenOnlineKbansMenu(param);
}

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
public void ItemHandler_OwnBans(TopMenu topmenu, TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength) {
	if(action == TopMenuAction_DisplayOption)
		FormatEx(buffer, maxlength, "%t", "Own KbList");
	else if(action == TopMenuAction_SelectOption)
		Kban_OpenOwnKbansMenu(param);
}

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
public void ItemHandler_OfflineKban(TopMenu topmenu, TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength) {
	if(action == TopMenuAction_DisplayOption)
		FormatEx(buffer, maxlength, "%t", "Offline Kban");
	else if(action == TopMenuAction_SelectOption)
		Kban_OpenOfflineKbanMenu(param);
}

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
void Kban_OpenMainMenu(int client) {
	Menu menu = new Menu(Menu_MainMenu);
	menu.SetTitle("[Kb-Restrict] Kban Main Menu");

	char sBuffer[128];
	FormatEx(sBuffer, sizeof(sBuffer), "%t", "KBan a player");
	menu.AddItem("0", sBuffer);

	FormatEx(sBuffer, sizeof(sBuffer), "%t", "List of KBans");
	menu.AddItem("1", sBuffer, CheckCommandAccess(client, "sm_koban", ADMFLAG_RCON, true) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);

	FormatEx(sBuffer, sizeof(sBuffer), "%t", "Online KBanned");
	menu.AddItem("2", sBuffer);

	FormatEx(sBuffer, sizeof(sBuffer), "%t", "Own KbList");
	menu.AddItem("3", sBuffer);

	FormatEx(sBuffer, sizeof(sBuffer), "%t", "Offline Kban");
	menu.AddItem("4", sBuffer);

	menu.ExitButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

void Kban_OpenKbanMenu(int client) {
	Menu menu = new Menu(Menu_KbanMenu);
	menu.SetTitle("[Kb-Restrict] %t", "Restrict a Player");

	for(int i = 1; i <= MaxClients; i++) {
		if(!IsClientInGame(i) || IsFakeClient(i) || IsClientSourceTV(i) || g_bIsClientRestricted[i])
			continue;

		char sBuffer[128], userid[10];
		IntToString(GetClientUserId(i), userid, sizeof(userid));
		FormatEx(sBuffer, sizeof(sBuffer), "%s |#%d", g_sName[i], i);
		menu.AddItem(userid, sBuffer);
	}

	if(menu.ItemCount == 0) {
		char sBuffer[128];
		FormatEx(sBuffer, sizeof(sBuffer), "%t", "No players to restrict");
		menu.AddItem("a", sBuffer, ITEMDRAW_DISABLED);
	}
	
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

void Kban_OpenAllKbansMenu(int client) {
	Menu menu = new Menu(Menu_AllKbansMenu);
	menu.SetTitle("[Kb-Restrict] %t", "All Active KBans");
	
	bool found = false;
	for(int i = 0; i < g_allKbans.Length; i++) {
		Kban info;
		g_allKbans.GetArray(i, info, sizeof(info));
		
		char menuItem[10];
		IntToString(info.id, menuItem, sizeof(menuItem));

		KbanType type = Kban_GetClientKbanType(-1, info.clientSteamID, info.clientIP);

		int target = -1;
		if(type == KBAN_TYPE_IP)
			target = Kban_GetClientByIP(info.clientIP);
		else
			target = Kban_GetClientBySteamID(info.clientSteamID);

		char clientStatus[32];
		FormatEx(clientStatus, sizeof(clientStatus), "%t", (target == -1) ? "Offline" : "Online");

		char clientName[70];
		if(target != -1)
			FormatEx(clientName, sizeof(clientName), "%s(%s)", g_sName[target], info.clientName);
		else
			FormatEx(clientName, sizeof(clientName), "%s", info.clientName);

		char menuBuffer[70];
		FormatEx(menuBuffer, sizeof(menuBuffer), "%s [%s][%s]", clientName, info.clientSteamID, clientStatus);

		menu.AddItem(menuItem, menuBuffer);
		found = true;
	}
	
	if(!found) {
		char sBuffer[64];
		FormatEx(sBuffer, sizeof(sBuffer), "%t", "No KBan Found");
		menu.AddItem("a", sBuffer, ITEMDRAW_DISABLED);
	}

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

void Kban_OpenOnlineKbansMenu(int client) {
	Menu menu = new Menu(Menu_OnlineKbansMenu);
	menu.SetTitle("[Kb-Restrict] %t", "Online KBanned");
	
	bool found = false;
	for(int i = 0; i < g_allKbans.Length; i++) {
		Kban info;
		g_allKbans.GetArray(i, info, sizeof(info));

		KbanType type = Kban_GetClientKbanType(-1, info.clientSteamID, info.clientIP);
		
		int target = -1;
		if(type == KBAN_TYPE_IP)
			target = Kban_GetClientByIP(info.clientIP);
		else
			target = Kban_GetClientBySteamID(info.clientSteamID);

		if(target != -1) {
			char menuItem[10];
			IntToString(info.id, menuItem, sizeof(menuItem));
			
			char clientNameEx[35];
			FormatEx(clientNameEx, sizeof(clientNameEx), "(%s)", info.clientName);

			char menuBuffer[55];
			FormatEx(menuBuffer, sizeof(menuBuffer), "%s%s [%s]", g_sName[target], (strcmp(g_sName[target], info.clientName, false) == 0) ? "" : clientNameEx, info.clientSteamID);
			menu.AddItem(menuItem, menuBuffer);
			found = true;
		}
	}
	
	if(!found) {
		char sBuffer[64];
		FormatEx(sBuffer, sizeof(sBuffer), "%t", "No KBan Found");
		menu.AddItem("a", sBuffer, ITEMDRAW_DISABLED);
	}
	
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);	
}

void Kban_OpenOwnKbansMenu(int client) {
	Menu menu = new Menu(Menu_OwnKbansMenu);
	menu.SetTitle("[Kb-Restrict] %t", "Own KbList");
	
	bool found = false;
	
	for(int i = 0; i < g_allKbans.Length; i++) {
		Kban info;
		g_allKbans.GetArray(i, info, sizeof(info));
		if(strcmp(info.adminSteamID, g_sSteamIDs[client], false) == 0) {
			char menuItem[10];
			IntToString(info.id, menuItem, sizeof(menuItem));

			KbanType type = Kban_GetClientKbanType(-1, info.clientSteamID, info.clientIP);
			int target = -1;
			if(type == KBAN_TYPE_IP)
				target = Kban_GetClientByIP(info.clientIP);
			else
				target = Kban_GetClientBySteamID(info.clientSteamID);

			char clientStatus[8], clientName[70];
			if(target != -1) {
				char clientNameEx[35];
				FormatEx(clientNameEx, sizeof(clientNameEx), "(%s)", info.clientName);
				FormatEx(clientStatus, sizeof(clientStatus), "%t", "Online");
				FormatEx(clientName, sizeof(clientName), "%s%s", g_sName[target], strcmp(g_sName[target], info.clientName, false) == 0 ? "" : clientNameEx);
			} else {
				FormatEx(clientStatus, sizeof(clientStatus), "%t", "Offline");
				FormatEx(clientName, sizeof(clientName), "%s", info.clientName);
			}

			char menuBuffer[70];
			FormatEx(menuBuffer, sizeof(menuBuffer), "%s [%s][%s]", clientName, info.clientSteamID, clientStatus);

			menu.AddItem(menuItem, menuBuffer);
			found = true;
		}
	}
	
	if(!found) {
		char sBuffer[64];
		FormatEx(sBuffer, sizeof(sBuffer), "%t", "No KBan Found");
		menu.AddItem("a", sBuffer, ITEMDRAW_DISABLED);
	}
	
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

int Menu_MainMenu(Menu menu, MenuAction action, int param1, int param2) {
	switch(action) {
		case MenuAction_End: {
			delete menu;
		}
		
		case MenuAction_Select: {
			switch(param2) {
				case 0: {
					Kban_OpenKbanMenu(param1);
				}
				
				case 1: {
					Kban_OpenAllKbansMenu(param1);
				}
				
				case 2: {
					Kban_OpenOnlineKbansMenu(param1);
				}
				
				case 3: {
					Kban_OpenOwnKbansMenu(param1);
				}

				case 4: {
					Kban_OpenOfflineKbanMenu(param1);
				}
			}
		}
	}
	
	return 0;
}

int Menu_KbanMenu(Menu menu, MenuAction action, int param1, int param2) {
	switch(action) {
		case MenuAction_End: {
			delete menu;
		}
		
		case MenuAction_Cancel: {
			if(param2 == MenuCancel_ExitBack) {
				Kban_OpenMainMenu(param1);
			}
		}
		
		case MenuAction_Select: {
			char buffer[10];
			menu.GetItem(param2, buffer, sizeof(buffer));
			int userid = StringToInt(buffer);
			int target = GetClientOfUserId(userid);
			if(IsValidClient(target))
				KR_DisplayLengthsMenu(param1, target, Menu_OnLengthClick);
		}
	}
	
	return 0;
}

int Menu_AllKbansMenu(Menu menu, MenuAction action, int param1, int param2) {
	switch(action) {
		case MenuAction_End: {
			delete menu;
		}
		
		case MenuAction_Cancel: {
			if(param2 == MenuCancel_ExitBack) {
				Kban_OpenMainMenu(param1);
			}
		}
		
		case MenuAction_Select: {
			char buffer[10];
			menu.GetItem(param2, buffer, sizeof(buffer));
			int id = StringToInt(buffer);
			g_iClientPreviousMenu[param1] = 0;
			Kban_OpenKbanInfoMenu(param1, id);
		}
	}
	
	return 0;
}

int Menu_OnlineKbansMenu(Menu menu, MenuAction action, int param1, int param2) {
	switch(action) {
		case MenuAction_End: {
			delete menu;
		}
		
		case MenuAction_Cancel: {
			if(param2 == MenuCancel_ExitBack) {
				Kban_OpenMainMenu(param1);
			}
		}
		
		case MenuAction_Select: {
			char buffer[10];
			menu.GetItem(param2, buffer, sizeof(buffer));
			int id = StringToInt(buffer);
			g_iClientPreviousMenu[param1] = 1;
			Kban_OpenKbanInfoMenu(param1, id);
		}
	}
	
	return 0;
}

int Menu_OwnKbansMenu(Menu menu, MenuAction action, int param1, int param2) {
	switch(action) {
		case MenuAction_End: {
			delete menu;
		}
		
		case MenuAction_Cancel: {
			if(param2 == MenuCancel_ExitBack) {
				Kban_OpenMainMenu(param1);
			}
		}
		
		case MenuAction_Select: {
			char buffer[10];
			menu.GetItem(param2, buffer, sizeof(buffer));
			int id = StringToInt(buffer);
			g_iClientPreviousMenu[param1] = 2;
			Kban_OpenKbanInfoMenu(param1, id);
		}
	}
	
	return 0;
}

void Kban_OpenKbanInfoMenu(int client, int id) {
	Menu menu = new Menu(Menu_KbanInfoMenu);
	
	Kban info;
	if(!Kban_GetKban(KBAN_GET_TYPE_ID, info, id)) {
		return;
	}
	
	menu.SetTitle("[Kb-Restrict] %t", "Infos and Actions", info.clientName);
	
	char dateStart[128], dateEnd[128], duration[20];
	FormatTime(dateStart, sizeof(dateStart), "%d %B %G @ %r", info.time_stamp_start);
	if(info.length == 0) {
		FormatEx(duration, sizeof(duration), "%t", "Permanent");
		FormatEx(dateEnd, sizeof(dateEnd), "%t", "Never");
	} else if(info.length == -1) {
		FormatEx(duration, sizeof(duration), "%t", "Temporary");
		FormatEx(dateEnd, sizeof(dateEnd), "%t", "Until Map End");
	} else {
		FormatEx(duration, sizeof(duration), "%t", "Minutes", info.length);
		FormatTime(dateEnd, sizeof(dateEnd), "%d %B %G @ %r", info.time_stamp_end);
	}
		
	char MenuText[180];

	FormatEx(MenuText, sizeof(MenuText), "%t", "Player Name", info.clientName);
	menu.AddItem("", MenuText, ITEMDRAW_DISABLED);
	FormatEx(MenuText, sizeof(MenuText), "%t", "Player SteamID", info.clientSteamID);
	menu.AddItem("", MenuText, ITEMDRAW_DISABLED);
	FormatEx(MenuText, sizeof(MenuText), "%t", "Admin Name", info.adminName);
	menu.AddItem("", MenuText, ITEMDRAW_DISABLED);
	FormatEx(MenuText, sizeof(MenuText), "%t", "Admin SteamID", info.adminSteamID);
	menu.AddItem("", MenuText, ITEMDRAW_DISABLED);
	FormatEx(MenuText, sizeof(MenuText), "%t", "Reason", info.reason);
	menu.AddItem("", MenuText, ITEMDRAW_DISABLED);
	FormatEx(MenuText, sizeof(MenuText), "%t", "Issued Map", info.map);
	menu.AddItem("", MenuText, ITEMDRAW_DISABLED);
	FormatEx(MenuText, sizeof(MenuText), "%t", "Duration", duration);
	menu.AddItem("", MenuText, ITEMDRAW_DISABLED);
	FormatEx(MenuText, sizeof(MenuText), "%t", "Date Issued", dateStart);
	menu.AddItem("", MenuText, ITEMDRAW_DISABLED);
	FormatEx(MenuText, sizeof(MenuText), "%t", "Date Expires", dateEnd);
	menu.AddItem("", MenuText, ITEMDRAW_DISABLED);
	
	bool canUnban = false;
	if(CheckCommandAccess(client, "sm_admin", ADMFLAG_RCON, true)) {
		canUnban = true;
	}
	
	if(!canUnban && strcmp(info.adminSteamID, g_sSteamIDs[client], false) == 0) {
		canUnban = true;
	}
	
	// Todo: Add Edit lenght and reason support via menu
	char menuBuffer[40], sBuffer[64];
	FormatEx(menuBuffer, sizeof(menuBuffer), "%s|%s", info.clientSteamID, info.clientIP);
	FormatEx(sBuffer, sizeof(sBuffer), "%t", "UnRestrict Player");
	menu.AddItem(menuBuffer, sBuffer, (canUnban) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

int Menu_KbanInfoMenu(Menu menu, MenuAction action, int param1, int param2) {
	switch(action) {
		case MenuAction_End: {
			delete menu;
		}
		
		case MenuAction_Cancel: {
			if(param2 == MenuCancel_ExitBack) {
				switch(g_iClientPreviousMenu[param1]) {
					case 0: {
						Kban_OpenAllKbansMenu(param1);
					}
					
					case 1: {
						Kban_OpenOnlineKbansMenu(param1);
					}
					
					case 2: {
						Kban_OpenOwnKbansMenu(param1);
					}
				}
			}
		}
		
		case MenuAction_Select: {
			char buffer[40];
			menu.GetItem(param2, buffer, sizeof(buffer));
			
			char buffers[2][20]; // buffers[0] = steamid | buffers[1] = ip 
			ExplodeString(buffer, "|", buffers, 2, sizeof(buffers[]));
			KbanType type = Kban_GetClientKbanType(-1, buffers[0], buffers[1]);

			int target = -1;
			if(type == KBAN_TYPE_IP)
				target = Kban_GetClientByIP(buffers[1]);
			else
				target = Kban_GetClientBySteamID(buffers[0]);

			char sReason[64];
			sReason = "No reason";
			if(target != -1) {
				Kban_RemoveBan(target, param1, sReason);
			} else {
				char escapedName[MAX_NAME_LENGTH * 2 + 1];
				if(!g_hDB.Escape(g_sName[param1], escapedName, sizeof(escapedName))) {
					return 0;
				}

				char query[MAX_QUERIE_LENGTH];
				g_hDB.Format(query, sizeof(query),  "UPDATE `KbRestrict_CurrentBans` SET `is_expired`=1, `is_removed`=1,"
												... "`admin_name_removed`='%s', `admin_steamid_removed`='%s', `reason_removed`,"
												... "`time_stamp_removed`=%d",
													escapedName, g_sSteamIDs[param1], sReason, GetTime());

				g_hDB.Query(OnKbanRemove, query);
			}
		}
	}

	return 0;
}

stock void AddLength(Menu menu, int time, const char[] sUnitSingle, const char[] sUnitPlural, int maxTime) {
	if (maxTime == 0 || time <= maxTime)
	{
		char buffer[32], sDuration[64];
		IntToString(time, buffer, sizeof(buffer));

		if (time >= 60 && time < 1440)
			time /= 60;
		else if (time >= 1440 && time < 10080)
			time /= 1440;
		else if (time >= 10080 && time < 40320)
			time /= 10080;
		else if (time >= 40320)
			time /= 40320;

		FormatEx(sDuration, sizeof(sDuration), time == 1 ? sUnitSingle : sUnitPlural);
		FormatEx(sDuration, sizeof(sDuration), "%t", sDuration, time);
		menu.AddItem(buffer, sDuration);
	}
}

void DisplayLengths_Menu(int client) {
	Menu menu = new Menu(Menu_KbRestrict_Lengths);
	menu.SetTitle("[Kb-Restrict] %t", "KBan Duration", g_sName[GetClientOfUserId(g_iClientTarget[client])]);
	menu.ExitBackButton = true;

	// -1 Will return the max time the admin can give based on his access
	int iMaxTime = Kban_CheckKbanAdminAccess(client, -1);

	char sBuffer[64];
	FormatEx(sBuffer, sizeof(sBuffer), "%t", "Permanently");
	menu.AddItem("0", sBuffer, iMaxTime == 0 ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);

	FormatEx(sBuffer, sizeof(sBuffer), "%t", "Temporary");
	menu.AddItem("-1", sBuffer);

	for (int i = 15; i < 241920; i++) {
		if (i == 15 || i == 30 || i == 45) {
			AddLength(menu, i, "Minute", "Minutes", iMaxTime);
		} else if (i == 60 || i == 120 || i == 240 || i == 480 || i == 720) {
			AddLength(menu, i, "Hour", "Hours", iMaxTime);
		} else if (i == 1440 || i == 2880 || i == 4320 || i == 5760 || i == 7200 || i == 8640) {
			AddLength(menu, i, "Day", "Days", iMaxTime);
		} else if (i == 10080 || i == 20160 || i == 30240) {
			AddLength(menu, i, "Week", "Weeks", iMaxTime);
		} else if (i == 40320 || i == 80640 || i == 120960 || i == 241920) {
			AddLength(menu, i, "Month", "Months", iMaxTime);
		}
	}

	menu.Display(client, MENU_TIME_FOREVER);
}

//----------------------------------------------------------------------------------------------------
// Menu :
//----------------------------------------------------------------------------------------------------
int Menu_KbRestrict_Lengths(Menu menu, MenuAction action, int param1, int param2)
{
	switch(action)
	{
		case MenuAction_End:
			delete menu;

		case MenuAction_Cancel:
		{
			if(param2 == MenuCancel_ExitBack)
				Kban_OpenKbanMenu(param1);
		}

		case MenuAction_Select:
		{
			char buffer[64];
			menu.GetItem(param2, buffer, sizeof(buffer));
			int time = StringToInt(buffer);
			int target = GetClientOfUserId(g_iClientTarget[param1]);

			if(!target)
				return 0;

			if(IsValidClient(target))
			{
				Call_StartForward(g_hLengthsMenuForward);

				Call_PushCell(param1);
				Call_PushCell(target);
				Call_PushCell(time);

				Call_Finish();
			}
		}
	}
	
	return 0;
}

void Menu_OnLengthClick(int admin, int target, int time)
{
	if (!g_bIsClientRestricted[target])
	{
		g_iClientTargetLength[admin] = time;
		DisplayReasons_Menu(admin);
	}
}

//----------------------------------------------------------------------------------------------------
// Menu :
//----------------------------------------------------------------------------------------------------
void DisplayReasons_Menu(int client)
{
	Menu menu = new Menu(Menu_Reasons);
	menu.SetTitle("[Kb-Restrict] %t", "KBan Reason for", g_sName[GetClientOfUserId(g_iClientTarget[client])], g_iClientTargetLength[client]);
	menu.ExitBackButton = true;
	
	char sBuffer[128];
	FormatEx(sBuffer, sizeof(sBuffer), "%s", "Boosting", client);
	menu.AddItem(sBuffer, sBuffer);
	
	FormatEx(sBuffer, sizeof(sBuffer), "%s", "Trying To Boost", client);
	menu.AddItem(sBuffer, sBuffer);

	FormatEx(sBuffer, sizeof(sBuffer), "%s", "Trimming team", client);
	menu.AddItem(sBuffer, sBuffer);

	FormatEx(sBuffer, sizeof(sBuffer), "%s", "Trolling on purpose", client);
	menu.AddItem(sBuffer, sBuffer);
	
	FormatEx(sBuffer, sizeof(sBuffer), "%s", "Custom Reason", client);
	menu.AddItem("4", sBuffer);
	
	menu.Display(client, MENU_TIME_FOREVER);
}

//----------------------------------------------------------------------------------------------------
// Menu :
//----------------------------------------------------------------------------------------------------
int Menu_Reasons(Menu menu, MenuAction action, int param1, int param2)
{
	switch(action)
	{
		case MenuAction_End:
		{
			delete menu;
		}
		
		case MenuAction_Cancel:
		{		
			if(param2 == MenuCancel_ExitBack)
			{
				g_bIsClientTypingReason[param1] = false;

				int target = GetClientOfUserId(g_iClientTarget[param1]);

				if(!target)
					return 0;

				if (IsValidClient(target))
					KR_DisplayLengthsMenu(param1, target, Menu_OnLengthClick);
				else
					CPrintToChat(param1, "%s %T", KR_Tag, "PlayerNotValid", param1);
			}
		}
		
		case MenuAction_Select:
		{
			int target = GetClientOfUserId(g_iClientTarget[param1]);
			if(!target)
					return 0;
					
			if(param2 == 4)
			{			
				if(IsValidClient(target))
				{
					if(!g_bIsClientRestricted[target])
					{
						CPrintToChat(param1, "%t", "ChatReason");
						g_bIsClientTypingReason[param1] = true;
					}
					else
						CPrintToChat(param1, "%t.", "AlreadyKBanned");
				}
				else
					CPrintToChat(param1, "%t", "PlayerNotValid");
			}
			else
			{	
				char buffer[128];
				menu.GetItem(param2, buffer, sizeof(buffer));
				
				if(IsValidClient(target)) {
					Kban_AddBan(target, param1, g_iClientTargetLength[param1], buffer);
				}
			}
		}
	}
	
	return 0;
}

void Kban_OpenOfflineKbanMenu(int client, const char[] arg = "") {
	Menu menu = new Menu(Menu_OfflineKbanMenu);
	menu.SetTitle("[Kb-Restrict] Offline Kban");
	
	bool found = false;
	for(int i = 0; i < g_OfflinePlayers.Length; i++) {
		OfflinePlayer player;
		g_OfflinePlayers.GetArray(i, player, sizeof(player));
		if(IsSteamIDBanned(player.steamID) || IsIPBanned(player.ip)) {
			continue;
		}
		
		
		if(arg[0]) {
			if(StrContains(player.name, arg, false)) {
				char menuBuffer[40];
				FormatEx(menuBuffer, sizeof(menuBuffer), "%s |#%d", player.name, player.userid);
				menu.AddItem(player.steamID, menuBuffer);
				found = true;
				continue;
			}
		}
		
		char menuBuffer[40];
		FormatEx(menuBuffer, sizeof(menuBuffer), "%s |#%d", player.name, player.userid);
		menu.AddItem(player.steamID, menuBuffer);
		found = true;
	}
	
	if(!found) {
		menu.AddItem("a", "No Offline Players", ITEMDRAW_DISABLED);
	}
	
	menu.ExitButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

int Menu_OfflineKbanMenu(Menu menu, MenuAction action, int param1, int param2) {
	switch(action) {
		case MenuAction_End: {
			delete menu;
		}
		
		case MenuAction_Select: {
			char steamID[20];
			menu.GetItem(param2, steamID, sizeof(steamID));
			int target = Kban_GetClientBySteamID(steamID);
			if(target != -1) {
				Kban_AddBan(target, param1, 120, "Knifing");
			} else {
				for(int i = 0; i < g_OfflinePlayers.Length; i++) {
					OfflinePlayer player;
					g_OfflinePlayers.GetArray(i, player, sizeof(player));
					if(strcmp(steamID, player.steamID, false) == 0) {
						Kban_AddOfflineBan(player, param1, 120, "Knifing");
					}
				}
			}
		}
	}
	
	return 0;
}

public Action OnClientSayCommand(int client, const char[] command, const char[] sArgs)
{
	if(!client)
		return Plugin_Continue;

	if(!IsValidClient(client))
		return Plugin_Continue;
	
	if(!g_bIsClientTypingReason[client])
		return Plugin_Continue;
		
	int target = GetClientOfUserId(g_iClientTarget[client]);
	int length = g_iClientTargetLength[client];

	if(!target)
		return Plugin_Continue;

	if(strcmp(command, "say", false) == 0 || strcmp(command, "say_team", false) == 0)
	{
		if(!IsValidClient(target))
		{
			CPrintToChat(client, "%t", "PlayerNotValid");
			g_bIsClientTypingReason[client] = false;
			return Plugin_Handled;
		}
	
		if(g_bIsClientRestricted[target])
		{
			CPrintToChat(client, "%t", "AlreadyKBanned");
			g_bIsClientTypingReason[client] = false;
			return Plugin_Handled;
		}
	
		char buffer[128];
		strcopy(buffer, sizeof(buffer), sArgs);
		StripQuotes(buffer);
		
		if(strlen(buffer) <= 3) {
			CPrintToChat(client, "Reason has to be over 3 characters!");
			return Plugin_Handled;
		}
		
		Kban_AddBan(target, client, length, buffer);
		
		g_bIsClientTypingReason[client] = false;
		return Plugin_Handled;
	}
	
	return Plugin_Continue;
}
