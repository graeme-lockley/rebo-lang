pub const Op = enum(u8) {
    ret,
    push_char, // C
    push_false,
    push_float, // F
    push_identifier, // SP
    push_int, // I
    push_function, // B
    push_record,
    push_sequence, //
    push_string, // S
    push_true,
    push_unit,

    jmp, // I
    jmp_true, // IP
    jmp_false, // IP

    call, // IP
    bind,
    assign,

    duplicate,
    discard,

    append_sequence_item_bang, // P
    append_sequence_items_bang, // P

    set_record_item_bang, // P
    set_record_items_bang, // P

    equals,
    not_equals,
    less_than, // P
    less_equal, // P
    greater_than, // P
    greater_equal, // P
    add, // P
    subtract, // P
    multiply, // P
    divide, // P
    modulo, // P
    seq_append, // P
    seq_append_bang, // P
    seq_prepend, // P
    seq_prepend_bang, // P
    dot, // P
    index, // PP
};
