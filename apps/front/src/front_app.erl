%%%-------------------------------------------------------------------
%% @doc front public API
%% @end
%%%-------------------------------------------------------------------

-module(front_app).

-behaviour(application).

%% Application callbacks
-export([start/2, stop/1, start/0]).

%%====================================================================
%% API
%%====================================================================
routes() ->
    cowboy_router:compile([{'_',
			    [
			     {"/ws/[...]", erws_handler, []},
			     {"/[...]", erws_api, dict:new()},
			     {"/static/[...]", cowboy_static,
			      [{directory, <<"static">>},
			       {mimetypes,
				[{<<".png">>, [<<"image/png">>]},
				 {<<".jpg">>, [<<"image/jpeg">>]},
				 {<<".css">>, [<<"text/css">>]},
				 {<<".js">>,
				  [<<"application/javascript">>]}]}]}
			     ]}]).
start()->
    inets:start(),
    ok = application:start(ranch),
     
    ok = application:start(crypto),
    ok = application:start(cowlib),
    ok = application:start(cowboy),
    ok = application:start(compiler),
    ok = application:start(dht_ring),
    ok = application:start(syntax_tools),
    ok = application:start(goldrush),    
    ok = application:start(lager),
    application:start(front).

start(_StartType, _StartArgs) ->
%     io:format("~p",[code:all_loaded()]),    
%     io:format("~p",[code:which(mcd)]), 
%     code:load_file(mcd),   
    Dispatch = routes(),
    ok = case cowboy:start_http(
                listener, 200,
                [{port, 4000}],
                [{env, [{dispatch, Dispatch}]}]) of
             {ok, _} -> ok;
             {error, {already_started, _}} -> ok;
             {error, _} = Error -> Error
         end,
    front_sup:start_link().

%%--------------------------------------------------------------------
stop(_State) ->
    ok.

%%====================================================================
%% Internal functions
%%====================================================================
