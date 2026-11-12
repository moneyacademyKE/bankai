-record(migration_plan, {
    moves :: list({integer(),
        list({aarondb@fact:eid(), binary(), aarondb@fact:value()})})
}).
