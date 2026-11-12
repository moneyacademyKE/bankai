-record(indexes, {
    vec_index :: aarondb@vec_index:vec_index(),
    bm25_indices :: gleam@dict:dict(binary(), aarondb@index@bm25:b_m25_index()),
    art_index :: aarondb@index@art:art(),
    columnar_store :: gleam@dict:dict(binary(), list(aarondb@storage@internal:storage_chunk()))
}).
