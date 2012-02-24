#include <sourcemod>
#include <tf2>
#include <tf2_stocks>
#include <adminmenu>

#define PLUGIN_VERSION "0.1"

public Plugin:myinfo = 
{
	name = "Team Restrictions",
	author = "angryzor",
	description = "Allows the admin to restrict players to a certain team choice.",
	version = PLUGIN_VERSION,
	url = "http://www.angryzor.com/~rt022830"
}

enum MaskMod
{
	MM_Restrict,
	MM_Allow,
	MM_Deny
};

#define TR_TM_ALL ~TRTeamMask:0
#define TR_TM_NONE TRTeamMask:0

new TRTeamMask:playerRestrictions[MAXPLAYERS+1] = { TR_TM_ALL, ... };
new Handle:hDelayTeamSwitch = INVALID_HANDLE;
new Handle:hTreshold = INVALID_HANDLE;
new Handle:hVotingEnable = INVALID_HANDLE;

new bool:hasBeenInfod[MAXPLAYERS+1] = { false, ... };

public OnPluginStart()
{
	LoadTranslations("common.phrases");
	LoadTranslations("basevotes.phrases");

	CreateConVar("sm_tr_version", PLUGIN_VERSION, "Team Restrictions Version", FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY);
	hDelayTeamSwitch = CreateConVar("sm_tr_delay_team_switch", "0", "If 1, the team restrictions will be enforced at the next respawn. If 0, the team restrictions will be enforced immediately and the player will be forced to respawn (without respawn timer).", FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_NOTIFY);
	hTreshold = CreateConVar("sm_tr_voting_treshold", "0.333", "Ratio of votes needed for team restriction vote to pass.", FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_NOTIFY,true,0.0,true,1.0);
	hVotingEnable = CreateConVar("sm_tr_voting_enable", "1", "Enables team restriction voting.", FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_NOTIFY);

	RegCmds();
	RegHooks();
}

public OnClientDisconnect(client)
{
	playerRestrictions[client] = TR_TM_ALL;
	hasBeenInfod[client] = false;
}

RegCmds()
{
	RegAdminCmd("sm_tr_restrict", Command_TR_Restrict, ADMFLAG_SLAY, "sm_tr_restrict <#userid|name> <teams separated by comma>");
	RegAdminCmd("sm_tr_allow", Command_TR_Allow, ADMFLAG_SLAY, "sm_tr_allow <#userid|name> <teams separated by comma>");
	RegAdminCmd("sm_tr_deny", Command_TR_Deny, ADMFLAG_SLAY, "sm_tr_deny <#userid|name> <teams separated by comma>");
	RegConsoleCmd("sm_tr_voterestrict", Command_TR_VoteRestrict, "sm_tr_voterestrict <#userid|name> <teams separated by comma>");
	RegConsoleCmd("sm_tr_voteallow", Command_TR_VoteAllow, "sm_tr_voteallow <#userid|name> <teams separated by comma>");
	RegConsoleCmd("sm_tr_votedeny", Command_TR_VoteDeny, "sm_tr_votedeny <#userid|name> <teams separated by comma>");
	RegConsoleCmd("sm_tr_help", Command_TR_Help, "sm_tr_help");
}

RegHooks()
{
	HookEvent("player_spawn", Event_PlayerSpawn);
	
	new String:game[64];
	GetGameDescription(game,sizeof(game),true);
	if(StrContains(game,"Team Fortress",false) != -1)
	{
		HookEvent("player_team", Event_TeamsChanged);
	}
	else 
	{
		GetGameFolderName(game,sizeof(game));
		if(strncmp(game,"tf",2,false) == 0)
		{
			HookEvent("player_team", Event_TeamsChanged);
		}
	}
}

TRTeamMask:TR_ToMask(team)
{
	return TRTeamMask:(1<<team);
}

bool:RealSetRestrictions(client, MaskMod:maskmod)
{
	new String:tgtstr[65];
	GetCmdArg(1, tgtstr, sizeof(tgtstr));

	new String:target_name[MAX_TARGET_LENGTH];
	new target_list[MAXPLAYERS], target_count, bool:tn_is_ml;
	
	if ((target_count = ProcessTargetString(
			tgtstr,
			client,
			target_list,
			MAXPLAYERS,
			0,
			target_name,
			sizeof(target_name),
			tn_is_ml)) <= 0)
	{
		ReplyToTargetError(client, target_count);
		return false;
	}
	
	new bool:delay = GetConVarBool(hDelayTeamSwitch);

	for (new i = 0; i < target_count; i++)
	{
		new TRTeamMask:clRange = ProcessTeamRange(client);
		
		switch(maskmod)
		{
		case MM_Restrict:
		{	playerRestrictions[target_list[i]] = clRange; }
		case MM_Allow:
		{	playerRestrictions[target_list[i]] = MaskMod_Allow(target_list[i], clRange); }
		case MM_Deny:
		{	playerRestrictions[target_list[i]] = MaskMod_Deny(target_list[i], clRange); }
		}

		new String:cname[65];
		new String:teamstr[200];
		GetClientName(target_list[i],cname,sizeof(cname));
		GetAllowedTeamString(target_list[i], teamstr, sizeof(teamstr));
		PrintToChatAll("[TR] Restricting player \"%s\" to teams \"%s\"", cname, teamstr);
		
		if(!delay)
		{
			CheckPlayerRestrictions(target_list[i]);
		}
	}
	
	if(delay)
	{
		PrintToChatAll("[TR] Delayed team switch is on. Restrictions will be enforced on respawn.");
	}
	
	return true;
}

TRTeamMask:ProcessTeamRange(client)
{
	new TRTeamMask:result = TR_TM_NONE;
	new String:teams[200];
	GetCmdArg(2, teams, sizeof(teams));
	
	new String:ranges[10][40];
	new numRanges = ExplodeString(teams,",",ranges,10,40);
	
	for(new i = 0; i < numRanges; i++)
	{
		if(strcmp(ranges[i],"all",false) == 0)
		{
			result |= TR_TM_ALL;
		}
		else
		{
			new team = FindTeamByName(ranges[i]);
			if(team == -1)
			{
				ReplyToCommand(client, "[TR] Unknown team name \"%s\"", ranges[i]);
			}
			else if(team == -2)
			{
				ReplyToCommand(client, "[TR] Team name \"%s\" is ambiguous", ranges[i]);
			}
			else
			{
				result |= TR_ToMask(team);
			}
		}
	}

	return result;
}

GetNumberOfAllowedTeams(client)
{
	new numAllowed = 0;
	for(new i = 1; i < GetTeamCount(); i++)
	{
		if((playerRestrictions[client] & TR_ToMask(i)) != TR_TM_NONE)
		{
			numAllowed++;
		}
	}

	return numAllowed;
}

GetRandomAllowedTeam(client)
{
	new numAllowed = GetNumberOfAllowedTeams(client);
	// FIXME: will go scout if no teams allowed.
	new r;
	if(numAllowed == 0)
	{
		return 1;
	}
	else
	{
		r = GetRandomInt(1,numAllowed);
	}
	
	for(new i = 1; i < GetTeamCount(); i++)
	{
		if((playerRestrictions[client] & TR_ToMask(i)) == TR_TM_NONE)
		{
			r++;
		}
			
		if(i == r)
		{
			return r;
		}
	}
	return 1;
}

GetAllowedTeamString(client, String:result[], buflen)
{
	new bool:isFirst = true;
	
	if(GetNumberOfAllowedTeams(client) == 0)
	{
		return 0;
	}
		
	for(new i = 1; i < GetTeamCount(); i++)
	{
		if((playerRestrictions[client] & TR_ToMask(i)) != TR_TM_NONE)
		{
			new String:cname[20];
			if(!isFirst)
			{
				StrCat(result, buflen, ",");
			}
			else
			{
				isFirst = false;
			}
			
			GetTeamName(i,cname,sizeof(cname));
			StrCat(result, buflen, cname);
		}
	}
	
	return 1;
}

TRTeamMask:MaskMod_Allow(tgt, TRTeamMask:mask)
{
	return playerRestrictions[tgt] | mask;
}

TRTeamMask:MaskMod_Deny(tgt, TRTeamMask:mask)
{
	return playerRestrictions[tgt] & ~mask;
}

public Action:Command_TR_Restrict(client, args)
{
	if(args != 2)
	{
		ReplyToCommand(client, "[TR] Usage: sm_tr_restrict <#userid|name> <teams separated by comma>");
		return Plugin_Handled;
	}
	
	RealSetRestrictions(client, MM_Restrict);
	return Plugin_Handled;
}

public Action:Command_TR_Allow(client, args)
{
	if(args != 2)
	{
		ReplyToCommand(client, "[TR] Usage: sm_tr_allow <#userid|name> <teams separated by comma>");
		return Plugin_Handled;
	}
	
	RealSetRestrictions(client, MM_Allow);
	return Plugin_Handled;
}

public Action:Command_TR_Deny(client, args)
{
	if(args != 2)
	{
		ReplyToCommand(client, "[TR] Usage: sm_tr_deny <#userid|name> <teams separated by comma>");
		return Plugin_Handled;
	}
	
	RealSetRestrictions(client, MM_Deny);
	return Plugin_Handled;
}

CheckPlayerRestrictions(client)
{
	new cl = GetClientTeam(client);
	
	if((playerRestrictions[client] & TR_ToMask(cl)) == TR_TM_NONE && playerRestrictions[client] != TR_TM_NONE && cl != 0)
	{
		new String:teamstr[200];
		ChangeClientTeam(client, GetRandomAllowedTeam(client));
		GetAllowedTeamString(client, teamstr, sizeof(teamstr));
		PrintToChat(client, "[TR] You have been restricted to the following teams: %s", teamstr);
	}
}

public Action:Event_PlayerSpawn(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event,"userid"));
	if(!hasBeenInfod[client] && GetClientTeam(client) != 0 && GetClientTeam(client) != 1 && GetConVarBool(hVotingEnable))
	{
		hasBeenInfod[client] = true;
		PrintToChat(client, "[TR] Is someone unwilling to switch to his/her team? Type !tr_voterestrict to restrict him/her to his/her proper team or !tr_help for more options.");
	}

	CheckPlayerRestrictions(client);
}

public Action:Event_TeamsChanged(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event,"userid"));
	new bool:silent = GetEventBool(event,"silent");
	new ot = GetEventInt(event,"oldteam");
	new nt = GetEventInt(event,"team");
	
	// For Team Fortress
	if(silent && ((ot == 3 && nt == 2) || (ot == 2 && nt == 3)))
	{
		new TRTeamMask:r = playerRestrictions[client];
		new TRTeamMask:rnewblue = ((r >> TRTeamMask:2) & TRTeamMask:1) << TRTeamMask:3;
		new TRTeamMask:rnewred = ((r >> TRTeamMask:3) & TRTeamMask:1) << TRTeamMask:2;

		playerRestrictions[client] = (r & ~TRTeamMask:0xC) | rnewblue | rnewred;
	}
}



/*
 * Voting
 */


#define VOTE_YES "###YES###"
#define VOTE_NO "###NO###"


new String:voteCmd[40];
new Handle:voteMenu = INVALID_HANDLE;
new String:voteTgts[65];
new String:voteTeams[200];
new voteTgt;

public Action:Command_TR_VoteRestrict(client, args)
{
	strcopy(voteCmd,sizeof(voteCmd),"sm_tr_restrict");
	Command_TR_Vote(client, args, "Restrict %s to teams \"%s\"?");
}

public Action:Command_TR_VoteAllow(client, args)
{
	strcopy(voteCmd,sizeof(voteCmd),"sm_tr_allow");
	Command_TR_Vote(client, args, "Allow %s to use teams \"%s\"?");
}

public Action:Command_TR_VoteDeny(client, args)
{
	strcopy(voteCmd,sizeof(voteCmd),"sm_tr_deny");
	Command_TR_Vote(client, args, "Deny %s access to team \"%s\"?");
}


public Action:Command_TR_Vote(client, args, String:voteTitle[])
{
	new String:thiscmd[50];
	GetCmdArg(0,thiscmd, sizeof(thiscmd));

	if(!GetConVarBool(hVotingEnable))
	{
		ReplyToCommand(client, "[TR] Voting is disabled.");
		return Plugin_Handled;
	}

	if(args != 2)
	{
		ReplyToCommand(client, "[TR] Usage: %s <#userid|name> <teams separated by comma>", thiscmd);
		return Plugin_Handled;
	}

	if(IsVoteInProgress())
	{
		ReplyToCommand(client, "[TR] %t", "Vote in Progress");
		return Plugin_Handled;
	}

	if(!TestVoteDelay(client))
	{
		return Plugin_Handled;
	}

	LogAction(client, -1, "\"%L\" initiated a %s vote.", client, thiscmd);
	ShowActivity2(client, "[TR] ", "%t", "Initiate Vote", thiscmd);

	voteMenu = CreateMenu(Handler_TR_VoteMenu, MENU_ACTIONS_ALL);
	GetCmdArg(1, voteTgts, sizeof(voteTgts));
	GetCmdArg(2, voteTeams, sizeof(voteTeams));

	voteTgt = FindTarget(client, voteTgts);

	if(voteTgt == -1)
	{
		return Plugin_Handled;
	}

	GetClientName(voteTgt, voteTgts, sizeof(voteTgts));

	SetMenuTitle(voteMenu, voteTitle, voteTgts, voteTeams);
	AddMenuItem(voteMenu,VOTE_YES,"Yes");
	AddMenuItem(voteMenu,VOTE_NO,"No");
	SetMenuExitButton(voteMenu,false);
	VoteMenuToAll(voteMenu, 30);

	return Plugin_Handled;
}

bool:TestVoteDelay(client)
{
	new delay = CheckVoteDelay();
		
	if (delay > 0)
	{
		if (delay > 60)
		{
			ReplyToCommand(client, "[TR] %t", "Vote Delay Minutes", delay % 60);
		}
		else
		{
			ReplyToCommand(client, "[TR] %t", "Vote Delay Seconds", delay);
		}
												
		return false;
	}
				
	return true;
}

public Handler_TR_VoteMenu(Handle:menu, MenuAction:action, param1, param2)
{
	switch(action)
	{
	case MenuAction_End:
	{
		CloseVoteMenu();
	}
	case MenuAction_VoteCancel:
	{
		if(param1 == VoteCancel_NoVotes)
		{
			PrintToChatAll("[TR] %t", "No Votes Cast");
		}
	}
	case MenuAction_VoteEnd:
	{
		new Float:percent, Float:treshold = GetConVarFloat(hTreshold), votes, totalVotes;
		GetMenuVoteInfo(param2, votes, totalVotes);

		if(param1 != 0)
		{
			votes = totalVotes - votes;
		}

		percent = FloatDiv(float(votes),float(totalVotes));

		if(FloatCompare(percent, treshold) != -1)
		{
			PrintToChatAll("[TR] %t", "Vote Successful", RoundToNearest(100.0 * percent), totalVotes);
			LogAction(-1, voteTgt, "%s on %d due to vote.", voteCmd, voteTgt);
			ServerCommand("%s \"%s\" \"%s\"", voteCmd, voteTgts, voteTeams);
		}
		else
		{
			PrintToChatAll("[TR] %t", "Vote Failed", RoundToNearest(100.0 * treshold), RoundToNearest(100.0 * percent), totalVotes);
		}
	}
	}
}

CloseVoteMenu()
{
	CloseHandle(voteMenu);
	voteMenu = INVALID_HANDLE;
}



/*
 * Help
 */

public Action:Command_TR_Help(client, args)
{
	PrintToChat(client, "[TR] See console for output");
	PrintToConsole(client, "[TR] Team Restrictions help. Available commands:");
	PrintToConsole(client, "[TR] - sm_tr_restrict <#userid|name> <teams separated by comma>");
	PrintToConsole(client, "[TR]     Restrict players to a certain set of teams. Teams must be separated by commas.");
	PrintToConsole(client, "[TR] - sm_tr_allow <#userid|name> <teams separated by comma>");
	PrintToConsole(client, "[TR]     Allow players to pick a certain set of teams.");
	PrintToConsole(client, "[TR] - sm_tr_deny <#userid|name> <teams separated by comma>");
	PrintToConsole(client, "[TR]     Deny players access to a certain set of teams.");
	PrintToConsole(client, "[TR] - sm_tr_voterestrict <#userid|name> <teams separated by comma>");
	PrintToConsole(client, "[TR]     Start a vote to restrict a player to a certain set of teams.");
	PrintToConsole(client, "[TR] - sm_tr_voteallow <#userid|name> <teams separated by comma>");
	PrintToConsole(client, "[TR]     Start a vote to allow a player to use a certain set of teams.");
	PrintToConsole(client, "[TR] - sm_tr_votedeny <#userid|name> <teams separated by comma>");
	PrintToConsole(client, "[TR]     Start a vote to deny a player access to a certain set of teams.");
	PrintToConsole(client, "[TR] - sm_tr_help");
	PrintToConsole(client, "[TR]     Print this message.");
}

