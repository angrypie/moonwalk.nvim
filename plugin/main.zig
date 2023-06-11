const api = @import("./api.zig");
const std = @import("std");

pub const KVInteger = extern struct { size: api.size_t, capacity: api.size_t, type: struct {
    type: c_uint,
    data: []i64,
} };

pub export fn get_magenta() i64 {
    var err: api.Error = api.ERROR_INIT;
    // var height = api.nvim_win_get_height(0, &err);
    // const n: i64 = 2;
    // const objects: [*c]api.Object = &[_]api.Object{
    //     .{ .type = api.kObjectTypeInteger, .data = n },
    //     .{ .type = api.kObjectTypeInteger, .data = n },
    // };
    const cursor = api.nvim_win_get_cursor(0, &err);
    //TODO defer kvec.kv_destroy(cursor);

    // const range = std.mem.zeroInit(api.Array, .{ .size = 2, .capacity = 2, .items = .{ .data = data } });
    //

    const line = cursor.items[0].data.integer;

    cursor.items[0].data.integer = 1;
    cursor.items[1].data.integer = 1;
    api.nvim_win_set_cursor(0, cursor, &err);

    return line;
}
