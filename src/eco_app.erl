%% Copyright (c) 2012, Adam Rutkowski <hq@mtod.org>
%%
%% Permission to use, copy, modify, and/or distribute this software for any
%% purpose with or without fee is hereby granted, provided that the above
%% copyright notice and this permission notice appear in all copies.
%%
%% THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
%% WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
%% MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
%% ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
%% WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
%% ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
%% OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.OF SUCH DAMAGE.

%% @doc Eco - Erlang environment configuration server (application module)
-module(eco_app).

-behaviour(application).

%% Application callbacks
-export([start/2, stop/1]).
-export([init_clean/0]).

-include("eco.hrl").

init_clean() ->
    error_logger:info_msg("Trying to initialize mnesia schema...~n"),
    ok = mnesia:create_schema([node()]),
    ok = mnesia:start(),
    mnesia:delete_table(eco_config),
    mnesia:delete_table(eco_snapshot),
    mnesia:delete_table(eco_kv),
    mnesia:create_table(eco_config, [
            {type, set},
            {attributes, record_info(fields, eco_config)},
            {disc_copies, [node()]}
            ]),
    mnesia:create_table(eco_snapshot, [
            {type, set},
            {attributes, record_info(fields, eco_snapshot)},
            {disc_copies, [node()]}
            ]),
    mnesia:create_table(eco_kv, [
            {type, set},
            {attributes, record_info(fields, eco_kv)},
            {disc_copies, [node()]}
            ]),
    stopped = mnesia:stop(),
    ok.

%% ===================================================================
%% Application callbacks
%% ===================================================================

start(_StartType, StartArgs) ->
    %% if eco_auto_init true argument is provided and Mnesia directory
    %% doesn't exist, call init_clean
    on(init:get_argument(eco_auto_init), {ok, [["true"]]},
        fun() -> on(schema_initialized(), false, fun init_clean/0) end),

    _ = application:start(pg2),
    _ = application:start(mnesia),

    case mnesia:wait_for_tables([eco_snapshot, eco_kv], 5000) of
        ok ->
            ConfigDir = proplists:get_value(config_dir, StartArgs),
            Ret = eco_sup:start_link(ConfigDir),
            start_plugins(get_plugins(StartArgs)),
            Ret;
        Error ->
            error_logger:error_msg("Eco could not find Mnesia tables.~n"
                                   "Possible solution: initialize Mnesia schema.~n"
                                   "To do this automatically, provide the '-eco_auto_init true' argument.~n"
                                   "The error message was: ~n~p~n", [Error]
                                  ),
            Error
    end.

-spec get_plugins(list()) -> list().
get_plugins(StartArgs) ->
    case init:get_argument(eco_plugins) of
        {ok, [Plugins]} ->
            lists:map(
                fun(Plugin) ->
                        try
                            erlang:list_to_existing_atom(Plugin)
                        catch error:badarg ->
                            erlang:error({unknown_eco_plugin, Plugin})
                        end
                end, Plugins);
        error ->
            proplists:get_value(plugins, StartArgs, [])
    end.

-spec start_plugins([atom()]) -> ok.
start_plugins([]) ->
    ok;
start_plugins([shell|Rest]) ->
    _ = application:start(crypto),
    _ = application:start(public_key),
    _ = application:start(ssh),
    {ok, _} = eco_sup:start_shell(),
    start_plugins(Rest);
start_plugins([Unknown|_]) ->
    erlang:error({unknown_eco_plugin, Unknown}).

-spec schema_initialized() -> boolean().
schema_initialized() ->
    %% A little naive but probably sufficient for basic cases.
    %% Should be enough to cover the 'false' case.
    MnesiaDir = mnesia:system_info(directory),
    filelib:is_dir(MnesiaDir).

stop(_State) ->
    ok.

%% @doc A simple wrapper for nested cases
-spec on(any(), any(), function()) -> any() | ignore.
on(Pred, Exp, F) when is_function(F) ->
    case Pred of
        Exp -> F();
        _ -> ignore
    end.
