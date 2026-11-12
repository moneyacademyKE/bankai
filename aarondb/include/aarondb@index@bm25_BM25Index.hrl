-record(b_m25_index, {
    term_freq :: gleam@dict:dict(binary(), gleam@dict:dict(aarondb@fact:entity_id(), integer())),
    doc_freq :: gleam@dict:dict(binary(), integer()),
    doc_len :: gleam@dict:dict(aarondb@fact:entity_id(), integer()),
    avg_doc_len :: float(),
    doc_count :: integer(),
    attribute :: binary()
}).
