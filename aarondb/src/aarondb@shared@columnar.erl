-module(aarondb@shared@columnar).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/aarondb/shared/columnar.gleam").
-export_type([column_chunk/0]).

-type column_chunk() :: {column_chunk,
        binary(),
        list(aarondb@fact:value()),
        integer(),
        boolean()}.


