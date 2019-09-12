-module(erws_handler).

-include("erws_console.hrl").

% Behaviour cowboy_http_handler
-export([init/3, terminate/2]).
% Behaviour cowboy_http_websocket_handler
-behaviour(cowboy_websocket_handler).

-export([revertkey/1]).

-export([websocket_init/3]).

-export([websocket_handle/3]).

-export([websocket_info/3]).

-export([websocket_terminate/3]).


% Called to know how to dispatch a new connection.
init({tcp, http}, _Req, _Opts) ->
    % "upgrade" every request to websocket,
    % we're not interested in serving any other content.
    {upgrade, protocol, cowboy_websocket}.

terminate(_Req, _State) -> ok.

% Called for every new websocket connection.
websocket_init(_Any, Req, []) ->
    ?CONSOLE_LOG("~nNew client ~p", [Req]),
    { { IP, _Port }, Req_2 } = cowboy_req:peer(Req),
    {CookieSession, Req_3} = cowboy_req:cookie(<<"sessionid">>, Req_2, undefined), 
    {UserId, SessionObj} = auth_user( CookieSession ),
    %TODO make key from server
    ?CONSOLE_LOG("~n new session  ~n", []),
    ReqRes = cowboy_req:compact(Req_3),
    {ok, ApiToken} = application:get_env(front, token),
    State = #chat_state{ index = 0, 
                        user_id=UserId,
                        token=ApiToken, 
                        start=now(),
                        ip=IP, tasks=[],
                        sessionobj=SessionObj, 
                        sessionkey=CookieSession,
                        pid = self()},
    ets:insert(?CONNS, State),
    {ok, ReqRes, State, hibernate}.

% Called when a text message arrives.
websocket_handle({text, Msg}, Req, State =  #chat_state{index=Index}) ->
    ?CONSOLE_LOG("~p Received: ~p ~n ~p~n~n",
                [{?MODULE, ?LINE}, Req, State]),
    ?CONSOLE_LOG(" Req: ~p ~n", [Msg]),
    JsonMsg = erws_api:json_decode(Msg), % decode received json object
    {Res, ProcessNewState } = process(JsonMsg, State#chat_state.user_id, State),
    NewState = ProcessNewState#chat_state{index=Index+1},
    Req2 = cowboy_req:compact(Req),
    ?CONSOLE_LOG("~p send back: ~p ~n",
                [{?MODULE, ?LINE}, {NewState, Res}]),

    {reply, {text, Res}, Req2, NewState, hibernate};
% With this callback we can handle other kind of
% messages, like binary.
websocket_handle(Any, Req, State) ->
    ?CONSOLE_LOG("unexpected: ~p ~n ~p~n~n", [Any, State]),
    {ok, Req, State}.

% Other messages from the system are handled here.
websocket_info({msg, Msg}, Req, State)->    
       ?CONSOLE_LOG("simple message result from somebody ~p to ~p",[Msg, State]),
       {reply, {text, Msg}, Req, hibernate}
;
websocket_info({deal_info, Msg}, Req, State)->
       ?CONSOLE_LOG("callback result from somebody ~p to ~p",[Msg, State]),
       {reply, {text, Msg}, Req, hibernate};
websocket_info({task_result, MyKey, Body, 200}, Req, State) ->
      ?CONSOLE_LOG("info: ~p ~n ~p~n~n", [Req, State]),

      ResTime = restime(State#chat_state.user_id, State),
      ?CONSOLE_LOG("callback result of task  ~p for ~p ~n",[MyKey, State]),
      {Key, Params} = MyKey,
      PreKey = case State#chat_state.user_id of
                   undefined -> Key;
                   Value ->  BinUserId = list_to_binary( integer_to_list(Value)), lists:delete(BinUserId, Key)
               end,                 
      FirstKey = revertkey(PreKey),
      ResBinary = <<"\"",FirstKey/binary, "\":", Body/binary>>,  
      Req2 = cowboy_req:compact(Req),
      Tasks =  State#chat_state.tasks,
      {reply, {text,  << "{\"result\":{", ResBinary/binary,"}, \"time_object\":", ResTime/binary, "}">> }, Req2, 
               State#chat_state{tasks=lists:delete(Key, Tasks)} , hibernate};
websocket_info({task_result, MyKey, _Body, OtherOf200}, Req, State) ->
      %%% TODO rework 500 task
      ?CONSOLE_LOG("info: ~p ~n ~p result is  ~p ~n~n", [Req, State, OtherOf200]),
      ResTime = restime(State#chat_state.user_id, State),
      {Key, Params} = MyKey,
      ?CONSOLE_LOG("callback result of task  ~p for ~p ~n",[Key, State]),
      PreKey = case State#chat_state.user_id of
                   undefined -> Key;
                   Value ->  BinUserId = list_to_binary( integer_to_list(Value)), 
                             lists:delete(BinUserId, Key)
               end,                 
      FirstKey = revertkey(PreKey),
      ResBinary = <<"\"",FirstKey/binary, "\": false" >>,  
      Req2 = cowboy_req:compact(Req),
      Tasks =  State#chat_state.tasks,
      
      {reply, {text,  << "{\"result\":{", ResBinary/binary,"}, \"time_object\":", ResTime/binary, "}">> }, Req2, 
               State#chat_state{tasks=lists:delete(Key, Tasks)} , hibernate};
websocket_info(_Info, Req, State) ->
    ?CONSOLE_LOG("info: ~p ~n ~p~n~n", [Req, State]),
    {ok, Req, State, hibernate}.
    

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

my_tokens(PreString)->
     [String|QTail]  = binary:split(PreString, [<<"?">>],[global]),
     binary:split(String, [<<"/">>],[global]).


start_delayed_task(Command,  undefined, State)->
    Key =  my_tokens(Command),
    case api_table_holder:find_in_cache(Key) of
                false-> 
                    ?CONSOLE_LOG(" start task ~p ~n",[ Key]),
                    api_table_holder:start_task(Key, [], self()),
                    Tasks = State#chat_state.tasks,    
                    { wait_response(), State#chat_state{tasks=[Key|Tasks] } };
                Val -> 
                    ?CONSOLE_LOG(" wait task ~p ~p ~n",[ Val, Key ]),
                    Tasks = State#chat_state.tasks,    
                    BinCommanKey = revertkey(Key),
                    { << "{","\"",BinCommanKey/binary, "\":", Val/binary, "}">>, State#chat_state{tasks=lists:delete(Key, Tasks)} } 
    end;
start_delayed_task(Command,  UserId, State)->
    StringTokens =  my_tokens(Command),
    Key =   case api_table_holder:public(StringTokens) of 
                  true ->  StringTokens;
                  false -> StringTokens ++ [list_to_binary(integer_to_list(UserId))] %% adding userid to the path in order to unify this request in cache
            end,
    case api_table_holder:find_in_cache(Key) of
                false-> 
                    ?CONSOLE_LOG(" start task ~p ~n",[ Key]),
                    api_table_holder:start_task(Key, [ {user_id, integer_to_list(UserId) }, {token, State#chat_state.token } ], self()),
                    Tasks = State#chat_state.tasks,    
                    { wait_response(), State#chat_state{tasks=[Key|Tasks] } };
                Val -> 
                    ?CONSOLE_LOG(" wait task ~p ~p ~n",[ Val, Key ]),
                    Tasks = State#chat_state.tasks,
                    BinCommanKey = revertkey(Key),
                    {  << "{", "\"" , BinCommanKey/binary, "\":", Val/binary, "}">>, State#chat_state{tasks=lists:delete(Key, Tasks)} } 
    end.
       

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
 
process({[{<<"get">>, Var}]}, UserId, State)->
% TODO 
% field task object as saved = started or not
% if task exist with result return it and pop from tasks
% if tasks not exist start it gather user information
%   starting tasks
    ?CONSOLE_LOG(" get task for ~p ~p ~n",[ Var, UserId ]),

    {Result, NewState} =  start_delayed_task(Var, UserId, State),
    ResTime = restime(UserId, State),
    
    {<< "{\"result\":", Result/binary,",\"time_object\":", ResTime/binary,"}">>, NewState}
;
process({[{<<"ping">>, true}] }, undefined, State)->
      ResTime = restime(undefined, State),
      looking4finshed(ResTime, undefined, State)
;
%TODO
% check ready tasks if existed return it all
process( ReqJson = {[{<<"ping">>, true}]}, UserId, State)->
    ResTime = restime(UserId, State),
    looking4finshed(ResTime, UserId, State)
.

restime(undefined, State)->
      ResTime = [{<<"deal_comission">>, <<"0.1">>},
               {<<"use_f2a">>, false},
               {<<"logged">>, false},
               {<<"x-cache">>, true},
               {<<"status">>, true}
              ],

      ResTime1  = erws_api:get_usd_rate(ResTime),
      ResTime2 = erws_api:get_time(ResTime1),
      ResTime3 = erws_api:get_state(ResTime2),
      erws_api:json_encode({ResTime3})
;    
restime(UserId, State)->
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
    ResTime = [
        {<<"logged">>, true},
        {<<"x-cache">>, true},
        {<<"status">>, true},
        {<<"sessionid">>, SessionKeyCustom},
        {<<"ui_settings">>, UiSettingsJ },
        {<<"ui_msg">>, erws_api:get_key_dict(SessionObj, <<"ui_msg">>, <<"">> ) },
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
          undefined -> {undefined, dict:new()};
          _ ->
              SessionObj =  erws_api:load_user_session(erws_api:django_session_key(CookieSession)),
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
      
      
      
