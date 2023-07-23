const std = @import("std");

const meta = @import("meta.zig");

pub fn Rc(comptime T: type) type {
    return struct {
        const is_slice = @typeInfo(T) == .Pointer and @typeInfo(T).Pointer.size == .Slice;
        const SliceItemT = if (is_slice) @typeInfo(T).Pointer.child else @compileError("T is not a slice");
        const slice_test = if (is_slice) if (@typeInfo(T).Pointer.sentinel != null) @compileError("Sentinel slices are unsupported");

        const default_deinit_fn = struct {
            pub fn deinit_fn(self: *T, allocator: std.mem.Allocator) void {
                const t_info = @typeInfo(T);

                switch (t_info) {
                    .Struct, .Union => if (meta.get_deinit_fn(T)) |deinit_fn_impl| {
                        deinit_fn_impl(self, allocator);
                    },
                    else => {},
                }
            }
        }.deinit_fn;
        const default_deinit_fn_slice = struct {
            pub fn deinit_fn(self: *T, allocator: std.mem.Allocator) void {
                const orig_data = @fieldParentPtr(RcImpl, "data", self).orig_data;
                allocator.free(orig_data);
            }
        }.deinit_fn;

        const DataT = if (is_slice) T else *T;

        allocator: std.mem.Allocator,
        data: if (is_slice) T else *T,
        orig_data: if (is_slice) DataT else void,
        counter: *isize,
        deinit_fn: *const fn (*T, std.mem.Allocator) void,

        const RcImpl = @This();

        fn _init_w_deinit_fn(data: T, allocator: std.mem.Allocator, deinit_fn: *const fn (*T, std.mem.Allocator) void) !RcImpl {
            return .{
                .allocator = allocator,
                .data = data: {
                    const data_p = try allocator.create(T);
                    data_p.* = data;
                    break :data data_p;
                },
                .orig_data = {},
                .counter = counter: {
                    const counter = try allocator.create(isize);
                    counter.* = 1;
                    break :counter counter;
                },
                .deinit_fn = deinit_fn,
            };
        }
        fn _init_w_deinit_fn_slice(n: usize, allocator: std.mem.Allocator, deinit_fn: *const fn (*T, std.mem.Allocator) void) !RcImpl {
            _ = slice_test;
            const slice = try allocator.alloc(SliceItemT, n);
            return .{
                .allocator = allocator,
                .data = slice,
                .orig_data = slice,
                .counter = counter: {
                    const counter = try allocator.create(isize);
                    counter.* = 1;
                    break :counter counter;
                },
                .deinit_fn = deinit_fn,
            };
        }

        fn _init(data: T, allocator: std.mem.Allocator) !RcImpl {
            return _init_w_deinit_fn(data, allocator, default_deinit_fn);
        }
        fn _init_slice(n: usize, allocator: std.mem.Allocator) !RcImpl {
            return _init_w_deinit_fn_slice(n, allocator, default_deinit_fn_slice);
        }
        pub const init = if (is_slice) _init_slice else _init;

        fn _init_dupe(data: []const SliceItemT, allocator: std.mem.Allocator) !RcImpl {
            _ = slice_test;
            const slice = try allocator.dupe(SliceItemT, data);
            return .{
                .allocator = allocator,
                .data = slice,
                .orig_data = slice,
                .counter = counter: {
                    const counter = try allocator.create(isize);
                    counter.* = 1;
                    break :counter counter;
                },
                .deinit_fn = default_deinit_fn_slice,
            };
        }
        pub const init_dupe = if (is_slice) _init_dupe else @compileError("init_dupe supported only on slices");

        fn _subslice(self: RcImpl, from: usize, to: usize) RcImpl {
            var new = self.borrow();
            new.data = new.data[from..to];
            return new;
        }
        pub const subslice = if (is_slice) _subslice else @compileError("subslice supported only on slices");

        pub fn atomic(self: RcImpl) RcImpl {
            if (self.counter.* > 0) {
                self.counter.* = -self.count.*;
            } else {
                std.debug.panic("Calling .atomic() can be only done once", .{});
            }
        }

        pub fn borrow(self: RcImpl) RcImpl {
            if (self.counter.* == 0) {
                std.debug.panic("Rc was already freed", .{});
            }
            if (self.counter.* >= 1) {
                self.counter.* += 1;
            } else {
                _ = @atomicRmw(isize, self.counter, .Sub, 1, .Release);
            }
            return self;
        }

        pub fn get(self: RcImpl) if (is_slice) T else *T {
            if (self.counter.* == 0) {
                std.debug.panic("Rc was already freed", .{});
            }
            return if (is_slice) self.data else self.data;
        }

        pub fn drop(self: *RcImpl) void {
            if (self.counter.* == 0) {
                std.debug.panic("Rc was already freed", .{});
            }

            if (self.counter.* > 1) {
                self.counter.* -= 1;
            } else {
                if (self.counter.* < -1) {
                    _ = @atomicRmw(isize, self.counter, .Add, 1, .Release);
                } else {
                    @fence(.Acquire);
                    self.deinit();
                }
            }
        }

        fn deinit(self: *RcImpl) void {
            self.counter.* = 0;
            self.deinit_fn(if (is_slice) &self.data else self.data, self.allocator);
            self.allocator.destroy(self.counter);
            if (!is_slice) {
                self.allocator.destroy(self.data);
            }
        }
    };
}

test "Rc: slice" {
    const str = try std.testing.allocator.alloc(u8, 20);
    defer std.testing.allocator.free(str);
    var s = try Rc([]u8).init(20, std.testing.allocator);
    defer s.drop();
    @memcpy(s.get(), str);

    _ = s.borrow();
    _ = s.borrow();
    _ = s.borrow();
    defer s.drop();
    s.drop();
    _ = s.borrow();
    s.drop();
    defer s.drop();
}

test "Rc: init dupe slice" {
    var rc = try Rc([]u8).init_dupe("aa", std.testing.allocator);
    defer rc.drop();
}

test "Rc: subslice" {
    var rc = try Rc([]u8).init_dupe("aaa", std.testing.allocator);
    var src = rc.subslice(2, rc.get().len);

    try std.testing.expectEqual(@as(usize, 1), src.get().len);
    src.drop();
    src.drop();
}

test "Rc: struct with deinit" {
    const Struct = struct {
        const Struct = @This();

        ptr: *void,
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator) !Struct {
            return .{
                .ptr = try allocator.create(void),
                .allocator = allocator,
            };
        }
        pub fn deinit(self: *Struct) void {
            self.allocator.destroy(self.ptr);
        }
    };

    var rc = try Rc(Struct).init(try Struct.init(std.testing.allocator), std.testing.allocator);
    _ = rc.borrow();
    _ = rc.drop();
    _ = rc.drop();
}
