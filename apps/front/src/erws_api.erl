-module(erws_api).

-include("erws_console.hrl").


% Behaviour cowboy_http_handler
-export([init/3, handle/2, terminate/3,load_user_session/1, django_session_key/1, django_read_token/1,
         hexstring/1, get_key_dict/3,get_usd_rate/1, get_user_state/2, 
         get_user_state/3, get_state/1, get_time/1, json_encode/1, json_decode/1, dict_to_json/1]).

% Behaviour cowboy_http_websocket_handler



% Called to know how to dispatch a new connection.
init({tcp, http}, Req, Opts) ->
    { Path, Req3} = cowboy_req:path_info(Req),
    ?CONSOLE_LOG("Request: ~p ~n", [ {Req, Path, Opts} ]),
    % we're not interested in serving any other content.
    {ok, Req3, Opts}
.
    
terminate(_Req, _State, _Reason) ->
    ok.

headers_text_plain() ->
        [ {<<"access-control-allow-origin">>, <<"*">>},  {<<"Content-Type">>, <<"text/plain">>} ].
        
headers_text_html() ->
        [ {<<"access-control-allow-origin">>, <<"*">>},  {<<"Content-Type">>, <<"text/html">>}  ].      

headers_json_plain() ->
        [ {<<"access-control-allow-origin">>, <<"*">>},  {<<"Content-Type">>, <<"application/json">>} ].
        
headers_png() ->
        [ {<<"access-control-allow-origin">>, <<"*">>},
          {<<"Cache-Control">>, <<"no-cache, must-revalidate">>},
          {<<"Pragma">>, <<"no-cache">>},
          {<<"Content-Type">>, <<"image/png">>} 
        ].
                
                
        
% Should never get here.
handle(Req, State) ->
      ?CONSOLE_LOG("====================================~nrequest: ~p ~n", [Req]),
      {Path, Req1} = cowboy_req:path_info(Req),
      {ok, Body, Req2 } = cowboy_req:body(Req1),      
      {UserId, ResReq} = auth_user(Req2, Body, State),
         
      ?CONSOLE_LOG("====================================~n user id: ~p ~n", [UserId]),
      case process(Path, UserId, Body, ResReq, State) of
	  {json, Json, ResReqLast, NewState }->
		?CONSOLE_LOG("got request result: ~p~n", [Json]),
		{ok, JsonReq} = cowboy_req:reply(200, headers_json_plain(), json_encode(Json), ResReqLast),
		{ok, JsonReq, NewState};
          {raw_answer, {Code, Binary, Headers }, ResReqLast, NewState } ->
		{ok, RawReq} = cowboy_req:reply(Code, Headers, Binary, ResReqLast),
		{ok, RawReq, NewState}
      end.      

terminate(_Req, _State) -> ok.

false_response(Req, State)->
   {raw_answer, {500, <<"{\"status\":\"false\"}">>, headers_json_plain() },  Req, State}.
 
wait_response(Req, State)->
   {raw_answer, {502, <<"{\"status\":\"wait\",\"timeout\":1000}">>, headers_json_plain() },  Req, State}.
 
 
-spec check_sign(tuple(), binary(), list())-> true|false. 
check_sign({undefined, undefined}, Body, State)->
  false;
check_sign({Sign, LocalKey}, Body, State)->
    CheckSign = generate_key(LocalKey, Body),
    ?CONSOLE_LOG("got salt result: calc sign ~p~n got sign ~p~n salt ~p~n body ~p~n ", 
                [CheckSign, Sign, LocalKey, Body ]),
    case list_to_binary(CheckSign)  of 
        Sign -> true;
        _ -> false
   end
.
% 

process_delayed_task(Key, Req, State)->
    
 case api_table_holder:check_task_in_work(Key)  of 
     false-> 
               case api_table_holder:find_in_cache(Key) of
                  false-> 

                           ?CONSOLE_LOG("start task ~p ~n",[ Key]),
                           api_table_holder:start_task(Key), 
                           wait_response(Req, State); 
                  Val -> 
            
                       ?CONSOLE_LOG(" wait task ~p ~p ~n",[ Val, Key ]),
                       {raw_answer, {200, Val, headers_json_plain() },  Req, State}   
               end;
     _ ->
           ?CONSOLE_LOG(" we have found  task in work ~p ~n",[ Key ]),
           wait_response(Req, State)
 end

.

process([<<"tasks">>, <<"restartall">> ,<<"mysecretkey2">>], _, _Body, Req, State)->
    TasksState = api_table_holder:restartall(),
    Tasks = dict:to_list(TasksState#monitor.tasks),
    ResTime = lists:map(fun({Elem, Val})-> { erws_handler:revertkey(Elem), list_to_binary(lists:flatten(io_lib:format("~p", [Val]))) } end, Tasks),
    {json, {ResTime}, Req, State};
process([<<"tasks">>, <<"mysecretkey2">>], _, _Body, Req, State)->
    TasksState = api_table_holder:status(),
    Tasks = dict:to_list(TasksState#monitor.tasks),
    ResTime = lists:map(fun({Elem, Val})-> { erws_handler:revertkey(Elem), list_to_binary(lists:flatten(io_lib:format("~p", [Val]))) } end, Tasks),
    {json, {ResTime}, Req, State};    
process(Key = [<<"start">>, <<"api">>| Tail], _User, _Body, Req, State)->
    ?CONSOLE_LOG(" cold start ~p ~n",[ Key]),
    [_|Task] = Key,
    api_table_holder:start_task_brutal(Task), 
    wait_response(Req, State); 
process(Key = [<<"api">>| Tail], _User, _Body, Req, State)->
    ?CONSOLE_LOG(" process path ~p ~n",[ Key]),
     process_delayed_task(Key, Req, State) ;
process([<<"time">>], undefined, _Body, Req, State)->
      ResTime = [{<<"deal_comission">>, <<"0.1">>},
		 {<<"use_f2a">>, false},
		 {<<"logged">>, false},
		 {<<"x-cache">>, true},
		 {<<"status">>, true}
		 ],
		 
      ResTime1  = get_usd_rate(ResTime),
      ResTime2 = get_time(ResTime1),
      ResTime3 = get_state(ResTime2),
      {json, {ResTime3}, Req, State};      
process([<<"time">>], {api, UserId}, Body, Req, State)->
         ResTime = [
                    {<<"logged">>, true},
                    {<<"x-cache">>, true},
                    {<<"status">>, true},
                    {<<"deal_comission">>,  <<"0.05">> }
                    ],		
        % move spawn
        ResTime1  = get_usd_rate(ResTime),
        ResTime3 = get_time(ResTime1),
        %ResTime4 = get_user_state(ResTime3, UserId),
        ResTime4 = get_state(ResTime3),
        {json, {ResTime3}, Req, State};
process([<<"time">>], {session, undefined, _SessionKey}, _Body, Req, State)->
   process([<<"time">>], undefined, _Body, Req, State);
process([<<"time">>], {session, SessionObj, SessionKey}, _Body, Req, NewState)->

     ?CONSOLE_LOG("session obj ~p ~n",[SessionObj]),
      case get_key_dict(SessionObj, <<"user_id">>, false) of
          false -> process([<<"time">>], undefined, _Body, Req, NewState);
          UserId->
              UserIdBinary = list_to_binary(integer_to_list(UserId)),
              ?CONSOLE_LOG("user id ~p~n", [UserIdBinary]), 
              SessionKeyCustom = list_to_binary(hexstring(crypto:hash(sha256, <<?KEY_PREFIX,SessionKey/binary, UserIdBinary/binary>>))), 
              ResTime = [
                    {<<"logged">>, true},
                    {<<"x-cache">>, true},
                    {<<"status">>, true},
                    {<<"sessionid">>, SessionKeyCustom},
                    {<<"ui_settings">>, get_key_dict(SessionObj, <<"ui_settings">>, []) },                    
                    {<<"user_custom_id">>, get_key_dict(SessionObj, <<"user_custom_id">>, <<>>) },
                    {<<"use_f2a">>, get_key_dict(SessionObj, <<"use_f2a">>, false) },
                    {<<"deal_comission">>, get_key_dict(SessionObj, <<"deal_comission_show">>, <<"0.05">>) }
                    ],		
            {pickle_unicode, UserName } = get_key_dict(SessionObj, <<"username">>, {pickle_unicode, <<>>} ),
      % move spawn
               mcd:set(?LOCAL_CACHE, <<?KEY_PREFIX, "chat_", SessionKeyCustom/binary>>, pickle:term_to_pickle(UserName)),
               mcd:set(?LOCAL_CACHE, <<?KEY_PREFIX, "user_", UserIdBinary/binary>>, pickle:term_to_pickle(SessionKey)),   
               ResTime1  = get_usd_rate(ResTime),
               ResTime3 = get_time(ResTime1),
               ResTime4 = get_user_state(ResTime3, UserIdBinary),
               {json, {ResTime4}, Req, NewState}
      end;
process(Path, _UserId, Body, Req, State)->
     ?CONSOLE_LOG("undefined request from ~p ~p ~n",[Path, Req]),
     false_response(Req, State).
    
 
load_user_session(SessionKey)->
  case mcd:get(?LOCAL_CACHE, SessionKey) of
    {ok, Val}->
	% add saving to localcache
	pickle:pickle_to_term(Val);
     _ ->
         
         undefined
  end.
      

auth_user(Req, Body, State)->
       {Sign, Req3 }  = cowboy_req:header(<<"api_sign">>, Req, undefined),
       {PublicKey, Req4_ }  = cowboy_req:header(<<"public_key">>, Req3, undefined),
       {Headers, Req4 }  = cowboy_req:headers(Req4_),
       {CookieSession, Req5} = cowboy_req:cookie(<<"sessionid">>, Req4, undefined), 

       ?CONSOLE_LOG(" request from ~p ~n",[ CookieSession]),
       ?CONSOLE_LOG(" request public key ~p ~n",[ PublicKey ]),
       ?CONSOLE_LOG(" headers ~p ~n",[ Headers ]),

       case CookieSession of 
            undefined ->
            {NewState, LocalKey, UserId} = case catch dict:fetch(State, PublicKey) of
                                                        {'EXIT', _ } -> {State, undefined, undefined};
                                                        {Value, User_Id} -> {State, Value, User_Id}
                                            end,				    
            case check_sign({Sign, LocalKey}, Body, State) of 
                    true ->   { {api, UserId}, Req5};
                    false ->  ?CONSOLE_LOG("salt false ~n", []), 
                                {undefined, Req5}
            end;
            Session->
                SessionObj =  load_user_session(django_session_key(CookieSession)),
                ?CONSOLE_LOG(" load session  ~n",[]),
                { {session, SessionObj, CookieSession}, Req5}
            end     
.
django_read_token(Session)->
    <<?KEY_PREFIX, "read_token", Session/binary>>.
  
django_session_key(Session)->
    <<?KEY_PREFIX, "django.contrib.sessions.cache", Session/binary>>.
  
get_user_state(ResTime, UserId)->
     get_user_state(ResTime, UserId, <<"state">>).
     
get_user_state(ResTime, UserId, Key)->
  case mcd:get(?LOCAL_CACHE, <<?KEY_PREFIX, "session_", UserId/binary>>) of
    {ok, Val1}->
        ?CONSOLE_LOG(" state  ~p ~n",[Val1]), 
	Val = pickle:pickle_to_term(Val1),
        ?CONSOLE_LOG(" state decoded  ~p ~n",[Val]), 
	[ {Key, Val}| ResTime];
     _ ->
        StateTime = my_time(),
        ?CONSOLE_LOG(" load new  state  ~p ~n",[StateTime]), 
        mcd:set(?LOCAL_CACHE, <<?KEY_PREFIX, "session_", UserId/binary>>, pickle:term_to_pickle(StateTime)),   
	[ {Key, StateTime}| ResTime]
  end.
  
get_state(ResTime)->
     get_state(ResTime, <<"state">>).

get_state(ResTime, Key)->
  case mcd:get(?LOCAL_CACHE, <<?KEY_PREFIX, Key/binary>>) of
    {ok, Val}->
	Rate = pickle:pickle_to_term(Val),
	[ {Key, Rate}| ResTime];
     _ ->
        StateTime = my_time(),
        ?CONSOLE_LOG(" load new  state  ~p ~n",[StateTime]), 
        mcd:set(?LOCAL_CACHE, <<?KEY_PREFIX, Key/binary>>, pickle:term_to_pickle(StateTime)),   
	[ {Key, StateTime}| ResTime]
  end.
  

my_time()->
 {MegSecs, Secx, _} = now(),
  Time = MegSecs*1000000 + Secx + 3600*3,
  Time.


get_time(ResTime)->
     get_time(ResTime, <<"time">>).
     
get_time(ResTime, Key)->
  Time = my_time(), 
  [ {Key, Time}| ResTime].
  
     
get_usd_rate(ResTime)->
     get_usd_rate(ResTime, <<"usd_uah_rate">>).
     
get_usd_rate(ResTime, Key)->
  case mcd:get(?LOCAL_CACHE, << ?KEY_PREFIX, "usd_uah_rate">>) of
    {ok, Val}->
	{pickle_unicode, Rate} = pickle:pickle_to_term(Val),
	[ {Key, Rate}| ResTime];
     _ ->
        ResTime
  end.
     

fetch_django_session( UserId)->
  fetch_django_session(UserId, <<"sessionid">>)
.

fetch_django_session(UserId, Key)->
    case mcd:get(?LOCAL_CACHE, << ?KEY_PREFIX, "user_", UserId/binary>>) of
        {ok, Val}->
            {pickle_unicode, Rate} = pickle:pickle_to_term(Val),
            Rate;
        _ ->
            undefined
    end
.

get_key_dict(SessionObj,Key, Default)->
    case dict:find(Key, SessionObj) of
        {ok, Value} -> Value;
        error -> Default
    end
.


     
generate_key(Salt, Body)->
        hexstring( crypto:hash(sha256, <<Salt/binary, Body/binary >>)  ) 
.

% [
%         {<<"logged">>, true},
%         {<<"x-cache">>, true},
%         {<<"status">>, true},
%         {<<"sessionid">>, SessionKeyCustom},
%         {<<"ui_settings">>, UiSettingsJ },
%         {<<"ui_msg">>, erws_api:get_key_dict(SessionObj, <<"ui_msg">>, <<"">> ) },
%         {<<"user_custom_id">>, erws_api:get_key_dict(SessionObj, <<"user_custom_id">>, <<>>) },
%         {<<"use_f2a">>, erws_api:get_key_dict(SessionObj, <<"use_f2a">>, false) },
%         {<<"deal_comission">>, erws_api:get_key_dict(SessionObj, <<"deal_comission_show">>, <<"0.05">>) }
%         ],	

dict_to_json(Dict)->
	 List = dict:to_list(Dict),
    ?CONSOLE_LOG(" dict to list  ~p ~n",[List]), 
    dict_to_json(List, [])
.

dict_to_json([], Accum)->
     {Accum};

dict_to_json([{{pickle_unicode, Key}, Val}| Tail], Accum)->
           dict_to_json([{Key, Val}| Tail], Accum)
; 
dict_to_json([{ Key, {pickle_unicode, Val}}| Tail], Accum)->
           dict_to_json([{Key, Val}| Tail], Accum);
dict_to_json([{Key, Val}| Tail], Accum)->
    case checkdict(Val) of
        true -> 
            ValNormal =  {dict_to_json( dict:to_list(Val), []  )},
            dict_to_json(Tail, [{Key, ValNormal}|Accum]);
        false-> 
            case Val of
            {pickle_unicode, Val1} -> % do not save here not ASCII symbols
                dict_to_json(Tail, [{Key, Val1}|Accum]);
            Val1 -> % do not save here not ASCII symbols
                dict_to_json(Tail, [{Key, Val1}|Accum])
            end    
    end.
    
checkdict(DictCand) when is_tuple(DictCand) andalso element(1, DictCand) =:= dict ->
  true;
checkdict(_NotDict) ->
  false.



json_decode(Json)->
        jiffy:decode(Json).

json_encode(Doc)->
        jiffy:encode(Doc).


-spec hexstring( binary() ) -> list().
hexstring(<<X:128/big-unsigned-integer>>) ->
    lists:flatten(io_lib:format("~32.16.0b", [X]));
hexstring(<<X:160/big-unsigned-integer>>) ->
    lists:flatten(io_lib:format("~40.16.0b", [X]));
hexstring(<<X:256/big-unsigned-integer>>) ->
    lists:flatten(io_lib:format("~64.16.0b", [X]));
hexstring(<<X:512/big-unsigned-integer>>) ->
    lists:flatten(io_lib:format("~128.16.0b", [X])).

