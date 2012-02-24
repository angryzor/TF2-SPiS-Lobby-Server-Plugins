/**
 * =============================================================================
 * SeeAll
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
#include <adminmenu>

#define PLUGIN_VERSION "0.1"

public Plugin:myinfo = 
{
	name = "See All",
	author = "angryzor",
	description = "For TF2. Admin can see all players' classes.",
	version = PLUGIN_VERSION,
	url = "http://www.angryzor.com/~rt022830"
}

public OnPluginStart()
{
	CreateConVars();
	RegCmds();
	RegHooks();
}

CreateConVars()
{
	CreateConVar("sm_sa_version", PLUGIN_VERSION, "See All Version", FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY);
}

RegCmds()
{
	RegAdminCmd("sm_sa_see", Command_SA_See, ADMFLAG_SLAY, "sm_sa_see <#userid|name> <teams separated by comma>");
}

RegHooks()
{
}

public Action:Command_SA_See(client, args)
{
	for(new i = 0; i < GetTeamCount(); i++)
	{
		SeeTeam(client,i);
	}
	return Plugin_Handled;
}

SeeTeam(client,team)
{
	new String:cn[20];
	new String:name[100];

	GetTeamName(team,name,sizeof(name));
	//ReplyToCommand(client,"[SA]---------------------------------------");
	ReplyToCommand(client,"[SA] %s",name);
	ReplyToCommand(client,"[SA]---------------------------------------");

	for(new i = 1; i <= MaxClients; i++)
	{
		if(IsClientInGame(i) && !IsFakeClient(i) && GetClientTeam(i) == team)
		{
			GetClientName(i,name,sizeof(name));
			GetClassName(TF2_GetPlayerClass(i),cn,sizeof(cn));
			ReplyToCommand(client,"[SA] %-30s\t%s",name,cn);
		}
	}

	//ReplyToCommand(client,"[SA]---------------------------------------");
	ReplyToCommand(client,"[SA]");
}

public Action:Event_PlayerSpawn(Handle:event, const String:name[], bool:dontBroadcast)
{
	return Plugin_Continue;
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

