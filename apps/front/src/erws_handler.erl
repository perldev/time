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
    %TODO make key from server
    ?CONSOLE_LOG("~n new session  ~n", []),
    Req2 = cowboy_req:compact(Req_2),
    {ok, Req2, #chat_state{ index = 0, start=now(), ip=IP}, hibernate}.

% Called when a text message arrives.
websocket_handle({text, Msg}, Req, State =  #chat_state{index=Index}) ->
    ?CONSOLE_LOG("~p Received: ~p ~n ~p~n~n",
		 [{?MODULE, ?LINE}, Req, State]),
    {UserId, Req1} = auth_user(Req),
    ?CONSOLE_LOG(" Req: ~p ~n", [Message]),
    Res = process(UserId),
    NewState = State#chat_state{index=Index+1},
    Req2 = cowboy_req:compact(Req1),
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
    
%     Doc4 =   [ {[{<<"bing">>,1},{<<"test">>,2}]}, 2.3, true] .
% [{[{<<"bing">>,1},{<<"test">>,2}]},2.3,true]
% (shellchat@localhost.localdomain)16> jiffy:encode( Doc4).                                      
% <<"[{\"bing\":1,\"test\":2},2.3,true]">>
% 
% 

process(undefined)->
      ResTime = [{<<"deal_comission">>, <<"0.1">>},
		 {<<"use_f2a">>, false},
		 {<<"logged">>, false},
		 {<<"x-cache">>, true},
		 {<<"status">>, true}
		 ],
		 
      ResTime1  = erws_api:get_usd_rate(ResTime),
      ResTime2 = erws_api:get_time(ResTime1),
      ResTime3 = erws_api:get_state(ResTime2),
      erws_api:json_encode({ResTime3});
process({session, undefined, _SessionKey})->
   process(undefined);
process({session, SessionObj, SessionKey})->

     ?CONSOLE_LOG("session obj ~p ~n",[SessionObj]),
      case erws_api:get_key_dict(SessionObj, <<"user_id">>, false) of
          false -> process( undefined);
          UserId->
              UserIdBinary = list_to_binary(integer_to_list(UserId)),
       
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
               ResTime4 = erws_api:get_user_state(ResTime3, UserIdBinary),
               erws_api:json_encode({ResTime4})
      end.

      
auth_user(Req)->
       {CookieSession, Req1} = cowboy_req:cookie(<<"sessionid">>, Req, undefined), 
       ?CONSOLE_LOG(" request from ~p ~n",[ CookieSession]),
       case CookieSession of 
          undefined -> {undefined, Req1 };
          Session->
              SessionObj =  erws_api:load_user_session(erws_api:django_session_key(CookieSession)),
              ?CONSOLE_LOG(" load session  ~n",[]),
	      { {session, SessionObj, CookieSession}, Req1}
      end     
.
      
      
      