const std = @import("std");
const Helper = @import("./helper.zig");

const BCInterpreter = @import("../bc-interpreter.zig");
const Interpreter = @import("../bc-interpreter/interpreter.zig");

pub fn compile(machine: *Helper.Runtime, numberOfArgs: usize) !void {
    const input = try Helper.getArgument(machine, numberOfArgs, 0, &[_]Helper.ValueKind{Helper.ValueValue.StringKind});

    const ast = try BCInterpreter.parse(machine, input.v.StringKind.slice());
    defer ast.destroy(machine.allocator);

    const bytecode = try BCInterpreter.compile(machine.allocator, ast);
    defer machine.allocator.free(bytecode);

    try machine.pushStringValue(bytecode);
}

pub fn eval(machine: *Helper.Runtime, numberOfArgs: usize) !void {
    const bytecode = try Helper.getArgument(machine, numberOfArgs, 0, &[_]Helper.ValueKind{Helper.ValueValue.StringKind});
    const scope = try Helper.getArgument(machine, numberOfArgs, 1, &[_]Helper.ValueKind{Helper.ValueValue.ScopeKind});

    try machine.openScopeUsing(scope);
    defer machine.restoreScope();

    try BCInterpreter.eval(machine, bytecode.v.StringKind.slice());
}

pub fn readInt(machine: *Helper.Runtime, numberOfArgs: usize) !void {
    const bytecode = try Helper.getArgument(machine, numberOfArgs, 0, &[_]Helper.ValueKind{Helper.ValueValue.StringKind});
    const offset = try Helper.getArgument(machine, numberOfArgs, 1, &[_]Helper.ValueKind{ Helper.ValueValue.IntKind, Helper.ValueValue.UnitKind });

    const ip = if (offset.isInt()) offset.v.IntKind else 0;

    const result = Interpreter.readInt(bytecode.v.StringKind.slice(), @intCast(ip));
    try machine.pushIntValue(result);
}

pub fn readFloat(machine: *Helper.Runtime, numberOfArgs: usize) !void {
    const bytecode = try Helper.getArgument(machine, numberOfArgs, 0, &[_]Helper.ValueKind{Helper.ValueValue.StringKind});
    const offset = try Helper.getArgument(machine, numberOfArgs, 1, &[_]Helper.ValueKind{ Helper.ValueValue.IntKind, Helper.ValueValue.UnitKind });

    const ip = if (offset.isInt()) offset.v.IntKind else 0;

    const result = Interpreter.readFloat(bytecode.v.StringKind.slice(), @intCast(ip));
    try machine.pushFloatValue(result);
}
