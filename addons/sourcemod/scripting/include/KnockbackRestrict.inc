// *************************************************************************
// This is the include file for KnockbackRestrict
//
// To check that KnockbackRestrict is installed and running.
// It will verify that the "KnockbackRestrict" library exists
//
// *************************************************************************

#if defined _KnockbackRestrict_included_
  #endinput
#endif
#define _KnockbackRestrict_included_

#define KR_V_MAJOR   "4"
#define KR_V_MINOR   "0"
#define KR_V_PATCH   "1"

#define KR_VERSION   KR_V_MAJOR..."."...KR_V_MINOR..."."...KR_V_PATCH

typedef LengthCallback = function void(int admin, int target, int time);

public SharedPlugin __pl_KnockbackRestrict = 
{
	name = "KnockbackRestrict",
	file = "KnockbackRestrict.smx",
#if defined REQUIRE_PLUGIN
	required = 1
#else
	required = 0
#endif
}

#if !defined REQUIRE_PLUGIN
public void __pl_knockbackrestrict_SetNTVOptional()
{
	MarkNativeAsOptional("KR_BanClient");
	MarkNativeAsOptional("KR_UnBanClient");
	MarkNativeAsOptional("KR_ClientStatus");
	MarkNativeAsOptional("KR_GetClientKbansNumber");
	MarkNativeAsOptional("KR_DisplayLengthsMenu");
}
#endif

/*********************************************************
 * KnockbackRestrict the target
 *
 * @param admin 	Admin Index
 * @param target	Target Index
 * @param time      Ban's length
 * @param sReason   Reason
*********************************************************/
native void KR_BanClient(int iadmin, int itarget, int itime, const char[] ssReason);

/*********************************************************
 * KbUnRestrict the target
 *
 * @param client 	Client Index
 * @param target	Target Index
 * @param sReason   Reason
 *********************************************************/
native void KR_UnBanClient(int iadmin, int itarget, char[] ssReason);

/*********************************************************
 * Check if client is restricted
 * 
 * @param client  	Client Index
 * @return 			true if client is restricted, false otherwise
 *********************************************************/
native bool KR_ClientStatus(int client);

/*********************************************************
 * Get client kbans number
 *
 * @param client  	Client Index
 * @return			Kbans number
 *********************************************************/
native int KR_GetClientKbansNumber(int client);

/*********************************************************
 * Display KBan Lengths Menu
 *
 * @param admin  	Admin Index
 * @param target	Target Index
 * @param callback	The callback where you can get the time in seconds
 * @noreturn	
 *********************************************************/
native void KR_DisplayLengthsMenu(int admin, int target, LengthCallback callback);

/**
 * Called when a client is knockback restricted.
 *
 * @param client        Client index
 * @param admin         Admin index
 * @param length        Ban length in minutes (0 = permanent, -1 = temporary)
 * @param reason        Ban reason
 * @param kbansNumber   Number of active knockback restrictions for this client
 * @noreturn
 */
forward void KR_OnClientKbanned(int client, int admin, int length, const char[] reason, int kbansNumber);

/**
 * Called when a client's knockback restriction is removed.
 *
 * @param client        Client index
 * @param admin         Admin index
 * @param reason        Unban reason
 * @param kbansNumber   Number of active knockback restrictions for this client
 * @noreturn
 */
forward void KR_OnClientKunbanned(int client, int admin, const char[] reason, int kbansNumber);
