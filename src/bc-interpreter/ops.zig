pub const Op = enum(u8) {
    ret,
    push_char, // C
    push_int, // I
    push_false,
    push_float, // F
    push_record,
    push_sequence, //
    push_string, // S
    push_true,
    push_unit,

    jmp, // I
    jmp_true, // IP
    jmp_false, // IP

    duplicate,
    discard,

    append_sequence_item_bang, // P
    append_sequence_items_bang, // P

    set_record_item_bang, // P
    set_record_items_bang, // P

    equals,
    not_equals,
    less_than,
    less_equal,
    greater_than,
    greater_equal,
    add,
    subtract,
    multiply,
    divide,
    modulo,
    seq_append,
    seq_append_bang,
    seq_prepend,
    seq_prepend_bang,
};
