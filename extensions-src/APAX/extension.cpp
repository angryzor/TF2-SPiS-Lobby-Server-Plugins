/**
 * =============================================================================
 * APAX
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
#include <fstream>
#include <sstream>
#include <stdexcept>
#include <map>
#include <queue>
#include <cstdlib>
#include <cstring>

#include <boost/bind.hpp>
#include <boost/thread/thread.hpp>
#include <boost/thread/mutex.hpp>
#include <boost/thread/locks.hpp>
#include <boost/thread/condition_variable.hpp>

#include <curl/curl.h>

#include "curlio.h"

using namespace std;

/**
 * @file extension.cpp
 * @brief Implement extension code here.
 */
APAX_Extension g_APAX;

SMEXT_LINK(&g_APAX);

boost::thread *thr = NULL;
boost::mutex mtx_todo, mtx_state, mtx_finished;
boost::condition_variable todo_updated;

bool query_running;
static unsigned current_thread_group_id(0);

queue<pending_query> query_todo;
queue<finished_query> query_finished;

class ResponseChecker : public ITimedEvent
{
public:
	ResultType OnTimer(ITimer *pTimer, void *pData)
	{
		try
		{
			boost::lock_guard<boost::mutex> lock(mtx_finished);
	
			while(!query_finished.empty())
			{
				cell_t addr, *data;
	
				finished_query q = query_finished.front();
				query_finished.pop();
	
				smutils->LogMessage(myself,"Processing finished query. Response code is %d.",q.response);
				smutils->LogMessage(myself,"Data: %s",q.data.c_str());

				IPluginContext* pCtx = q.func->GetParentRuntime()->GetDefaultContext();
				if(pCtx->HeapAlloc(q.data.size() + 1, &addr, &data) != SP_ERROR_NONE)
					throw runtime_error("Data too large for the heap of your plugin. Use ./spcomp -S<memsize> to compile with a bigger heap.");
				pCtx->StringToLocal(addr, q.data.size() + 1, q.data.c_str());
				
				cell_t prms[3];
				prms[0] = q.response;
				prms[1] = addr;
				prms[2] = q.user_data;
				cell_t res;
	
				q.func->CallFunction(prms, 3, &res);
				pCtx->HeapPop(addr);
			}
		}
		catch(runtime_error& e)
		{
			smutils->LogMessage(myself,"Runtime error during in CheckResponses: %s",e.what());
		}
		catch(exception& e)
		{
			smutils->LogMessage(myself,"Error during in CheckResponses: %s",e.what());
		}
		return Pl_Handled;
	}

	void OnTimerEnd(ITimer *pTimer, void *pData)
	{
	}
};

ResponseChecker rchecker;

void perform_query(pending_query& query)
{
	CURL *curl;
	CURLcode res;

	smutils->LogMessage(myself,"Starting query...");

	curl = curl_easy_init();
	if(!curl)
		throw runtime_error("Could not execute query: can't init libcurl");

	curl_write_buffer responseBody;
	curl_read_buffer queryBody(query.data.c_str(),query.data.size());

	curl_easy_setopt(curl, CURLOPT_NOSIGNAL, 1);
	curl_easy_setopt(curl, CURLOPT_URL, query.url.c_str());
	curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, &write_buffer);
	curl_easy_setopt(curl, CURLOPT_WRITEDATA, &responseBody);

	bool sendingData(true);
	switch(query.method)
	{
		case HTTPM_PUT:
			curl_easy_setopt(curl, CURLOPT_UPLOAD, 1);
			break;
		case HTTPM_POST:
			curl_easy_setopt(curl, CURLOPT_POST, 1);
			curl_easy_setopt(curl, CURLOPT_POSTFIELDS, NULL);
			curl_easy_setopt(curl, CURLOPT_POSTFIELDSIZE, queryBody.buf_size);
			break;
		default:
			sendingData = false;
			break;
	}

	string cthead = string("Content-Type: ")+query.content_type;
	curl_slist *slist = NULL;
	
	if(sendingData)
	{
		curl_easy_setopt(curl, CURLOPT_READFUNCTION, &read_buffer);
		curl_easy_setopt(curl, CURLOPT_READDATA, &queryBody);
		curl_easy_setopt(curl, CURLOPT_INFILESIZE, queryBody.buf_size);

		slist = curl_slist_append(slist,cthead.c_str());
		curl_easy_setopt(curl, CURLOPT_HTTPHEADER, slist);
	}

	curl_easy_setopt(curl, CURLOPT_TIMEOUT, 30);
	res = curl_easy_perform(curl);

	if(sendingData)
		curl_slist_free_all(slist);
	
	int response;
	curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &response);
	curl_easy_cleanup(curl);

	finished_query q;
	q.response = response;
	q.data = string(responseBody.buffer);
	q.func = query.func;
	q.user_data = query.user_data;

	{
		boost::lock_guard<boost::mutex> lock(mtx_finished);
		query_finished.push(q);
	}

	smutils->LogMessage(myself,"Query finished.");
	
	if(res != CURLE_OK) {
		ostringstream oss;
		oss << "Can't perform query, error code: " << res;
		throw runtime_error(oss.str());
	}
}

void query_thread(unsigned int tgid)
{
	boost::unique_lock<boost::mutex> lock_state(mtx_state);
	while(tgid == current_thread_group_id)
	{
		try
		{
			boost::unique_lock<boost::mutex> lock(mtx_todo);
			if(!query_todo.empty())
			{
				lock_state.unlock();
				pending_query query = query_todo.front();
				query_todo.pop();

				lock.unlock();

				smutils->LogMessage(myself,"Processing query for %s, method %d.",query.url.c_str(),(int)query.method);

				try // Add another try. We don't want to be thrown past our lock
				{
					perform_query(query);
				}
				catch(runtime_error& e)
				{
					smutils->LogMessage(myself,"Runtime error during indexing: %s",e.what());
				}
				catch(exception& e)
				{
					smutils->LogMessage(myself,"Error during indexing: %s",e.what());
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
			smutils->LogMessage(myself,"Runtime error during indexing: %s",e.what());
		}
		catch(exception& e)
		{
			smutils->LogMessage(myself,"Error during indexing: %s",e.what());
		}
	}
}

const char *APAX_Extension::GetExtensionVerString()
{
	return SM_FULL_VERSION;
}

const char *APAX_Extension::GetExtensionDateString()
{
	return SM_BUILD_TIMESTAMP;
}

bool APAX_Extension::SDK_OnLoad(char *error, size_t maxlength, bool late)
{
	try
	{
		curl_global_init(CURL_GLOBAL_ALL);

		{
			boost::lock_guard<boost::mutex> lock(mtx_state);
			query_running = true;
		}
		
		thr = new boost::thread(boost::bind(query_thread,current_thread_group_id));
		
		sharesys->AddNatives(myself, APAX_natives);
		sharesys->RegisterLibrary(myself, "APAX");

		resp_check_timer = timersys->CreateTimer(&rchecker,0.5f,NULL,TIMER_FLAG_REPEAT);

		return true;
	}
	catch(runtime_error& e)
	{
		smutils->LogMessage(myself,"Runtime error during startup: %s",e.what());
		return false;
	}
}

void APAX_Extension::SDK_OnUnload()
{
	timersys->KillTimer(resp_check_timer);

	{
		boost::lock_guard<boost::mutex> lock(mtx_state);
		query_running = false;
		current_thread_group_id++;
	}

	todo_updated.notify_all();
	delete thr;

	curl_global_cleanup();
}

static cell_t APAX_Query(IPluginContext *pCtx, const cell_t *params)
{
	try
	{
		pending_query q;
		char *url, *data, *cttype;

		pCtx->LocalToString(params[1], &url);
		pCtx->LocalToString(params[3], &data);
		pCtx->LocalToString(params[4], &cttype);
		IPluginFunction* func = pCtx->GetFunctionById(static_cast<funcid_t>(params[5]));

		smutils->LogMessage(myself,"Adding query for %s, method %d to queue.",url,params[2]);

		q.url = string(url);
		q.data = string(data);
		q.method = (HTTPMethod)params[2];
		q.content_type = string(cttype);
		q.func = func;
		q.user_data = params[6];

		{
			boost::lock_guard<boost::mutex> lock(mtx_todo);
			query_todo.push(q);
		}
		todo_updated.notify_all();
	}
	catch(runtime_error& e)
	{
		smutils->LogMessage(myself,"Runtime error in APAX_Query: %s",e.what());
	}
	catch(exception& e)
	{
		smutils->LogMessage(myself,"Error during in APAX_Query: %s",e.what());
	}

	return 1;
}

const sp_nativeinfo_t APAX_natives[] = 
{
	{"APAX_Query",			APAX_Query},
	{NULL,					NULL},
};

