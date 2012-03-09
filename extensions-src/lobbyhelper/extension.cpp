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

#include <sourcemod_version.h>
#include "extension.h"
#include <json/json.h>
#include <fstream>
#include <sstream>
#include <stdexcept>
#include <map>
#include <queue>
#include <cstdlib>
#include <cstring>

#include <curl/curl.h>

#include <boost/function.hpp>
#include <boost/thread/thread.hpp>
#include <boost/thread/mutex.hpp>
#include <boost/thread/locks.hpp>
#include <boost/thread/condition_variable.hpp>

using namespace std;

typedef std::map<int,steamid> sids_map;

boost::thread *thr, *thr_upd = NULL;
boost::mutex mtx_todo, mtx_sids, mtx_state;
boost::condition_variable todo_updated;

sids_map sids;
std::queue<steamid_todo> sids_todo;
bool lookup_running;

#define BUF_SIZE 500000
char api_buffer[BUF_SIZE];
char profile_buffer[BUF_SIZE];
size_t api_ptr, profile_ptr;

/**
 * @file extension.cpp
 * @brief Implement extension code here.
 */
LobbyHelper_Extension g_LobbyHelper;

SMEXT_LINK(&g_LobbyHelper);

bool LobbyHelper_Extension::SDK_OnLoad(char *error, size_t maxlength, bool late)
{
	char path[PLATFORM_MAX_PATH];

	curl_global_init(CURL_GLOBAL_ALL);

	g_pShareSys->AddNatives(myself, lobbyhelper_natives);
	g_pShareSys->RegisterLibrary(myself, "LobbyHelper");

	g_pSM->BuildPath(Path_SM, path, sizeof(path), "configs/lobbyhelper/lobbyidcache.txt");
	ifstream ifs(path);
	if(ifs.is_open())
	{
		Json::Value root;
		Json::Reader reader;

		if(!reader.parse(ifs, root))
			return true;

		for(Json::Value::ArrayIndex i = 0; i < root.size(); i++)
		{
			Json::Value el(root[i]);
			steamid s;
			s.srvId = el["srvId"].asInt();
			s.steamId = el["steamId"].asInt();
			s.name = el["name"].asString();
			s.uId = el["uid"].asInt();
			sids[el["uid"].asInt()] = s;
		}

		ifs.close();
	}

	return true;
}

void LobbyHelper_Extension::SDK_OnUnload()
{
	char path[PLATFORM_MAX_PATH];

	if(thr_upd)
	{
		thr_upd->join();
		delete thr_upd;
	}

	g_pSM->BuildPath(Path_SM, path, sizeof(path), "configs/lobbyhelper/lobbyidcache.txt");
	ofstream ofs(path, ios::trunc);
	if(ofs.is_open())
	{
		Json::Value root(Json::arrayValue);

		for(sids_map::const_iterator i = sids.begin(); i != sids.end(); i++)
		{
			Json::Value obj(Json::objectValue);
			obj["uid"] = Json::Value(i->second.uId);
			obj["srvId"] = Json::Value(i->second.srvId);
			obj["steamId"] = Json::Value(i->second.steamId);
			obj["name"] = Json::Value(i->second.name);
			root.append(obj);
		}

		ofs << root;
		ofs.close();
	}

	curl_global_cleanup();
}

const char *LobbyHelper_Extension::GetExtensionVerString()
{
	return SM_FULL_VERSION;
}

const char *LobbyHelper_Extension::GetExtensionDateString()
{
	return SM_BUILD_TIMESTAMP;
}



size_t write_buffer( char *ptr, size_t size, size_t count, char* buf, size_t& bufptr)
{
	size_t written = ((BUF_SIZE - bufptr) < (size * count) ? BUF_SIZE - bufptr : size * count);
	memcpy(buf+bufptr,ptr,written);
	bufptr += written;
	buf[bufptr] = '\0';
	return written;
}

size_t write_api_buffer( char *ptr, size_t size, size_t count, void *ignore)
{
	return write_buffer(ptr,size,count,api_buffer,api_ptr);
}

size_t write_profile_buffer( char *ptr, size_t size, size_t count, void *ignore)
{
	return write_buffer(ptr,size,count,profile_buffer,profile_ptr);
}

string find_and_extract(const string& source, const string& before, const string& after)
{
	size_t i = source.find(before);
	size_t j = source.find(after, i + before.size());

	if(j <= i)
		throw runtime_error("Strange indexes");

	return source.substr(i+before.size(),j-(i+before.size()));
}

void download_profile(int id)
{
	CURL *curl;
	CURLcode res;

	curl = curl_easy_init();
	if(!curl)
		throw runtime_error("Could not fetch profile: can't init libcurl");

	profile_ptr = 0;
	ostringstream oss;
	oss << "http://tf2lobby.com/profile?id=" << id;
	curl_easy_setopt(curl, CURLOPT_NOSIGNAL, 1);
	curl_easy_setopt(curl, CURLOPT_URL, oss.str().c_str());
	curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, &write_profile_buffer);
	curl_easy_setopt(curl, CURLOPT_TIMEOUT, 20);
	res = curl_easy_perform(curl);
	curl_easy_cleanup(curl);

	if(res != CURLE_OK) {
		ostringstream oss;
		oss << "Could not fetch profile: can't perform query, error code: " << res;
		throw runtime_error(oss.str());
	}
}

void add_steamid(int id)
{
	download_profile(id);

	string prf(profile_buffer);

	string myfriendid(find_and_extract(prf, "<a href=\"http://tf2stats.net/player_stats/", "\""));
	istringstream iss(myfriendid);
	long long friendid;
	if(!(iss >> friendid))
		throw runtime_error("Wrong friendid format");

	steamid sid;
	sid.uId = id;
	sid.srvId = friendid % 2;
	friendid -= sid.srvId;
	friendid -= 76561197960265728LL;
	sid.steamId = friendid / 2;
	sid.name = find_and_extract(prf, "<title>TF2Lobby - Profile - ", "</title>");

	{
		boost::lock_guard<boost::mutex> lock(mtx_sids);

		sids[id] = sid;
	}
}

void json_enqueue_sids_todo()
{
	Json::Value root;
	Json::Reader reader;

	if(!reader.parse(api_buffer, api_buffer+api_ptr, root))
		throw runtime_error("Could not parse TF2Lobby API JSON.");

	const Json::Value lobbies = root["lobbies"];
	for(Json::Value::ArrayIndex i = 0; i < lobbies.size(); i++)
	{
		const Json::Value tlob = lobbies[i];
		const Json::Value inlob = tlob["inLobby"];
		for(Json::Value::ArrayIndex j = 0; j < inlob.size(); j++)
		{
			int uid;
			istringstream iss2(inlob[j].asString());
			iss2 >> uid;

			{
				boost::lock_guard<boost::mutex> lock(mtx_sids);
				boost::lock_guard<boost::mutex> lock2(mtx_todo);

				if(sids.find(uid) == sids.end())
					sids_todo.push(steamid_todo(uid,false));
			}
		}
	}

	todo_updated.notify_all();
}

void lookup_thread()
{
	boost::unique_lock<boost::mutex> lock_state(mtx_state);
	while(lookup_running)
	{
		try
		{
			boost::unique_lock<boost::mutex> lock(mtx_todo);
			if(!sids_todo.empty())
			{
				lock_state.unlock();
				steamid_todo id = sids_todo.front();
				sids_todo.pop();

				lock.unlock();
				try // Add another try. We don't want to be thrown past our lock
				{
			
					if(!id.is_update)
					{
						boost::lock_guard<boost::mutex> lock(mtx_sids);

						// We don't want to update known users constantly, 'cause then we're doing nothing but downloading profiles all the time
						// We'll only update existing names of people in our current lobby.
						if(sids.find(id.id) != sids.end())
						{
							lock_state.lock();
							continue;
						}
					}

					add_steamid(id.id);
				}
				catch(runtime_error& e)
				{
					g_pSM->LogMessage(myself,"Runtime error during indexing: %s",e.what());
				}
				catch(exception& e)
				{
					g_pSM->LogMessage(myself,"Error during indexing: %s",e.what());
				}
				lock_state.lock();
			}
			else
			{
				lock.unlock();
				todo_updated.wait(lock_state);
			}
		}
		catch(runtime_error& e)
		{
			g_pSM->LogMessage(myself,"Runtime error during indexing: %s",e.what());
		}
		catch(exception& e)
		{
			g_pSM->LogMessage(myself,"Error during indexing: %s",e.what());
		}
	}
}


vector<steamid> json_get_participating_sids(int lobbyid)
{
	Json::Value root;
	Json::Reader reader;

	vector<steamid> res;

	if(!reader.parse(api_buffer,api_buffer+api_ptr, root))
		throw runtime_error("Could not parse TF2Lobby API JSON.");

	const Json::Value lobbies = root["lobbies"];
	for(Json::Value::ArrayIndex i = 0; i < lobbies.size(); i++)
	{
		const Json::Value tlob = lobbies[i];
		int tlid;

		istringstream iss(tlob["lobbyId"].asString());
		iss >> tlid;

		if(tlid == lobbyid)
		{
			const Json::Value inlob = tlob["inLobby"];
			for(Json::Value::ArrayIndex j = 0; j < inlob.size(); j++)
			{
				int uid;
				istringstream iss2(inlob[j].asString());
				iss2 >> uid;

				{
					boost::lock_guard<boost::mutex> lock(mtx_sids);
			
					sids_map::const_iterator i = sids.find(uid);
					if(i != sids.end())
						res.push_back(i->second);
				}
			}
			break;
		}
	}

	return res;
}

void get_api_json_file()
{
	CURL *curl;
	CURLcode res;

	curl = curl_easy_init();
	if(!curl)
		throw runtime_error("Could not fetch API json file: can't init libcurl");
	
//	g_pSM->LogMessage(myself,"Getting API file");

	api_ptr = 0;
	ostringstream oss;
	oss << "http://tf2lobby.com/api/lobbies";
	curl_easy_setopt(curl, CURLOPT_NOSIGNAL, 1);
	curl_easy_setopt(curl, CURLOPT_URL, oss.str().c_str());
	curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, write_api_buffer);
	curl_easy_setopt(curl, CURLOPT_TIMEOUT, 5);
	res = curl_easy_perform(curl);
	curl_easy_cleanup(curl);

//	g_pSM->LogMessage(myself,"Got API file");

	if(res != CURLE_OK)
		throw runtime_error("Could not fetch API json file: can't perform query");
}

void update_lobby_participants(int id)
{
	vector<steamid> v = json_get_participating_sids(id);

	{
		boost::lock_guard<boost::mutex> lock(mtx_todo);

		for(vector<steamid>::const_iterator i = v.begin(); i != v.end(); i++)
		{
			sids_todo.push(steamid_todo(i->uId,true));
		}
	}

	todo_updated.notify_all();
}

void upd_thread()
{
	try
	{
		get_api_json_file();
		json_enqueue_sids_todo();
	}
	catch(exception& e)
	{
		g_pSM->LogMessage(myself,"Error during processing: %s",e.what());
	}
}

static cell_t start_indexing_steamids(IPluginContext *pCtx, const cell_t *params)
{
	try{
		{
			boost::lock_guard<boost::mutex> lock(mtx_state);

			if(lookup_running)
				return 1;

			lookup_running = true;
		}
		thr = new boost::thread(boost::function<void()>(&lookup_thread));
	}
	catch(runtime_error& e)
	{
		g_pSM->LogMessage(myself,"Runtime error during processing: %s",e.what());
	}
	catch(exception& e)
	{
		g_pSM->LogMessage(myself,"Error during processing: %s",e.what());
	}

	return 1;
}


static cell_t stop_indexing_steamids(IPluginContext *pCtx, const cell_t *params)
{
	try{
		{
			boost::lock_guard<boost::mutex> lock(mtx_state);

			if(!lookup_running)
				return 1;

			lookup_running = false;
		}
		// Wake the thread up in case it was sleeping
		todo_updated.notify_all();
		thr->join();
		delete thr;
	}
	catch(runtime_error& e)
	{
		g_pSM->LogMessage(myself,"Runtime error during processing: %s",e.what());
	}
	catch(exception& e)
	{
		g_pSM->LogMessage(myself,"Error during processing: %s",e.what());
	}

	return 1;
}


static cell_t update_index(IPluginContext *pCtx, const cell_t *params)
{
	try{
		if(thr_upd)
		{
			if(!thr_upd->timed_join(boost::posix_time::milliseconds(0)))
				return 1;
			delete thr_upd;
		}
		thr_upd = new boost::thread(boost::function<void()>(&upd_thread));
	}
	catch(runtime_error& e)
	{
		g_pSM->LogMessage(myself,"Runtime error during processing: %s",e.what());
	}
	catch(exception& e)
	{
		g_pSM->LogMessage(myself,"Error during processing: %s",e.what());
	}

	return 1;
}

static cell_t enumerate_participants(IPluginContext *pCtx, const cell_t *params)
{
	try
	{
		IPluginFunction* enm = pCtx->GetFunctionById(static_cast<funcid_t>(params[2]));

		vector<steamid> lpids(json_get_participating_sids(params[1]));
//		pCtx->LocalToPhysAddr(params[3], &steamIds);
		for(size_t i = 0; i < lpids.size(); i++)
		{
			cell_t addr;
			cell_t* data;
			pCtx->HeapAlloc(lpids[i].name.size() + 1, &addr, &data);
			pCtx->StringToLocal(addr, lpids[i].name.size() + 1, lpids[i].name.c_str());


			cell_t prms[3];
			prms[0] = lpids[i].srvId;
			prms[1] = lpids[i].steamId;
			prms[2] = addr;
			cell_t res;
			enm->CallFunction(prms, 3, &res);
			pCtx->HeapPop(addr);
		}
	}
	catch(runtime_error& e)
	{
		g_pSM->LogMessage(myself,"Runtime error during processing: %s",e.what());
	}
	catch(exception& e)
	{
		g_pSM->LogMessage(myself,"Error during processing: %s",e.what());
	}

	return 1;
}

static cell_t update_lobby(IPluginContext *pCtx, const cell_t *params)
{
	try
	{
		update_lobby_participants(params[1]);
	}
	catch(runtime_error& e)
	{
		g_pSM->LogMessage(myself,"Runtime error during processing: %s",e.what());
	}
	catch(exception& e)
	{
		g_pSM->LogMessage(myself,"Error during processing: %s",e.what());
	}

	return 1;
}


const sp_nativeinfo_t lobbyhelper_natives[] = 
{
	{"LobbyH_EnumerateParticipants",	enumerate_participants},
	{"LobbyH_StartIndexingSteamIDs",	start_indexing_steamids},
	{"LobbyH_StopIndexingSteamIDs",		stop_indexing_steamids},
	{"LobbyH_UpdateIndex",				update_index},
	{"LobbyH_UpdateLobby",				update_lobby},
	{NULL,					NULL},
};
