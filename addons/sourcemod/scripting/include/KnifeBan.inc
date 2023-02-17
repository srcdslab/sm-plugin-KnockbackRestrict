// *************************************************************************
// This is the include file for KnifeBan
//
// To check that KnifeBan is installed and running, verify that the "KnifeBan" library exists
//
// *************************************************************************

#if defined _KnifeBan_included_
  #endinput
#endif
#define _KnifeBan_included_

public SharedPlugin __pl_KnifeBan = 
{
	name = "KnifeBan",
	file = "KnifeBan.smx",
#if defined REQUIRE_PLUGIN
	required = 1
#else
	required = 0
#endif
}

#if !defined REQUIRE_PLUGIN
public void __pl_knifeban_SetNTVOptional()
{
	MarkNativeAsOptional("KB_BanClient");
	MarkNativeAsOptional("KB_UnBanClient");
	MarkNativeAsOptional("KB_ClientStatus");
}
#endif

/*********************************************************
 * KnifeBan the target
 *
 * @param admin 	Admin Index
 * @param target	Target Index
 * @param time      Ban's length
 * @param sReason   Reason
*********************************************************/
native void KB_BanClient(int iadmin, int itarget, int itime, const char[] ssReason);

/*********************************************************
 * KnifeUnBan the target
 *
 * @param client 	Client Index
 * @param target	Target Index
 * @param sReason   Reason
 *********************************************************/
native void KB_UnBanClient(int iadmin, int itarget, char[] ssReason);

/*********************************************************
 * Check if client is knife banned
 * 
 * @return 	true if client is knifed banned, false otherwise
 *********************************************************/
native bool KB_ClientStatus(int client);
