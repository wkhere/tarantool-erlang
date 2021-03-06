%%
%% @copyright 2012 Roman Tsisyk
%% @author Roman Tsisyk <roman@tsisyk.com>
%%      [http://roman.tsisyk.com/]
%%
%% @doc ETarantool is an Erlang client for Tarantool/Box NoSQL database.
%% @end
-module(etarantool).
-behaviour(gen_server).

%% ------------------------------------------------------------------
%% Public Types and Consts Exports
%% ------------------------------------------------------------------

-type space_id() :: integer().
%% Tarantool's Space Identifier

-type index_id() :: integer().
%% Tarantool'sIndex Identifier in the space.

-type field_id() :: integer().
%% Tarantool's Field Identifier.

-type field() :: binary() | pos_integer() | list(). 
%% Acceptable field types for all methods. Please note, that fields in
%% the tuples returned from the server always have `binary()' type.

-type conn() :: pid().
%% Tarantool Connection

-type return_code() :: atom() | integer().
%% Predefined return code

-type result_error() :: {error, ErrorCode::return_code(), Reason::any()}.
%% Query result (return code and error message)

-type result_tuples() :: {ok, [[field()]]}.
%% Query result (tuples)

-type result_count() :: {ok, integer()}.
%% Query result (number of affected tuples)

-export_type([
    space_id/0,
    index_id/0,
    field_id/0,
    field/0,
    conn/0,
    result_error/0,
    result_tuples/0,
    result_count/0
]).

%% ------------------------------------------------------------------
%% API Function Exports
%% ------------------------------------------------------------------

-export([
    connect/1,
    connect/2,
    connect/3,
    close/1,

    ping/1,
    select/4,
    select/5,
    insert/3,
    insert/4,
    replace/3,
    replace/4,
    delete/3,
    delete/4,
    call/3,
    call/4
]).

%% ------------------------------------------------------------------
%% gen_server Function Exports
%% ------------------------------------------------------------------

-export([
    init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3
]).

%% ------------------------------------------------------------------
%% Module Private Definitions
%% ------------------------------------------------------------------

-define(TARANTOOL_PRIMARY_PORT, 33013).
-define(TARANTOOL_READONLY_PORT, 33014).
-define(PACKET_MIN_SIZE, 3). % bytes

-record(state, {
    socket :: gen_tcp:socket(),
    request_id :: pos_integer(),
    packet_buf = <<>> :: binary(),
    mode :: atom()
}).

%% ------------------------------------------------------------------
%% API Function Definitions
%% ------------------------------------------------------------------

%% @equiv connect(Host, 33013)
connect(Address) ->
    connect(Address, ?TARANTOOL_PRIMARY_PORT).

%% @equiv connect(Host, Port, [])
connect(Address, Port) ->
    connect(Address, Port, []).

%% @doc Connects to a server `Host':`Port' using Tarantool's binary protocol
%% (IPROTO). The `Address' argument can be either a hostname, or an IP address.
%% 
%% `Opts' is `proplist' with the following options:
%% <ul>
%%  <li><b>mode</b> - configures how to process results from a server
%%   <ol>
%%      <li><b>blocked</b> (default) - perform requests in blocking mode.
%%          Client waits for the result and then returns it to the user.</li>
%%      <li><b>async</b> -  perform request in asynchronous mode. Client
%%          returns `{ok, RequestId}' immediately and sends message
%%          `{etarantool, Conn, RequestId, Result}' with the same `RequestId'
%%          to the callee when the response is got from a server.</li>
%%      <li><b>discard</b> - discard all results. Client returns
%%          `{ok, RequestId}' immediately and ignores all responces from a
%%           server (including error messages).</li>
%%   </ol>
%% </li>
%% </ul>
%%
%% @end
-spec connect(inet:ip_address() | inet:hostname(),
        inet:port_number(), proplists:proplist()) ->
    {ok, Conn::conn()} | {error, ErrorCode::atom(), Reason::list()}.
connect(Address, Port, Opts) ->
    gen_server:start_link(?MODULE, [Address, Port, Opts], []).

%% @doc Closes the connection `Conn' and stops `gen_server'.
-spec close(conn()) -> ok.
close(Conn) ->
    gen_server:call(Conn, close).

%% @doc Sends PING request using `Conn'.
-spec ping(conn()) -> ok.
ping(Conn) ->
    gen_server:call(Conn, ping_request).

%% @equiv insert(Conn, SpaceId, Tuples, [])
-spec insert(conn(), space_id(), [[field()]|tuple()]) ->
    result_tuples() | result_count() | result_error().
insert(Conn, SpaceId, Tuples) ->
    insert(Conn, SpaceId, Tuples, []).

%% @doc Inserts `Tuples' to the space `SpaceId' using `Conn'.
%% 
%% `insert' requires that no tuple with the same pkey exists in the space.
%% 
%% `Opts' is `proplist' with following options:
%% <ul>
%%  <li><b>return_tuple</b> - return inserted tuples (`result_tuples()') 
%%      instead of tuples count (`result_count()')</li>
%% </ul>
%%
%% Please note, that due to limitations of the protocol only one tuple can be
%% placed in `Tuples' list. This limitation may be removed in the future.
%%
%% @end
-spec insert(conn(), space_id(), [[field()]|tuple()],
        [proplists:property(return_tuple, true)]) ->
    result_tuples() | result_count() | result_error().
insert(Conn, SpaceId, Tuples, Opts) ->
    gen_server:call(Conn, {insert_request, SpaceId, Tuples, Opts}).

%% @equiv replace(Conn, SpaceId, Tuples, [])
-spec replace(conn(), space_id(), [[field()]|tuple()]) ->
    result_tuples() | result_count() | result_error().
replace(Conn, SpaceId, Tuples) ->
    replace(Conn, SpaceId, Tuples, []).

%% @doc Replaces `Tuples' in the space `SpaceId' using `Conn'.
%% 
%% `replace' requires that a tuple with the same pkey is present in the space.
%%
%% `Opts' is `proplist' with following options:
%% <ul>
%%  <li><b>return_tuple</b> - return replaced tuples (`result_tuples()') 
%%      instead of tuples count (`result_count()')</li>
%% </ul>
%%
%% Please note, that due to limitations of the protocol only one tuple can be
%% placed in `Tuples' list. This limitation may be removed in the future.
%%
%% @end
-spec replace(conn(), space_id(), [[field()]|tuple()],
        [proplists:property(return_tuple, true)]) ->
    result_tuples() | result_count() | result_error().
replace(Conn, SpaceId, Tuples, Opts) ->
    gen_server:call(Conn, {replace_request, SpaceId, Tuples, Opts}).


%% @equiv delete(Conn, SpaceId, Tuples, [])
-spec delete(conn(), space_id(), [[field()]|tuple()]) ->
    result_tuples() | result_count() | result_error().
delete(Conn, SpaceId, Tuples) ->
    replace(Conn, SpaceId, Tuples, []).

%% @doc Deletes `Tuples' in the space `SpaceId' using `Conn'.
%% 
%% `Opts' is `proplist' with following options:
%% <ul>
%%  <li><b>return_tuple</b> - return removed tuples (`result_tuples()') 
%%      instead of tuples count (`result_count()')</li>
%% </ul>
%%
%% Please note, that due to limitations of the protocol only one tuple can be
%% placed in `Tuples' list. This limitation may be removed in the future.
%%
%% @end
-spec delete(conn(), space_id(), [[field()]|tuple()],
        [proplists:property(return_tuple, true)]) ->
    result_tuples() | result_count() | result_error().
delete(Conn, SpaceId, Tuples, Opts) ->
    gen_server:call(Conn, {delete_request, SpaceId, Tuples, Opts}).


%% @equiv call(Conn, ProcName, Args, [])
-spec call(conn(), field(), [field()]|tuple()) ->
    result_tuples() | result_error().
call(Conn, ProcName, Args) ->
    call(Conn, ProcName, Args, []).

%% @doc Execute stored procedure on the server.
%% 
%% ProcName(*Args) where `*' means `unpack arguments' will be executed
%% on the server.
%% @end
%% 
%% `Opts' is `proplist' with no additional options currently supported.
%%
%% @end
-spec call(conn(), field(), [field()]|tuple(), [proplists:property(any())]) ->
    result_tuples() | result_error().
call(Conn, ProcName, Args, Opts) ->
    gen_server:call(Conn, {call_request, ProcName, Args, Opts}).

%% @equiv select(Conn, SpaceId, IndexId, Tuples, [])
select(Conn, SpaceId, IndexId, Tuples) ->
    select(Conn, SpaceId, IndexId, Tuples, []).

%% @doc Selects tuples from the space `SpaceId' by `IndexId' using `Conn'
%% where space keys match `Tuples' keys.
%%
%% You do not need entire tuple to select (of course), you just need indexed
%% keys. These keys must be in same order as defined in the space configuration.
%% 
%% `Opts' is `proplist' with following options:
%% <ul>
%%  <li><b>offset</b> - skip a specified number of tuples from result.
%%      Default is 0.</li>
%%  <li><b>limit</b> - limit number of resulting tuples.
%%      Default is -1.</li>
%% </ul>
%%
%% @end
-spec select(conn(), space_id(), index_id(), [[field()] | tuple()],
    [proplists:property(offset, integer()) |
     proplists:property(limit, integer())]) ->
    result_tuples() | result_error().
select(Conn, SpaceId, IndexId, Tuples, Opts) ->
    gen_server:call(Conn, {select_request, SpaceId, IndexId, Tuples, Opts}).

%% ------------------------------------------------------------------
%% gen_server Function Definitions
%% ------------------------------------------------------------------

%% @private
init([Address, Port, Opts]) ->
    ok = gen_server:cast(self(), {connect, Address, Port, Opts}),
    State = #state{
        socket = undefined,
        request_id = 0
    },
    {ok, State}.

%% @private
terminate(_Reason, State) ->
    ok = gen_tcp:close(State#state.socket),
    ok.

%% @private
handle_call(ping_request, From, State) ->
    {Type, Body} = etarantool_iproto:encode_request_body_ping(),
    send_packet(Type, Body, From, State);

handle_call({select_request, SpaceId, IndexId, Tuples, Opts}, From, State) ->
    {Type, Body} = etarantool_iproto:encode_request_body_select(
             SpaceId, IndexId, Tuples, Opts),
    send_packet(Type, Body, From, State);

handle_call({insert_request, SpaceId, Tuples, Opts}, From, State) ->
    {Type, Body} = etarantool_iproto:encode_request_body_insert(
             SpaceId, Tuples, Opts),
    send_packet(Type, Body, From, State);

handle_call({replace_request, SpaceId, Tuples, Opts}, From, State) ->
    {Type, Body} = etarantool_iproto:encode_request_body_replace(
             SpaceId, Tuples, Opts),
    send_packet(Type, Body, From, State);

handle_call({delete_request, SpaceId, Tuples, Opts}, From, State) ->
    {Type, Body} = etarantool_iproto:encode_request_body_delete(
             SpaceId, Tuples, Opts),
    send_packet(Type, Body, From, State);

handle_call({call_request, ProcName, Args, Opts}, From, State) ->
    {Type, Body} = etarantool_iproto:encode_request_body_call(
             ProcName, Args, Opts),
    send_packet(Type, Body, From, State);

handle_call(close, _From, State) ->
    ok = gen_tcp:close(State#state.socket),
    {stop, normal, ok, State};

handle_call(Msg, _From, State) ->
    {stop, {invalid_call, Msg}, State}.

%% @private
handle_cast({connect, Address, Port, Opts}, State) ->
    Mode = proplists:get_value(mode, Opts, blocked),
    true = (Mode =:= blocked) or (Mode =:= async) or (Mode =:= discard),
    TcpOpts = [
        {exit_on_close, true},
        {mode, binary},
        {packet, raw},
%        {delay_send, Mode =/= blocked},
        {keepalive, true}
    ],
    {ok, Socket} = gen_tcp:connect(Address, Port, TcpOpts),
    State2 = State#state{
        socket = Socket,
        mode = Mode
    },
    {noreply, State2};

handle_cast(Msg, State) ->
    {stop, {invalid_cast, Msg}, State}.

%% @private
handle_info({tcp, Socket, Packet}, State)
        when Socket =:= State#state.socket->
    recv_packet(Packet, State);

handle_info({tcp_closed, Socket}, State)
        when Socket =:= State#state.socket ->
    {stop, normal, State};

handle_info(Msg, State) ->
    {stop, {invalid_message, Msg}, State}.

%% @private
code_change(_OldVsn, State, _Extra) ->
        {ok, State}.

%% ------------------------------------------------------------------
%% Internal Function Definitions
%% ------------------------------------------------------------------

send_packet(Type, Body, From, State) ->
    RequestId = State#state.request_id,
    State2 = State#state{
        request_id = RequestId + 1
    },
    Request = etarantool_iproto:encode_request(Type, RequestId, Body),
    ok = gen_tcp:send(State#state.socket, Request),
    case State#state.mode of
        blocked ->
            erlang:put(RequestId, {From, Type}),
            {noreply, State2};
        async ->
            {Callee, _Ref} = From,
            erlang:put(RequestId, {Callee, Type}),
            {reply, {ok, RequestId}, State2};
        discard ->
            {reply, {ok, RequestId}, State2}
    end.

recv_packet(Packet, State) ->
    PacketAssembled = <<(State#state.packet_buf)/binary, Packet/binary>>,
    ProcessFun = case State#state.mode of
        blocked -> fun process_packet_blocked/4;
        async   -> fun process_packet_async/4;
        discard -> fun process_packet_discard/4
    end,
    {true, Tail} = etarantool_iproto:decode_responses(
        PacketAssembled, ProcessFun, true),
    State2 = State#state{packet_buf = Tail},
    {noreply, State2}.

process_packet_blocked(Type, RequestId, Result, true) ->
    {From, Type} = erlang:erase(RequestId),
    gen_server:reply(From, Result), true.

process_packet_async(Type, RequestId, Result, true) ->
    {Callee, Type} = erlang:erase(RequestId),
    Callee ! {etarantool, erlang:self(), RequestId, Result},
    true.

process_packet_discard(_Type, _RequestId, _Result, true) ->
    true.

