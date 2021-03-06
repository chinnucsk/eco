-module(eco_json_jsx).
-compile([{parse_transform, eco_optional}]).
-require([jsx]).

-export([process_config/1]).

process_config(File) ->
    {ok, Conf} = file:read_file(File),
    case jsx:is_json(Conf) of
        true -> {ok, jsx:decode(Conf)};
        false -> {error, invalid_json}
    end.

