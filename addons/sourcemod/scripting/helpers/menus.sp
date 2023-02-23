#pragma semicolon 1
#pragma newdecls required

/* Admin Menu */
public void OnAdminMenuReady(Handle aTopMenu)
{
	TopMenu topmenu = TopMenu.FromHandle(aTopMenu);
	
	if(g_hAdminMenu == topmenu)
		return;
	
	g_hAdminMenu = topmenu;
	
	TopMenuObject hMenuObj = g_hAdminMenu.AddCategory("KbRestrictCommands", CategoryHandler, "sm_koban", ADMFLAG_BAN);

	if(hMenuObj == INVALID_TOPMENUOBJECT)
		return;
		
	g_hAdminMenu.AddItem("KbRestrict_RestrictPlayer", ItemHandler_RestrictPlayer, hMenuObj, "sm_koban", ADMFLAG_BAN);
	g_hAdminMenu.AddItem("KbRestrict_ListOfKbans", ItemHandler_ListOfKbans, hMenuObj, "sm_koban", ADMFLAG_RCON);
	g_hAdminMenu.AddItem("KbRestrict_OnlineKBanned", ItemHandler_OnlineKBanned, hMenuObj, "sm_koban", ADMFLAG_BAN);
	g_hAdminMenu.AddItem("KbRestrict_OwnBans", ItemHandler_OwnBans, hMenuObj, "sm_koban", ADMFLAG_BAN);
}

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
public void CategoryHandler(TopMenu topmenu, 
      TopMenuAction action,
      TopMenuObject object_id,
      int param,
      char[] buffer,
      int maxlength)
{
	if(action == TopMenuAction_DisplayTitle)
	{
		strcopy(buffer, maxlength, "KbRestrict Commands Main Menu");
	}
	else if(action == TopMenuAction_DisplayOption)
	{
		strcopy(buffer, maxlength, "KbRestrict Commands");
	}
}

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
public void ItemHandler_RestrictPlayer(TopMenu topmenu, 
      TopMenuAction action,
      TopMenuObject object_id,
      int param,
      char[] buffer,
      int maxlength)
{
	if(action == TopMenuAction_DisplayOption)
	{
		strcopy(buffer, maxlength, "KBan a Player");
	}
	else if(action == TopMenuAction_SelectOption)
	{
		Kban_OpenKbanMenu(param);
	}
}

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
public void ItemHandler_ListOfKbans(TopMenu topmenu, 
      TopMenuAction action,
      TopMenuObject object_id,
      int param,
      char[] buffer,
      int maxlength)
{
	if(action == TopMenuAction_DisplayOption)
	{
		strcopy(buffer, maxlength, "List of KBans");
	}
	else if(action == TopMenuAction_SelectOption)
	{
		if(CheckCommandAccess(param, "sm_koban", ADMFLAG_RCON, true))
		{
			Kban_OpenAllKbansMenu(param);
		}
		else
		{
			CPrintToChat(param, "%s You don't have access to view the KBan List.", KR_Tag);
		}
	}
}

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
public void ItemHandler_OnlineKBanned(TopMenu topmenu, 
      TopMenuAction action,
      TopMenuObject object_id,
      int param,
      char[] buffer,
      int maxlength)
{
	if(action == TopMenuAction_DisplayOption)
	{
		strcopy(buffer, maxlength, "Online KBanned");
	}
	else if(action == TopMenuAction_SelectOption)
	{
		Kban_OpenOnlineKbansMenu(param);
	}
}

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
public void ItemHandler_OwnBans(TopMenu topmenu, 
      TopMenuAction action,
      TopMenuObject object_id,
      int param,
      char[] buffer,
      int maxlength)
{
	if(action == TopMenuAction_DisplayOption)
	{
		strcopy(buffer, maxlength, "Your Own List of KBans");
	}
	else if(action == TopMenuAction_SelectOption)
	{
		Kban_OpenOwnKbansMenu(param);
	}
}

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
void Kban_OpenMainMenu(int client) {
	Menu menu = new Menu(Menu_MainMenu);
	menu.SetTitle("[Kb-Restrict] Kban Main Menu");
	
	menu.AddItem("0", "Kban a Player");
	menu.AddItem("1", "List of Kbans", CheckCommandAccess(client, "sm_koban", ADMFLAG_RCON, true) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	menu.AddItem("2", "Online KBanned");
	menu.AddItem("3", "Your Own List of Kbans");
	
	menu.ExitButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

void Kban_OpenKbanMenu(int client) {
	Menu menu = new Menu(Menu_KbanMenu);
	menu.SetTitle("[Kb-Restrict] Restrict a Player");
	
	for(int i = 1; i <= MaxClients; i++) {
		if(!IsClientInGame(i)) {
			continue;
		}
		
		if(g_bIsClientRestricted[i]) {
			continue;
		}
		
		char userid[10];
		IntToString(GetClientUserId(i), userid, sizeof(userid));
		
		char name[32];
		if(!GetClientName(i, name, sizeof(name))) {
			continue;
		}
		
		menu.AddItem(userid, name);
	}
	
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

void Kban_OpenAllKbansMenu(int client) {
	Menu menu = new Menu(Menu_AllKbansMenu);
	menu.SetTitle("[Kb-Restrict] All Active KBans");
	
	bool found = false;
	for(int i = 0; i < g_allKbans.Length; i++) {
		Kban info;
		g_allKbans.GetArray(i, info, sizeof(info));
		
		char menuItem[10];
		IntToString(info.id, menuItem, sizeof(menuItem));
		
		char menuBuffer[70];
		
		KbanType type = Kban_GetClientKbanType(-1, info.clientSteamID, info.clientIP);
		int target = -1;
		if(type == KBAN_TYPE_IP) {
			target = Kban_GetClientByIP(info.clientIP);
		} else {
			target = Kban_GetClientBySteamID(info.clientSteamID);
		}
		
		char clientStatus[8];
		clientStatus = (target == -1) ? "Offline" : "Online";
		
		char clientName[70];
		if(target != -1) {
			char clientNameEx[32];
			GetClientName(target, clientNameEx, sizeof(clientNameEx));
			FormatEx(clientName, sizeof(clientName), "%s(%s)", clientNameEx, info.clientName);
		} else {
			FormatEx(clientName, sizeof(clientName), "%s", info.clientName);
		}
		
		FormatEx(menuBuffer, sizeof(menuBuffer), "%s [%s][%s]", clientName, info.clientSteamID, clientStatus);
		
		menu.AddItem(menuItem, menuBuffer);
		found = true;
	}
	
	if(!found) {
		menu.AddItem("a", "No KBan Found!", ITEMDRAW_DISABLED);
	}
	
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

void Kban_OpenOnlineKbansMenu(int client) {
	Menu menu = new Menu(Menu_OnlineKbansMenu);
	menu.SetTitle("[Kb-Restrict] Online KBans");
	
	bool found = false;
	for(int i = 0; i < g_allKbans.Length; i++) {
		Kban info;
		g_allKbans.GetArray(i, info, sizeof(info));

		KbanType type = Kban_GetClientKbanType(-1, info.clientSteamID, info.clientIP);
		
		int target = -1;
		if(type == KBAN_TYPE_IP) {
			target = Kban_GetClientByIP(info.clientIP);
		} else {
			target = Kban_GetClientBySteamID(info.clientSteamID);
		}

		if(target != -1) {
			char menuItem[10];
			IntToString(info.id, menuItem, sizeof(menuItem));
			
			char clientName[32];
			GetClientName(target, clientName, sizeof(clientName));
			
			char clientNameEx[35];
			FormatEx(clientNameEx, sizeof(clientNameEx), "(%s)", info.clientName);
			
			char menuBuffer[55];
			FormatEx(menuBuffer, sizeof(menuBuffer), "%s%s [%s]", clientName, (StrEqual(clientName, info.clientName)) ? "" : clientNameEx, info.clientSteamID);
			menu.AddItem(menuItem, menuBuffer);
			found = true;
		}
	}
	
	if(!found) {
		menu.AddItem("a", "No KBan Found!", ITEMDRAW_DISABLED);
	}
	
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);	
}

void Kban_OpenOwnKbansMenu(int client) {
	Menu menu = new Menu(Menu_OwnKbansMenu);
	menu.SetTitle("[Kb-Restrict] Own KBans");
	
	char steamID[20];
	if(!GetClientAuthId(client, AuthId_Steam2, steamID, sizeof(steamID))) {
		return;
	}
	
	bool found = false;
	
	for(int i = 0; i < g_allKbans.Length; i++) {
		Kban info;
		g_allKbans.GetArray(i, info, sizeof(info));
		if(StrEqual(info.adminSteamID, steamID)) {
			char menuItem[10];
			IntToString(info.id, menuItem, sizeof(menuItem));
			
			char menuBuffer[70];
			
			KbanType type = Kban_GetClientKbanType(-1, info.clientSteamID, info.clientIP);
			int target = -1;
			if(type == KBAN_TYPE_IP) {
				target = Kban_GetClientByIP(info.clientIP);
			} else {
				target = Kban_GetClientBySteamID(info.clientSteamID);
			}
			
			char clientStatus[8];
			clientStatus = (target == -1) ? "Offline" : "Online";
			
			char clientName[70];
			if(target != -1) {
				char clientNameEx[32];
				GetClientName(target, clientNameEx, sizeof(clientNameEx));
				FormatEx(clientName, sizeof(clientName), "%s(%s)", clientNameEx, info.clientName);
			} else {
				FormatEx(clientName, sizeof(clientName), "%s", info.clientName);
			}
			
			FormatEx(menuBuffer, sizeof(menuBuffer), "%s [%s][%s]", clientName, info.clientSteamID, clientStatus);
			
			menu.AddItem(menuItem, menuBuffer);
			found = true;
		}
	}
	
	if(!found) {
		menu.AddItem("a", "No KBan Found!", ITEMDRAW_DISABLED);
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
			g_iClientTarget[param1] = userid;
			DisplayLengths_Menu(param1);
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
	
	char steamID[20];
	if(!GetClientAuthId(client, AuthId_Steam2, steamID, sizeof(steamID))) {
		return;
	}
	
	menu.SetTitle("[Kb-Restrict] Kban Info and Actions for %s[%s]", info.clientName, info.clientSteamID);
	
	char dateStart[128];
	char dateEnd[128];
	char duration[20];
	
	FormatTime(dateStart, sizeof(dateStart), "%d %B %G @ %r", info.time_stamp_start);
	if(info.length == 0) {
		duration = "Permanent";
		dateEnd = "Never"; 
	} else if(info.length == -1) {
		duration = "Session";
		dateEnd = "When Current Map Ends";
	} else {
		FormatEx(duration, sizeof(duration), "%d Minutes", info.length);
		FormatTime(dateEnd, sizeof(dateEnd), "%d %B %G @ %r", info.time_stamp_end);
	}
		
	char MenuText[180];
	
	Format(MenuText, sizeof(MenuText), "Player Name : %s", info.clientName);
	menu.AddItem("", MenuText, ITEMDRAW_DISABLED);
	Format(MenuText, sizeof(MenuText), "Player SteamID : %s", info.clientSteamID);
	menu.AddItem("", MenuText, ITEMDRAW_DISABLED);
	Format(MenuText, sizeof(MenuText), "Admin Name : %s", info.adminName);
	menu.AddItem("", MenuText, ITEMDRAW_DISABLED);
	Format(MenuText, sizeof(MenuText), "Admin SteamID : %s", info.adminSteamID);
	menu.AddItem("", MenuText, ITEMDRAW_DISABLED);
	Format(MenuText, sizeof(MenuText), "Reason : %s", info.reason);
	menu.AddItem("", MenuText, ITEMDRAW_DISABLED);
	Format(MenuText, sizeof(MenuText), "Issued on Map : %s", info.map);
	menu.AddItem("", MenuText, ITEMDRAW_DISABLED);
	Format(MenuText, sizeof(MenuText), "Duration : %s", duration);
	menu.AddItem("", MenuText, ITEMDRAW_DISABLED);
	Format(MenuText, sizeof(MenuText), "Date Issued : %s", dateStart);
	menu.AddItem("", MenuText, ITEMDRAW_DISABLED);
	Format(MenuText, sizeof(MenuText), "Date End : %s", dateEnd);
	menu.AddItem("", MenuText, ITEMDRAW_DISABLED);
	
	bool canUnban = false;
	if(CheckCommandAccess(client, "sm_admin", ADMFLAG_RCON, true)) {
		canUnban = true;
	}
	
	if(!canUnban && StrEqual(info.adminSteamID, steamID)) {
		canUnban = true;
	}
	
	char menuBuffer[40];
	FormatEx(menuBuffer, sizeof(menuBuffer), "%s|%s", info.clientSteamID, info.clientIP);
	menu.AddItem(menuBuffer, "Kb-UnRestrict Player", (canUnban) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	
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
			
			char buffers[2][20];
			ExplodeString(buffer, "|", buffers, 2, sizeof(buffers[]));
			/*
				buffers[0] = steamid
				buffers[1] = ip 
			*/
			
			KbanType type = Kban_GetClientKbanType(-1, buffers[0], buffers[1]);
			
			int target = -1;
			if(type == KBAN_TYPE_IP) {
				target = Kban_GetClientByIP(buffers[1]);
			} else {
				target = Kban_GetClientBySteamID(buffers[0]);
			}
			
			if(target != -1) {
				Kban_RemoveBan(target, param1, "Giving another chance");
			} else {
				char steamID[20];
				if(!GetClientAuthId(param1, AuthId_Steam2, steamID, sizeof(steamID))) {
					return 0;
				}
				
				char name[32];
				if(!GetClientName(param1, name, sizeof(name))) {
					return 0;
				}
				
				char escapedName[32 * 2 + 1];
				if(!g_hDB.Escape(name, escapedName, sizeof(escapedName))) {
					return 0;
				}
				
				char query[1024];
				g_hDB.Format(query, sizeof(query),  "UPDATE `KbRestrict_CurrentBans` SET `is_expired`=1, `is_removed`=1,"
												... "`admin_name_removed`='%s', `admin_steamid_removed`='%s', `reason_removed`,"
												... "`time_stamp_removed`=%d",
													escapedName, steamID, "Giving another chance", GetTime());
													
				g_hDB.Query(OnKbanRemove, query);
			}
		}
	}
	
	return 0;
}

void DisplayLengths_Menu(int client)
{
	Menu menu = new Menu(Menu_KbRestrict_Lengths);
	menu.SetTitle("[Kb-Restrict] KBan Duration");
	menu.ExitBackButton = true;
	
	char LengthBufferP[64], LengthBufferT[64];
	FormatEx(LengthBufferP, sizeof(LengthBufferP), "%s", "Permanently");
	FormatEx(LengthBufferT, sizeof(LengthBufferT), "%s", "Temporary");
	
	menu.AddItem("0", LengthBufferP, CheckCommandAccess(client, "sm_rcon", ADMFLAG_RCON, true) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	menu.AddItem("-1", LengthBufferT);
	
	for(int i = 15; i >= 15 && i < 241920; i++)
	{
		if(i == 15 || i == 30 || i == 45)
		{
			if(!Kban_CheckKbanMaxLength(client, i)) {
				continue;
			}
			
			char buffer[32], text[32];
			IntToString(i, buffer, sizeof(buffer));
			FormatEx(text, sizeof(text), "%d %s", i, "Minutes");
			menu.AddItem(buffer, text);
		}
		else if(i == 60)
		{
			if(!Kban_CheckKbanMaxLength(client, i)) {
				continue;
			}
			
			char buffer[32], text[32];
			IntToString(i, buffer, sizeof(buffer));
			int hour = (i / 60);
			FormatEx(text, sizeof(text), "%d %s", hour, "Hour");
			menu.AddItem(buffer, text);
		}
		else if(i == 120 || i == 240 || i == 480 || i == 720)
		{
			if(!Kban_CheckKbanMaxLength(client, i)) {
				continue;
			}
				
			char buffer[32], text[32];
			IntToString(i, buffer, sizeof(buffer));
			int hour = (i / 60);
			FormatEx(text, sizeof(text), "%d %s", hour, "Hours");
			menu.AddItem(buffer, text);
		}
		else if(i == 1440)
		{
			if(!Kban_CheckKbanMaxLength(client, i)) {
				continue;
			}
			
			char buffer[32], text[32];
			IntToString(i, buffer, sizeof(buffer));
			int day = (i / 1440);
			FormatEx(text, sizeof(text), "%d %s", day, "Day");
			menu.AddItem(buffer, text);
		}
		else if(i == 2880 || i == 4320 || i == 5760 || i == 7200 || i == 8640)
		{
			if(!Kban_CheckKbanMaxLength(client, i)) {
				continue;
			}
			
			char buffer[32], text[32];
			IntToString(i, buffer, sizeof(buffer));
			int day = (i / 1440);
			FormatEx(text, sizeof(text), "%d %s", day, "Days");
			menu.AddItem(buffer, text);
		}
		else if(i == 10080)
		{
			if(!Kban_CheckKbanMaxLength(client, i)) {
				continue;
			}
			
			char buffer[32], text[32];
			IntToString(i, buffer, sizeof(buffer));
			int week = (i / 10080);
			FormatEx(text, sizeof(text), "%d %s", week, "Week");
			menu.AddItem(buffer, text);
		}
		else if(i == 20160 || i == 30240)
		{
			if(!Kban_CheckKbanMaxLength(client, i)) {
				continue;
			}
			
			char buffer[32], text[32];
			IntToString(i, buffer, sizeof(buffer));
			int week = (i / 10080);
			FormatEx(text, sizeof(text), "%d %s", week, "Weeks");
			menu.AddItem(buffer, text);
		}
		else if(i == 40320)
		{
			if(!Kban_CheckKbanMaxLength(client, i)) {
				continue;
			}
			
			char buffer[32], text[32];
			IntToString(i, buffer, sizeof(buffer));
			int month = (i / 40320);
			FormatEx(text, sizeof(text), "%d %s", month, "Month");
			menu.AddItem(buffer, text);
		}
		else if(i == 80640 || i == 120960 || i == 241920)
		{
			if(!Kban_CheckKbanMaxLength(client, i)) {
				continue;
			}
			
			char buffer[32], text[32];
			IntToString(i, buffer, sizeof(buffer));
			int month = (i / 40320);
			FormatEx(text, sizeof(text), "%d %s", month, "Months");
			menu.AddItem(buffer, text);
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
				g_iClientTargetLength[param1] = time;
				DisplayReasons_Menu(param1);
			}
		}
	}
	
	return 0;
}

//----------------------------------------------------------------------------------------------------
// Menu :
//----------------------------------------------------------------------------------------------------
void DisplayReasons_Menu(int client)
{
	Menu menu = new Menu(Menu_Reasons);
	char sMenuTranslate[128];
	FormatEx(sMenuTranslate, sizeof(sMenuTranslate), "[Kb-Restrict] Please Select a Reason");
	menu.SetTitle(sMenuTranslate);
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
			g_bIsClientTypingReason[param1] = false;
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

				if(IsValidClient(target))
					DisplayLengths_Menu(param1);
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
				FormatEx(menuBuffer, sizeof(menuBuffer), "%s (# %d)", player.name, player.userid);
				menu.AddItem(player.steamID, menuBuffer);
				found = true;
				continue;
			}
		}
		
		char menuBuffer[40];
		FormatEx(menuBuffer, sizeof(menuBuffer), "%s (# %d)", player.name, player.userid);
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
					if(StrEqual(steamID, player.steamID)) {
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

	if(StrEqual(command, "say") || StrEqual(command, "say_team"))
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
