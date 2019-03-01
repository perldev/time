-module(api_table_holder).
-behaviour(gen_server).

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).
-export([start_link/0, stop/0, status/0, check_task_in_work/1, find_in_cache/1, start_task/1, start_task_brutal/1, start_task/2]).

-include("erws_console.hrl").

-record(monitor,{
                  tasks,
                  pids,
                  tid,
                  base_url = <<"http://127.0.0.1">>,
                  routes = [] 
           %       base_url = <<"http://185.61.138.187">> 
                  
                }).


           
start_link() ->
          gen_server:start_link({local, ?MODULE},?MODULE, [],[]).

init([]) ->
        Tid = ets:new(tasks, [set, protected,  {heir,none}, {write_concurrency,false}, {read_concurrency,true}]),
        {ok, #monitor{
                         tasks = dict:new() ,
                         pids = dict:new(), 
                         tid = Tid}
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
    {reply, {dict:to_list(State#monitor.tasks),  dict:to_list(State#monitor.pids)}, State};
handle_call(Info,_From ,State) ->
    ?LOG_DEBUG("get msg call ~p ~n", [Info]),
    {reply, undefined , State}.

 
start_task_brutal(Key)->
    gen_server:cast(?MODULE, {start_task, Key}). 

start_task(Key, Params)->
    gen_server:cast(?MODULE, {start_task, Key, Params}).
    
start_task(Key)->
    gen_server:cast(?MODULE, {start_task, Key, []})      
.        
check_task_in_work(Key)->
    case ets:lookup(tasks, Key)  of 
        [{Key, Result = {_Status, _Pid} } ] ->  Result;
        [] ->   false
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

run_http(GetUrl, Headers)->
   spawn_monitor(fun()->  
                    ?CONSOLE_LOG(" task url  ~p ~p ~n",[ Host, GetUrl ]), 
                    httpc:request(get, {binary_to_list(GetUrl) ,  Headers }, [], [])
                 end) 
.
 

run_http( GetUrl)->
   run_http(GetUrl, [])
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
      

 
route_search(Key, [{Prefix, Host}|Tail]) ->
    case lists:prefix(Prefix, Key) of
       true -> Host;
       false-> route_search(Key, Tail)
    end
;
route_search(Key, [{<<>>, Host}]) -> %% yes it's match everything
   Host
.
 
process_params2headers({user_id, Value})->
  {<<"X-Forwarded-User">>, Value}
.
      
start_asyn_task(Key, Params, State)->
     Host = route_search(Key, State#monitor.routes),
     Headers = lists:map(fun(E)-> process_params2headers(E) end, Params),
     Url = lists:foldl(fun(Key, Url) -> << "/", Key/binary >>   end, <<>> ,Key),
     HostUrl = <<Host/binary, "/", Url/binary>>,
     run_http(HostUrl, Headers)
.
      

% start_asyn_task(Key = [<<"api">>, <<"my_orders">>, Var], State)->
%       run_http(Key, <<Url/binary,"api/my_orders/", Var/binary>>);  
% start_asyn_task(Key = [<<"api">>, <<"order">>, <<"status">>, Var], Url)->
%       run_http(Key, <<Url/binary,"api/order/status/", Var/binary>>);        
% start_asyn_task(Key = [<<"apui">>, <<"balance">>], Url)->
%       run_http(Key, <<Url/binary,"/api/balance", Var/binary>>);   
% start_asyn_task(Key = [<<"api">>, <<"trades">>, <<"buy">>, Var], Url)->
%       run_http(Key, <<Url/binary,"/api/trades/buy/", Var/binary>>);   
% start_asyn_task(Key = [<<"api">>, <<"trades">>, <<"sell">>, Var], Url)->
%     run_http(Key, <<Url/binary,"/api/trades/sell/", Var/binary>>);   
% start_asyn_task(Key = [<<"api">>, <<"deals">>, Var], Url)->
%     run_http(Key, <<Url/binary,"/api/deals/", Var/binary>>);   
% start_asyn_task(Key = [<<"api">>, <<"japan_stat">>, <<"high">>, Var], Url)->
%     run_http(Key, <<Url/binary, "/api/japan_stat/high/", Var/binary>>);   
% start_asyn_task(Key = [<<"api">>, <<"market_prices">>], Url)->
%     run_http(Key, <<Url/binary,"/api/market_prices">>).   
    
    
handle_cast({start_task_brutal, Key, Params }, MyState) ->
      {Pid, Mont} = start_asyn_task(Key, Params, MyState),
       DictNew1 = dict:store(Pid, Key, MyState#monitor.pids),
       DictNew2 = dict:store(Key, Pid, MyState#monitor.tasks),
       % duplicate info to ets table
       ets:insert(tasks, {Key, Pid}),
       {noreply, MyState#monitor{tasks=DictNew2, pids=DictNew1 } };
       
handle_cast({start_task, Key, Params }, MyState) ->
    case dict:find(Key, MyState#monitor.tasks) of
          {ok, Value} ->  {noreply, MyState};
          error ->
                {Pid, Mont} = start_asyn_task(Key, Params, MyState#monitor.routes),
                DictNew1 = dict:store(Pid, Key, MyState#monitor.pids),
                DictNew2 = dict:store(Key, Pid, MyState#monitor.tasks),
                % duplicate info to ets table
                ets:insert(tasks, {Key, Pid}),
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
    

handle_info({'DOWN',Ref,process, Pid, Exit},  State)->
    ?LOG_DEBUG("kill child process ~p ~p ~n", [Pid, Exit]),
     case  dict:find(Pid, State#monitor.pids) of 
          {ok, Key}->
             DictNew1 = dict:erase(Pid, State#monitor.pids),
             DictNew2 = dict:erase(Key, State#monitor.tasks),
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




