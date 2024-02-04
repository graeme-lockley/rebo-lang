const std = @import("std");
const Helper = @import("./helper.zig");

const BCInterpreter = @import("../bc-interpreter.zig");
const Interpreter = @import("../bc-interpreter/interpreter.zig");

pub fn compile(machine: *Helper.ASTInterpreter, numberOfArgs: usize) !void {
    const input = try Helper.getArgument(machine, numberOfArgs, 0, &[_]Helper.ValueKind{Helper.ValueValue.StringKind});

    const ast = try BCInterpreter.parse(&machine.runtime, input.v.StringKind.slice());
    defer ast.destroy(machine.runtime.allocator);

    const bytecode = try BCInterpreter.compile(machine.runtime.allocator, ast);
    defer machine.runtime.allocator.free(bytecode);

    try machine.runtime.pushStringValue(bytecode);
}

pub fn eval(machine: *Helper.ASTInterpreter, numberOfArgs: usize) !void {
    const bytecode = try Helper.getArgument(machine, numberOfArgs, 0, &[_]Helper.ValueKind{Helper.ValueValue.StringKind});
    const scope = try Helper.getArgument(machine, numberOfArgs, 1, &[_]Helper.ValueKind{Helper.ValueValue.ScopeKind});

    try machine.runtime.openScopeUsing(scope);
    defer machine.runtime.restoreScope();

    try BCInterpreter.eval(&machine.runtime, bytecode.v.StringKind.slice());
}

pub fn readInt(machine: *Helper.ASTInterpreter, numberOfArgs: usize) !void {
    const bytecode = try Helper.getArgument(machine, numberOfArgs, 0, &[_]Helper.ValueKind{Helper.ValueValue.StringKind});
    const offset = try Helper.getArgument(machine, numberOfArgs, 1, &[_]Helper.ValueKind{ Helper.ValueValue.IntKind, Helper.ValueValue.UnitKind });

    const ip = if (offset.isInt()) offset.v.IntKind else 0;

    const result = Interpreter.readInt(bytecode.v.StringKind.slice(), @intCast(ip));
    try machine.runtime.pushIntValue(result);
}

pub fn readFloat(machine: *Helper.ASTInterpreter, numberOfArgs: usize) !void {
    const bytecode = try Helper.getArgument(machine, numberOfArgs, 0, &[_]Helper.ValueKind{Helper.ValueValue.StringKind});
    const offset = try Helper.getArgument(machine, numberOfArgs, 1, &[_]Helper.ValueKind{ Helper.ValueValue.IntKind, Helper.ValueValue.UnitKind });

    const ip = if (offset.isInt()) offset.v.IntKind else 0;

    const result = Interpreter.readFloat(bytecode.v.StringKind.slice(), @intCast(ip));
    try machine.runtime.pushFloatValue(result);
}
