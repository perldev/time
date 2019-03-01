-module(erws_handler).

-include("erws_console.hrl").

% Behaviour cowboy_http_handler
-export([init/3, terminate/2]).
% Behaviour cowboy_http_websocket_handler
-behaviour(cowboy_websocket_handler).

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
    {ok, ReqRes, #chat_state{ index = 0, user_id=UserId, start=now(), ip=IP, tasks=[], sessionobj=SessionObj, sessionkey=CookieSession}, hibernate}.

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
    lists:foldl(fun(Key, {List, TempState})-> 
                    case api_table_holder:find_in_cache(Key) of 
                        false -> {List, TempState};
                        Val -> 
                            Tasks = State#chat_state.tasks,    
                            {[{Key, Val}|List], TempState#chat_state{tasks=lists:delete(Key, Tasks) } } %%binary
                    end
                end, {[], State}, State#chat_state.tasks)
.
   
revertkey(Command)->
   lists:foldl(Key, Url) -> << "/", Key/binary >>   end, <<>>, Command)
.
   
process_delayed_task(Command,  UserId, State)->
    StringTokens =  string:tokens(Command),
    Key = case api_table_holder:public(StringTokens) of 
                  true ->  StringTokens;
                  false -> string:tokens(StringTokens) ++ integer_to_list(UserId)
            end,
    case api_table_holder:check_task_in_work(Key,  State)  of 
        false -> 
                case api_table_holder:find_in_cache(Key) of
                    false-> 
                    ?CONSOLE_LOG(" start task ~p ~n",[ Key]),
                        api_table_holder:start_task(Key, [ {user_id, list_to_binary(integer_to_list(UserId)) }] ),
                        Tasks = State#chat_state.tasks,    
                        { wait_response(), State#chat_state{tasks=[Key|Tasks] } } 
                    Val -> 
                        ?CONSOLE_LOG(" wait task ~p ~p ~n",[ Val, Key ]),
                        Tasks = State#chat_state.tasks,    
                        {Val, State#chat_state{tasks=lists:delete(Key, Tasks) } 
                end;
        Result ->
            %% add here timeout of repeat execution, or failed tasks
            ?CONSOLE_LOG(" we have found  task in work ~p ~n",[ Key ]),
            Tasks = State#chat_state.tasks,    
            { wait_response(), State#chat_state{tasks=[Key|Tasks] } } 
    end.

looking4finshed(ResTime, undefined, State)-> 
      ?CONSOLE_LOG(" looking finished tasks for anonym ~n",[ ]),
      case wait_tasks_in_work(State) of 
        {[], NewState}  ->  {erws_api:json_encode({ResTime}), NewState };
        { Result, NewState } -> 
                                %% NOT very good way of producings delayed tasks
                                TempBinary =  erws_api:json_encode({ResTime}),
                                TempBinary2 = binary:replace(TempBinary, <<"}">>,<<>>),
                                ?CONSOLE_LOG("corrupt json in order to add  info from tasks  ~p ~n",[TempBinary2]),
                                ResBinary = lists:foldl(fun({ Command, BinaryValue}, Binary)->  
                                                                                              Key = revertkey(Command),
                                                                                              <<Binary/binary, ",\"",
                                                                                              Key/binary, "\":", %%join path for client 
                                                                                              BinaryValue/binary>> end, TempBinary2, Result),
                                
                            { <<ResBinary/binary, "}">>, NewState}
      end;    
looking4finshed(ResTime, UserId, State)-> 
      ?CONSOLE_LOG(" looking finished tasks for ~p ~n",[ UserId ]),
      BinUserId = list_to_binary(integer_to_list(UserId)),
      case wait_tasks_in_work(State) of 
        {[], NewState}  ->  {erws_api:json_encode({ResTime}), NewState };
        { Result, NewState } -> 
                                %% NOT very good way of producings delayed tasks
                                TempBinary =  erws_api:json_encode({ResTime}),
                                TempBinary2 = binary:replace(TempBinary, <<"}">>,<<>>),
                                ?CONSOLE_LOG("corrupt json in order to add  info from tasks  ~p ~n",[TempBinary2]),
                                ResBinary = lists:foldl(fun({ Command, BinaryValue}, Binary)->  
                                                                                              BinCommanKey = lists:delete(BinUserId, Command),
                                                                                              Key = revertkey(BinCommanKey),
                                                                                              <<Binary/binary, ",\"",
                                                                                              Key/binary, "\":", %%join path for client 
                                                                                              BinaryValue/binary>> end, TempBinary2, Result),
                                
                            { <<ResBinary/binary, "}">>, NewState}
      end.
 
process({[{<<"get">>, Var}]}, UserId, State)->
% TODO 
% field task object as saved = started or not
% if task exist with result return it and pop from tasks
% if tasks not exist start it gather user information
%   starting tasks

    {Result, NewState} =  process_delayed_task(Var, UserId, State),
    {Result, NewState}
;
process({[{<<"ping">>, true}] }, undefined, State)->
    ResTime = [{<<"deal_comission">>, <<"0.1">>},
               {<<"use_f2a">>, false},
               {<<"logged">>, false},
               {<<"x-cache">>, true},
               {<<"status">>, true}
              ],

      ResTime1  = erws_api:get_usd_rate(ResTime),
      ResTime2 = erws_api:get_time(ResTime1),
      ResTime3 = erws_api:get_state(ResTime2),
      looking4finshed(ResTime3, undefined, State)
;
%TODO
% check ready tasks if existed return it all
process( ReqJson = {[{<<"ping">>, true}]}, UserId, State)->
    UserIdBinary = list_to_binary(integer_to_list(UserId)),
    SessionKey =  State#chat_state.sessionkey,
    SessionObj =  State#chat_state.sessionobj,
    ?CONSOLE_LOG("session obj ~p ~n",[SessionObj]),
    ?CONSOLE_LOG("user id ~p~n", [UserIdBinary]), 
    SessionKeyCustom = list_to_binary(erws_api:hexstring(crypto:hash(sha256, <<?KEY_PREFIX, SessionKey/binary, UserIdBinary/binary>>))), 
    ResTime = [
        {<<"logged">>, true},
        {<<"x-cache">>, true},
        {<<"status">>, true},
        {<<"sessionid">>, SessionKeyCustom},
        {<<"user_custom_id">>, erws_api:get_key_dict(SessionObj, <<"user_custom_id">>, <<>>) },
        {<<"use_f2a">>, erws_api:get_key_dict(SessionObj, <<"use_f2a">>, false) },
        {<<"deal_comission">>, erws_api:get_key_dict(SessionObj, <<"deal_comission_show">>, <<"0.05">>) }
        ],		
    {pickle_unicode, UserName } = erws_api:get_key_dict(SessionObj, <<"username">>, {pickle_unicode, <<>>} ),
    % move spawn
    mcd:set(?LOCAL_CACHE, <<?KEY_PREFIX, "chat_", SessionKeyCustom/binary>>, pickle:term_to_pickle(UserName)),
    mcd:set(?LOCAL_CACHE, <<?KEY_PREFIX, "user_", UserIdBinary/binary>>, pickle:term_to_pickle(SessionKey)),   
    ResTime1  = erws_api:get_usd_rate(ResTime),
    ResTime3 = erws_api:get_time(ResTime1),
    %ResTime4 = erws_api:get_user_state(ResTime3, UserIdBinary),
    ResTime4 = erws_api:get_state(ResTime3),
    looking4finshed(ResTime4, UserId, State).
    
auth_user(CookieSession)->
       ?CONSOLE_LOG(" auth for session  ~p ~n",[ CookieSession]),
       case CookieSession of 
          undefined -> undefined;
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
      
      
      
