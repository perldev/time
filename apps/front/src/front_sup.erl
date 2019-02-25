%%%-------------------------------------------------------------------
%% @doc front top level supervisor.
%% @end
%%%-------------------------------------------------------------------

-module(front_sup).

-behaviour(supervisor).

%% API
-export([start_link/0]).

%% Supervisor callbacks
-export([init/1]).

-define(SERVER, ?MODULE).

%%====================================================================
%% API functions
%%====================================================================

start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

%%====================================================================
%% Supervisor callbacks
%%====================================================================

%% Child :: {Id,StartFunc,Restart,Shutdown,Type,Modules}
init([]) ->
   ApiTableHolder ={
                "api_table_holder",
             {api_table_holder, start_link, [] },
             permanent, 10000, worker , [ api_table_holder]   
        
        },
    Mcd = {local_memcache,
                {mcd, start_link, ['myMcd', ["127.0.0.1", 11211]]},
               permanent, 10000, worker, [mcd] },
                
    {ok, { {one_for_one, 10000, 10}, [ApiTableHolder, Mcd]} }.

%%====================================================================
%% Internal functions
%%====================================================================
