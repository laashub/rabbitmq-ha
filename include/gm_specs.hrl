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

-ifdef(use_specs).

-export_type([joined/0, members_changed/0, handle_msg/0, terminate/0]).

-type(callback_result() :: 'ok' | {'stop', any()}).
-type(args() :: [any()]).
-type(members() :: [pid()]).

-spec(joined/2          :: (args(), members())            -> callback_result()).
-spec(members_changed/3 :: (args(), members(), members()) -> callback_result()).
-spec(handle_msg/3      :: (args(), pid(), any())         -> callback_result()).
-spec(terminate/2       :: (args(), term())               -> any()).

-endif.
