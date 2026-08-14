-module(bankai_molecules_ffi).
-export([
    init/1, reset_workspace/1,
    register/5, get/2, list/1,
    instance_by_key/3, instantiate/9,
    instance/2, provenance/2
]).

-define(TEMPLATES, bankai_molecule_templates_v1).
-define(INSTANCES, bankai_molecule_instances_v1).
-define(PROVENANCE, bankai_molecule_provenance_v1).
-define(CURRENT, bankai_current_v2).
-define(VERSIONS, bankai_versions_v2).

init(_Workspace) ->
    ensure_table(?TEMPLATES, [key, workspace, hash, schema, name, source]),
    ensure_table(?INSTANCES, [key, workspace, template_hash, idempotency_key,
                              fingerprint, instance_id, bindings_json,
                              node_tasks, created_at]),
    ensure_table(?PROVENANCE, [key, workspace, task_id, template_hash,
                               instance_id, node]),
    case mnesia:wait_for_tables([?TEMPLATES, ?INSTANCES, ?PROVENANCE], 5000) of
        ok -> {ok, nil};
        {timeout, Bad} -> {error, format("molecule table timeout: ~p", [Bad])}
    end.

reset_workspace(Workspace) -> transaction(fun() ->
    delete_rows({?TEMPLATES, '_', Workspace, '_', '_', '_', '_'}),
    delete_rows({?INSTANCES, '_', Workspace, '_', '_', '_', '_', '_', '_', '_'}),
    delete_rows({?PROVENANCE, '_', Workspace, '_', '_', '_', '_', '_'}),
    {ok, nil}
end).

register(Workspace, Hash, Schema, Name, Source) -> transaction(fun() ->
    Key = {Workspace, Hash},
    case mnesia:read(?TEMPLATES, Key, write) of
        [] ->
            mnesia:write({?TEMPLATES, Key, Workspace, Hash, Schema, Name, Source}),
            {ok, nil};
        [{?TEMPLATES, Key, Workspace, Hash, Schema, Name, Source}] -> {ok, nil};
        _ -> {error, <<"molecule template hash collision: ", Hash/binary>>}
    end
end).

get(Workspace, Hash) -> transaction(fun() ->
    case mnesia:read(?TEMPLATES, {Workspace, Hash}, read) of
        [{?TEMPLATES, _Key, Workspace, Hash, Schema, Name, Source}] ->
            {ok, {Schema, Name, Source}};
        [] -> {error, <<"no such molecule template: ", Hash/binary>>}
    end
end).

list(Workspace) -> transaction(fun() ->
    Rows = mnesia:match_object({?TEMPLATES, '_', Workspace, '_', '_', '_', '_'}),
    {ok, lists:sort([{Hash, Schema, Name} ||
        {?TEMPLATES, _Key, _Workspace, Hash, Schema, Name, _Source} <- Rows])}
end).

instance_by_key(Workspace, TemplateHash, IdempotencyKey) -> transaction(fun() ->
    Key = {Workspace, TemplateHash, IdempotencyKey},
    case mnesia:read(?INSTANCES, Key, read) of
        [{?INSTANCES, Key, Workspace, TemplateHash, IdempotencyKey,
          Fingerprint, InstanceId, BindingsJson, NodeTasks, CreatedAt}] ->
            {ok, {some, {Fingerprint, InstanceId, BindingsJson, NodeTasks, CreatedAt}}};
        [] -> {ok, none}
    end
end).

%% TaskRows are {Id, Hash, Json, Node}. Template, tasks, provenance, idempotency,
%% and one ordered change event commit in a single Mnesia transaction.
instantiate(Workspace, TemplateHash, IdempotencyKey, Fingerprint, InstanceId,
            BindingsJson, TaskRows, CreatedAt, _Reserved) -> transaction(fun() ->
    TemplateKey = {Workspace, TemplateHash},
    InstanceKey = {Workspace, TemplateHash, IdempotencyKey},
    case mnesia:read(?TEMPLATES, TemplateKey, read) of
        [] -> {error, <<"no such molecule template: ", TemplateHash/binary>>};
        _ ->
            case mnesia:read(?INSTANCES, InstanceKey, write) of
                [{?INSTANCES, InstanceKey, Workspace, TemplateHash, IdempotencyKey,
                  Fingerprint, SavedId, SavedBindings, SavedNodes, SavedAt}] ->
                    {ok, {SavedId, SavedBindings, SavedNodes, SavedAt, true}};
                [{?INSTANCES, InstanceKey, Workspace, TemplateHash, IdempotencyKey,
                  _Other, _SavedId, _SavedBindings, _SavedNodes, _SavedAt}] ->
                    {error, <<"molecule idempotency key reused with different bindings">>};
                [] ->
                    case validate_new_tasks(Workspace, TaskRows) of
                        ok ->
                            write_tasks(Workspace, TemplateHash, InstanceId, TaskRows),
                            NodeTasks = [{Node, Id} || {Id, _Hash, _Json, Node} <- TaskRows],
                            mnesia:write({?INSTANCES, InstanceKey, Workspace,
                                          TemplateHash, IdempotencyKey, Fingerprint,
                                          InstanceId, BindingsJson, NodeTasks, CreatedAt}),
                            bankai_changefeed_ffi:record_in_transaction(
                                Workspace, <<"molecule-instantiate">>,
                                [{Id, <<"none">>, Hash} ||
                                    {Id, Hash, _Json, _Node} <- TaskRows]),
                            {ok, {InstanceId, BindingsJson, NodeTasks, CreatedAt, false}};
                        Error -> Error
                    end
            end
    end
end).

instance(Workspace, InstanceId) -> transaction(fun() ->
    Rows = mnesia:match_object({?INSTANCES, '_', Workspace, '_', '_', '_',
                                InstanceId, '_', '_', '_'}),
    case Rows of
        [{?INSTANCES, _Key, Workspace, TemplateHash, IdempotencyKey,
          Fingerprint, InstanceId, BindingsJson, NodeTasks, CreatedAt}] ->
            {ok, {TemplateHash, IdempotencyKey, Fingerprint,
                  BindingsJson, NodeTasks, CreatedAt}};
        [] -> {error, <<"no such molecule instance: ", InstanceId/binary>>}
    end
end).

provenance(Workspace, TaskId) -> transaction(fun() ->
    case mnesia:read(?PROVENANCE, {Workspace, TaskId}, read) of
        [{?PROVENANCE, _Key, Workspace, TaskId, TemplateHash, InstanceId, Node}] ->
            {ok, {TemplateHash, InstanceId, Node}};
        [] -> {error, <<"no molecule provenance for task: ", TaskId/binary>>}
    end
end).

validate_new_tasks(_Workspace, []) -> ok;
validate_new_tasks(Workspace, [{Id, _Hash, _Json, _Node} | Rest]) ->
    case mnesia:read(?CURRENT, {Workspace, Id}, write) of
        [] -> validate_new_tasks(Workspace, Rest);
        _ -> {error, <<"molecule task already exists: ", Id/binary>>}
    end.

write_tasks(Workspace, TemplateHash, InstanceId, Rows) ->
    lists:foreach(fun({Id, Hash, Json, Node}) ->
        VersionKey = {Workspace, Hash},
        case mnesia:read(?VERSIONS, VersionKey, write) of
            [] -> mnesia:write({?VERSIONS, VersionKey, Workspace, Hash, Json});
            _ -> ok
        end,
        mnesia:write({?CURRENT, {Workspace, Id}, Workspace, Id, Hash, Json}),
        mnesia:write({?PROVENANCE, {Workspace, Id}, Workspace, Id,
                      TemplateHash, InstanceId, Node})
    end, Rows).

delete_rows(Pattern) ->
    lists:foreach(fun(Row) -> mnesia:delete_object(Row) end,
                  mnesia:match_object(Pattern)).

ensure_table(Name, Attributes) ->
    case mnesia:create_table(Name, [{attributes, Attributes}, {disc_copies, [node()]}]) of
        {atomic, ok} -> ok;
        {aborted, {already_exists, Name}} ->
            case mnesia:table_info(Name, attributes) of
                Attributes -> ok;
                Actual -> throw({bankai_molecule_schema_mismatch, Name, Actual})
            end;
        {aborted, Reason} -> throw({bankai_molecule_table_create_failed, Name, Reason})
    end.

transaction(Fun) ->
    try mnesia:transaction(Fun) of
        {atomic, Reply} -> Reply;
        {aborted, Reason} -> {error, format("molecule transaction aborted: ~p", [Reason])}
    catch
        Class:Reason -> {error, format("molecule persistence failure (~p): ~p", [Class, Reason])}
    end.

format(Template, Args) ->
    iolist_to_binary(io_lib:format(Template, Args)).
