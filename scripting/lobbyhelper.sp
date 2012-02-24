/**
 * =============================================================================
 * Lobby Helper
 * Copyright (C) 2011-2012 Ruben "angryzor" Tytgat
 * =============================================================================
 *
 * This program is free software; you can redistribute it and/or modify it under
 * the terms of the GNU General Public License, version 3.0, as published by the
 * Free Software Foundation.
 * 
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
 * details.
 *
 * You should have received a copy of the GNU General Public License along with
 * this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 */


#include <sourcemod>
#include <tf2>
#include <tf2_stocks>
#include <lobbyhelper>

#define PLUGIN_VERSION "0.1"

public Plugin:myinfo = 
{
	name = "Lobby Helper",
	author = "angryzor",
	description = "For tf2lobby.com lobbies",
	version = PLUGIN_VERSION,
	url = "http://www.angryzor.com/~rt022830"
}

new Handle:myTimer = INVALID_HANDLE;
new Handle:notifyReportDelay = INVALID_HANDLE;
new Handle:updTimer = INVALID_HANDLE;
new Handle:updDelay = INVALID_HANDLE;
new timesPassed;
new thisLobby = -1;
new String:savePath[400];
new bool:activated = true;

public OnPluginStart()
{
//	BuildPath(Path_SM,savePath,sizeof(savePath),"configs/lobbyhelper/save.dat");

	CreateConVar("sm_lh_version", PLUGIN_VERSION, "Lobby Helper Version", FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY);
	notifyReportDelay = CreateConVar("sm_lh_notify_report_delay", "180.0", "Delay after last teamswitch/join before a notice is displayed to report someone.", FCVAR_PLUGIN|FCVAR_SPONLY);
	updDelay = CreateConVar("sm_lh_update_index_delay", "10.0", "Delay between updates.", FCVAR_PLUGIN|FCVAR_SPONLY);

	RegCmds();
	RegHooks();

	LobbyH_StartIndexingSteamIDs();

/*	new Handle:f = OpenFile(savePath,"r");
	if(f != INVALID_HANDLE)
	{
		ReadFileCell(f,thisLobby,4);
		CloseHandle(f);
	}*/

	DecideTimers();
}

public OnPluginEnd()
{
	StopUpdTimer();
	StopTimer();

/*	new Handle:f = OpenFile(savePath,"w");
	if(f != INVALID_HANDLE)
	{
		WriteFileCell(f,thisLobby,4);
		CloseHandle(f);
	}*/

	LobbyH_StopIndexingSteamIDs();
}

public OnMapStart()
{
	timesPassed = 0;
	DecideTimers();
}

public OnClientAuthorized()
{
	if(activated)
	{
		timesPassed = 0;
		DecideTimers();
	}
}

public OnClientDisconnect_Post(client)
{
	// For faillobbies
	if(GetClientCount() == 0)
	{
		thisLobby = -1;
		DecideTimers();
	}
}

RegCmds()
{
	RegServerCmd("say",OnSrvSay);
	RegAdminCmd("sm_lh_activate",LH_Activate,ADMFLAG_SLAY,"sm_lh_activate");
	RegAdminCmd("sm_lh_deactivate",LH_Deactivate,ADMFLAG_SLAY,"sm_lh_deactivate");
	RegAdminCmd("sm_lh_shownotice",LH_ShowNotice,ADMFLAG_SLAY,"sm_lh_shownotice");
}

RegHooks()
{
}

RenewTimer()
{
	if(myTimer != INVALID_HANDLE)
	{
		StopTimer();
	}

	myTimer = CreateTimer(GetConVarFloat(notifyReportDelay),Timer_ShowReportNotice,_,TIMER_REPEAT);
}

StopTimer()
{
	if(myTimer == INVALID_HANDLE)
	{
		return;
	}

	CloseHandle(myTimer);
	myTimer = INVALID_HANDLE;
}

StartUpdTimer()
{
	if(updTimer != INVALID_HANDLE)
	{
		return;
	}

	updTimer = CreateTimer(GetConVarFloat(updDelay),LH_Upd,_,TIMER_REPEAT);
}

StopUpdTimer()
{
	if(updTimer == INVALID_HANDLE)
	{
		return;
	}

	CloseHandle(updTimer);
	updTimer = INVALID_HANDLE;
}

DecideTimers()
{
	if(thisLobby != -1)
	{
		StopUpdTimer();
		RenewTimer();
	}
	else
	{
		StopTimer();
		StartUpdTimer();
	}
}

new String:users[2000];

public Action:Timer_ShowReportNotice(Handle:timer)
{
	timesPassed++;
	ShowReportNotice(true);
	return Plugin_Handled;
}

public ShowReportNotice(bool:printTime)
{
	LogMessage("[LH] Showing report notice. (stage 1)");
	if(thisLobby != -1 && GetClientCount() != MaxClients)
	{
		LogMessage("[LH] Showing report notice. (stage 2)");
		strcopy(users, sizeof(users), "");
		LobbyH_EnumerateParticipants(thisLobby, LH_Enumer);

		LogMessage("[LH] Showing report notice. Users: %s",users);

		if(strcmp(users,"") != 0)
		{
			if(printTime)
			{
				new String:t[30];
				FormatTime(t,sizeof(t),"%Mm%Ss",GetConVarInt(notifyReportDelay) * timesPassed);
				PrintCenterTextAll("%s passed since the last person logged on.\nPlease report the following people:%s\nReport link: http://tf2lobby.com/lobby/start?id=%d",
						t,users,thisLobby);
				PrintToChatAll("\x04%s passed since the last person logged on.\nPlease report the following people:%s\nReport link: http://tf2lobby.com/lobby/start?id=%d",
						t,users,thisLobby);
			}
			else
			{
				PrintCenterTextAll("Please report the following people:%s\nReport link: http://tf2lobby.com/lobby/start?id=%d",
						users,thisLobby);
				PrintToChatAll("\x04Please report the following people:%s\nReport link: http://tf2lobby.com/lobby/start?id=%d",
						users,thisLobby);
			}
		}
	}
}

public Action:LH_Upd(Handle:timer)
{
	LobbyH_UpdateIndex();
	PrintToChatAll("[LH] Updating...");
	return Plugin_Handled;
}

public LH_Enumer(srvId, steamId, String:name[])
{
	new bool:passed = false;
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
			passed = true;
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
					passed = true;
					break;
				}
			}
		}

	}			

	if(!passed)
	{
		//PrintToChatAll("\x04%s", name);
		StrCat(users, sizeof(users), "\n");
		StrCat(users, sizeof(users), name);
	}
}

public Action:OnSrvSay(args)
{
	if(!activated)
	{
		return Plugin_Continue;
	}

	new String:arg[500];
	new String:opts[4][100];
	GetCmdArg(1,arg,sizeof(arg));

	ExplodeString(arg," ",opts,2,100);
	if(strcmp(opts[0],"lobbyId") != 0)
	{
		return Plugin_Continue;
	}

	thisLobby = StringToInt(opts[1]);

	LogMessage("[LH] Initializing for new lobby: lobbyID = %d, caused by chat '%s'",thisLobby,arg);

	DecideTimers();
	LobbyH_UpdateLobby(thisLobby);

	return Plugin_Continue;
}

public Action:LH_Activate(client,args)
{
	if(activated)
	{
		ReplyToCommand(client,"[LH] Already active");
		return Plugin_Handled;
	}
	activated = true;
	LobbyH_StartIndexingSteamIDs();
	DecideTimers();
	return Plugin_Handled;
}

public Action:LH_Deactivate(client,args)
{
	if(!activated)
	{
		ReplyToCommand(client,"[LH] Not active");
		return Plugin_Handled;
	}
	activated = false;
	StopUpdTimer();
	StopTimer();
	LobbyH_StopIndexingSteamIDs();
	return Plugin_Handled;
}

public Action:LH_ShowNotice(client,args)
{
	if(thisLobby == -1)
	{
		ReplyToCommand(client,"[LH] Current lobby unknown");
		return Plugin_Handled;
	}
	ShowReportNotice(false);
	return Plugin_Handled;
}
