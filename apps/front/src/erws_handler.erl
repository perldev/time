-module(erws_handler).

-include("erws_console.hrl").

% Behaviour cowboy_http_handler
-export([init/3, terminate/2]).
% Behaviour cowboy_http_websocket_handler
-behaviour(cowboy_websocket_handler).

-export([revertkey/1, process/3]).

-export([websocket_init/3]).

-export([websocket_handle/3]).

-export([websocket_info/3]).

-export([websocket_terminate/3]).


% Called to know how to dispatch a new connection.
init({tcp, http}, _Req, _Opts) ->
    % "upgrade" every request to websocket,
    % we're not interested in serving any other content.
    {upgrade, protocol, cowboy_websocket}.

terminate(_Req, State) -> 
                ?CONSOLE_LOG("termination of socket: ~p ,~n",
                [State]).

% Called for every new websocket connection.
websocket_init(_Any, Req, []) ->
    ?CONSOLE_LOG("~nNew client ~p", [Req]),
    {IP, Req_2 } = cowboy_req:header(<<"x-real-ip">>, Req, undefined),

    {CookieSession, Req_3} = cowboy_req:qs_val(<<"token">>, Req_2, undefined), 
    {UserId, SessionObj} = auth_user( CookieSession ),
    %TODO make key from server
    ?CONSOLE_LOG("~n new session  ~n", []),
    ReqRes = cowboy_req:compact(Req_3),
    {ok, ApiToken} = application:get_env(front, token),
    State = #chat_state{
                        index = 0, 
                        user_id=UserId,
                        token=ApiToken, 
                        start=now(),
                        ip=IP,
                        tasks=[],
                        sessionobj=SessionObj, 
                        sessionkey=CookieSession,
                        pid = self()},
    ets:insert(?CONNS, State),
    {ok, ReqRes, State}.

% Called when a text message arrives.
websocket_handle({text, Msg}, Req, State=#chat_state{index=Index}) ->
    ?CONSOLE_LOG("~p Received: ~p ~n ~p~n~n",
                [{?MODULE, ?LINE}, Req, State]),
    ?CONSOLE_LOG(" Req: ~p ~n", [Msg]),
    JsonMsg = erws_api:json_decode(Msg), % decode received json object
    {Res, ProcessNewState } = process(JsonMsg, State#chat_state.user_id, State),
    NewState = ProcessNewState#chat_state{index=Index+1},
    Req2 = cowboy_req:compact(Req),
    ?CONSOLE_LOG("~p send back: ~p ~n",
                [{?MODULE, ?LINE}, {NewState, Res}]),
    ets:insert(?CONNS, NewState),                
    case Res of
        ok  -> {ok, Req2, NewState};
        Res -> {reply, {text, Res}, Req2, NewState}
    end;
% With this callback we can handle other kind of
% messages, like binary.
websocket_handle(Any, Req, State) ->
    ?CONSOLE_LOG("unexpected: ~p ~n ~p~n~n", [Any, State]),
    {ok, Req, State}.

% Other messages from the system are handled here.
websocket_info({msg, Msg}, Req, State)->    
       ?CONSOLE_LOG("simple message result from somebody ~p to ~p",[Msg, State]),
        ResTime = restime(State#chat_state.user_id, State, Msg),
       {reply, {text, ResTime},  Req, State}
;
websocket_info({deal_info, Msg}, Req, State)->
       ?CONSOLE_LOG("callback result from somebody ~p to ~p",[Msg, State]),
       {reply, {text, Msg}, Req, State};       
websocket_info({http, {ReqestId,  { {HttpVer, 200, HTTP}, _Headers, Body} } }, Req, State )->
    ?CONSOLE_LOG("get result from task child process ~p ~p ~n", [ReqestId,  { {HttpVer, Status, HTTP}, _Headers, Body} ]),
    Tasks =  State#chat_state.tasks,
    case lists:keysearch(ReqestId, 1, Tasks) of 
        {value, {ReqestId, Key, Command}} ->
            Msg =   << "{", "\"/" , Command/binary, "\":", Body/binary, "}">>,
            NewTaskList = lists:keydelete(ReqestId, 1,  Tasks),
            {reply, {text, Msg}, Req, State#chat_state{tasks=NewTaskList}};
        _ ->
            ?CONSOLE_LOG("unexpected  result from somebody ~p to ~p",[ReqestId, State]),
            {ok, Req, State}

    end
;%%everything other than 200 just delete
websocket_info({http, {ReqestId,  Res} }, Req, State )->
    ?CONSOLE_LOG("get FAIL result  from task child process ~p ~p ~n", [ReqestId,  Res ]),
    Tasks =  State#chat_state.tasks,
    NewTaskList = lists:keydelete(ReqestId, 1,  Tasks),
    {ok, Req, State#chat_state{tasks=NewTaskList}}
;
websocket_info(_Info, Req, State) ->
      ?CONSOLE_LOG("info: ~p ~n ~p~n~n", [Req, State]),
      {ok, Req, State}.
    

websocket_terminate(Reason, Req, State) ->
    
    ?CONSOLE_LOG("terminate: ~p ,~n ~p, ~n ~p~n~n",
		 [Reason, Req, State]),
    ok.

% jiffy     {[
%                     {<<"logged">>, true} }

%     Doc4 =   [ {[{<<"bing">>,1},{<<"test">>,2}]}, 2.3, true] .
% [{[{<<"bing">>,1},{<<"test">>,2}]},2.3,true]
% (shellchat@localhost.localdomain)16> jiffy:encode( Doc4).                                      
% <<"[{\"bing\":1,\"test\":2},2.3,true]">>
% 
% 

wait_response()->
   erws_api:json_encode({[{<<"status">>, <<"wait">>}]}).

   
wait_tasks_in_work(State)->
    SessionKey = State#chat_state.sessionkey,
    
    lists:foldl(fun(Key, {List, TempState})-> 
                    ?CONSOLE_LOG(" check key from erws handler ~p ~n",[ Key ]),
                    case api_table_holder:find_in_cache(Key) of 
                        false -> {List, TempState};
                        Val -> 
                            Tasks = State#chat_state.tasks,    
                            {[{Key, Val}|List], TempState#chat_state{tasks=lists:delete(Key, Tasks) } } %%binary
                    end
                end, {[], State}, State#chat_state.tasks)
.
   
revertkey(Command)->
   lists:foldl(fun(Key, Url) -> <<Url/binary, "/", Key/binary >>   end, <<>>, Command)
.


url_encode(Q)->
    List = binary:split(Q, [<<"&">>],[global]),
    url_encode(List, <<>>).

url_encode([], Accum)->
    Accum;
url_encode([K|Tail], Accum)->
   case binary:split(K, [<<"=">>],[]) of
    [Key, Value] -> 
        KeyB = list_to_binary(edoc_lib:escape_uri( binary_to_list(Key))),
        ValueB = list_to_binary(edoc_lib:escape_uri(binary_to_list(Value))),    
        url_encode(Tail, <<KeyB/binary,"=", ValueB/binary,"&", Accum/binary>>);
    [Key]->
        KeyB = list_to_binary(edoc_lib:escape_uri( binary_to_list(Key))),    
        url_encode(Tail, <<KeyB/binary,"=&", Accum/binary>>)
   end. 


my_tokens(PreString)->
    case binary:split(PreString, [<<"?">>],[global]) of
     [String, QTail]  -> {binary:split(String, [<<"/">>],[global]), url_encode(QTail)};
     [String]->{binary:split(String, [<<"/">>],[global]), <<>>}
    end.

     
   


start_sync_task(Command,  undefined, State)->
    {Key, Q} =  my_tokens(Command),  
    ?CONSOLE_LOG(" start task ~p ~p ~n",[ Key, Q]),
    Val = api_table_holder:start_synctask(Key, [], Q, [{sync, true}, {body_format, binary}]),
    ?CONSOLE_LOG(" wait task ~p ~p ~n",[ Val, Key ]),
    { << "{","\"/",Command/binary, "\":", Val/binary, "}">>, State };
start_sync_task(Command,  UserId, State)->
    {StringTokens, Q} =  my_tokens(Command),
    ?CONSOLE_LOG(" start task ~p ~p ~n",[ StringTokens, Q]),

    Key =   case api_table_holder:public(StringTokens) of 
                  true ->  StringTokens;
                  false -> StringTokens ++ [list_to_binary(integer_to_list(UserId))] %% adding userid to the path in order to unify this request in cache
            end,
    Val = api_table_holder:start_synctask(Key, [ {user_id, integer_to_list(UserId) }, {token, State#chat_state.token } ], Q, [{sync, true}, {body_format, binary}]),
    ?CONSOLE_LOG(" wait task ~p ~p ~n",[ Val, Key ]),
    {  << "{", "\"/" , Command/binary, "\":", Val/binary, "}">>, State}.

start_delayed_task(Command,  undefined, State)->
    {Key, Q} =  my_tokens(Command),  
    ?CONSOLE_LOG(" start task ~p ~p ~n",[ Key, Q]),
    {ok, Val} = api_table_holder:start_synctask(Key, [], Q, [{sync, false}, {body_format, binary}]),
    ?CONSOLE_LOG(" wait task ~p ~p ~n",[ Val, Key ]),
    {Val, Key, Command}    
    ;
start_delayed_task(Command,  UserId, State)->
    {StringTokens, Q}  =  my_tokens(Command),
    Key =   case api_table_holder:public(StringTokens) of 
                  true ->  StringTokens;
                  false -> StringTokens ++ [list_to_binary(integer_to_list(UserId))] %% adding userid to the path in order to unify this request in cache
            end,
    {StringTokens, Q} =  my_tokens(Command),
    ?CONSOLE_LOG(" start task ~p ~p ~n",[ StringTokens, Q]),

    Key =   case api_table_holder:public(StringTokens) of 
                  true ->  StringTokens;
                  false -> StringTokens ++ [list_to_binary(integer_to_list(UserId))] %% adding userid to the path in order to unify this request in cache
            end,
    {ok, Val} = api_table_holder:start_synctask(Key, [ {user_id, integer_to_list(UserId) }, {token, State#chat_state.token } ], Q, [{sync, false}, {body_format, binary}]),
    ?CONSOLE_LOG(" wait task ~p ~p ~n",[ Val, Key ]),
    {Val, Key, Command}    
.
       

looking4finshed(ResTime, undefined, State)-> 
      ?CONSOLE_LOG(" looking finished tasks for anonym ~p ~p ~n",[ResTime, State]),
      case wait_tasks_in_work(State) of 
        {[], NewState}  ->  {<< "{\"time_object\":", ResTime/binary,"}">> , NewState };
        { [Head|Result], NewState } -> 
                                %% NOT very good way of producings delayed tasks
                                ?CONSOLE_LOG("corrupt json in order to add  info from tasks  ~p ~n",[ResTime]),
                                { FirstBinCommanKey, FirstBinaryValue} = Head,
                                FirstKey = revertkey(FirstBinCommanKey),
                                StartBinary = <<"\"",FirstKey/binary, "\":", FirstBinaryValue/binary>>,  
                                ResBinary = lists:foldl(fun({ BinCommanKey, BinaryValue}, Binary)->  
                                                                                              Key = revertkey(BinCommanKey),
                                                                                              <<Binary/binary, ",",
                                                                                                "\"",  Key/binary, "\":", %%join path for client 
                                                                                                BinaryValue/binary>> end,  StartBinary, Result),
                                {<< "{\"result\":{", ResBinary/binary,"},\"time_object\":", ResTime/binary, "}">>, NewState}
                                
      end;    
looking4finshed(ResTime, UserId, State)-> 
      ?CONSOLE_LOG(" looking finished tasks for ~p for ~p ~n",[ ResTime, State]),
      BinUserId = list_to_binary(integer_to_list(UserId)),
      case wait_tasks_in_work(State) of 
        {[], NewState}  ->  {<< "{\"time_object\":", ResTime/binary,"}">> , NewState };
        { [Head|Result], NewState } -> 
                                %% NOT very good way of producings delayed tasks
                                ?CONSOLE_LOG("corrupt json in order to add  info from tasks  ~p ~n",[ResTime]),
                                { FirstCommand, FirstBinaryValue} = Head,
                                FirstBinCommanKey = lists:delete(BinUserId, FirstCommand),
                                FirstKey = revertkey(FirstBinCommanKey),
                                StartBinary = <<"\"",FirstKey/binary, "\":", FirstBinaryValue/binary>>,  
                                ResBinary = lists:foldl(fun({ Command, BinaryValue}, Binary)->  
                                                                                              BinCommanKey = lists:delete(BinUserId, Command),
                                                                                              Key = revertkey(BinCommanKey),
                                                                                              <<Binary/binary, ",",
                                                                                                "\"",  Key/binary, "\":", %%join path for client 
                                                                                                BinaryValue/binary>> end,  StartBinary, Result),
                                {<< "{\"result\":{", ResBinary/binary,"},\"time_object\":", ResTime/binary, "}">>, NewState}
      end.
 
 
process({[{<<"syncget">>, Var}]}, UserId, State)->
% TODO 
% field task object as saved = started or not
% if task exist with result return it and pop from tasks
% if tasks not exist start it gather user information
%   starting tasks
    ?CONSOLE_LOG(" get sync task for ~p ~p ~n",[ Var, UserId ]),
    {Result, NewState} =  start_sync_task(Var, UserId, State),
    ?CONSOLE_LOG(" and result of it ~p ~n",[ Result]),
    { << "{\"result\":", Result/binary,"}">> , NewState}
; 
process({[{<<"get">>, Var}]}, UserId, State)->
% TODO 
% field task object as saved = started or not
% if task exist with result return it and pop from tasks
% if tasks not exist start it gather user information
%   starting tasks
    ?CONSOLE_LOG(" get task for ~p ~p ~n",[ Var, UserId ]),
    {ReqestId, Key, Command} =  start_delayed_task(Var, UserId, State),
    L = State#chat_state.tasks,
    {<< "{\"status\": True}">> , State#chat_state{tasks=[{ReqestId, Key, Command}|L]}}
  
;
process({[{<<"echo">>, true}] }, _, State)->
        ResTime = restime(undefined, State, <<"this ">>),
        {ResTime, State}
;
process({[{<<"ping">>, true}] }, undefined, State)->
      ResTime = restime(undefined, State),
      { <<"{\"time_object\":", ResTime/binary, "}">> , State}
;
%TODO
% check ready tasks if existed return it all
process( ReqJson = {[{<<"ping">>, true}]}, UserId, State)->
    ResTime = restime(UserId, State),
    {<<"{\"time_object\":",  ResTime/binary, "}">>, State}
.


restime(UserId, State)->
    restime(UserId, State, <<>>)
.

restime(undefined, State, UiMsg)->
      ResTime = [{<<"deal_comission">>, <<"0.1">>},
               {<<"use_f2a">>, false},
               {<<"logged">>, false},
               {<<"ui_msg">>, UiMsg},
               {<<"x-cache">>, true},
               {<<"status">>, true}
              ],

      ResTime1  = erws_api:get_usd_rate(ResTime),
      ResTime2 = erws_api:get_time(ResTime1),
      ResTime3 = erws_api:get_state(ResTime2),
      erws_api:json_encode({ResTime3})
;    
restime(UserId, State, UiMsg)->
    UserIdBinary = list_to_binary(integer_to_list(UserId)),
    SessionKey =  State#chat_state.sessionkey,
    SessionObj =  State#chat_state.sessionobj,
    ?CONSOLE_LOG("session obj ~p ~n",[SessionObj]),
    ?CONSOLE_LOG("user id ~p~n", [UserIdBinary]), 
    SessionKeyCustom = list_to_binary(erws_api:hexstring(crypto:hash(sha256, <<?KEY_PREFIX, SessionKey/binary, UserIdBinary/binary>>))), 
    UiSettingsJ = case erws_api:get_key_dict(SessionObj, <<"ui_settings">>, [] ) of
                    [] ->  [];
                    UiSettings -> erws_api:dict_to_json(UiSettings)
                  end,
   ?CONSOLE_LOG("session obj ~p ~n",[SessionObj]),
    ResTime = [
        {<<"logged">>, true},
        {<<"x-cache">>, true},
        {<<"status">>, true},
        {<<"sessionid">>, SessionKeyCustom},
        {<<"ui_settings">>, UiSettingsJ },
        {<<"ui_msg">>, UiMsg},
        {<<"user_custom_id">>, erws_api:get_key_dict(SessionObj, <<"user_custom_id">>, <<>>) },
        {<<"use_f2a">>, erws_api:get_key_dict(SessionObj, <<"use_f2a">>, false) },
        {<<"deal_comission">>, erws_api:get_key_dict(SessionObj, <<"deal_comission_show">>, <<"0.05">>) }
        ],
    
    {pickle_unicode, UserName } = erws_api:get_key_dict(SessionObj, <<"username">>, {pickle_unicode, <<>>} ),
    ?CONSOLE_LOG("time to user ~p ~n",[ResTime]),

    % move spawn
    mcd:set(?LOCAL_CACHE, <<?KEY_PREFIX, "chat_", SessionKeyCustom/binary>>, pickle:term_to_pickle(UserName)),
    mcd:set(?LOCAL_CACHE, <<?KEY_PREFIX, "user_", UserIdBinary/binary>>, pickle:term_to_pickle(SessionKey)),   
    ResTime1  = erws_api:get_usd_rate(ResTime),
    ResTime3 = erws_api:get_time(ResTime1),
    ResTime4 = erws_api:get_state(ResTime3),
    erws_api:json_encode({ResTime4})
.
    
    
    
auth_user(CookieSession)->
       ?CONSOLE_LOG(" auth for session  ~p ~n",[ CookieSession]),
       case CookieSession of 
          undefined ->
                ?CONSOLE_LOG(" nothing found for auth for session  ~p ~n",[ CookieSession]),
                {undefined, dict:new()};
          _ ->
              SessionObj =  erws_api:load_user_session(erws_api:django_read_token(CookieSession)),
              ?CONSOLE_LOG(" load session ~p ~n",[SessionObj]),
              case SessionObj of 
                undefined -> {undefined, dict:new()};
                SessionObj ->
                    case erws_api:get_key_dict(SessionObj, <<"user_id">>, false) of
                            false -> {undefined, SessionObj};
                            UserId-> {UserId, SessionObj}
                    end
              end      
      end     
.
