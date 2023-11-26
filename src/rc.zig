const std = @import("std");

const meta = @import("meta.zig");

pub fn Rc(comptime T: type) type {
    const Deinit_Fn = *const fn (*T, allocator: std.mem.Allocator) void;

    const deinit_fn_impl = meta.get_deinit_fn(T);

    const default_deinit_fn: Deinit_Fn = struct {
        pub fn deinit_fn(self: *T, allocator: std.mem.Allocator) void {
            if (deinit_fn_impl) |impl| {
                impl(self, allocator);
            }
        }
    }.deinit_fn;

    return struct {
        const Container = struct {
            data: T,
            counter: isize,
        };
        const RcImpl = @This();

        /// `true` if the Rc will call the T's
        /// `deinit(...)` function.
        pub const has_deinit_fn = deinit_fn_impl != null;

        allocator: std.mem.Allocator,
        container: *Container,
        deinit_fn: Deinit_Fn,

        fn _init_w_deinit_fn(data: T, allocator: std.mem.Allocator, deinit_fn: Deinit_Fn) !RcImpl {
            return .{
                .allocator = allocator,
                .container = blk: {
                    const ptr = try allocator.create(Container);
                    ptr.* = .{
                        .counter = 1,
                        .data = data,
                    };
                    break :blk ptr;
                },
                .deinit_fn = deinit_fn,
            };
        }

        pub fn init(data: T, allocator: std.mem.Allocator) !RcImpl {
            return _init_w_deinit_fn(data, allocator, default_deinit_fn);
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
    try std.testing.expect(@TypeOf(rc).has_deinit_fn);

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
    try std.testing.expect(!@TypeOf(b).has_deinit_fn);
    const rawPtr = b.get();
    _ = rawPtr;
}
