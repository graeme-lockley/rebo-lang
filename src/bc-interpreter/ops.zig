pub const Op = enum(u8) {
    ret,
    push_char,
    push_int,
    push_false,
    push_float,
    push_sequence,
    push_string,
    push_true,
    push_unit,

    append_sequence_item_bang,
    append_sequence_items_bang,

    op_eql,
    op_neql,
    op_lt,
};
