// ═════════════════════════════════════════════════════════════════════════════
// Grimoire Runtime — embedded into every compiled .gr program
// ═════════════════════════════════════════════════════════════════════════════

const std = @import("std");

pub const ValueTag = enum {
    number,
    boolean,
    nil,
    string,
    symbol,
    keyword,
    list,
    vector,
    map,
    set,
};

pub const Value = union(ValueTag) {
    number: i64,
    boolean: bool,
    nil: void,
    string: []const u8,
    symbol: []const u8,
    keyword: []const u8,
    list: *List,
    vector: *Vector,
    map: *Map,
    set: *Set,
};

pub const List = struct {
    first: Value,
    rest: ?*List,
    count: usize,

    pub fn empty() List {
        return .{ .first = .nil, .rest = null, .count = 0 };
    }

    pub fn isEmpty(self: List) bool {
        return self.count == 0;
    }

    pub fn cons(self: List, al: std.mem.Allocator, v: Value) !*List {
        const node = try al.create(List);
        node.* = .{ .first = v, .rest = if (self.count == 0) null else try self.copy(al), .count = self.count + 1 };
        return node;
    }

    pub fn copy(self: List, al: std.mem.Allocator) !*List {
        const node = try al.create(List);
        node.* = .{ .first = self.first, .rest = self.rest, .count = self.count };
        return node;
    }

    pub fn get(self: List, idx: usize) Value {
        var cur: ?*const List = if (self.count == 0) null else &self;
        var i = idx;
        while (cur) |node| {
            if (i == 0) return node.first;
            cur = node.rest;
            i -= 1;
        }
        return Value{ .nil = {} };
    }
};

pub const Vector = struct {
    const SHIFT = 5;
    const WIDTH = 1 << SHIFT;
    const MASK = WIDTH - 1;

    pub const Node = union(enum) {
        internal: [WIDTH]?*Node,
        leaf: [WIDTH]Value,
    };

    root: ?*Node,
    len: usize,
    shift: u6,

    pub fn empty() Vector {
        return .{ .root = null, .len = 0, .shift = 0 };
    }

    pub fn get(self: Vector, idx: usize) Value {
        if (idx >= self.len) return Value{ .nil = {} };
        const node = self.root.?;
        if (self.shift == 0) {
            return node.leaf[idx];
        }
        return self.getNode(node, self.shift, idx);
    }

    fn getNode(self: Vector, node: *Node, shift: u6, idx: usize) Value {
        const child_idx = (idx >> shift) & MASK;
        const child = node.internal[child_idx].?;
        if (shift == SHIFT) {
            return child.leaf[idx & MASK];
        }
        return self.getNode(child, shift - SHIFT, idx);
    }

    pub fn conj(self: Vector, al: std.mem.Allocator, v: Value) !Vector {
        if (self.len == 0) {
            const leaf = try al.create(Node);
            var vals: [WIDTH]Value = undefined;
            vals[0] = v;
            leaf.* = .{ .leaf = vals };
            return .{ .root = leaf, .len = 1, .shift = 0 };
        }

        if (self.shift == 0 and self.len < WIDTH) {
            const leaf = try al.create(Node);
            var vals = self.root.?.leaf;
            vals[self.len] = v;
            leaf.* = .{ .leaf = vals };
            return .{ .root = leaf, .len = self.len + 1, .shift = 0 };
        }

        // Ensure enough depth.
        const new_shift = blk: {
            const cap = std.math.pow(usize, WIDTH, (self.shift / SHIFT) + 1);
            if (self.len == cap) break :blk self.shift + SHIFT;
            break :blk self.shift;
        };

        const new_root = try al.create(Node);
        if (new_shift != self.shift) {
            var children: [WIDTH]?*Node = undefined;
            children = @splat(null);
            children[0] = self.root.?;
            new_root.* = .{ .internal = children };
        } else {
            new_root.* = self.root.?.*;
        }

        var cur = new_root;
        var shift = new_shift;
        while (shift > 0) {
            const child_idx = (self.len >> shift) & MASK;
            const old_child = cur.internal[child_idx];
            const new_child = try al.create(Node);
            if (old_child) |oc| {
                new_child.* = oc.*;
            } else if (shift == SHIFT) {
                var vals: [WIDTH]Value = undefined;
                vals = @splat(.nil);
                new_child.* = .{ .leaf = vals };
            } else {
                var children2: [WIDTH]?*Node = undefined;
                children2 = @splat(null);
                new_child.* = .{ .internal = children2 };
            }
            cur.internal[child_idx] = new_child;
            cur = new_child;
            shift -= SHIFT;
        }

        cur.leaf[self.len & MASK] = v;
        return .{ .root = new_root, .len = self.len + 1, .shift = new_shift };
    }

    pub fn assoc(self: Vector, al: std.mem.Allocator, idx: usize, v: Value) !Vector {
        if (idx >= self.len) return self;
        if (self.shift == 0) {
            const leaf = try al.create(Node);
            var vals = self.root.?.leaf;
            vals[idx] = v;
            leaf.* = .{ .leaf = vals };
            return .{ .root = leaf, .len = self.len, .shift = 0 };
        }
        const new_root = try al.create(Node);
        new_root.* = self.root.?.*;
        var cur = new_root;
        var shift = self.shift;
        while (shift > 0) {
            const child_idx = (idx >> shift) & MASK;
            const old_child = cur.internal[child_idx].?;
            const new_child = try al.create(Node);
            new_child.* = old_child.*;
            cur.internal[child_idx] = new_child;
            cur = new_child;
            shift -= SHIFT;
        }
        cur.leaf[idx & MASK] = v;
        return .{ .root = new_root, .len = self.len, .shift = self.shift };
    }
};

pub const Map = struct {
    pub const Entry = struct { key: Value, val: Value };
    entries: []Entry,

    pub fn empty() Map {
        return .{ .entries = &[_]Entry{} };
    }

    fn orderToI8(o: std.math.Order) i8 {
        return switch (o) {
            .lt => -1,
            .eq => 0,
            .gt => 1,
        };
    }

    fn compareKeys(a: Value, b: Value) i8 {
        const ta = @intFromEnum(std.meta.activeTag(a));
        const tb = @intFromEnum(std.meta.activeTag(b));
        if (ta != tb) return if (ta < tb) -1 else 1;
        return switch (a) {
            .number => |n| if (n < b.number) -1 else if (n > b.number) 1 else 0,
            .string => |s| orderToI8(std.mem.order(u8, s, b.string)),
            .keyword => |s| orderToI8(std.mem.order(u8, s, b.keyword)),
            .symbol => |s| orderToI8(std.mem.order(u8, s, b.symbol)),
            .boolean => |x| if (x == b.boolean) 0 else if (x) 1 else -1,
            .nil => 0,
            else => 0,
        };
    }

    pub fn find(self: Map, key: Value) ?usize {
        var lo: usize = 0;
        var hi = self.entries.len;
        while (lo < hi) {
            const mid = (lo + hi) / 2;
            const c = compareKeys(key, self.entries[mid].key);
            if (c == 0) return mid;
            if (c < 0) hi = mid else lo = mid + 1;
        }
        return null;
    }

    pub fn get(self: Map, key: Value) Value {
        if (self.find(key)) |i| return self.entries[i].val;
        return Value{ .nil = {} };
    }

    pub fn contains(self: Map, key: Value) bool {
        return self.find(key) != null;
    }

    pub fn assoc(self: Map, al: std.mem.Allocator, key: Value, val: Value) !Map {
        const new_entries = try al.alloc(Entry, self.entries.len + 1);
        var inserted = false;
        var i: usize = 0;
        for (self.entries) |e| {
            const c = compareKeys(key, e.key);
            if (c == 0) {
                new_entries[i] = .{ .key = key, .val = val };
                i += 1;
                inserted = true;
            } else if (c < 0 and !inserted) {
                new_entries[i] = .{ .key = key, .val = val };
                i += 1;
                inserted = true;
                new_entries[i] = e;
                i += 1;
            } else {
                new_entries[i] = e;
                i += 1;
            }
        }
        if (!inserted) {
            new_entries[i] = .{ .key = key, .val = val };
            i += 1;
        }
        return .{ .entries = new_entries[0..i] };
    }
};

pub const Set = struct {
    map: Map,

    pub fn empty() Set {
        return .{ .map = Map.empty() };
    }

    pub fn contains(self: Set, v: Value) bool {
        return self.map.contains(v);
    }

    pub fn conj(self: Set, al: std.mem.Allocator, v: Value) !Set {
        return .{ .map = try self.map.assoc(al, v, .nil) };
    }
};

// ═════════════════════════════════════════════════════════════════════════════
// Public constructor / helper API used by emitted code
// ═════════════════════════════════════════════════════════════════════════════

pub fn number(n: i64) Value { return .{ .number = n }; }
pub fn boolean(b: bool) Value { return .{ .boolean = b }; }
pub const nil: Value = .{ .nil = {} };
pub fn string(s: []const u8) Value { return .{ .string = s }; }
pub fn symbol(s: []const u8) Value { return .{ .symbol = s }; }
pub fn keyword(s: []const u8) Value { return .{ .keyword = s }; }

pub fn listFrom(al: std.mem.Allocator, items: []const Value) !Value {
    var head = List.empty();
    var i = items.len;
    while (i > 0) {
        i -= 1;
        head = (try head.cons(al, items[i])).*;
    }
    return .{ .list = try head.copy(al) };
}

pub fn vectorFrom(al: std.mem.Allocator, items: []const Value) !Value {
    var v = Vector.empty();
    for (items) |it| v = try v.conj(al, it);
    const ptr = try al.create(Vector);
    ptr.* = v;
    return .{ .vector = ptr };
}

pub fn mapFrom(al: std.mem.Allocator, items: []const Map.Entry) !Value {
    var m = Map.empty();
    var i: usize = 0;
    while (i < items.len) : (i += 2) {
        m = try m.assoc(al, items[i].key, items[i].val);
    }
    const ptr = try al.create(Map);
    ptr.* = m;
    return .{ .map = ptr };
}

pub fn setFrom(al: std.mem.Allocator, items: []const Value) !Value {
    var s = Set.empty();
    for (items) |it| s = try s.conj(al, it);
    const ptr = try al.create(Set);
    ptr.* = s;
    return .{ .set = ptr };
}

pub fn count(v: Value) i64 {
    return switch (v) {
        .list => |list| @intCast(list.count),
        .vector => |p| @intCast(p.len),
        .map => |p| @intCast(p.entries.len),
        .set => |p| @intCast(p.map.entries.len),
        .string => |s| @intCast(s.len),
        else => 0,
    };
}

pub fn first(v: Value) Value {
    return switch (v) {
        .list => |list| if (list.count == 0) .nil else list.first,
        .vector => |p| if (p.len == 0) .nil else p.get(0),
        .map => |p| if (p.entries.len == 0) .nil else p.entries[0].key,
        .set => |p| if (p.map.entries.len == 0) .nil else p.map.entries[0].key,
        else => .nil,
    };
}

pub fn rest(v: Value, al: std.mem.Allocator) Value {
    return switch (v) {
        .list => |list| if (list.rest) |r| .{ .list = r } else .nil,
        .vector => |p| if (p.len <= 1) .nil else blk: {
            const new = try al.create(Vector);
            new.* = .{ .root = p.root, .len = p.len - 1, .shift = p.shift };
            break :blk .{ .vector = new };
        },
        else => .nil,
    };
}

pub fn conj(v: Value, al: std.mem.Allocator, item: Value) !Value {
    return switch (v) {
        .list => |list| .{ .list = try list.cons(al, item) },
        .vector => |p| .{ .vector = try p.conj(al, item) },
        .set => |p| .{ .set = try p.conj(al, item) },
        else => .nil,
    };
}

pub fn concat(al: std.mem.Allocator, a: Value, b: Value) !Value {
    return switch (a) {
        .list => |la| blk: {
            var items = std.ArrayList(Value).empty;
            var cur: ?*const List = if (la.count == 0) null else la;
            while (cur) |node| {
                try items.append(al, node.first);
                cur = node.rest;
            }
            switch (b) {
                .list => |lb| {
                    cur = if (lb.count == 0) null else lb;
                    while (cur) |node| {
                        try items.append(al, node.first);
                        cur = node.rest;
                    }
                },
                .vector => |vb| {
                    var i: usize = 0;
                    while (i < vb.len) : (i += 1) try items.append(al, vb.get(i));
                },
                else => {},
            }
            break :blk try listFrom(al, items.items);
        },
        .vector => |va| switch (b) {
            .vector => |vb| blk: {
                var out = va.*;
                var i: usize = 0;
                while (i < vb.len) : (i += 1) out = try Vector.conj(out, al, vb.get(i));
                const ptr = try al.create(Vector);
                ptr.* = out;
                break :blk .{ .vector = ptr };
            },
            else => .nil,
        },
        else => .nil,
    };
}

pub fn get(v: Value, key: Value) Value {
    return switch (v) {
        .map => |p| p.get(key),
        .vector => |p| if (key == .number) p.get(@intCast(key.number)) else .nil,
        .list => |p| if (key == .number) p.get(@intCast(key.number)) else .nil,
        .set => |p| if (p.contains(key)) key else .nil,
        else => .nil,
    };
}

pub fn assoc(v: Value, al: std.mem.Allocator, key: Value, val: Value) !Value {
    return switch (v) {
        .map => |p| .{ .map = try p.assoc(al, key, val) },
        .vector => |p| .{ .vector = try p.assoc(al, @intCast(key.number), val) },
        else => .nil,
    };
}

pub fn contains(v: Value, key: Value) bool {
    return switch (v) {
        .map => |p| p.contains(key),
        .set => |p| p.contains(key),
        else => false,
    };
}

pub fn equal(a: Value, b: Value) bool {
    if (@intFromEnum(std.meta.activeTag(a)) != @intFromEnum(std.meta.activeTag(b))) return false;
    return switch (a) {
        .number => |n| n == b.number,
        .boolean => |x| x == b.boolean,
        .nil => true,
        .string => |s| std.mem.eql(u8, s, b.string),
        .keyword => |s| std.mem.eql(u8, s, b.keyword),
        .symbol => |s| std.mem.eql(u8, s, b.symbol),
        else => false,
    };
}

pub fn truthy(v: Value) bool {
    return switch (v) {
        .nil => false,
        .boolean => |b| b,
        else => true,
    };
}

pub fn deref(v: Value) Value {
    return v;
}

pub fn add(a: Value, b: Value) Value { return .{ .number = a.number + b.number }; }
pub fn sub(a: Value, b: Value) Value { return .{ .number = a.number - b.number }; }
pub fn mul(a: Value, b: Value) Value { return .{ .number = a.number * b.number }; }
pub fn div(a: Value, b: Value) Value { return .{ .number = @divTrunc(a.number, b.number) }; }
pub fn mod(a: Value, b: Value) Value { return .{ .number = @mod(a.number, b.number) }; }
pub fn neg(a: Value) Value { return .{ .number = -a.number }; }

pub fn lt(a: Value, b: Value) bool { return a.number < b.number; }
pub fn gt(a: Value, b: Value) bool { return a.number > b.number; }
pub fn le(a: Value, b: Value) bool { return a.number <= b.number; }
pub fn ge(a: Value, b: Value) bool { return a.number >= b.number; }

pub fn grPrint(v: Value) Value {
    std.debug.print("{s}\n", .{toString(v)});
    return nil;
}

pub fn toString(v: Value) []const u8 {
    return switch (v) {
        .number => |n| std.fmt.allocPrint(std.heap.page_allocator, "{d}", .{n}) catch "",
        .boolean => |b| if (b) "true" else "false",
        .nil => "nil",
        .string => |s| s,
        .symbol => |s| s,
        .keyword => |s| s,
        else => "#<collection>",
    };
}
