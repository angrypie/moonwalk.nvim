const shadow = @import("./shadow.zig");

pub export fn get_number() i64 {
    // Returns the LLM request duration in ms, or -1 on failure.
    return shadow.make_suggestions();
}

pub export fn setup_shadow(config_json: [*:0]const u8) i32 {
    // Init-only runtime config entrypoint consumed from Lua.
    return shadow.shadow_setup(config_json);
}

pub export fn apply_patch() i64 {
    // Returns the LLM request duration in ms, or -1 on failure.
    // Uses OpenAI Responses API with apply_patch tool for structured diffs.
    return shadow.make_suggestions_patch();
}

pub export fn process_array(arr: [*]const u32, len: usize) u32 {
    if (len == 0) {
        return 0;
    }
    return arr[len - 1];
}
