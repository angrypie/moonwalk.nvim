const c_api = @import("./nvim_c_api.zig");
const arena = @import("./arena.zig");
const std = @import("std");

// IMPORTANT
// This function must be called exactly once during the lifetime of the plugin from lua side.
pub export fn init_plugin() void {
    arena.arena_init();
}

pub fn nvim_win_set_cursor(win: i32, row: i64, col: i64) void {
    var err: c_api.Error = c_api.ERROR_INIT;

    var cursorInts: [2]c_api.Object = .{
        .{
            .type = c_api.kObjectTypeInteger,
            .data = .{ .integer = col },
        },
        .{
            .type = c_api.kObjectTypeInteger,
            .data = .{ .integer = row },
        },
    };
    const cursor2 = c_api.Array{
        .size = 2,
        .capacity = 2,
        .items = &cursorInts[0],
    };
    c_api.nvim_win_set_cursor(win, cursor2, &err);
    return;
}

pub fn nvim_win_get_cursor(win: i32) struct { col: i64, row: i64 } {
    var err: c_api.Error = c_api.ERROR_INIT;
    const arena_ptr = arena.arena();
    const cursor = c_api.nvim_win_get_cursor(win, arena_ptr, &err);

    return .{
        .col = cursor.items[0].data.integer,
        .row = cursor.items[1].data.integer,
    };
}

pub fn nvim_buf_get_name(buffer: i32) []const u8 {
    var err: c_api.Error = c_api.ERROR_INIT;
    const c_str = c_api.nvim_buf_get_name(buffer, &err);
    //c_str is [*:0]const u8 is a pointer to a null terminated string
    return std.mem.span(c_str);
}

const ExtmarkOpts = struct {
    details: bool = false,
    hl_name: bool = false,
};

pub fn nvim_buf_get_extmark_by_id(buffer: i32, ns_id: i64, id: i64, opts: ?ExtmarkOpts) ?struct { row: i64, col: i64 } {
    var err: c_api.Error = c_api.ERROR_INIT;
    const arena_ptr = arena.arena();

    // Convert our Zig options to C API options
    var c_opts = c_api.KeyDict_get_extmark{
        .is_set__get_extmark_ = 0,
        .details = if (opts != null) opts.details else false,
        .hl_name = if (opts != null) opts.hl_name else false,
    };

    const result = c_api.nvim_buf_get_extmark_by_id(buffer, ns_id, id, &c_opts, arena_ptr, &err);
    if (result.size == 0) return null;

    return .{
        .row = result.items[0].data.integer,
        .col = result.items[1].data.integer,
    };
}

pub const EchoOpts = struct { verbose: bool };

/// TODO: not working for now
/// Prints a message given by a list of [text, hl_group] chunks.
/// @param chunks List of [text, hl_group] pairs, where each is a text string highlighted by
///               the (optional) name or ID hl_group.
/// @param history if true, add to message-history.
/// @param opts Optional parameters:
///          - verbose: Message is controlled by the 'verbose' option.
pub fn nvim_echo(chunks: *[1][2][]const u8, history: bool, opts: ?EchoOpts) void {
    // Create text and hl_group objects
    var chunk_pair = [_]c_api.Object{
        .{ // text string
            .type = c_api.kObjectTypeString,
            .data = .{ .string = chunks[0][0].ptr },
        },
        .{ // hl_group string
            .type = c_api.kObjectTypeString,
            .data = .{ .string = chunks[0][1].ptr },
        },
    };

    var chunk_array_obj = c_api.Object{
        .type = c_api.kObjectTypeArray,
        .data = .{ .array = .{
            .items = &chunk_pair,
            .size = 2,
        } },
    };

    // Create the final chunks array
    const c_chunks = c_api.Array{
        .items = &chunk_array_obj,
        .size = 1,
    };

    const chunk = c_chunks.items[0].data.array;
    // print size of the chunk array
    std.debug.print("size of chunk array: {d}\n", .{chunk.size});
    const first_data_string = chunk.items[0].data.string;
    std.debug.print("first data string: {s}\n", .{first_data_string});

    // Convert our Zig options to C API options
    var c_opts = c_api.KeyDict_echo_opts{
        .verbose = if (opts != null) opts.?.verbose else false,
    };

    var err: c_api.Error = c_api.ERROR_INIT;
    c_api.nvim_echo(c_chunks, history, &c_opts, &err);
    std.debug.print("Nvim echo error: type={}\n", .{err.type});
    return;
}

pub fn nvim_out_write(str: []const u8) void {
    c_api.nvim_err_writeln(str.ptr);
}
