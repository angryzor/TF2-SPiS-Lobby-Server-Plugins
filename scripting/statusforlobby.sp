/**
 * =============================================================================
 * Lobby Status Fix
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

#define PLUGIN_VERSION "0.1"

new Handle:cvHostName = INVALID_HANDLE;
new Handle:cvIp = INVALID_HANDLE;
new Handle:cvPort = INVALID_HANDLE;

public Plugin:myinfo = 
{
	name = "Lobby Status Fix",
	author = "angryzor",
	description = "Status fix to allow lobbies to work with replay servers.",
	version = PLUGIN_VERSION,
	url = "http://www.angryzor.com/~rt022830"
}

public OnPluginStart()
{
	CreateConVar("sm_lsf_version", PLUGIN_VERSION, "Lobby Status Fix Version", FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY);
	cvHostName = FindConVar("hostname");
	cvIp = FindConVar("ip");
	cvPort = FindConVar("hostport");

	RegCmds();
	RegHooks();
}

RegCmds()
{
	RegConsoleCmd("status", Command_Status, "Display map and connection status.");
}

RegHooks()
{
}

public Action:Command_Status(client, args)
{
	if(GetRealClientCount() != 0)
		return Plugin_Continue;

	new String:hostname[500];
	new String:ip[60];
	new String:port[7];
	new String:map[100];
	GetConVarString(cvHostName,hostname,sizeof(hostname));
	GetConVarString(cvIp,ip,sizeof(ip));
	GetConVarString(cvPort,port,sizeof(port));
	GetCurrentMap(map,sizeof(map));

/*	new String:versionStr[300];
	new String:protV[10];
	new String:exeV[10];
	new String:buildV[10];
	ServerCommandEx(versionStr,sizeof(versionStr),"version");
	new Handle:regex = CompileRegex("Protocol version.*(\\d+).*Exe version.*(\\d+).*Exe build.*\\((\\d+)\\).*\\((\\d+)\\)",PCRE_UNGREEDY);
	MatchRegex(regex,versionStr);
	GetRegexSubString(regex,0,protV,sizeof(protV));
	GetRegexSubString(regex,1,exeV,sizeof(exeV));
	GetRegexSubString(regex,2,buildV,sizeof(buildV));
	CloseHandle(regex);*/


	ReplyToCommand(client,"hostname: %s",hostname);
	ReplyToCommand(client,"version : 1.2.5.8/24 5231 secure");
	ReplyToCommand(client,"udp/ip  : %s:%s",ip,port);
	ReplyToCommand(client,"map     : %s at: 0 x, 0 y, 0 z",map);
	ReplyToCommand(client,"players : %d (%d max)",GetRealClientCount(),MaxClients);
	ReplyToCommand(client,"");
	ReplyToCommand(client,"# userid name uniqueid connected ping loss state adr");
/*	for(new i = 1; i <= MaxClients; i++)
	{
		if(IsClientInGame(i) && !IsFakeClient(i))
		{
			new String:name[100];
			new String:auth[50];
			new Float:secsOnline = GetClientTime(i);
			new String:time[50];
			if(secsOnline >= 3600.0)
			{
				FormatTime(time,sizeof(time),"%H:%M:%S",RoundToNearest(secsOnline));
			}
			else
			{
				FormatTime(time,sizeof(time),"%M:%S",RoundToNearest(secsOnline));
			}
			GetClientName(i,name,sizeof(name));
			GetClientAuthString(i,auth,sizeof(auth));
			ReplyToCommand(client,"%d \"%s\" %s %s %d %d active",GetClientUserId(i),name,auth,time,GetClientLatency(i,NetFlow_Both),GetClientAvgLoss(i,NetFlow_Both));
		}
	}
*/
	return Plugin_Handled;
}

stock GetRealClientCount( bool:inGameOnly = true ) {
    new clients = 0;
    for( new i = 1; i <= MaxClients; i++ ) {
 	   if( ( ( inGameOnly ) ? IsClientInGame( i ) : IsClientConnected( i ) ) && !IsFakeClient( i ) ) {
 		   clients++;
 	   }
    }
    return clients;
}

