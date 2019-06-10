


-define(DEBUG,1).

-ifdef(DEBUG).

-define('CONSOLE_LOG'(Str, Params),  lager:info(Str, Params) ).
-define('LOG_DEBUG'(Str, Params), lager:debug(Str, Params) ).


-else.

-define('CONSOLE_LOG'(Str, Params),  true).
-define('LOG_DEBUG'(Str, Params),  true ).


-endif.

-define(INIT_APPLY_TIMEOUT,1000).
-define(HOST,"http://127.0.0.1:8098").
-define(RANDOM_CHOICE, 10).
-define(SESSIONS, ets_sessions).
-define(MYSQL_POOL, mysql_pool).
-define(DEFAULT_FLUSH_SIZE, 1000).
-define(MESSAGES, ets_sessions_holder).
-define(UNDEF, undefined).
-define(SESSION_SALT_CODE, <<"aasa_salts">> ).
-define(SESSION_SALT, <<"tesC_aasa_salts">> ).
-define(KEY_PREFIX, "crypton" ).
-define(LOCAL_CACHE, myMcd).

-record(
        chat_state,{
               start,
               index = 0,
               ip,
               user_id, 
               tasks, 
               token,
               sessionkey,
               sessionobj
        }

).


-record(monitor,{
                  tasks,
                  pids,
                  tid,
                  base_url = <<"http://127.0.0.1">>,
                  routes = [],
                  tidcache
           %       base_url = <<"http://185.61.138.187">> 
                  
                }).



