const std = @import("std");

pub const StringPool = struct {
    allocator: std.mem.Allocator,
    items: std.StringHashMap(*String),

    pub fn init(allocator: std.mem.Allocator) StringPool {
        return StringPool{
            .allocator = allocator,
            .items = std.StringHashMap(*String).init(allocator),
        };
    }

    pub fn deinit(self: *StringPool) void {
        if (self.items.count() > 0) {
            std.log.err("string pool: memory leak: {d} items in pool", .{self.items.count()});
        }

        self.items.deinit();
    }

    pub fn intern(self: *StringPool, data: []const u8) !*String {
        const s = self.items.get(data);
        if (s == null) {
            var string = try self.allocator.create(String);
            const dataDup = try self.allocator.dupe(u8, data);
            string.* = String.init(self, dataDup);
            try self.items.put(dataDup, string);

            return string;
        } else {
            s.?.incRef();

            return s.?;
        }
    }

    pub fn internOwned(self: *StringPool, data: []u8) !*String {
        const s = self.items.get(data);
        if (s == null) {
            var string = try self.allocator.create(String);
            string.* = String.init(self, data);
            try self.items.put(string.data, string);
            return string;
        } else {
            s.?.incRef();
            self.allocator.free(data);

            return s.?;
        }
    }
};

pub const String = struct {
    pool: *StringPool,
    data: []const u8,
    count: u32,

    pub fn init(pool: *StringPool, data: []const u8) String {
        return String{
            .pool = pool,
            .data = data,
            .count = 1,
        };
    }

    pub fn deinit(this: *String) void {
        if (this.pool.items.remove(this.data)) {
            this.pool.allocator.free(this.data);
        } else {
            std.log.err("string pool: failed to remove string", .{});
        }
    }

    pub fn slice(this: *const String) []const u8 {
        return this.data;
    }

    pub fn incRef(this: *String) void {
        if (this.count == std.math.maxInt(u32)) {
            this.count = 0;
        } else if (this.count > 0) {
            this.count += 1;
        }
    }

    pub fn decRef(this: *String) bool {
        if (this.count == 1) {
            return true;
        }

        if (this.count != 0) {
            this.count -= 1;
        }
        return false;
    }

    pub fn len(this: *const String) usize {
        return this.data.len;
    }
};
