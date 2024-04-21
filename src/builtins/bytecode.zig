const std = @import("std");
const Helper = @import("./helper.zig");

const BCInterpreter = @import("../bc-interpreter.zig");
const Interpreter = @import("../bc-interpreter/interpreter.zig");

pub fn body(machine: *Helper.Runtime, numberOfArgs: usize) !void {
    const function = try Helper.getArgument(machine, numberOfArgs, 0, &[_]Helper.ValueKind{Helper.ValueValue.BCFunctionKind});

    try machine.pushCodeValue(function.v.BCFunctionKind.code);
}

pub fn compile(machine: *Helper.Runtime, numberOfArgs: usize) !void {
    const input = try Helper.getArgument(machine, numberOfArgs, 0, &[_]Helper.ValueKind{Helper.ValueValue.StringKind});
    const name = try Helper.getArgument(machine, numberOfArgs, 1, &[_]Helper.ValueKind{ Helper.ValueValue.StringKind, Helper.ValueValue.UnitKind });

    const ast = try BCInterpreter.parse(machine, if (name.isString()) name.v.StringKind.slice() else "eval", input.v.StringKind.slice());
    defer ast.destroy(machine.allocator);

    const bytecode = try BCInterpreter.compile(machine.stringPool, machine.allocator, ast);
    defer bytecode.decRef(machine.allocator);

    try machine.pushCodeValue(bytecode);
}

pub fn eval(machine: *Helper.Runtime, numberOfArgs: usize) !void {
    const bytecode = try Helper.getArgument(machine, numberOfArgs, 0, &[_]Helper.ValueKind{ Helper.ValueValue.CodeKind, Helper.ValueValue.StringKind });
    const scope = try Helper.getArgument(machine, numberOfArgs, 1, &[_]Helper.ValueKind{Helper.ValueValue.ScopeKind});

    try machine.openScopeUsing(scope);
    defer machine.restoreScope();

    if (bytecode.isString()) {
        try BCInterpreter.eval(machine, bytecode.v.StringKind.slice());
    } else {
        try bytecode.v.CodeKind.eval(machine);
    }
}

pub fn readCode(machine: *Helper.Runtime, numberOfArgs: usize) !void {
    const bytecode = try Helper.getArgument(machine, numberOfArgs, 0, &[_]Helper.ValueKind{Helper.ValueValue.CodeKind});
    const offset = try Helper.getArgument(machine, numberOfArgs, 1, &[_]Helper.ValueKind{ Helper.ValueValue.IntKind, Helper.ValueValue.UnitKind });

    const ip = if (offset.isInt()) offset.v.IntKind else 0;

    const result = @as(?*BCInterpreter.Code, @ptrFromInt(@as(usize, @bitCast(Interpreter.readInt(bytecode.v.CodeKind.code, @intCast(ip))))));

    if (result == null) {
        try machine.pushUnitValue();
    } else {
        try machine.pushCodeValue(result.?);
    }
}

pub fn readFloat(machine: *Helper.Runtime, numberOfArgs: usize) !void {
    const bytecode = try Helper.getArgument(machine, numberOfArgs, 0, &[_]Helper.ValueKind{Helper.ValueValue.CodeKind});
    const offset = try Helper.getArgument(machine, numberOfArgs, 1, &[_]Helper.ValueKind{ Helper.ValueValue.IntKind, Helper.ValueValue.UnitKind });

    const ip = if (offset.isInt()) offset.v.IntKind else 0;

    const result = Interpreter.readFloat(bytecode.v.CodeKind.code, @intCast(ip));
    try machine.pushFloatValue(result);
}

pub fn readInt(machine: *Helper.Runtime, numberOfArgs: usize) !void {
    const bytecode = try Helper.getArgument(machine, numberOfArgs, 0, &[_]Helper.ValueKind{Helper.ValueValue.CodeKind});
    const offset = try Helper.getArgument(machine, numberOfArgs, 1, &[_]Helper.ValueKind{ Helper.ValueValue.IntKind, Helper.ValueValue.UnitKind });

    const ip = if (offset.isInt()) offset.v.IntKind else 0;

    const result = Interpreter.readInt(bytecode.v.CodeKind.code, @intCast(ip));
    try machine.pushIntValue(result);
}

pub fn readString(machine: *Helper.Runtime, numberOfArgs: usize) !void {
    const bytecode = try Helper.getArgument(machine, numberOfArgs, 0, &[_]Helper.ValueKind{Helper.ValueValue.CodeKind});
    const offset = try Helper.getArgument(machine, numberOfArgs, 1, &[_]Helper.ValueKind{ Helper.ValueValue.IntKind, Helper.ValueValue.UnitKind });

    const ip = if (offset.isInt()) offset.v.IntKind else 0;

    const result = Interpreter.readString(bytecode.v.CodeKind.code, @intCast(ip));
    if (result == null) {
        try machine.pushUnitValue();
    } else {
        try machine.pushStringPoolValue(result.?);
    }
}
