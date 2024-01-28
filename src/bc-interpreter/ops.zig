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

    equals,
    not_equals,
    less_than,
};
