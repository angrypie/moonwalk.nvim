const c_api = @import("./nvim_c_api.zig");
const arena = @import("./arena.zig");
const std = @import("std");
//TODO figure out errors
//TODO: decide when and how to free memory from neovim. What use copy of data or Array wrapper?
//TODO: functions we need to implement for now
//nvim_buf_set_extmark
//nvim_buf_del_extmark
//nvim_buf_get_extmarks

// IMPORTANT
// This function must be called exactly once during the lifetime of the plugin from lua side.
pub export fn init_plugin() void {
    arena.arena_init();
}

// pub fn init_cursor(comptime

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
    const cursor = c_api.Array{
        .size = 2,
        .capacity = 2,
        .items = &cursorInts,
    };
    c_api.nvim_win_set_cursor(win, cursor, &err);
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

const GetExmarkResult = struct {
    row: i64,
    col: i64,
};

pub fn nvim_buf_get_extmark_by_id(buffer: i32, ns_id: i64, id: i64, opts: ?ExtmarkOpts) ?GetExmarkResult {
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

const ObjectArray = Array(c_api.Object);

/// Echo text with optional highlighting
/// @param chunks Array of [text, hl_group] pairs
/// @param history Whether to add to message history
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

    // const chunk = c_chunks.items[0].data.array;
    // print size of the chunk array
    // std.debug.print("size of chunk array: {d}\n", .{chunk.size});
    // const first_data_string = chunk.items[0].data.string;
    // std.debug.print("first data string: {s}\n", .{first_data_string});

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

const String = []const u8;
const Integer = i64;

pub fn Array(comptime T: type) type {
    return struct {
        arr: c_api.Array,
        len: usize = 0,
        const Self = @This();
        pub fn init(arr: c_api.Array) Self {
            return Self{ .arr = arr, .len = arr.size };
        }
        pub fn get(self: Self, index: usize) ?T {
            if (index >= self.len) {
                return null; // End of iteration
            }
            const item = self.arr.items[index];
            return switch (T) {
                []const u8 => {
                    if (item.data.string == null) {
                        return "";
                    }
                    return std.mem.span(item.data.string);
                },
                i64 => item.data.integer,
                else => @compileError("Unsupported type"),
            };
        }
        pub fn iterator(self: Self) Iterator(Self, T) {
            return Iterator(Self, T).init(self);
        }
    };
}

const StringArray = Array(String);
const IntegerArray = Array(i64);

// Define the Iterator type
pub fn Iterator(comptime T: type, comptime Item: type) type {
    return struct {
        array: T,
        index: usize = 0,

        const Self = @This();

        pub fn init(array: T) Self {
            return Self{ .array = array };
        }

        pub fn next(self: *Self) ?Item {
            if (self.index >= self.array.len) {
                self.index = 0;
                return null;
            }
            const value = self.array.get(self.index);
            self.index += 1;
            return value;
        }
    };
}

const NvimApiError = error{ GetLinesError, WrongResponseType };

/// Get a range of lines from a buffer
/// @param buffer Buffer handle, or 0 for current buffer
/// @param start Start line (0-based, inclusive)
/// @param end End line (0-based, exclusive)
/// @param strict_indexing Whether out-of-bounds should be an error
pub fn nvim_buf_get_lines(buffer: i32, start: i64, end: i64, strict_indexing: bool) StringArray {
    const arena_ptr = arena.arena();

    var err: c_api.Error = c_api.ERROR_INIT;
    const result = c_api.nvim_buf_get_lines(
        c_api.LUA_INTERNAL_CALL,
        buffer,
        start,
        end,
        strict_indexing,
        arena_ptr,
        null,
        &err,
    );

    if (err.type != c_api.kErrorTypeNone) {
        std.debug.print("nvim_buf_get_lines error: type={s}\n", .{err.msg});
    }
    return StringArray.init(result);
}

/// Creates a new namespace, or gets an existing one
/// @param name Name of the namespace
/// @return Namespace id
pub fn nvim_create_namespace(name: []const u8) i64 {
    var err: c_api.Error = c_api.ERROR_INIT;
    const ns_id = c_api.nvim_create_namespace(name.ptr, &err);
    if (err.type != c_api.kErrorTypeNone) {
        std.debug.print("nvim_create_namespace error: type={}\n", .{err.type});
    }
    return ns_id;
}

/// Clear a namespace in a buffer
/// @param buffer Buffer handle, or 0 for current buffer
/// @param ns_id Namespace to clear, or -1 to clear all namespaces
/// @param line_start Start of range of lines to clear (inclusive)
/// @param line_end End of range of lines to clear (exclusive)
pub fn nvim_buf_clear_namespace(buffer: i32, ns_id: i64, line_start: i64, line_end: i64) void {
    var err: c_api.Error = c_api.ERROR_INIT;
    c_api.nvim_buf_clear_namespace(buffer, ns_id, line_start, line_end, &err);
    if (err.type != c_api.kErrorTypeNone) {
        std.debug.print("nvim_buf_clear_namespace error: type={}\n", .{err.type});
    }
}

/// Delete an extmark
/// @param buffer Buffer handle, or 0 for current buffer
/// @param ns_id Namespace id from nvim_create_namespace()
/// @param id Extmark id
/// @return true if the extmark was found and deleted
pub fn nvim_buf_del_extmark(buffer: i32, ns_id: i64, id: i64) bool {
    var err: c_api.Error = c_api.ERROR_INIT;
    const result = c_api.nvim_buf_del_extmark(buffer, ns_id, id, &err);
    if (err.type != c_api.kErrorTypeNone) {
        std.debug.print("nvim_buf_del_extmark error: type={}\n", .{err.type});
    }
    return result;
}
