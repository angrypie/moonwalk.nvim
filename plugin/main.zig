// const ts = @cImport({
//     @cInclude("./treesitter_api.h");
// });

const std = @import("std");
const api = @import("./nvim_lib.zig");
const shadow = @import("./shadow.zig");

pub export fn get_number() i64 {
    // Call the LLM suggestion function and return API execution time
    const api_time_ms = shadow.make_suggestions();
    return api_time_ms;
}

pub export fn process_array(arr: [*]const u32, len: usize) u32 {
    // Simple message without highlighting
    // var chunks = [1][2][]const u8{.{ "ya\n", "WarningMsg\n" }};
    // api.nvim_echo(&chunks, true, null);
    // const str: []const u8 = "Hello world";
    // api.nvim_err_writeln(str);
    // api.nvim_err_writeln(str);

    // const zig_str = std.mem.span(name);
    // std.debug.print("extmark: {any}\n", .{extmark});
    // const file = api.nvim_buf_get_name(0);
    // const array = api.nvim_buf_get_lines(0, 0, 3, false);
    // var iterator = array.iterator();
    // while (iterator.next()) |line| {
    //     std.debug.print("line: {s}\n", .{line});
    // }
    // This function can be used for testing other features
    if (len == 0) {
        return 0;
    }
    return arr[len - 1];
}

// cursor.items[0].data.integer = 1;
// cursor.items[1].data.integer = 1;
// api.nvim_win_set_cursor(0, cursor, &err);
// const range = std.mem.zeroInit(api.Array, .{ .size = 2, .capacity = 2, .items = .{ .data = data } });
