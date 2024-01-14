const Helper = @import("./helper.zig");

pub fn scope(machine: *Helper.Machine, numberOfArgs: usize) !void {
    _ = numberOfArgs;
    try machine.memoryState.push(machine.memoryState.scope().?);
}

pub fn super(machine: *Helper.Machine, numberOfArgs: usize) !void {
    const v = try Helper.getArgument(machine, numberOfArgs, 0, &[_]Helper.ValueKind{Helper.ValueValue.ScopeKind});

    if (v.v.ScopeKind.parent == null) {
        try machine.memoryState.pushUnitValue();
    } else {
        try machine.memoryState.push(v.v.ScopeKind.parent.?);
    }
}

pub fn assign(machine: *Helper.Machine, numberOfArgs: usize) !void {
    const scp = try Helper.getArgument(machine, numberOfArgs, 0, &[_]Helper.ValueKind{Helper.ValueValue.ScopeKind});
    const v = try Helper.getArgument(machine, numberOfArgs, 1, &[_]Helper.ValueKind{ Helper.ValueValue.ScopeKind, Helper.ValueValue.UnitKind });

    if (v.isUnit()) {
        scp.v.ScopeKind.parent = null;
    } else {
        scp.v.ScopeKind.parent = v;
    }

    try machine.memoryState.push(scp);
}

pub fn bind(machine: *Helper.Machine, numberOfArgs: usize) !void {
    const scp = try Helper.getArgument(machine, numberOfArgs, 0, &[_]Helper.ValueKind{Helper.ValueValue.ScopeKind});
    const key = try Helper.getArgument(machine, numberOfArgs, 1, &[_]Helper.ValueKind{Helper.ValueValue.StringKind});
    const value = if (numberOfArgs > 2) machine.memoryState.peek(numberOfArgs - 3) else machine.memoryState.unitValue.?;

    try scp.v.ScopeKind.set(key.v.StringKind.value, value);

    try machine.memoryState.push(value);
}
