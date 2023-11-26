const std = @import("std");

pub fn get_deinit_fn(comptime T: type) ?fn (*T, std.mem.Allocator) void {
    if (@hasDecl(T, "deinit")) {
        const deinit_fn = @field(T, "deinit");

        switch (@typeInfo(@TypeOf(deinit_fn))) {
            .Fn => |fun| {
                if (fun.params.len == 2 and (fun.params[0].type.? == *T) and fun.params[1].type.? == std.mem.Allocator) {
                    return deinit_fn;
                } else if (fun.params.len == 1 and fun.params[0].type.? == *T) {
                    return struct {
                        pub fn deinit_wrapper(self: *T, allocator: std.mem.Allocator) void {
                            _ = allocator;
                            deinit_fn(self);
                        }
                    }.deinit_wrapper;
                } else return null;
            },
            else => {
                return null;
            },
        }
    } else return null;
}
