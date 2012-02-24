#include <sourcemod>
#include <tf2>
#include <tf2_stocks>
#include <adminmenu>

#define PLUGIN_VERSION "0.4"

public Plugin:myinfo = 
{
	name = "Class Restrictions",
	author = "angryzor",
	description = "Allows the admin to restrict players to a certain class choice.",
	version = PLUGIN_VERSION,
	url = "http://www.angryzor.com/~rt022830"
}

#define CR_TOMASK(%1) CRClassMask:(TFClassType:1<<%1)

enum CRClassMask
{
	CRClass_Scout		= CR_TOMASK(TFClass_Scout),
	CRClass_Sniper		= CR_TOMASK(TFClass_Sniper),
	CRClass_Soldier		= CR_TOMASK(TFClass_Soldier),
	CRClass_DemoMan		= CR_TOMASK(TFClass_DemoMan),
	CRClass_Medic		= CR_TOMASK(TFClass_Medic),
	CRClass_Heavy		= CR_TOMASK(TFClass_Heavy),
	CRClass_Pyro		= CR_TOMASK(TFClass_Pyro),
	CRClass_Spy			= CR_TOMASK(TFClass_Spy),
	CRClass_Engineer	= CR_TOMASK(TFClass_Engineer)
};

enum MaskMod
{
	MM_Restrict,
	MM_Allow,
	MM_Deny
};

#define CR_CM_ALL CRClass_Scout|CRClass_Sniper|CRClass_Soldier|CRClass_DemoMan|CRClass_Medic|CRClass_Heavy|CRClass_Pyro|CRClass_Spy|CRClass_Engineer
#define CR_CM_NONE CRClassMask:0

new CRClassMask:playerRestrictions[MAXPLAYERS+1] = { CR_CM_ALL, ... };
new Handle:hDelayClassSwitch = INVALID_HANDLE;
new Handle:hTreshold = INVALID_HANDLE;
new Handle:hVotingEnable = INVALID_HANDLE;

new bool:hasBeenInfod[MAXPLAYERS+1] = { false, ... };

public OnPluginStart()
{
	LoadTranslations("common.phrases");
	LoadTranslations("basevotes.phrases");

	CreateConVar("sm_cr_version", PLUGIN_VERSION, "Class Restrictions Version", FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY);
	hDelayClassSwitch = CreateConVar("sm_cr_delay_class_switch", "0", "If 1, the class restrictions will be enforced at the next respawn. If 0, the class restrictions will be enforced immediately and the player will be forced to respawn (without respawn timer).", FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_NOTIFY);
	hTreshold = CreateConVar("sm_cr_voting_treshold", "0.333", "Ratio of votes needed for class restriction vote to pass.", FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_NOTIFY,true,0.0,true,1.0);
	hVotingEnable = CreateConVar("sm_cr_voting_enable", "1", "Enables class restriction voting.", FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_NOTIFY);

	RegCmds();
	RegHooks();
	
	/* Account for late loading */
/*	new Handle:topmenu;
	if (LibraryExists("adminmenu") && ((topmenu = GetAdminTopMenu()) != INVALID_HANDLE))
	{
		OnAdminMenuReady(topmenu);
	}*/
}

public OnClientDisconnect(client)
{
	playerRestrictions[client] = CR_CM_ALL;
	hasBeenInfod[client] = false;
}

RegCmds()
{
	RegAdminCmd("sm_cr_restrict", Command_CR_Restrict, ADMFLAG_SLAY, "sm_cr_restrict <#userid|name> <classes separated by comma>");
	RegAdminCmd("sm_cr_allow", Command_CR_Allow, ADMFLAG_SLAY, "sm_cr_allow <#userid|name> <classes separated by comma>");
	RegAdminCmd("sm_cr_deny", Command_CR_Deny, ADMFLAG_SLAY, "sm_cr_deny <#userid|name> <classes separated by comma>");
	RegConsoleCmd("sm_cr_voterestrict", Command_CR_VoteRestrict, "sm_cr_voterestrict <#userid|name> <classes separated by comma>");
	RegConsoleCmd("sm_cr_voteallow", Command_CR_VoteAllow, "sm_cr_voteallow <#userid|name> <classes separated by comma>");
	RegConsoleCmd("sm_cr_votedeny", Command_CR_VoteDeny, "sm_cr_votedeny <#userid|name> <classes separated by comma>");
	RegConsoleCmd("sm_cr_help", Command_CR_Help, "sm_cr_help");
}

RegHooks()
{
	HookEvent("player_spawn", Event_PlayerSpawn);
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
	
	new bool:delay = GetConVarBool(hDelayClassSwitch);

	for (new i = 0; i < target_count; i++)
	{
		new CRClassMask:clRange = ProcessClassRange(client);
		
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
		new String:classstr[200];
		GetClientName(target_list[i],cname,sizeof(cname));
		GetAllowedClassString(target_list[i], classstr, sizeof(classstr));
		PrintToChatAll("[CR] Restricting player \"%s\" to classes \"%s\"", cname, classstr);
		
		if(!delay)
		{
			CheckPlayerRestrictions(target_list[i]);
		}
	}
	
	if(delay)
	{
		PrintToChatAll("[CR] Delayed class switch is on. Restrictions will be enforced on respawn.");
	}
	
	return true;
}

CRClassMask:ProcessClassRange(client)
{
	new CRClassMask:result = CR_CM_NONE;
	new String:classes[200];
	GetCmdArg(2, classes, sizeof(classes));
	
	new String:ranges[10][40];
	new numRanges = ExplodeString(classes,",",ranges,10,40);
	
	for(new i = 0; i < numRanges; i++)
	{
		if(strcmp(ranges[i],"all",false) == 0)
		{
			result |= CR_CM_ALL;
		}
		else
		{
			new TFClassType:class = TF2_GetClass(ranges[i]);
			if(class == TFClass_Unknown)
			{
				ReplyToCommand(client, "[CR] Unknown class name \"%s\"", ranges[i]);
			}
				
			result |= CR_TOMASK(class);
		}
	}

	return result;
}

GetNumberOfAllowedClasses(client)
{
	new numAllowed = 0;
	for(new i = 1; i <= 9; i++)
	{
		if((playerRestrictions[client] & CR_TOMASK(TFClassType:i)) != CR_CM_NONE)
		{
			numAllowed++;
		}
	}

	return numAllowed;
}

TFClassType:GetRandomAllowedClass(client)
{
	new numAllowed = GetNumberOfAllowedClasses(client);
	// FIXME: will go scout if no classes allowed.
	new r;
	if(numAllowed == 0)
	{
		return TFClass_Scout;
	}
	else
	{
		r = GetRandomInt(1,numAllowed);
	}
	
	for(new i = 1; i <= 9; i++)
	{
		if((playerRestrictions[client] & CR_TOMASK(TFClassType:i)) == CR_CM_NONE)
		{
			r++;
		}
			
		if(i == r)
		{
			return TFClassType:r;
		}
	}
	return TFClass_Scout;
}

GetClassName(TFClassType:ctype, String:cname[], buflen)
{
	switch(ctype)
	{
	case TFClass_Unknown:
	{	strcopy(cname,buflen,"MISSINGNO.");}
	case TFClass_Scout:
	{	strcopy(cname,buflen,"scout");}
	case TFClass_Sniper:
	{	strcopy(cname,buflen,"sniper");}
	case TFClass_Soldier:
	{	strcopy(cname,buflen,"soldier");}
	case TFClass_DemoMan:
	{	strcopy(cname,buflen,"demoman");}
	case TFClass_Medic:
	{	strcopy(cname,buflen,"medic");}
	case TFClass_Heavy:
	{	strcopy(cname,buflen,"heavy");}
	case TFClass_Pyro:
	{	strcopy(cname,buflen,"pyro");}
	case TFClass_Spy:
	{	strcopy(cname,buflen,"spy");}
	case TFClass_Engineer:
	{	strcopy(cname,buflen,"engineer");}
	}
}

GetAllowedClassString(client, String:result[], buflen)
{
	new bool:isFirst = true;
	
	if(GetNumberOfAllowedClasses(client) == 0)
	{
		return 0;
	}
		
	for(new i = 1; i <= 9; i++)
	{
		if((playerRestrictions[client] & CR_TOMASK(TFClassType:i)) != CR_CM_NONE)
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
			
			GetClassName(TFClassType:i,cname,sizeof(cname));
			StrCat(result, buflen, cname);
		}
	}
	
	return 0;
}

CRClassMask:MaskMod_Allow(tgt, CRClassMask:mask)
{
	return playerRestrictions[tgt] | mask;
}

CRClassMask:MaskMod_Deny(tgt, CRClassMask:mask)
{
	return playerRestrictions[tgt] & ~mask;
}

public Action:Command_CR_Restrict(client, args)
{
	if(args != 2)
	{
		ReplyToCommand(client, "[CR] Usage: sm_cr_restrict <#userid|name> <classes separated by comma>");
		return Plugin_Handled;
	}
	
	RealSetRestrictions(client, MM_Restrict);
	return Plugin_Handled;
}

public Action:Command_CR_Allow(client, args)
{
	if(args != 2)
	{
		ReplyToCommand(client, "[CR] Usage: sm_cr_allow <#userid|name> <classes separated by comma>");
		return Plugin_Handled;
	}
	
	RealSetRestrictions(client, MM_Allow);
	return Plugin_Handled;
}

public Action:Command_CR_Deny(client, args)
{
	if(args != 2)
	{
		ReplyToCommand(client, "[CR] Usage: sm_cr_deny <#userid|name> <classes separated by comma>");
		return Plugin_Handled;
	}
	
	RealSetRestrictions(client, MM_Deny);
	return Plugin_Handled;
}

CheckPlayerRestrictions(client)
{
	new TFClassType:cl = TF2_GetPlayerClass(client);
	
	if((playerRestrictions[client] & CR_TOMASK(cl)) == CR_CM_NONE && playerRestrictions[client] != CR_CM_NONE && cl != TFClass_Unknown)
	{
		new String:classstr[200];
		TF2_SetPlayerClass(client, GetRandomAllowedClass(client));
		GetAllowedClassString(client, classstr, sizeof(classstr));
		PrintToChat(client, "[CR] You have been restricted to the following classes: %s", classstr);
		TF2_RespawnPlayer(client);
	}
}

public Action:Event_PlayerSpawn(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event,"userid"));
	if(!hasBeenInfod[client] && TF2_GetPlayerClass(client) != TFClass_Unknown && GetConVarBool(hVotingEnable))
	{
		hasBeenInfod[client] = true;
		PrintToChat(client, "[CR] Has someone stolen your class slot? Type !cr_voterestrict to restrict him/her to his/her proper class or !cr_help for more options.");
	}

	CheckPlayerRestrictions(client);
}



/*
 * Voting
 */


#define VOTE_YES "###YES###"
#define VOTE_NO "###NO###"


new String:voteCmd[40];
new Handle:voteMenu = INVALID_HANDLE;
new String:voteTgts[65];
new String:voteClasses[200];
new voteTgt;

public Action:Command_CR_VoteRestrict(client, args)
{
	strcopy(voteCmd,sizeof(voteCmd),"sm_cr_restrict");
	Command_CR_Vote(client, args, "Restrict %s to classes \"%s\"?");
}

public Action:Command_CR_VoteAllow(client, args)
{
	strcopy(voteCmd,sizeof(voteCmd),"sm_cr_allow");
	Command_CR_Vote(client, args, "Allow %s to use classes \"%s\"?");
}

public Action:Command_CR_VoteDeny(client, args)
{
	strcopy(voteCmd,sizeof(voteCmd),"sm_cr_deny");
	Command_CR_Vote(client, args, "Deny %s access to class \"%s\"?");
}


public Action:Command_CR_Vote(client, args, String:voteTitle[])
{
	new String:thiscmd[50];
	GetCmdArg(0,thiscmd, sizeof(thiscmd));

	if(!GetConVarBool(hVotingEnable))
	{
		ReplyToCommand(client, "[CR] Voting is disabled.");
		return Plugin_Handled;
	}

	if(args != 2)
	{
		ReplyToCommand(client, "[CR] Usage: %s <#userid|name> <classes separated by comma>", thiscmd);
		return Plugin_Handled;
	}

	if(IsVoteInProgress())
	{
		ReplyToCommand(client, "[CR] %t", "Vote in Progress");
		return Plugin_Handled;
	}

	if(!TestVoteDelay(client))
	{
		return Plugin_Handled;
	}

	LogAction(client, -1, "\"%L\" initiated a %s vote.", client, thiscmd);
	ShowActivity2(client, "[CR] ", "%t", "Initiate Vote", thiscmd);

	voteMenu = CreateMenu(Handler_CR_VoteMenu, MENU_ACTIONS_ALL);
	GetCmdArg(1, voteTgts, sizeof(voteTgts));
	GetCmdArg(2, voteClasses, sizeof(voteClasses));

	voteTgt = FindTarget(client, voteTgts);

	if(voteTgt == -1)
	{
		return Plugin_Handled;
	}

	GetClientName(voteTgt, voteTgts, sizeof(voteTgts));

	SetMenuTitle(voteMenu, voteTitle, voteTgts, voteClasses);
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
			ReplyToCommand(client, "[CR] %t", "Vote Delay Minutes", delay % 60);
		}
		else
		{
			ReplyToCommand(client, "[CR] %t", "Vote Delay Seconds", delay);
		}
												
		return false;
	}
				
	return true;
}

public Handler_CR_VoteMenu(Handle:menu, MenuAction:action, param1, param2)
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
			PrintToChatAll("[CR] %t", "No Votes Cast");
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
			PrintToChatAll("[CR] %t", "Vote Successful", RoundToNearest(100.0 * percent), totalVotes);
			LogAction(-1, voteTgt, "%s on %d due to vote.", voteCmd, voteTgt);
			ServerCommand("%s \"%s\" \"%s\"", voteCmd, voteTgts, voteClasses);
		}
		else
		{
			PrintToChatAll("[CR] %t", "Vote Failed", RoundToNearest(100.0 * treshold), RoundToNearest(100.0 * percent), totalVotes);
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

public Action:Command_CR_Help(client, args)
{
	PrintToChat(client, "[CR] See console for output");
	PrintToConsole(client, "[CR] Class Restrictions help. Available commands:");
	PrintToConsole(client, "[CR] - sm_cr_restrict <#userid|name> <classes separated by comma>");
	PrintToConsole(client, "[CR]     Restrict players to a certain set of classes. Classes must be separated by commas.");
	PrintToConsole(client, "[CR] - sm_cr_allow <#userid|name> <classes separated by comma>");
	PrintToConsole(client, "[CR]     Allow players to pick a certain set of classes.");
	PrintToConsole(client, "[CR] - sm_cr_deny <#userid|name> <classes separated by comma>");
	PrintToConsole(client, "[CR]     Deny players access to a certain set of classes.");
	PrintToConsole(client, "[CR] - sm_cr_voterestrict <#userid|name> <classes separated by comma>");
	PrintToConsole(client, "[CR]     Start a vote to restrict a player to a certain set of classes.");
	PrintToConsole(client, "[CR] - sm_cr_voteallow <#userid|name> <classes separated by comma>");
	PrintToConsole(client, "[CR]     Start a vote to allow a player to use a certain set of classes.");
	PrintToConsole(client, "[CR] - sm_cr_votedeny <#userid|name> <classes separated by comma>");
	PrintToConsole(client, "[CR]     Start a vote to deny a player access to a certain set of classes.");
	PrintToConsole(client, "[CR] - sm_cr_help");
	PrintToConsole(client, "[CR]     Print this message.");
}

