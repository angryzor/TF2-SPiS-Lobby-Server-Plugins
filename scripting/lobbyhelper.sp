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
//#define USE_REVERSE_PSYCHOLOGY 1

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
//new String:savePath[400];
new bool:activated = true;

// BALANCING CONVARS
new Handle:enableTeamBalance = INVALID_HANDLE;
new Handle:numPlayersToBalance = INVALID_HANDLE;
new Handle:kadImbaTresh = INVALID_HANDLE;
new Handle:playersInToBalance = INVALID_HANDLE;
new bool:hasStartedBalance = true;

public OnPluginStart()
{
//	BuildPath(Path_SM,savePath,sizeof(savePath),"configs/lobbyhelper/save.dat");

	CreateConVar("sm_lh_version", PLUGIN_VERSION, "Lobby Helper Version", FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY);
	notifyReportDelay = CreateConVar("sm_lh_notify_report_delay", "180.0", "Delay after last teamswitch/join before a notice is displayed to report someone.", FCVAR_PLUGIN|FCVAR_SPONLY);
	updDelay = CreateConVar("sm_lh_update_index_delay", "10.0", "Delay between updates.", FCVAR_PLUGIN|FCVAR_SPONLY);

	enableTeamBalance = CreateConVar("sm_lh_enable_teambalance","1","Turn automatic lobby teambalancing on", FCVAR_PLUGIN|FCVAR_SPONLY);
	numPlayersToBalance = CreateConVar("sm_lh_num_players_to_balance", "5", "Amount of player couples that will be asked to switch teams when the game is imba.", FCVAR_PLUGIN|FCVAR_SPONLY);
	kadImbaTresh = CreateConVar("sm_lh_avg_kad_imba_treshold", "0.17", "Max allowed average class-corrected KA/D imbalance between 2 teams.", FCVAR_PLUGIN|FCVAR_SPONLY);
	playersInToBalance = CreateConVar("sm_lh_num_players_in_to_balance", "16", "Amount of players that must have chosen a team before the autobalance checks start.", FCVAR_PLUGIN|FCVAR_SPONLY);

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
	RegAdminCmd("sm_lh_teambalance",LH_TeamBalance,ADMFLAG_SLAY,"sm_lh_teambalance");
}

RegHooks()
{
	HookEvent("player_spawn", Event_PlayerSpawn);
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

public LH_Enumer(srvId, steamId, String:name[], Float:kad)
{
	if(IdentifyUser(srvId, steamId, name) == -1)
	{
		//PrintToChatAll("\x04%s", name);
		StrCat(users, sizeof(users), "\n");
		StrCat(users, sizeof(users), name);
	}
}

/*****************************************************************************
  TEAM BALANCING
*****************************************************************************/


new imbaPlayers[10];
new Float:imbaKads[10];
new imbaPlayerAmt;
new imbaTeam;

public ShiftImbaPlayers(startAt)
{
	for(new i = imbaPlayerAmt; i > startAt; i--)
	{
		imbaPlayers[i] = imbaPlayers[i-1];
		imbaKads[i] = imbaKads[i-1];
	}
}

public EnumerateImbaPlayers(srvId, steamId, String:name[], Float:kad)
{
	LogMessage("[LH]   Considering user '%s', srvId = %d, steamId = %d, kad = %f",name,srvId,steamId,kad);
	new client = IdentifyUser(srvId, steamId, name);
	if(client == -1)
	{
		LogMessage("[LH]   Unable to identify player in game.");
		return;
	}

	new team = GetClientTeam(client);
	if(team != imbaTeam)
	{
		LogMessage("[LH]   Player is not on team %d, is instead on team %d.",imbaTeam,team);
		return;
	}

	new ptb = GetConVarInt(numPlayersToBalance);
	LogMessage("[LH]   Player is on right team. Want to balance %d players. Current imbaPlayerAmt is %d.",ptb,imbaPlayerAmt);

	for(new i = 0; i < imbaPlayerAmt; i++)
	{
		LogMessage("[LH]   Comparing to imba player idx %d (client %d with kad %f)...",i,imbaPlayers[i],imbaKads[i]);
		if(kad > imbaKads[i])
		{
			ShiftImbaPlayers(i);
			imbaPlayers[i] = client;
			imbaKads[i] = kad;
			if(imbaPlayerAmt < ptb)
			{
				imbaPlayerAmt++;
			}
			return;
		}
	}

	if(imbaPlayerAmt < ptb)
	{
		LogMessage("[LH]   Adding player to end of imba players sorted list.");
		imbaPlayers[imbaPlayerAmt] = client;
		imbaKads[imbaPlayerAmt] = kad;
		imbaPlayerAmt++;
	}
}

public GetMostImbaPlayersOnTeam(team)
{
	LogMessage("[LH]  Finding most imba players on team %d.",team);
	imbaPlayerAmt = 0;
	imbaTeam = team;
	LobbyH_EnumerateParticipants(thisLobby,EnumerateImbaPlayers);
}

public FindPlayerWithClassInTeam(team, TFClassType:class)
{
	new player = -1;
	for(new i = 1; i < MaxClients; i++)
	{
		if(!IsClientInGame(i))
		{
			continue;
		}

		if(GetClientTeam(i) == team && TF2_GetPlayerClass(i) == class)
		{
			player = i;
			break;
		}
	}
	return player;
}

new imbaPlayersToAsk[10][2], imbaTotalPlayersToAsk;

public BalanceTeams(imbateam)
{
	new String:teamname[50];
	GetTeamName(imbateam,teamname,sizeof(teamname));

	LogMessage("[LH] Balancing team %s",teamname);
#if defined USE_REVERSE_PSYCHOLOGY
//	PrintToChatAll("\x04[LH] [TF2Lobby-AutoStack] Stacking team %s",teamname);
#else
//	PrintToChatAll("\x04[LH] [TF2Lobby-AutoBalance] Balancing overpowered team %s",teamname);
#endif

	GetMostImbaPlayersOnTeam(imbateam);

	imbaTotalPlayersToAsk = 0;

	for(new i = 0; i < imbaPlayerAmt; i++)
	{
		new client1 = imbaPlayers[i];
		new TFClassType:class = TF2_GetPlayerClass(client1);

		LogMessage("[LH] Attempting to balance imba player %d with class %d",client1,class);

		new client2 = FindPlayerWithClassInTeam(imbateam ^ 1, class);
		if(client2 == -1)
		{
			LogMessage("[LH] Corresponding classmate not found. Aborting.");
			continue;
		}

		LogMessage("[LH] Found client %d!",client2);

		// Sadly this ugly hack is necessary because sourcemod can't handle 2 simultaneous votes.
		imbaPlayersToAsk[imbaTotalPlayersToAsk][0] = client1;
		imbaPlayersToAsk[imbaTotalPlayersToAsk][1] = client2;
		imbaTotalPlayersToAsk++;
	}
	AskClientsToSwitch();
}

public BalanceSwapClients(c1, c2)
{
	new String:c1Name[100], String:c2Name[100];
	GetClientName(c1, c1Name, sizeof(c1Name));
	GetClientName(c2, c2Name, sizeof(c2Name));
#if defined USE_REVERSE_PSYCHOLOGY
	PrintToChatAll("\x04[LH] [TF2Lobby-AutoStack] Swapping players %s and %s with their consent to increase stacking.",c1Name, c2Name);
#else
	PrintToChatAll("\x04[LH] [TF2Lobby-AutoBalance] Swapping players %s and %s with their consent for team balance.",c1Name, c2Name);
#endif

	new c1Team = GetClientTeam(c1), c2Team = GetClientTeam(c2);
	ChangeClientTeam(c1, c2Team);
	ChangeClientTeam(c2, c1Team);
}

/**********************************************
  BALANCE CHECK
**********************************************/

new Float:totalKad[4];
new totalPlayers[4];

public EnumerateForBalanceCheck(srvId, steamId, String:name[], Float:kad)
{
	new client = IdentifyUser(srvId,steamId,name);
	if(client == -1)
		return;

	new team = GetClientTeam(client);
	totalKad[team] += kad;
	totalPlayers[team]++;
}

public Float:CalcAvgKad(team)
{
	if(totalPlayers[team] <= 0)
		return -1.0;
	else
		return totalKad[team] / totalPlayers[team];
}

public CheckTeamBalance()
{
	LobbyH_EnumerateParticipants(thisLobby,EnumerateForBalanceCheck);

	new Float:avgR = CalcAvgKad(2);
	new Float:avgB = CalcAvgKad(3);
	if(avgR == -1.0 || avgB == -1.0)
		return;

#if defined USE_REVERSE_PSYCHOLOGY
	PrintToChatAll("\x04[LH] [TF2Lobby-AutoStack] Average KA/D in team Red: %f; Blue: %f",avgR,avgB);
#else
	PrintToChatAll("\x04[LH] [TF2Lobby-AutoBalance] Average KA/D in team Red: %f; Blue: %f",avgR,avgB);
#endif

	if(avgB - avgR > GetConVarFloat(kadImbaTresh))
		BalanceTeams(3);
	else if(avgR - avgB > GetConVarFloat(kadImbaTresh))
		BalanceTeams(2);
}

#define VOTE_YES "###YES###"
#define VOTE_NO "###NO###"

public AskClientsToSwitch()
{
	if(imbaTotalPlayersToAsk <= 0)
		return;

	imbaTotalPlayersToAsk--;
	new client1 = imbaPlayersToAsk[imbaTotalPlayersToAsk][0];
	new client2 = imbaPlayersToAsk[imbaTotalPlayersToAsk][1];
	new String:client1name[100];
	new String:client2name[100];

	GetClientName(client1,client1name,sizeof(client1name));
	GetClientName(client2,client2name,sizeof(client2name));

	LogMessage("[LH] Asking clients %s and %s to swap.",client1name,client2name);
#if defined USE_REVERSE_PSYCHOLOGY
	PrintToChatAll("\x04[LH] [TF2Lobby-AutoStack] Asking players %s and %s to swap for stacking awesomeness.",client1name,client2name);
#else
	PrintToChatAll("\x04[LH] [TF2Lobby-AutoBalance] Asking players %s and %s to swap for teambalance.",client1name,client2name);
#endif

	new clients[2];
	clients[0] = client1;
	clients[1] = client2;

#if defined USE_REVERSE_PSYCHOLOGY
	PrintToChat(client1,"\x04The teams are too balanced. Do you want to switch teams? You keep your class.");
	PrintToChat(client2,"\x04The teams are too balanced. Do you want to switch teams? You keep your class.");
#else
	PrintToChat(client1,"\x04The teams are unbalanced. Do you want to switch teams? You keep your class.");
	PrintToChat(client2,"\x04The teams are unbalanced. Do you want to switch teams? You keep your class.");
#endif

	new Handle:voteMenu = CreateMenu(Handler_Imba_VoteMenu, MENU_ACTIONS_ALL);

#if defined USE_REVERSE_PSYCHOLOGY
	SetMenuTitle(voteMenu, "Teams not stacked enough. Switch teams?");
#else
	SetMenuTitle(voteMenu, "Teams imbalanced!");
#endif
	AddMenuItem(voteMenu,VOTE_YES,"Balance teams");
	AddMenuItem(voteMenu,VOTE_NO,"Get steamrolled");
	SetMenuExitButton(voteMenu,false);
	SetVoteResultCallback(voteMenu, Imba_VoteHandler);
	VoteMenu(voteMenu, clients, 2, 30);

	return;
}

public Handler_Imba_VoteMenu(Handle:menu, MenuAction:action, param1, param2)
{
	switch(action)
	{
	case MenuAction_End:
	{
		CloseHandle(menu);
	}
	case MenuAction_VoteCancel:
	{
		LogMessage("[LH] Vote was cancelled.");
		AskClientsToSwitch(); // Next vote.
	}
	}
}

public Imba_VoteHandler(Handle:menu, num_votes, num_clients, const client_info[][2], num_items, const item_info[][2])
{
	if(num_votes != 2 || num_clients != 2 || num_items != 1 || item_info[0][VOTEINFO_ITEM_INDEX] != 0)
	{
		LogMessage("[LH] Clients did not agree: nVotes = %d, nClients = %d, nItems = %d, itemIdx = %d",num_votes,num_clients,num_items,item_info[0][VOTEINFO_ITEM_INDEX]);
#if defined USE_REVERSE_PSYCHOLOGY
		PrintToChatAll("\x04[LH] [TF2Lobby-AutoStack] Players did not agree. They must take some troll lessons!");
#else
		PrintToChatAll("\x04[LH] [TF2Lobby-AutoBalance] Players did not agree. Shame on them :(");
#endif
		for(new i = 0; i < 2; i++)
		{
			if(client_info[i][VOTEINFO_CLIENT_ITEM] == 1)
			{
				PrintToChat(client_info[i][VOTEINFO_CLIENT_INDEX],"[LH] You did not agree to switch teams.");
				PrintToChat(client_info[(i+1)%2][VOTEINFO_CLIENT_INDEX],"[LH] The other player did not agree to switch teams.");
			}
		}
		AskClientsToSwitch(); // Next vote.
		return;
	}

	LogMessage("[LH] Clients agreed to swap!");

	BalanceSwapClients(client_info[0][VOTEINFO_CLIENT_INDEX], client_info[1][VOTEINFO_CLIENT_INDEX]);
	AskClientsToSwitch(); // Next vote.
}

/*************************************************************************
  EVENTS AND ACTIONS
*************************************************************************/

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
	hasStartedBalance = false;

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
// Disabled to avoid thread join lag
//	LobbyH_StartIndexingSteamIDs();
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
//	LobbyH_StopIndexingSteamIDs();
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

public Action:LH_TeamBalance(client,args)
{
	if(thisLobby == -1)
	{
		ReplyToCommand(client,"[LH] Current lobby unknown");
		return Plugin_Handled;
	}

	/*if(args != 1)
	{
		ReplyToCommand(client,"[LH] Usage: sm_lh_teambalance <OP team>");
	}

	new String:arg[200];
	GetCmdArg(1,arg,sizeof(arg));

	new imbateam = StringToInt(arg);*/
	CheckTeamBalance();

	return Plugin_Handled;
}

public Action:Event_PlayerSpawn(Handle:event, const String:name[], bool:dontBroadcast)
{
	if(hasStartedBalance)
		return Plugin_Continue;

	new numClientsIn = 0;
	for(new i = 1; i < MaxClients; i++)
	{
		if(!IsClientInGame(i))
			continue;

		new t = GetClientTeam(i);
		if(t == 2 || t == 3)
			numClientsIn++;
	}

	if(GetConVarBool(enableTeamBalance) && numClientsIn >= GetConVarInt(playersInToBalance))
	{
		hasStartedBalance = true;
		CheckTeamBalance();
	}

	return Plugin_Continue;
}

