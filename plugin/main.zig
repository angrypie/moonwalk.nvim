// const ts = @cImport({
//     @cInclude("./treesitter_api.h");
// });

const api = @import("./api.zig");
const std = @import("std");
const arena = @import("./arena.zig");

// This function must be called exactly once during the lifetime of the plugin from lua side.
pub export fn init_plugin() void {
    arena.arena_init();
}

fn getEchoOpts(verobose: bool, err: bool) [*c]api.DictEchoOpts {
    var opts = api.DictEchoOpts{ .verbose = verobose, .err = err };
    return &opts;
}

fn getCString(str: []const u8) [*c]const u8 {
    const c_string = std.mem.span(str);
    return c_string;
}

fn getStringArray(str: []const u8) api.Array {
    var array = api.Array{
        .size = 1,
        .capacity = 1,
        .items = &api.Object{
            .type = api.kObjectTypeString,
            .data = .{ .string = getCString(str) },
        },
    };
    return &array;
}

pub export fn get_number() i64 {

    // const lines = api.nvim_buf_get_lines(api.LUA_INTERNAL_CALL, 0, 0, 5, false, arena_ptr, null, &err);
    // const lines = arena.getBufferLines(api.LUA_INTERNAL_CALL, 0, line_num - 1, line_num, false, null);
    // const line_size = lines.size; //usize
    //print first line
    // const object_type = lines.items[0].data.type;
    // std.debug.print("object type: {d}\n", .{object_type});

    var exec_err: api.Error = api.ERROR_INIT;
    // const ptr = arena.arena();
    // const c_string: [*c]const u8 = "vim.notify('hello')";
    const arr = getStringArray("test");
    const opts = getEchoOpts(true, true);

    _ = api.nvim_echo(arr, false, opts, &exec_err);
    // _ = api.nvim_exec_lua(c_string, array, ptr, &exec_err);

    // var err: api.Error = api.ERROR_INIT;
    // //create pointer to arena.Arena
    // // const arena_ptr: ?*api.Arena = null;
    // const arena_ptr = arena.arena();
    // // api.arena_alloc_block(arena_ptr);
    // const cursor = api.nvim_win_get_cursor(0, arena_ptr, &err);
    // const line_num = cursor.items[0].data.integer;
    // std.debug.print("line num: {d}\n", .{line_num});

    return 3;
}

pub export fn get_last_number(arr: [*]const u32, len: usize) u32 {
    if (len == 0) {
        return 0;
    }
    return arr[len - 1];
}

// cursor.items[0].data.integer = 1;
// cursor.items[1].data.integer = 1;
// api.nvim_win_set_cursor(0, cursor, &err);
// const range = std.mem.zeroInit(api.Array, .{ .size = 2, .capacity = 2, .items = .{ .data = data } });
