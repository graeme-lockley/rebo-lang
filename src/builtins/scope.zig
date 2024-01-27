const Helper = @import("./helper.zig");

pub fn scope(machine: *Helper.ASTInterpreter, numberOfArgs: usize) !void {
    _ = numberOfArgs;
    try machine.runtime.push(machine.runtime.scope().?);
}

pub fn open(machine: *Helper.ASTInterpreter, numberOfArgs: usize) !void {
    const scp = try Helper.getArgument(machine, numberOfArgs, 0, &[_]Helper.ValueKind{Helper.ValueValue.ScopeKind});

    try machine.runtime.pushScopeValue(scp);
}

pub fn super(machine: *Helper.ASTInterpreter, numberOfArgs: usize) !void {
    const v = try Helper.getArgument(machine, numberOfArgs, 0, &[_]Helper.ValueKind{Helper.ValueValue.ScopeKind});

    if (v.v.ScopeKind.parent == null) {
        try machine.runtime.pushUnitValue();
    } else {
        try machine.runtime.push(v.v.ScopeKind.parent.?);
    }
}

pub fn assign(machine: *Helper.ASTInterpreter, numberOfArgs: usize) !void {
    const scp = try Helper.getArgument(machine, numberOfArgs, 0, &[_]Helper.ValueKind{Helper.ValueValue.ScopeKind});
    const v = try Helper.getArgument(machine, numberOfArgs, 1, &[_]Helper.ValueKind{ Helper.ValueValue.ScopeKind, Helper.ValueValue.UnitKind });

    if (v.isUnit()) {
        scp.v.ScopeKind.parent = null;
    } else {
        scp.v.ScopeKind.parent = v;
    }

    try machine.runtime.push(scp);
}

pub fn bind(machine: *Helper.ASTInterpreter, numberOfArgs: usize) !void {
    const scp = try Helper.getArgument(machine, numberOfArgs, 0, &[_]Helper.ValueKind{Helper.ValueValue.ScopeKind});
    const key = try Helper.getArgument(machine, numberOfArgs, 1, &[_]Helper.ValueKind{Helper.ValueValue.StringKind});
    const value = if (numberOfArgs > 2) machine.runtime.peek(numberOfArgs - 3) else machine.runtime.unitValue.?;

    try scp.v.ScopeKind.set(key.v.StringKind.value, value);

    try machine.runtime.push(value);
}

pub fn delete(machine: *Helper.ASTInterpreter, numberOfArgs: usize) !void {
    const scp = try Helper.getArgument(machine, numberOfArgs, 0, &[_]Helper.ValueKind{Helper.ValueValue.ScopeKind});
    const key = try Helper.getArgument(machine, numberOfArgs, 1, &[_]Helper.ValueKind{Helper.ValueValue.StringKind});

    const value = try scp.v.ScopeKind.delete(key.v.StringKind.value);

    if (value == null) {
        try machine.runtime.pushUnitValue();
    } else {
        try machine.runtime.push(value.?);
    }
}
