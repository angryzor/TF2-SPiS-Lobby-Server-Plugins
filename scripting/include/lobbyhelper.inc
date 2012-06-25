
#if defined _lobbyhelper_included
  #endinput
#endif
#define _lobbyhelper_included

#include <core>

functag public LobbyH_PtcptEnumerator(srvId, steamId, String:name[], Float:kad);

native bool:LobbyH_EnumerateParticipants(const lobbyId, LobbyH_PtcptEnumerator:enumerator);
native bool:LobbyH_StartIndexingSteamIDs();
native bool:LobbyH_StopIndexingSteamIDs();
native bool:LobbyH_UpdateIndex();
native bool:LobbyH_UpdateLobby(const lobbyId);


/**
 * @endsection
 */

/**
 * Do not edit below this line!
 */
public Extension:__ext_lobbyhelper = 
{
	name = "LobbyHelper",
	file = "lobbyhelper.ext",
#if defined AUTOLOAD_EXTENSIONS
	autoload = 1,
#else
	autoload = 0,
#endif
#if defined REQUIRE_EXTENSIONS
	required = 1,
#else
	required = 0,
#endif
};

stock IdentifyUser(srvId,steamId,String:name[])
{
	new client = -1;
	for(new i = 1; i <= MaxClients; i++)
	{
		new String:sId[50];
		new String:sId2[50];
		new String:clName[100];

		if(!IsClientInGame(i))
		{
			continue;
		}

		GetClientName(i, clName, sizeof(clName));

		if(StrContains(name,clName,false) != -1 || StrContains(clName,name,false) != -1)
		{
			client = i;
			break;
		}
		else
		{
			if(IsClientAuthorized(i))
			{
				GetClientAuthString(i, sId, sizeof(sId));
				Format(sId2, sizeof(sId2), "STEAM_0:%d:%d", srvId, steamId);
				if(strcmp(sId,sId2) == 0)
				{
					client = i;
					break;
				}
			}
		}
	}
	return client;
}


