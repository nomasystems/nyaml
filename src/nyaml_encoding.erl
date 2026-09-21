-module(nyaml_encoding).

-moduledoc """
Character encoding detection and conversion for YAML input.

Detects UTF-8, UTF-16 (BE/LE), and UTF-32 (BE/LE) encodings from BOM or
byte patterns and converts to UTF-8 for parsing.
""".

%%%-----------------------------------------------------------------------------
%% API EXPORTS
%%%-----------------------------------------------------------------------------
-export([
    detect_and_convert/1
]).

%%%-----------------------------------------------------------------------------
%% TYPE EXPORTS
%%%-----------------------------------------------------------------------------
-export_type([
    encoding_error/0
]).

%%%-----------------------------------------------------------------------------
%% TYPES
%%%-----------------------------------------------------------------------------
-type encoding() :: utf16be | utf16le | utf32be | utf32le.

-type encoding_error() ::
    invalid_utf16
    | incomplete_utf16
    | invalid_utf32
    | incomplete_utf32.

%%%-----------------------------------------------------------------------------
%% API FUNCTIONS
%%%-----------------------------------------------------------------------------

-doc """
Detects encoding from BOM or byte pattern and converts to UTF-8.

Supports UTF-8, UTF-16 (big/little endian), and UTF-32 (big/little endian).
Returns the input unchanged if already UTF-8 or no BOM is present.
""".
-spec detect_and_convert(binary()) -> {ok, binary()} | {error, encoding_error()}.
detect_and_convert(<<16#00, 16#00, 16#FE, 16#FF, Rest/binary>>) ->
    convert_to_utf8(Rest, utf32be);
detect_and_convert(<<16#FF, 16#FE, 16#00, 16#00, Rest/binary>>) ->
    convert_to_utf8(Rest, utf32le);
detect_and_convert(<<16#EF, 16#BB, 16#BF, Rest/binary>>) ->
    {ok, Rest};
detect_and_convert(<<16#FE, 16#FF, Rest/binary>>) ->
    convert_to_utf8(Rest, utf16be);
detect_and_convert(<<16#FF, 16#FE, Rest/binary>>) ->
    convert_to_utf8(Rest, utf16le);
detect_and_convert(<<0, 0, 0, _, _/binary>> = Bin) ->
    convert_to_utf8(Bin, utf32be);
detect_and_convert(<<_, 0, 0, 0, _/binary>> = Bin) ->
    convert_to_utf8(Bin, utf32le);
detect_and_convert(<<0, _, _/binary>> = Bin) ->
    convert_to_utf8(Bin, utf16be);
detect_and_convert(<<_, 0, _/binary>> = Bin) ->
    convert_to_utf8(Bin, utf16le);
detect_and_convert(Bin) ->
    {ok, Bin}.

%%%-----------------------------------------------------------------------------
%% INTERNAL FUNCTIONS
%%%-----------------------------------------------------------------------------

-spec convert_to_utf8(binary(), encoding()) -> {ok, binary()} | {error, encoding_error()}.
convert_to_utf8(Bin, utf16be) ->
    case unicode:characters_to_binary(Bin, utf16) of
        {error, _, _} -> {error, invalid_utf16};
        {incomplete, _, _} -> {error, incomplete_utf16};
        Result when is_binary(Result) -> {ok, Result}
    end;
convert_to_utf8(Bin, utf16le) ->
    case unicode:characters_to_binary(Bin, {utf16, little}) of
        {error, _, _} -> {error, invalid_utf16};
        {incomplete, _, _} -> {error, incomplete_utf16};
        Result when is_binary(Result) -> {ok, Result}
    end;
convert_to_utf8(Bin, utf32be) ->
    case unicode:characters_to_binary(Bin, utf32) of
        {error, _, _} -> {error, invalid_utf32};
        {incomplete, _, _} -> {error, incomplete_utf32};
        Result when is_binary(Result) -> {ok, Result}
    end;
convert_to_utf8(Bin, utf32le) ->
    case unicode:characters_to_binary(Bin, {utf32, little}) of
        {error, _, _} -> {error, invalid_utf32};
        {incomplete, _, _} -> {error, incomplete_utf32};
        Result when is_binary(Result) -> {ok, Result}
    end.
