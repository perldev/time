-module(api_table_holder).
-behaviour(gen_server).


-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).
-export([start_link/0, stop/0, status/0, check_task_in_work/1, find_in_cache/1, 
         start_task/1, start_task_brutal/1, start_task/2, start_task/3, public/1, restartall/0]).

-include("erws_console.hrl").



           
start_link() ->
          gen_server:start_link({local, ?MODULE},?MODULE, [],[]).

init([]) ->
        Tid = ets:new(tasks, [set, protected, named_table, {heir,none},
                              {write_concurrency, false}, {read_concurrency,true}]),
        
        TidCache = ets:new(waitcache, [set, protected, named_table, {heir,none},
                              {write_concurrency,false}, {read_concurrency,true}]),
                              
        {ok, Routes} = application:get_env(front, routes),
        {ok, #monitor{
                         tasks = dict:new() ,
                         pids = dict:new(), 
                         tid = Tid,
                         tidcache = TidCache,
                         routes = Routes}
        }.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.


handle_call({check, Key }, _From, State) ->
    ?LOG_DEBUG("get msg call ~p ~n", [status]),
    case dict:find(Key, State#monitor.tasks) of
          error -> {reply, false, State};
          {ok, Value} -> {reply, true, State}
    end;
handle_call(status,_From ,State) ->
    ?LOG_DEBUG("get msg call ~p ~n", [status]),
    {reply, State, State};

handle_call(restartall, From, State)->
    NewState = restartall_taskinwork(State), 
    {reply, NewState, NewState};    
handle_call(Info,_From ,State) ->
    ?LOG_DEBUG("get msg call ~p ~n", [Info]),
    {reply, undefined , State}.

 
start_task_brutal(Key)->
    gen_server:cast(?MODULE, {start_task, Key}). 


start_task(Key, Params)->
    gen_server:cast(?MODULE, {start_task, Key, Params}).
    
restartall()->
    gen_server:call(?MODULE, restartall).

    
start_task(Key, Params, Session2Connect)->
    gen_server:cast(?MODULE, {start_task, Key, Params, Session2Connect}).
    
start_task(Key)->
    gen_server:cast(?MODULE, {start_task, Key, []})      
.        
check_task_in_work(Key)->
    case ets:lookup(tasks, Key)  of 
        [] ->   false;
        Result  ->  Result
    end                 
.        
    
finish_task(Key)->
    gen_server:cast(?MODULE, {finish, Key})      
.        
stop() ->
    gen_server:cast(?MODULE, stop).

    
find_in_cache([<<"api">>, <<"trades">>, <<"buy">>, Var])->
   MemKey = <<?KEY_PREFIX, "buy_list_", Var/binary>>,
   ?CONSOLE_LOG(" key  ~p ~n",[MemKey]),
   case mcd:get(?LOCAL_CACHE, MemKey) of
    {ok, Val}->
        ?CONSOLE_LOG(" get local from cache  ~p ~n",[Val]),
        %Rate = pickle:pickle_to_term(Val),
        Val;
     _ ->
        false
  end;
find_in_cache([<<"api">>, <<"trades">>, <<"sell">>, Var])->
   MemKey = <<?KEY_PREFIX, "sell_list_", Var/binary>>,
   ?CONSOLE_LOG(" key  ~p ~n",[MemKey]),
   case mcd:get(?LOCAL_CACHE, MemKey) of
    {ok, Val}->
        ?CONSOLE_LOG(" get local from cache  ~p ~n",[Val]),
        %Rate = pickle:pickle_to_term(Val),
        Val;
     _ ->
        false
  end;
find_in_cache([<<"api">>, <<"deals">>, Var])->

   MemKey = <<?KEY_PREFIX, "deal_list_", Var/binary>>,
   ?CONSOLE_LOG(" key  ~p ~n",[MemKey]),
   case mcd:get(?LOCAL_CACHE, MemKey) of
    {ok, Val}->
        ?CONSOLE_LOG(" get local from cache  ~p ~n",[Val]),
        %Rate = pickle:pickle_to_term(Val),
        Val;
     _ ->
        false
  end;


find_in_cache([<<"api">>, <<"japan_stat">>, <<"high">>, Var])->
   MemKey = <<?KEY_PREFIX, "high_japan_stat_", Var/binary>>,

   ?CONSOLE_LOG(" key  ~p ~n",[MemKey]),
   case mcd:get(?LOCAL_CACHE, MemKey) of
    {ok, Val}->
        ?CONSOLE_LOG(" get local from cache  ~p ~n",[Val]),
        %Rate = pickle:pickle_to_term(Val),
        Val;
     _ ->
        false
  end;
  
find_in_cache([<<"api">>, <<"balance">>,  Var])->
   MemKey = <<?KEY_PREFIX, "balance_", Var/binary>>,
   ?CONSOLE_LOG(" key  ~p ~n",[MemKey]),
   case mcd:get(?LOCAL_CACHE, MemKey) of
    {ok, Val}->
        ?CONSOLE_LOG(" get local from cache  ~p ~n",[Val]),
        Val;
     _ ->
        false
end;

find_in_cache([<<"api">>, <<"market_prices">>])->
   MemKey = <<?KEY_PREFIX, "market_prices">>,
   case mcd:get(?LOCAL_CACHE, MemKey) of
    {ok, Val}->
        ?CONSOLE_LOG(" get local from cache  ~p ~n",[Val]),
        %Rate = pickle:pickle_to_term(Val),
        Val;
     _ ->
        false
  end;
find_in_cache(Key)->
    ?CONSOLE_LOG(" unrecognized search   ~p ~n",[Key]),
    false.

    
subscribe_on_cache(K1, K2)->
    case ets:lookup(waitcache, K1 ) of %%check wait list
        [{K1, WaitList}] ->
               case lists:member(K2, WaitList) of 
                  false -> ets:insert(waitcache, {K1, [K2| WaitList]} );
                  true ->  ok  %almost impossible position cause check_ets_cache
               end;
            % save result to wait list if using local cache
        [] -> 
            ets:insert(waitcache, {K1, [K2]} ) %%initilize wait list                
    end.

    
    

run_http(Key, GetUrl, Headers)->
   ?CONSOLE_LOG("start separte process ~p with url  ~p with headers ~p  ~n",[ Key, GetUrl, Headers ]), 
%    spawn_monitor(fun()->  
    {ok, RequestId} = httpc:request(get, {binary_to_list(GetUrl) ,  Headers }, [], [{body_format, binary}, {sync, false}]),
    {ok, RequestId}
%                      {ok, Result} = httpc:request(get, {binary_to_list(GetUrl) ,  Headers }, [], [{body_format, binary}]),
%                      {_Status, _Headers, Body}  = Result, 
%                      api_table_holder:save_in_cache(Key, Body)        
                    
%                  end) 
.
 


public(Key = [<<"api">>, <<"my_orders">>, Var | Tail])->
      false;  
public(Key = [<<"api">>, <<"order">>, <<"status">>, Var | Tail])->
      false;
public(Key = [<<"api">>, <<"balance">> | Tail])->
      false;
public(Key = [<<"api">>, <<"trades">>, <<"buy">>, Var | Tail])->
      true;
public(Key = [<<"api">>, <<"trades">>, <<"sell">>, Var | Tail])->
      true;
public(Key = [<<"api">>, <<"deals">>, Var | Tail])->
      true;   
public(Key = [<<"api">>, <<"japan_stat">>, <<"high">>, Var | Tail])->
      true;   
public(Key = [<<"api">>, <<"market_prices">> | Tail])->
      true.   
      

route_search(Key, [{<<>>, Host}]) -> %% yes it's match everything
   Host
; 
route_search(Key, [{Prefix, Host}|Tail]) ->
    case lists:prefix(Prefix, Key) of
       true -> Host;
       false-> route_search(Key, Tail)
    end
.


process_params2headers({token, Value})->
  {"token", Value}
;
process_params2headers({user_id, Value})->
  {"X-Forwarded-User", Value}
.


restartall_taskinwork(State)->
    Tasks = State#monitor.tasks,
    lists:foldl(fun(MyKey = {Key, Params}, StateTmp)-> 
                      {ok, RequestId} = start_asyn_task(Key, Params, StateTmp),
                      DictNew1 = dict:store(RequestId, MyKey, StateTmp#monitor.pids),
                      DictNew2 = dict:store(MyKey, RequestId, StateTmp#monitor.tasks),
                      % duplicate info to ets table
                      ets:insert(tasks, {MyKey, RequestId}),
                      StateTmp#monitor{tasks=DictNew2, 
                                      pids=DictNew1} 
                end,
                State#monitor{tasks=dict:new(), pids=dict:new()}, 
                dict:to_list(Tasks))
.

start_asyn_task(KeyPath, Params, State)->
     Host = route_search(KeyPath, State#monitor.routes),
     Headers = lists:map(fun(E)-> process_params2headers(E) end, Params),
     Url = lists:foldl(fun(Key, Url) -> <<Url/binary,  "/", Key/binary >>   end, <<>>, KeyPath),
     HostUrl = <<Host/binary,  Url/binary, "?api=erl">>,
     run_http(KeyPath, HostUrl, Headers)
.      

    
handle_cast({start_task_brutal, Key, Params }, MyState) ->
      MyKey = {Key, Params},
      {Pid, Mont} = start_asyn_task(Key, Params, MyState),
       DictNew1 = dict:store(Pid, MyKey, MyState#monitor.pids),
       DictNew2 = dict:store(MyKey, Pid, MyState#monitor.tasks),
       % duplicate info to ets table
       ets:insert(tasks, {Key, Pid}),
       {noreply, MyState#monitor{tasks=DictNew2, pids=DictNew1 } };      
%%HERE WebSocket
handle_cast({start_task, Key, Params, Key2}, MyState) ->
   MyKey = {Key, Params},
   case dict:find( MyKey, MyState#monitor.tasks) of
          {ok, Value} ->
               subscribe_on_cache(MyKey, Key2),
               {noreply, MyState};
          error ->
                {ok, RequestId} = start_asyn_task(Key, Params, MyState),
                DictNew1 = dict:store(RequestId, MyKey, MyState#monitor.pids),
                DictNew2 = dict:store(MyKey, RequestId, MyState#monitor.tasks),
                % duplicate info to ets table
                ets:insert(tasks, {MyKey, RequestId}),
                subscribe_on_cache(MyKey, Key2),                
                {noreply, MyState#monitor{tasks=DictNew2, pids=DictNew1 } } 
   end;
%%HERE we receive tasks from common ajax
handle_cast({start_task, Key, Params}, MyState) ->
    MyKey = {Key, Params},
    case dict:find(MyKey, MyState#monitor.tasks) of
          {ok, Value} ->  
            {noreply, MyState};
          error ->
                {ok, RequestId} = start_asyn_task(Key, Params, MyState),
                DictNew1 = dict:store(RequestId, MyKey, MyState#monitor.pids),
                DictNew2 = dict:store(MyKey , RequestId, MyState#monitor.tasks),
                ets:insert(tasks, { MyKey, RequestId}),
                {noreply, MyState#monitor{tasks=DictNew2, pids=DictNew1 } } 
   end;
handle_cast( archive_mysql_start, MyState) ->
    ?LOG_DEBUG("start archiving ~p ~n", [MyState]),

    {ok, User} = application:get_env(erws, mysql_user),
    {ok, Host} = application:get_env(erws, mysql_host),
    {ok, Pwd} = application:get_env(erws,
                                      mysql_pwd),
    {ok, Base} = application:get_env(erws,
                                      database), 
    {ok, MaxSize } = application:get_env(erws, ets_max_size),
    {ok, Size } = application:get_env(erws, archive_size),
    {ok, Interval } = application:get_env(erws, archive_interval),
    
    emysql:add_pool(?MYSQL_POOL, [{size,4},
                     {user, User},
                     {password, Pwd},
                     {host, Host},
                     {database, Base},
                     {encoding, utf8}]),
%% TODO change NOW() to the value of ets table                     
    emysql:prepare(stmt_get_private, 
                 <<"SELECT public_key, private_key  FROM main_apikeys">>),
    {noreply, MyState}.
    

handle_info({http, {ReqestId, Result}}, State )->
    { {HttpVer, Status, _HTTP}, _Headers, Body}  = Result,
    ?CONSOLE_LOG("get child process ~p ~p ~n", [ReqestId, Result]),
      
     case  dict:find(ReqestId, State#monitor.pids) of 
          {ok, Key}->
              DictNew1 = dict:erase(ReqestId, State#monitor.pids),
              DictNew2 = dict:erase(Key, State#monitor.tasks),
              ets:delete(tasks, Key),
              NewState = State#monitor{pids=DictNew1, tasks=DictNew2}, 
              case ets:lookup(waitcache, Key ) of %%check wait list
                 [{Key, WaitList}] ->
                    lists:foreach(fun(Pid)->  Pid ! {task_result, Key, Body, Status} end, WaitList), %%send body to all subscribers  
                    ets:delete(waitcache, Key),
                    {noreply, NewState}; % save result to wait list if using local cache
                 [] -> 
                    {noreply,  NewState} %%thereis no wait list
              end;
          error ->   
             ?CONSOLE_LOG("something wrong with state for this reqest ~p ~p ~n", [ReqestId, Body]),
             {noreply,  State}
     end
;
handle_info({'DOWN', Ref, process, Pid, Exit},  State)->
    ?LOG_DEBUG("kill child process ~p ~p ~n", [Pid, Exit]),
     case  dict:find(Pid, State#monitor.pids) of 
          {ok, Key}->
             DictNew1 = dict:erase(Pid, State#monitor.pids),
             DictNew2 = dict:erase(Key, State#monitor.tasks),
             ets:delete(tasks, Key),
             {noreply,  State#monitor{tasks=DictNew2, pids=DictNew1}};
           error ->   
             {noreply,  State}
     end;
handle_info(Message,  State)->
    ?LOG_DEBUG("undefined child process ~p ~n", [Message]),
     {noreply,  State}.
  

terminate(_Reason, _State) ->
   terminated.

status() ->
        gen_server:call(?MODULE, status)
    .




