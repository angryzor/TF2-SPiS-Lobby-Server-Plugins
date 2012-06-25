
#if defined _APAX_included
  #endinput
#endif
#define _APAX_included

#include <core>

functag public APAX_Callback(const responseCode, String:responseBody[], userData);

native bool:APAX_Query(String:url[], const httpMethod, String:requestBody[], String:contentType[], APAX_Callback:onComplete, userData=0);
native bool:APAX_CheckResponses();


/**
 * @endsection
 */

/**
 * Do not edit below this line!
 */
public Extension:__ext_APAX = 
{
	name = "APAX",
	file = "APAX.ext",
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

#define APAX_METHOD_GET 0
#define APAX_METHOD_PUT 1
#define APAX_METHOD_POST 2


