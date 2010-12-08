%% The contents of this file are subject to the Mozilla Public License
%% Version 1.1 (the "License"); you may not use this file except in
%% compliance with the License. You may obtain a copy of the License at
%% http://www.mozilla.org/MPL/
%%
%% Software distributed under the License is distributed on an "AS IS"
%% basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See the
%% License for the specific language governing rights and limitations
%% under the License.
%%
%% The Original Code is RabbitMQ.
%%
%% The Initial Developer of the Original Code is VMware, Inc.
%% Copyright (c) 2007-2010 VMware, Inc.  All rights reserved.
%%

-module(rabbit_mirror_queue_slave).

-export([start_link/1]).

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2,
         code_change/3]).

-export([joined/2, members_changed/3, handle_msg/3]).

-behaviour(gen_server2).
-behaviour(gm).

-include_lib("rabbit_common/include/rabbit.hrl").
-include("gm_specs.hrl").

-record(state, { name,
                 gm,
                 master_node
               }).

start_link(QueueName) ->
    gen_server2:start_link(?MODULE, [QueueName], []).

init([QueueName]) ->
    ok = gm:create_tables(),
    {ok, GM} = gm:start_link(QueueName, ?MODULE, [self()]),
    receive {joined, GM, Nodes} ->
            ok
    end,
    Self = self(),
    Node = node(),
    case rabbit_misc:execute_mnesia_transaction(
           fun () ->
                   [Q = #amqqueue { pid = QPid, extra_pids = EPids }] =
                       mnesia:read({rabbit_queue, QueueName}),
                   case [Pid || Pid <- [QPid | EPids], node(Pid) =:= Node] of
                       [] ->
                           EPids1 = EPids ++ [Self],
                           mnesia:write(rabbit_queue,
                                        Q #amqqueue { extra_pids = EPids1 },
                                        write),
                           {ok, QPid};
                       _ ->
                           {error, node_already_present}
                   end
           end) of
        {ok, MPid}     -> {ok, #state { name        = QueueName,
                                        gm          = GM,
                                        master_node = node(MPid) }, hibernate,
                           {backoff, ?HIBERNATE_AFTER_MIN, ?HIBERNATE_AFTER_MIN,
                            ?DESIRED_HIBERNATE}};
        {error, Error} -> {stop, Error}
    end.

handle_call({deliver_immediately, Txn, Message, ChPid}, _From, State) ->
    %% Synchronous, "immediate" delivery mode
    fix_me;

handle_call({deliver, Txn, Message, ChPid}, _From, State) ->
    %% Synchronous, "mandatory" delivery mode
    fix_me.

handle_cast({deliver, Txn, Message, ChPid}, State) ->
    %% Asynchronous, non-"mandatory", non-"immediate" deliver mode.
    fix_me;

handle_cast({gm_deaths, Deaths}, State = #state { name        = QueueName,
                                                  gm          = GM,
                                                  master_node = MNode }) ->
    io:format("Slave (~p) got deaths: ~p~n", [self(), Deaths]),
    noreply(
      case {node(), node(rabbit_mirror_queue_misc:remove_from_queue(
                           QueueName, Deaths))} of
          {_Node, MNode} ->
              State;
          {Node, Node} ->
              promote_me(State);
          {_Node, MNode1} ->
              ok = gm:broadcast(GM, heartbeat),
              State #state { master_node = MNode1 }
      end).

handle_info(Msg, State) ->
    {stop, {unexpected_info, Msg}, State}.

terminate(_Reason, State = #state {}) ->
    %% gen_server case
    ok;
terminate([SPid], Reason) ->
    %% gm case
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%% ---------------------------------------------------------------------------
%% GM
%% ---------------------------------------------------------------------------

joined([SPid], Members) ->
    SPid ! {joined, self(), [node(Pid) || Pid <- Members]},
    ok.

members_changed([SPid], Births, Deaths) ->
    io:format("S: ~p ~p ~p~n", [SPid, Births, Deaths]),
    ok = gen_server2:cast(SPid, {gm_deaths, Deaths}).

handle_msg([_SPid], _From, heartbeat) ->
    ok;
handle_msg([SPid], From, Msg) ->
    ok.

%% ---------------------------------------------------------------------------
%% Others
%% ---------------------------------------------------------------------------

noreply(State) ->
    {noreply, State, hibernate}.

reply(Reply, State) ->
    {reply, Reply, State, hibernate}.

promote_me(#state { gm = GM }) ->
    ok = gm:broadcast(GM, heartbeat),
    io:format("Promoting ~p~p!", [self()]),
    todo.
