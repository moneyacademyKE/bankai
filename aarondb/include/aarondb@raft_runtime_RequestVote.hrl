-record(request_vote, {
    term :: integer(),
    candidate :: binary(),
    last_index :: integer(),
    last_term :: integer()
}).
