// const ts = @cImport({
//     @cInclude("./treesitter_api.h");
// });

const std = @import("std");
const api = @import("./nvim_lib.zig");

pub export fn get_number() i64 {

    // const lines = api.nvim_buf_get_lines(api.LUA_INTERNAL_CALL, 0, 0, 5, false, arena_ptr, null, &err);
    // const lines = arena.getBufferLines(api.LUA_INTERNAL_CALL, 0, line_num - 1, line_num, false, null);
    // const line_size = lines.size; //usize
    //print first line
    // const object_type = lines.items[0].data.type;
    // std.debug.print("object type: {d}\n", .{object_type});

    // var exec_err: api.Error = api.ERROR_INIT;
    // const ptr = arena.arena();
    // const c_string: [*c]const u8 = "vim.notify('hello')";
    // const arr = getStringArray("test");
    // const opts = getEchoOpts(true, true);

    // _ = api.nvim_echo(arr, false, opts, &exec_err);
    // _ = api.nvim_exec_lua(c_string, array, ptr, &exec_err);

    // api.arena_alloc_block(arena_ptr);
    const cursor = api.nvim_win_get_cursor(0);
    const line_num = cursor.row;
    // std.debug.print("line num: {d}\n", .{line_num});
    api.nvim_win_set_cursor(0, 2, 2);
    return line_num;
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
    const file = api.nvim_buf_get_name(0);
    api.nvim_out_write(file);
    if (len == 0) {
        return 0;
    }
    return arr[len - 1];
}

// cursor.items[0].data.integer = 1;
// cursor.items[1].data.integer = 1;
// api.nvim_win_set_cursor(0, cursor, &err);
// const range = std.mem.zeroInit(api.Array, .{ .size = 2, .capacity = 2, .items = .{ .data = data } });
