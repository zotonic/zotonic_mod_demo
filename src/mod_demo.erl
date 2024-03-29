%% @author Marc Worrell <marc@worrell.nl>
%% @copyright 2022-2023 Marc Worrell
%% @doc Demo site, automatically reset content after a set period.
%% @enddoc

%% Copyright 2022-2023 Marc Worrell
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.

-module(mod_demo).
-author("Marc Worrell <marc@worrell.nl>").

-mod_title("Demo").
-mod_description("Used for the Zotonic demo site.").
-mod_prio(100).
-mod_schema(3).
-mod_depends([mod_content_groups, mod_acl_user_groups]).

-export([
    observe_tick_1h/2,
    observe_acl_is_allowed/2,
    observe_rsc_update/3,
    periodic_cleanup/1,
    manage_schema/2,
    manage_data/2
    ]).

-include_lib("zotonic_core/include/zotonic.hrl").

-spec observe_tick_1h(tick_1h, z:context()) -> ok.
observe_tick_1h(tick_1h, Context) ->
    periodic_cleanup(Context).


%% @doc Prevent that the demo user can edit itself
-spec observe_acl_is_allowed(#acl_is_allowed{}, z:context()) -> boolean() | undefined.
observe_acl_is_allowed(#acl_is_allowed{ action = Action, object = Id }, Context)
    when is_integer(Id), Action =/= view ->
    case z_acl:user(Context) =:= Id of
        true ->
            case m_rsc:p_no_acl(Id, name, Context) of
                <<"demo_user">> -> false;
                _ -> undefined
            end;
        _ ->
            undefined
    end;
observe_acl_is_allowed(_, _Context) ->
    undefined.


%% @doc On rsc update - force the seo_noindex flag for resources in the
%% demo content group. This to prevent spammers from abusing the demo site.
observe_rsc_update(#rsc_update{ props = Raw }, {ok, Update}, Context) ->
    CGId = cg_id(Update, Raw),
    case m_rsc:p_no_acl(CGId, name, Context) of
        <<"demo_content_group">> ->
            Update1 = Update#{
                <<"seo_noindex">> => true
            },
            {ok, Update1};
        _ ->
            {ok, Update}
    end;
observe_rsc_update(#rsc_update{}, {error, _} = Error, _Context) ->
    Error.

cg_id(#{ <<"content_group_id">> := CGId }, _) -> CGId;
cg_id(_, #{ <<"content_group_id">> := CGId }) -> CGId;
cg_id(_, _) -> undefined.


%% @doc Every hour delete all demo content that is created more than a day ago
%% and is not edited in the last hour.
-spec periodic_cleanup( z:context() ) -> ok.
periodic_cleanup(Context) ->
    DayAgo = z_datetime:prev_day(calendar:universal_time()),
    HourAgo = z_datetime:prev_hour(calendar:universal_time()),
    CGId = m_rsc:rid(demo_content_group, Context),
    Ids = z_db:q("
        select id
        from rsc
        where created < $1
          and modified < $2
          and content_group_id = $3",
        [ DayAgo, HourAgo, CGId ],
        Context),
    ContextSudo = z_acl:sudo(Context),
    lists:foreach(
        fun({Id}) ->
            case m_rsc:p(Id, <<"is_protected">>, ContextSudo) of
                true ->
                    m_rsc:update(Id, #{ <<"is_protected">> => false }, ContextSudo);
                false ->
                    ok
            end,
            m_rsc:delete(Id, ContextSudo)
        end,
        Ids).

%% @doc Ensure that the user "demo" and the content group "demo" are created.
manage_schema(_, _Context) ->
    #datamodel{
        resources = [
            {demo_user, person, #{
                <<"is_published">> => true,
                <<"is_protected">> => true,
                <<"title">> => <<"Demo User">>,
                <<"name_first">> => <<"Demo">>,
                <<"name_surname">> => <<"User">>,
                <<"language">> => [ en ],
                <<"email">> => <<"demo@example.com">>,
                <<"content_group_id">> => system_content_group
            }},
            {demo_content_group, content_group, #{
                <<"is_published">> => true,
                <<"is_protected">> => true,
                <<"title">> => <<"Demo content group">>,
                <<"summary">> => <<"All demonstration content is created in this content group.">>,
                <<"language">> => [ en ],
                <<"content_group_id">> => system_content_group
            }},
            {acl_user_group_demo, acl_user_group, #{
                <<"is_published">> => true,
                <<"is_protected">> => true,
                <<"title">> => <<"Demo user group">>,
                <<"summary">> => <<"The user group for the demo account.">>,
                <<"language">> => [ en ],
                <<"content_group_id">> => system_content_group
            }},
            {page_logon, other, #{
                <<"is_published">> => true,
                <<"is_protected">> => true,
                <<"title">> => <<"Logon">>,
                <<"body">> => <<"<p>Use username <b>demo</b> with password <b>demo</b>.</p>">>,
                <<"language">> => [ en ],
                <<"content_group_id">> => system_content_group,
                <<"page_path">> => <<"/logon">>
            }}
        ],
        edges = [
            {demo_user, hasusergroup, acl_user_group_demo}
        ]
    }.

%% @doc Set the username/password of the demo user to "demo/demo"
manage_data(_, Context) ->
    ContextSudo = z_acl:sudo(Context),
    DemoUserId = m_rsc:rid(demo_user, Context),
    ok = m_identity:set_username_pw(DemoUserId, <<"demo">>, <<"demo">>, ContextSudo).
