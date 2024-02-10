const Helper = @import("./helper.zig");

pub fn scope(machine: *Helper.Runtime, numberOfArgs: usize) !void {
    _ = numberOfArgs;
    try machine.push(machine.scope().?);
}

pub fn open(machine: *Helper.Runtime, numberOfArgs: usize) !void {
    const scp = try Helper.getArgument(machine, numberOfArgs, 0, &[_]Helper.ValueKind{Helper.ValueValue.ScopeKind});

    try machine.pushScopeValue(scp);
}

pub fn super(machine: *Helper.Runtime, numberOfArgs: usize) !void {
    const v = try Helper.getArgument(machine, numberOfArgs, 0, &[_]Helper.ValueKind{Helper.ValueValue.ScopeKind});

    if (v.v.ScopeKind.parent == null) {
        try machine.pushUnitValue();
    } else {
        try machine.push(v.v.ScopeKind.parent.?);
    }
}

pub fn assign(machine: *Helper.Runtime, numberOfArgs: usize) !void {
    const scp = try Helper.getArgument(machine, numberOfArgs, 0, &[_]Helper.ValueKind{Helper.ValueValue.ScopeKind});
    const v = try Helper.getArgument(machine, numberOfArgs, 1, &[_]Helper.ValueKind{ Helper.ValueValue.ScopeKind, Helper.ValueValue.UnitKind });

    if (v.isUnit()) {
        scp.v.ScopeKind.parent = null;
    } else {
        scp.v.ScopeKind.parent = v;
    }

    try machine.push(scp);
}

pub fn bind(machine: *Helper.Runtime, numberOfArgs: usize) !void {
    const scp = try Helper.getArgument(machine, numberOfArgs, 0, &[_]Helper.ValueKind{Helper.ValueValue.ScopeKind});
    const key = try Helper.getArgument(machine, numberOfArgs, 1, &[_]Helper.ValueKind{Helper.ValueValue.StringKind});
    const value = if (numberOfArgs > 2) machine.peek(numberOfArgs - 3) else machine.unitValue.?;

    try scp.v.ScopeKind.set(key.v.StringKind.value, value);

    try machine.push(value);
}

pub fn delete(machine: *Helper.Runtime, numberOfArgs: usize) !void {
    const scp = try Helper.getArgument(machine, numberOfArgs, 0, &[_]Helper.ValueKind{Helper.ValueValue.ScopeKind});
    const key = try Helper.getArgument(machine, numberOfArgs, 1, &[_]Helper.ValueKind{Helper.ValueValue.StringKind});

    const value = try scp.v.ScopeKind.delete(key.v.StringKind.value);

    if (value == null) {
        try machine.pushUnitValue();
    } else {
        try machine.push(value.?);
    }
}
