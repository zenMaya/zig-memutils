const std = @import("std");

const meta = @import("meta.zig");

pub fn Rc(comptime T: type) type {
    return struct {
        const Container = struct {
            data: T,
            counter: isize,
        };
        const RcImpl = @This();

        const Deinit_Fn = *const fn (*T, allocator: std.mem.Allocator) void;
        pub fn empty_deinit_fn(_: *T, _: std.mem.Allocator) void {}

        /// `true` if the Rc will call the T's
        /// `deinit(...)` function.
        pub fn has_deinit_fn(self: RcImpl) bool {
            return self.deinit_fn != empty_deinit_fn;
        }

        container: *Container,
        allocator: std.mem.Allocator,
        deinit_fn: Deinit_Fn,

        pub fn init_w_deinit_fn(data: T, allocator: std.mem.Allocator, deinit_fn: Deinit_Fn) !RcImpl {
            return .{
                .container = blk: {
                    const ptr = try allocator.create(Container);
                    ptr.* = .{
                        .counter = 1,
                        .data = data,
                    };
                    break :blk ptr;
                },
                .allocator = allocator,
                .deinit_fn = deinit_fn,
            };
        }

        pub fn init(data: T, allocator: std.mem.Allocator) !RcImpl {
            const default_deinit_fn = meta.get_deinit_fn(T) orelse empty_deinit_fn;
            return init_w_deinit_fn(data, allocator, default_deinit_fn);
        }

        pub fn atomic(self: RcImpl) RcImpl {
            if (self.container.counter > 0) {
                self.container.counter = -self.container.count;
            } else {
                std.debug.panic("Calling .atomic() can be only done once", .{});
            }
        }

        pub fn borrow(self: RcImpl) RcImpl {
            if (self.container.counter == 0) {
                std.debug.panic("Rc was already freed", .{});
            }
            if (self.container.counter >= 1) {
                self.container.counter += 1;
            } else {
                _ = @atomicRmw(isize, &self.container.counter, .Sub, 1, .Release);
            }
            return self;
        }

        pub fn get(self: RcImpl) *T {
            if (self.container.counter == 0) {
                std.debug.panic("Rc was already freed", .{});
            }
            return &self.container.data;
        }

        pub fn drop(self: *RcImpl) void {
            if (self.container.counter == 0) {
                std.debug.panic("Rc was already freed", .{});
            }

            if (self.container.counter > 1) {
                self.container.counter -= 1;
            } else {
                if (self.container.counter < -1) {
                    _ = @atomicRmw(isize, &self.container.counter, .Add, 1, .Release);
                } else {
                    @fence(.Acquire);
                    self.deinit();
                }
            }
        }

        fn deinit(self: *RcImpl) void {
            self.container.counter = 0;
            self.deinit_fn(&self.container.data, self.allocator);
            self.allocator.destroy(self.container);
        }
    };
}

test "Rc: struct with deinit" {
    const Struct = struct {
        const Struct = @This();

        ptr: *usize,
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator) !Struct {
            return .{
                .ptr = try allocator.create(usize),
                .allocator = allocator,
            };
        }
        pub fn deinit(self: *Struct) void {
            self.allocator.destroy(self.ptr);
        }
    };

    var rc = try Rc(Struct).init(try Struct.init(std.testing.allocator), std.testing.allocator);
    defer rc.drop();
    try std.testing.expect(rc.has_deinit_fn());
    var rc2 = rc.borrow();
    defer rc2.drop();
}

const A = struct {
    b: Rc(B),
};

const B = struct {
    a: A,
};

test "Rc: recursive comptime structure" {
    var b = try Rc(B).init(.{ .a = undefined }, std.testing.allocator);
    defer b.drop();
    try std.testing.expect(!b.has_deinit_fn());
    const rawPtr = b.get();
    _ = rawPtr;
}

const Rc_C = Rc(C);
const C = struct {
    c: ?Rc(C),

    pub fn deinit(self: *C, _: std.mem.Allocator) void {
        if (self.c) |*c| {
            c.drop();
        }
    }
};

test "Rc: test Rc inside the struct" {
    var c_0 = try Rc_C.init_w_deinit_fn(.{ .c = null }, std.testing.allocator, C.deinit);
    defer c_0.drop();
    var c_1 = try Rc_C.init_w_deinit_fn(.{ .c = c_0.borrow() }, std.testing.allocator, C.deinit);
    defer c_1.drop();
    var c_2 = try Rc_C.init(.{ .c = c_1.borrow() }, std.testing.allocator);
    defer c_2.drop();
}
