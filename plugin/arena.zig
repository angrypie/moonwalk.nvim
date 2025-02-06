const std = @import("std");
const api = @import("./api.zig");

pub const Arena = api.Arena;

threadlocal var ARENA: struct {
    initialized: bool = false,
    data: Arena = undefined,
} = .{};

/// Initializes the Arena.
/// This should be called exactly once during the lifetime of the plugin.
/// Panics if already initialized.
pub export fn arena_init() void {
    if (ARENA.initialized) {
        @panic("Arena is already initialized");
    }

    ARENA.data = .{
        .cur_blk = null,
        .pos = 0,
        .size = 0,
    };
    ARENA.initialized = true;
}

/// Returns a pointer to the Arena that can be passed to the C API.
/// Panics if not initialized.
pub export fn arena() [*c]Arena {
    if (!ARENA.initialized) {
        @panic("Arena is not initialized");
    }
    return &ARENA.data;
}
