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


forward void KR_OnClientKbanned(int client, int admin, int length, const char[] reason, int kbansNumber);

forward void KR_OnClientKunbanned(int client, int admin, const char[] reason, int kbansNumber);
