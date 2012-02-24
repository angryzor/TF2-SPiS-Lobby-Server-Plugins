#include <sourcemod>
#include <tf2>
#include <tf2_stocks>
#include <adminmenu>

#define PLUGIN_VERSION "0.1"

//new bool:globBlocked = false
new bool:playerBlocked[MAXPLAYERS] = { false, ... }
//new Float:currentBlockTime

//new Handle:cvInitBlockTime = INVALID_HANDLE;

public Plugin:myinfo = 
{
	name = "Anti-RUP war",
	author = "angryzor",
	description = "Reduce RUP wars and allow the admin to override the ready state.",
	version = PLUGIN_VERSION,
	url = "http://www.angryzor.com/~rt022830"
}

public OnPluginStart()
{
	CreateConVars();
	RegCmds();
	RegHooks();
}

public OnClientDisconnect(client)
{
	playerBlocked[client] = false;
}

CreateConVars()
{
	CreateConVar("sm_arw_version", PLUGIN_VERSION, "Anti-RUP War Version", FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY);
//	cvInitBlockTime = CreateConVar("sm_awr_init_block_time", "5.0", "First delay on RUPs.", FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_NOTIFY);
}

RegCmds()
{
	RegAdminCmd("sm_arw_block", Command_ARW_Block, ADMFLAG_SLAY, "sm_arw_block <#userid|name>");
	RegAdminCmd("sm_arw_unblock", Command_ARW_Unblock, ADMFLAG_SLAY, "sm_arw_unblock <#userid|name>");
	RegConsoleCmd("tournament_readystate", Command_ARW_Tourn_StatusUpdate, "tournament_readystate state");
}

RegHooks()
{
}

public Action:Command_ARW_Tourn_StatusUpdate(client,args)
{
	if(playerBlocked[client])
	{
		PrintToChat(client,"[ARW] You have been blocked from toggling the tournament ready state.");
		return Plugin_Handled;
	}
	else
		return Plugin_Continue;
}

SetBlock(client,bool:block)
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

	for (new i = 0; i < target_count; i++)
	{
		playerBlocked[target_list[i]] = block;

		new String:cname[65];
		GetClientName(target_list[i],cname,sizeof(cname));
		if(block)
		{
			PrintToChatAll("[ARW] Preventing \"%s\" from toggling ready state", cname);
		}
		else
		{
			PrintToChatAll("[ARW] Allowing \"%s\" to toggle ready state", cname);
		}
	}
	return 0;
}

public Action:Command_ARW_Block(client, args)
{
	if(args != 1)
	{
		ReplyToCommand(client, "[ARW] Usage: sm_arw_block <#userid|name>");
		return Plugin_Handled;
	}

	SetBlock(client,true);
	return Plugin_Handled;
}

public Action:Command_ARW_Unblock(client, args)
{
	if(args != 1)
	{
		ReplyToCommand(client, "[ARW] Usage: sm_arw_unblock <#userid|name>");
		return Plugin_Handled;
	}

	SetBlock(client,false);
	return Plugin_Handled;
}

