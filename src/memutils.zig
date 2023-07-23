const std = @import("std");

pub const Rc = @import("rc.zig").Rc;

pub fn Owner(comptime T: type) type {
    return struct {
        data: ?T,

        const OwnerImpl = @This();

        pub fn borrow(self: OwnerImpl) Borrower(T) {
            std.debug.assert(self.data != null);
            return .{
                .data = self.data.?,
            };
        }

        pub fn give(self: *OwnerImpl) OwnerImpl {
            if (self.data == null) {
                std.debug.panic("Owner does not own the data anymore", .{});
            }
            const new_owner = .{
                .data = self.data,
            };
            self.data = null;
            return new_owner;
        }

        pub fn get(self: OwnerImpl) T {
            if (self.data == null) {
                std.debug.panic("Owner does not own the data anymore", .{});
            }
            return self.data.?;
        }

        pub fn deinit(self: OwnerImpl) void {
            if (self.data != null) {
                std.debug.panic("Ownership was not transfered anywhere", .{});
            }
        }
    };
}

pub fn Borrower(comptime T: type) type {
    return struct {
        data: T,

        const BorrowerImpl = @This();

        pub fn borrow(self: BorrowerImpl) BorrowerImpl {
            return .{
                .data = self.data,
            };
        }

        pub fn get(self: BorrowerImpl) T {
            return self.data;
        }
    };
}

test {
    std.testing.refAllDeclsRecursive(@This());
}

test "OB: borrow and give back" {
    var o1 = Owner(usize){ .data = 0 };
    defer o1.deinit();

    var b1 = o1.borrow();
    _ = b1;
    var o2 = o1.give();
    defer o2.deinit();

    var o3 = o2.give();
    _ = o3;
}
