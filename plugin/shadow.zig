const nvim = @import("./nvim_lib.zig");
const helpers = @import("./shadow_helpers.zig");
const std = @import("std");

const SetupStatus = enum(i32) {
    ok = 0,
    invalid_json = 1,
    invalid_config = 2,
    already_initialized = 3,
};

const RuntimeConfig = struct {
    provider_override: ?helpers.Provider = null,
    openai_model: []const u8 = "gpt-4o",
    mistral_model: []const u8 = "codestral-latest",
    temperature: f32 = 0.2,
    max_tokens: u32 = 2000,
    context_before: i64 = 100,
    context_after: i64 = 100,
    timeout_ms: u32 = 30_000,
    max_output_multiplier: usize = 3,
    max_output_lines_min: usize = 200,
    debug: bool = false,
    openai_api_key: ?[]const u8 = null,
    mistral_api_key: ?[]const u8 = null,
};

const ConfigUpdate = struct {
    provider: ?[]const u8 = null,
    openai_model: ?[]const u8 = null,
    mistral_model: ?[]const u8 = null,
    temperature: ?f32 = null,
    max_tokens: ?u32 = null,
    context_before: ?i64 = null,
    context_after: ?i64 = null,
    timeout_ms: ?u32 = null,
    max_output_multiplier: ?usize = null,
    max_output_lines_min: ?usize = null,
    debug: ?bool = null,
    openai_api_key: ?[]const u8 = null,
    mistral_api_key: ?[]const u8 = null,
};

const RequestMessage = struct {
    role: []const u8,
    content: []const u8,
};

const Prediction = struct {
    type: []const u8,
    content: []const u8,
};

const ChatCompletionRequest = struct {
    model: []const u8,
    messages: []const RequestMessage,
    temperature: f32,
    max_tokens: u32,
    prediction: Prediction,
};

const ChatCompletionResponse = struct {
    choices: []const Choice = &.{},
};

const Choice = struct {
    message: ResponseMessage = .{},
};

const ResponseMessage = struct {
    content: []const u8 = "",
};

const TmpDumpMeta = struct {
    provider: ?helpers.Provider = null,
    model: ?[]const u8 = null,
    llm_response_ms: ?i64 = null,
    last_user_message_content: ?[]const u8 = null,
};

const ApiKey = struct {
    bytes: []const u8,
    owned: bool,

    fn deinit(self: ApiKey, allocator: std.mem.Allocator) void {
        if (self.owned) {
            allocator.free(self.bytes);
        }
    }
};

const SYSTEM_PROMPT =
    "You are a code fixing assistant. Return only raw code for the provided visible context. " ++
    "Do not use markdown fences, prose, headers, or explanations.";
const TMP_PROMPT_PATH = "/tmp/moonwalk_prompt.txt";
const TMP_RESPONSE_PATH = "/tmp/moonwalk_response.txt";

var runtime_config = RuntimeConfig{};
var setup_done = false;

pub export fn shadow_setup(config_json: [*:0]const u8) i32 {
    if (setup_done) {
        return @intFromEnum(SetupStatus.already_initialized);
    }

    const allocator = std.heap.page_allocator;
    const json_bytes = std.mem.span(config_json);
    if (std.mem.trim(u8, json_bytes, " \t\r\n").len == 0) {
        setup_done = true;
        return @intFromEnum(SetupStatus.ok);
    }

    var parsed = std.json.parseFromSlice(ConfigUpdate, allocator, json_bytes, .{
        .ignore_unknown_fields = true,
    }) catch return @intFromEnum(SetupStatus.invalid_json);
    defer parsed.deinit();

    applyConfigUpdate(allocator, parsed.value) catch return @intFromEnum(SetupStatus.invalid_config);
    setup_done = true;
    return @intFromEnum(SetupStatus.ok);
}

pub export fn make_suggestions() i64 {
    const allocator = std.heap.page_allocator;

    const cursor = nvim.nvim_win_get_cursor(0);
    const row_zero = cursor.row - 1;
    const total_lines = nvim.nvim_buf_line_count(0);
    if (total_lines <= 0) {
        nvim.nvim_out_write("moonwalk: buffer has no lines to process");
        return -1;
    }

    const start = if (runtime_config.context_before > row_zero) 0 else row_zero - runtime_config.context_before;
    const desired_end = row_zero + runtime_config.context_after + 1;
    const end = if (desired_end > total_lines) total_lines else desired_end;
    debugInfo(
        "moonwalk debug: make_suggestions range=[{d},{d}) cursor=({d},{d}) total_lines={d}",
        .{ start, end, cursor.row, cursor.col, total_lines },
    );

    const context = getBufferSliceText(allocator, start, end) catch {
        nvim.nvim_out_write("moonwalk: failed to collect buffer context");
        return -1;
    };
    defer allocator.free(context);

    const prompt = buildPrompt(allocator, nvim.nvim_buf_get_name(0), cursor.row, cursor.col) catch {
        nvim.nvim_out_write("moonwalk: failed to build request prompt");
        return -1;
    };
    defer allocator.free(prompt);
    const provider = resolveProvider(allocator);
    const model_name = providerModel(provider);
    writeTmpDebugDump(
        TMP_PROMPT_PATH,
        "prompt",
        prompt,
        .{
            .provider = provider,
            .model = model_name,
            .llm_response_ms = null,
            .last_user_message_content = context,
        },
    );
    debugInfo(
        "moonwalk debug: prompt/context bytes prompt={d} context={d}",
        .{ prompt.len, context.len },
    );
    debugInfo("moonwalk debug: provider={s} model={s}", .{ @tagName(provider), model_name });

    const llm_call_start_ms = std.time.milliTimestamp();
    const api_start = std.time.milliTimestamp();
    const raw_output = sendToLlm(allocator, provider, prompt, context) catch |err| {
        debugError("request", err);
        reportFailure(err);
        return -1;
    };
    const llm_response_ms = std.time.milliTimestamp() - llm_call_start_ms;
    defer allocator.free(raw_output);
    writeTmpDebugDump(
        TMP_RESPONSE_PATH,
        "raw_response",
        raw_output,
        .{
            .provider = provider,
            .model = model_name,
            .llm_response_ms = llm_response_ms,
        },
    );
    debugInfo("moonwalk debug: raw_output bytes={d}", .{raw_output.len});

    const extracted_output = helpers.extractCodePayload(allocator, raw_output) catch |err| {
        debugError("extract", err);
        reportFailure(err);
        return -1;
    };
    defer allocator.free(extracted_output);
    debugInfo("moonwalk debug: extracted_output bytes={d}", .{extracted_output.len});

    var replacement = helpers.parseReplacementLines(
        allocator,
        extracted_output,
        @intCast(end - start),
        runtime_config.max_output_multiplier,
        runtime_config.max_output_lines_min,
    ) catch |err| {
        debugError("validate", err);
        reportFailure(err);
        return -1;
    };
    defer replacement.deinit(allocator);
    debugInfo("moonwalk debug: replacement lines={d}", .{replacement.lines.items.len});

    debugInfo("moonwalk debug: applying buffer lines range=[{d},{d})", .{ start, end });
    nvim.nvim_buf_set_lines(0, start, end, false, replacement.lines.items);
    debugInfo("moonwalk debug: restoring cursor after apply", .{});
    restoreCursorAfterApply(cursor.row - 1, cursor.col, start, end, replacement.lines.items.len);

    const api_end = std.time.milliTimestamp();
    return @intCast(api_end - api_start);
}

fn applyConfigUpdate(allocator: std.mem.Allocator, update: ConfigUpdate) !void {
    if (update.provider) |provider_name| {
        runtime_config.provider_override = try helpers.parseProvider(provider_name);
    }

    if (update.openai_model) |model| {
        runtime_config.openai_model = try dupeNonEmptyString(allocator, model);
    }

    if (update.mistral_model) |model| {
        runtime_config.mistral_model = try dupeNonEmptyString(allocator, model);
    }

    if (update.temperature) |temperature| {
        if (temperature < 0 or temperature > 2) {
            return error.InvalidConfig;
        }
        runtime_config.temperature = temperature;
    }

    if (update.max_tokens) |max_tokens| {
        if (max_tokens == 0) {
            return error.InvalidConfig;
        }
        runtime_config.max_tokens = max_tokens;
    }

    if (update.context_before) |before| {
        if (before < 0) {
            return error.InvalidConfig;
        }
        runtime_config.context_before = before;
    }

    if (update.context_after) |after| {
        if (after < 0) {
            return error.InvalidConfig;
        }
        runtime_config.context_after = after;
    }

    if (update.timeout_ms) |timeout_ms| {
        if (timeout_ms == 0) {
            return error.InvalidConfig;
        }
        runtime_config.timeout_ms = timeout_ms;
    }

    if (update.max_output_multiplier) |multiplier| {
        if (multiplier == 0) {
            return error.InvalidConfig;
        }
        runtime_config.max_output_multiplier = multiplier;
    }

    if (update.max_output_lines_min) |min_lines| {
        if (min_lines == 0) {
            return error.InvalidConfig;
        }
        runtime_config.max_output_lines_min = min_lines;
    }

    if (update.debug) |debug| {
        runtime_config.debug = debug;
    }

    if (update.openai_api_key) |key| {
        runtime_config.openai_api_key = try dupeNonEmptyString(allocator, key);
    }

    if (update.mistral_api_key) |key| {
        runtime_config.mistral_api_key = try dupeNonEmptyString(allocator, key);
    }
}

fn dupeNonEmptyString(allocator: std.mem.Allocator, value: []const u8) ![]const u8 {
    if (std.mem.trim(u8, value, " \t\r\n").len == 0) {
        return error.InvalidConfig;
    }
    return allocator.dupe(u8, value);
}

fn resolveProvider(allocator: std.mem.Allocator) helpers.Provider {
    if (runtime_config.provider_override) |provider| {
        return provider;
    }

    const env_value = std.process.getEnvVarOwned(allocator, "LLM_PROVIDER") catch return .mistral;
    defer allocator.free(env_value);

    return helpers.parseProvider(env_value) catch .mistral;
}

fn resolveApiKey(allocator: std.mem.Allocator, provider: helpers.Provider) !ApiKey {
    switch (provider) {
        .openai => {
            if (runtime_config.openai_api_key) |key| {
                return .{ .bytes = key, .owned = false };
            }
            const env_key = try std.process.getEnvVarOwned(allocator, "OPENAI_API_KEY");
            return .{ .bytes = env_key, .owned = true };
        },
        .mistral => {
            if (runtime_config.mistral_api_key) |key| {
                return .{ .bytes = key, .owned = false };
            }
            const env_key = try std.process.getEnvVarOwned(allocator, "MISTRAL_API_KEY");
            return .{ .bytes = env_key, .owned = true };
        },
    }
}

fn providerUrl(provider: helpers.Provider) []const u8 {
    return switch (provider) {
        .openai => "https://api.openai.com/v1/chat/completions",
        .mistral => "https://api.mistral.ai/v1/chat/completions",
    };
}

fn providerModel(provider: helpers.Provider) []const u8 {
    return switch (provider) {
        .openai => runtime_config.openai_model,
        .mistral => runtime_config.mistral_model,
    };
}

fn buildPrompt(allocator: std.mem.Allocator, file_name: []const u8, cursor_row_one: i64, cursor_col: i64) ![]u8 {
    return std.fmt.allocPrint(
        allocator,
        \\File: {s}
        \\Cursor row (1-based): {d}
        \\Cursor col (0-based): {d}
        \\Task: Fix syntax errors or incomplete code in the visible context.
        \\Return only code for the full visible context.
    ,
        .{ file_name, cursor_row_one, cursor_col },
    );
}

fn getBufferSliceText(allocator: std.mem.Allocator, start: i64, end: i64) ![]u8 {
    const lines = nvim.nvim_buf_get_lines(0, start, end, false);
    var builder = std.ArrayList(u8).empty;
    errdefer builder.deinit(allocator);

    var iter = lines.iterator();
    var first_line = true;
    while (iter.next()) |line| {
        if (!first_line) {
            try builder.append(allocator, '\n');
        }
        try builder.appendSlice(allocator, line);
        first_line = false;
    }

    return builder.toOwnedSlice(allocator);
}

fn sendToLlm(
    allocator: std.mem.Allocator,
    provider: helpers.Provider,
    prompt: []const u8,
    context: []const u8,
) ![]const u8 {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    var client = std.http.Client{ .allocator = arena_allocator };
    defer client.deinit();

    const api_key = resolveApiKey(allocator, provider) catch return error.ApiKeyNotSet;
    defer api_key.deinit(allocator);

    const messages = [_]RequestMessage{
        .{ .role = "system", .content = SYSTEM_PROMPT },
        .{ .role = "user", .content = prompt },
        // Keep prediction content identical to the last chat message content.
        .{ .role = "user", .content = context },
    };

    const request_payload = ChatCompletionRequest{
        .model = providerModel(provider),
        .messages = &messages,
        .temperature = runtime_config.temperature,
        .max_tokens = runtime_config.max_tokens,
        .prediction = .{
            .type = "content",
            .content = context,
        },
    };

    const json_payload = try std.json.Stringify.valueAlloc(arena_allocator, request_payload, .{});
    const auth_header = try std.fmt.allocPrint(arena_allocator, "Bearer {s}", .{api_key.bytes});

    const headers = [_]std.http.Header{
        .{ .name = "Content-Type", .value = "application/json" },
        .{ .name = "Authorization", .value = auth_header },
    };

    var response_body: std.Io.Writer.Allocating = .init(arena_allocator);
    defer response_body.deinit();

    const llm_start_ms = std.time.milliTimestamp();
    const response = client.fetch(.{
        .method = .POST,
        .location = .{ .url = providerUrl(provider) },
        .extra_headers = &headers,
        .payload = json_payload,
        .response_writer = &response_body.writer,
    }) catch {
        return error.HttpRequestFailed;
    };
    const llm_end_ms = std.time.milliTimestamp();
    const llm_duration_ms = llm_end_ms - llm_start_ms;

    const status_code: u16 = @intFromEnum(response.status);
    debugInfo(
        "moonwalk debug: provider={s} model={s} http_status={d} llm_response_ms={d} timeout_ms={d} payload_bytes={d}",
        .{ @tagName(provider), providerModel(provider), status_code, llm_duration_ms, runtime_config.timeout_ms, json_payload.len },
    );
    if (status_code < 200 or status_code >= 300) {
        if (runtime_config.debug) {
            const details = std.fmt.allocPrint(
                allocator,
                "moonwalk debug: provider status {d}, body: {s}",
                .{ status_code, response_body.written() },
            ) catch {
                return error.ApiRequestFailed;
            };
            defer allocator.free(details);
            nvim.nvim_out_write(details);
        }
        return error.ApiRequestFailed;
    }

    var parsed = try std.json.parseFromSlice(ChatCompletionResponse, arena_allocator, response_body.written(), .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();

    if (parsed.value.choices.len == 0) {
        return error.NoSuggestion;
    }

    const suggestion = parsed.value.choices[0].message.content;
    if (suggestion.len == 0) {
        return error.NoSuggestion;
    }

    return allocator.dupe(u8, suggestion);
}

fn restoreCursorAfterApply(
    original_row_zero: i64,
    original_col: i64,
    start: i64,
    end: i64,
    replacement_line_count: usize,
) void {
    const replaced_line_count = end - start;
    const replacement_count_i64: i64 = @intCast(replacement_line_count);

    var new_row_zero = original_row_zero;

    if (original_row_zero >= start and original_row_zero < end) {
        // Keep relative position when cursor was inside the replaced region.
        const relative_row = original_row_zero - start;
        if (replacement_count_i64 == 0) {
            new_row_zero = start;
        } else {
            new_row_zero = start + @min(relative_row, replacement_count_i64 - 1);
        }
    } else if (original_row_zero >= end) {
        const row_delta = replacement_count_i64 - replaced_line_count;
        new_row_zero = original_row_zero + row_delta;
    }

    const total_after = nvim.nvim_buf_line_count(0);
    if (total_after <= 0) {
        return;
    }

    new_row_zero = clampI64(new_row_zero, 0, total_after - 1);

    const current_line = nvim.nvim_buf_get_lines(0, new_row_zero, new_row_zero + 1, false);
    var iter = current_line.iterator();
    var max_col: i64 = 0;
    if (iter.next()) |line| {
        max_col = @intCast(line.len);
    }

    const clamped_col = clampI64(original_col, 0, max_col);
    debugInfo(
        "moonwalk debug: cursor restore old=({d},{d}) new=({d},{d}) line_max_col={d}",
        .{ original_row_zero + 1, original_col, new_row_zero + 1, clamped_col, max_col },
    );
    nvim.nvim_win_set_cursor(0, new_row_zero + 1, clamped_col);
}

fn clampI64(value: i64, min_value: i64, max_value: i64) i64 {
    if (value < min_value) {
        return min_value;
    }
    if (value > max_value) {
        return max_value;
    }
    return value;
}

fn reportFailure(err: anyerror) void {
    const message = switch (err) {
        error.ApiKeyNotSet => "moonwalk: missing API key for selected provider",
        error.NoSuggestion => "moonwalk: provider returned empty suggestion",
        error.HttpRequestFailed, error.ApiRequestFailed => "moonwalk: request to provider failed",
        error.InvalidCodeBlock, error.MultipleCodeBlocks, error.NonCodeTextAroundFence, error.MarkdownFence => "moonwalk: rejected output (non-code markdown response)",
        error.InvalidOutput, error.EmptyOutput, error.TooManyOutputLines => "moonwalk: rejected output (failed safety checks)",
        else => "moonwalk: suggestion failed",
    };

    nvim.nvim_out_write(message);
}

fn debugError(stage: []const u8, err: anyerror) void {
    if (!isDebugEnabled()) {
        return;
    }

    const allocator = std.heap.page_allocator;
    const message = std.fmt.allocPrint(allocator, "moonwalk debug [{s}]: {s}", .{ stage, @errorName(err) }) catch return;
    defer allocator.free(message);

    nvim.nvim_out_write(message);
}

fn debugInfo(comptime fmt: []const u8, args: anytype) void {
    if (!isDebugEnabled()) {
        return;
    }

    const allocator = std.heap.page_allocator;
    const message = std.fmt.allocPrint(allocator, fmt, args) catch return;
    defer allocator.free(message);
    nvim.nvim_out_write(message);
}

fn writeTmpDebugDump(path: []const u8, label: []const u8, payload: []const u8, meta: TmpDumpMeta) void {
    // Keep fixed paths so it's easy to inspect the latest prompt/response quickly.
    const allocator = std.heap.page_allocator;
    const provider_name = if (meta.provider) |provider| @tagName(provider) else "unknown";
    const model_name = meta.model orelse "unknown";
    const llm_response_ms = meta.llm_response_ms orelse -1;
    const body = if (meta.last_user_message_content) |last_user_message| blk: {
        // When present, record the exact code sent in the final user message and prediction.
        break :blk std.fmt.allocPrint(
            allocator,
            "timestamp_ms={d}\nlabel={s}\nprovider={s}\nmodel={s}\nllm_response_ms={d}\n" ++
                "instruction_bytes={d}\n---instruction---\n{s}\n" ++
                "last_user_message_bytes={d}\n---last_user_message---\n{s}\n" ++
                "prediction_content_bytes={d}\n---prediction_content---\n{s}\n",
            .{
                std.time.milliTimestamp(),
                label,
                provider_name,
                model_name,
                llm_response_ms,
                payload.len,
                payload,
                last_user_message.len,
                last_user_message,
                last_user_message.len,
                last_user_message,
            },
        ) catch return;
    } else std.fmt.allocPrint(
        allocator,
        "timestamp_ms={d}\nlabel={s}\nprovider={s}\nmodel={s}\nllm_response_ms={d}\nbytes={d}\n---\n{s}\n",
        .{ std.time.milliTimestamp(), label, provider_name, model_name, llm_response_ms, payload.len, payload },
    ) catch return;
    defer allocator.free(body);

    const file = std.fs.createFileAbsolute(path, .{}) catch |err| {
        debugError("tmp-write-open", err);
        return;
    };
    defer file.close();

    file.writeAll(body) catch |err| {
        debugError("tmp-write-data", err);
    };
}

fn isDebugEnabled() bool {
    if (runtime_config.debug) {
        return true;
    }

    const allocator = std.heap.page_allocator;
    const raw = std.process.getEnvVarOwned(allocator, "MOONWALK_DEBUG") catch return false;
    defer allocator.free(raw);

    const value = std.mem.trim(u8, raw, " \t\r\n");
    return std.mem.eql(u8, value, "1") or
        std.ascii.eqlIgnoreCase(value, "true") or
        std.ascii.eqlIgnoreCase(value, "yes") or
        std.ascii.eqlIgnoreCase(value, "on");
}
