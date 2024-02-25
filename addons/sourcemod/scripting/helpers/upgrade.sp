#pragma semicolon 1
#pragma newdecls required

public void OnPluginStart_Upgrade() {
	char sPluginVersion[256];
	GetPluginInfo(INVALID_HANDLE, PlInfo_Version, sPluginVersion, sizeof(sPluginVersion));

	if (strcmp(sPluginVersion, "3.4.0", false) == 0){
		RegAdminCmd("sm_kupdate_tables", Command_UpdateTables, ADMFLAG_ROOT, "Update the tables structure in the database.");
		LogMessage("An update of tables is avaiable, did you already run it? (sm_kupdate_tables)");
	}
}

public Action Command_UpdateTables(int client, int args) {
	if(g_hDB == null) {
		ReplyToCommand(client, "Database not connected. Aborting.");
		return Plugin_Handled;
	}
	
	ReplyToCommand(client, "Starting Updating tables...(check logs for details)");

	UpdateTable_CurrentBans();
	UpdateTable_ServerLogs();
	UpdateTable_WebLogs();

	return Plugin_Handled;
}

stock void UpdateTable_CurrentBans() {
	if(g_hDB == null) {
		LogError("Database connection has been lost during update of \"KbRestrict_CurrentBans\"");
		LogError("Please verify the connection and run again the update.");
		return;
	}

	LogMessage("Start updating \"KbRestrict_CurrentBans\" ..");

	char query[MAX_QUERIE_LENGTH];
	g_hDB.Format(query, sizeof(query),
		"ALTER TABLE `KbRestrict_CurrentBans` \
		MODIFY COLUMN `client_name` varchar(%d) NOT NULL, \
		MODIFY COLUMN `client_steamid` varchar(%d) NOT NULL, \
		MODIFY COLUMN `client_ip` varchar(%d) NOT NULL, \
		MODIFY COLUMN `admin_name` varchar(%d) NOT NULL, \
		MODIFY COLUMN `admin_steamid` varchar(%d) NOT NULL, \
		MODIFY COLUMN `reason` varchar(%d) NOT NULL, \
		MODIFY COLUMN `map` varchar(%d) NOT NULL, \
		MODIFY COLUMN `admin_name_removed` varchar(%d) NOT NULL, \
		MODIFY COLUMN `admin_steamid_removed` varchar(%d) NOT NULL, \
		MODIFY COLUMN `reason_removed` varchar(%d) NOT NULL;", 
		MAX_NAME_LENGTH, MAX_AUTHID_LENGTH, MAX_IP_LENGTH, // Client
		MAX_NAME_LENGTH, MAX_AUTHID_LENGTH, // Admin
		REASON_MAX_LENGTH, PLATFORM_MAX_PATH, // Map + Reason
		MAX_NAME_LENGTH, MAX_AUTHID_LENGTH, REASON_MAX_LENGTH // Admin + Remove reason
	);
	g_hDB.Query(SQL_CurrentBans, query);
}

void SQL_CurrentBans(Database db, DBResultSet results, const char[] error, any data) {
	if(results == null || error[0])
		LogError("Update FAILED for: \"KbRestrict_CurrentBans\". Error: %s", error);
	else
		LogMessage("Table: \"KbRestrict_CurrentBans\" successfully updated.");
}

stock void UpdateTable_ServerLogs() {
	if(g_hDB == null) {
		LogError("Database connection has been lost during update of \"KbRestrict_srvlogs\"");
		LogError("Please verify the connection and run again the update.");
		return;
	}

	LogMessage("Start updating \"KbRestrict_srvlogs\" ..");

	char query[MAX_QUERIE_LENGTH];
	g_hDB.Format(query, sizeof(query), "ALTER TABLE `KbRestrict_srvlogs` \
										MODIFY COLUMN `admin_name` varchar(%d) NOT NULL, \
										MODIFY COLUMN `admin_steamid` varchar(%d) NOT NULL, \
										MODIFY COLUMN `client_name` varchar(%d) NOT NULL, \
										MODIFY COLUMN `client_steamid` varchar(%d) NOT NULL;",
										MAX_NAME_LENGTH, MAX_AUTHID_LENGTH, // Admin
										MAX_NAME_LENGTH, MAX_AUTHID_LENGTH // Client
	);
	g_hDB.Query(SQL_ServerLogs, query);
}

void SQL_ServerLogs(Database db, DBResultSet results, const char[] error, any data) {
	if(results == null || error[0])
		LogError("Update FAILED for: \"KbRestrict_srvlogs\". Error: %s", error);
	else
		LogMessage("Table: \"KbRestrict_srvlogs\" successfully updated.");
}

stock void UpdateTable_WebLogs() {
	if(g_hDB == null) {
		LogError("Database connection has been lost during update of \"KbRestrict_weblogs\"");
		LogError("Please verify the connection and run again the update.");
		return;
	}

	LogMessage("Start updating \"KbRestrict_weblogs\" ..");

	char query[MAX_QUERIE_LENGTH];
	g_hDB.Format(query, sizeof(query), "ALTER TABLE `KbRestrict_weblogs` \
										MODIFY COLUMN `admin_name` varchar(%d) NOT NULL, \
										MODIFY COLUMN `admin_steamid` varchar(%d) NOT NULL, \
										MODIFY COLUMN `client_name` varchar(%d) NOT NULL, \
										MODIFY COLUMN `client_steamid` varchar(%d) NOT NULL;",
										MAX_NAME_LENGTH, MAX_AUTHID_LENGTH, // Admin
										MAX_NAME_LENGTH, MAX_AUTHID_LENGTH // Client
	);
	g_hDB.Query(SQL_WebLogs, query);
}

void SQL_WebLogs(Database db, DBResultSet results, const char[] error, any data) {
	if(results == null || error[0])
		LogError("Update FAILED for: \"KbRestrict_weblogs\". Error: %s", error);
	else
		LogMessage("Table: \"KbRestrict_weblogs\" successfully updated.");
}