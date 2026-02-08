//this is simple implementation of the edit suggestion plugin
//that uses any LLM to generate shadow text suggestions to edit code
const nvim = @import("./nvim_lib.zig");
const std = @import("std");

// Configuration constants
const CONTEXT_LINES_BEFORE = 100; // Get more context for better understanding
const CONTEXT_LINES_AFTER = 100;

// LLM Provider enum
const LLMProvider = enum {
    OpenAI,
    Mistral,
};

// OpenAI API structures
const OpenAIRequest = struct {
    model: []const u8,
    messages: []const Message,
    temperature: f32,
    max_tokens: u32,
    prediction: ?Prediction = null,
};

const Message = struct {
    role: []const u8,
    content: []const u8,
};

const OpenAIResponse = struct {
    choices: []const Choice,
};

const Choice = struct {
    message: Message,
    finish_reason: []const u8,
    index: u32,
};

// Mistral API structures
const MistralRequest = struct {
    model: []const u8,
    messages: []const Message,
    temperature: f32,
    max_tokens: u32,
    prediction: ?Prediction = null,
};

const Prediction = struct {
    type: []const u8,
    content: []const u8,
};

const MistralResponse = struct {
    choices: []const Choice,
};

// Thread-local storage for allocator
threadlocal var tls_allocator: ?std.mem.Allocator = null;

fn get_allocator() std.mem.Allocator {
    if (tls_allocator) |alloc| {
        return alloc;
    }
    // Initialize with page allocator if not set
    tls_allocator = std.heap.page_allocator;
    return std.heap.page_allocator;
}

fn send_to_llm(prompt: []const u8, context: []const u8, provider: LLMProvider, allocator: std.mem.Allocator) ![]const u8 {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    var client = std.http.Client{
        .allocator = arena_allocator,
    };
    defer client.deinit();

    // Get API key and URL based on provider
    const api_key = switch (provider) {
        .OpenAI => std.process.getEnvVarOwned(allocator, "OPENAI_API_KEY") catch {
            nvim.nvim_out_write("Error: OPENAI_API_KEY environment variable not set");
            return error.ApiKeyNotSet;
        },
        .Mistral => std.process.getEnvVarOwned(allocator, "MISTRAL_API_KEY") catch {
            nvim.nvim_out_write("Error: MISTRAL_API_KEY environment variable not set");
            return error.ApiKeyNotSet;
        },
    };
    defer allocator.free(api_key);

    const api_url = switch (provider) {
        .OpenAI => "https://api.openai.com/v1/chat/completions",
        .Mistral => "https://api.mistral.ai/v1/chat/completions",
    };

    // Prepare the request payload
    const messages = [_]Message{
        .{ .role = "system", .content = "You are a code fixing and completion assistant. Analyze the provided code context and suggest fixes or completions for any incomplete, broken, or missing code. Return ONLY the raw code lines, one per line, without any markdown formatting, no ``` blocks, no language identifiers, no line numbers like '1' or '+1', no + prefixes. Just pure code text." },
        .{ .role = "user", .content = prompt },
    };

    // Serialize to JSON based on provider
    const json_payload = switch (provider) {
        .OpenAI => blk: {
            const request_data = OpenAIRequest{
                .model = "gpt-4o", // Use gpt-4o which supports predicted outputs
                .messages = &messages,
                .temperature = 0.2,
                .max_tokens = 2000,
                .prediction = Prediction{
                    .type = "content",
                    .content = context,
                },
            };
            break :blk try std.json.Stringify.valueAlloc(arena_allocator, request_data, .{});
        },
        .Mistral => blk: {
            const request_data = MistralRequest{
                .model = "codestral-latest",
                .messages = &messages,
                .temperature = 0.2,
                .max_tokens = 2000,
                .prediction = Prediction{
                    .type = "content",
                    .content = context,
                },
            };
            break :blk try std.json.Stringify.valueAlloc(arena_allocator, request_data, .{});
        },
    };

    // Prepare headers
    const auth_header = try std.fmt.allocPrint(arena_allocator, "Bearer {s}", .{api_key});
    const headers = [_]std.http.Header{
        .{ .name = "Content-Type", .value = "application/json" },
        .{ .name = "Authorization", .value = auth_header },
    };

    // Make the request
    var response_body: std.Io.Writer.Allocating = .init(arena_allocator);
    defer response_body.deinit();

    const response = client.fetch(.{
        .method = .POST,
        .location = .{ .url = api_url },
        .extra_headers = &headers,
        .payload = json_payload,
        .response_writer = &response_body.writer,
    }) catch {
        return error.HttpRequestFailed;
    };

    if (response.status != .ok) {
        return error.ApiRequestFailed;
    }

    // Parse response (both providers use same response structure)
    const parsed_response = try std.json.parseFromSlice(
        OpenAIResponse,
        arena_allocator,
        response_body.written(),
        .{ .ignore_unknown_fields = true },
    );

    if (parsed_response.value.choices.len > 0) {
        const suggestion = parsed_response.value.choices[0].message.content;
        // Copy to persistent allocator
        const result = try allocator.dupe(u8, suggestion);
        return result;
    }

    return error.NoSuggestion;
}

pub export fn make_suggestions() i64 {
    const allocator = get_allocator();

    const cursor = nvim.nvim_win_get_cursor(0);
    const row = cursor.row - 1; // make cursor row zero indexed

    // Get total number of lines in the buffer
    const total_lines = nvim.nvim_buf_line_count(0);

    // Calculate context window
    const start = if (CONTEXT_LINES_BEFORE > row) 0 else row - CONTEXT_LINES_BEFORE;
    const desired_end = row + CONTEXT_LINES_AFTER + 1;
    const end = if (desired_end > total_lines) total_lines else desired_end;

    // Get lines for context
    const lines = nvim.nvim_buf_get_lines(0, start, end, false);

    // Get file information
    const file_name = nvim.nvim_buf_get_name(0);

    // Build context for LLM
    var context_lines = std.ArrayList(u8).empty;
    defer context_lines.deinit(allocator);

    var line_iterator = lines.iterator();
    var current_line_idx: i64 = 0;
    var cursor_line_idx: i64 = 0; // Track which line in the context has the cursor

    while (line_iterator.next()) |line| {
        const line_num = start + current_line_idx + 1; // 1-indexed for display
        const is_current = (start + current_line_idx) == row;

        if (is_current) {
            cursor_line_idx = current_line_idx;
        }

        context_lines.writer(allocator).print("{d:>4} {s} {s}\n", .{
            line_num,
            if (is_current) ">>>" else "   ",
            line,
        }) catch continue;

        // Add cursor position indicator
        if (is_current) {
            const padding: usize = @intCast(8 + cursor.col); // 8 is prefix length
            context_lines.writer(allocator).writeByteNTimes(' ', padding) catch continue;
            context_lines.writer(allocator).writeByte('^') catch continue;
            context_lines.writer(allocator).writeAll(" <- cursor here") catch continue;
            context_lines.writer(allocator).writeByte('\n') catch continue;
        }

        current_line_idx += 1;
    }

    // Determine which LLM provider to use
    const provider = blk: {
        // Check for LLM_PROVIDER env var first
        if (std.process.getEnvVarOwned(allocator, "LLM_PROVIDER")) |p| {
            defer allocator.free(p);
            if (std.mem.eql(u8, p, "mistral")) {
                break :blk LLMProvider.OpenAI;
            }
        } else |_| {}
        break :blk LLMProvider.Mistral; // Default to Mistral (faster)
    };

    // Prepare the prompt
    const prompt = std.fmt.allocPrint(allocator,
        \\File: {s}
        \\
        \\Analyze this code and fix any issues (syntax errors, incomplete statements, missing brackets, etc).
        \\Return the complete corrected code for the visible area.
        \\Current cursor position is marked with >>> and ^.
        \\
        \\Code to analyze and fix:
        \\{s}
        \\
        \\Return only the fixed code, preserving line numbers and structure.
    , .{ file_name, context_lines.items }) catch return -1;
    defer allocator.free(prompt);

    // Send to LLM and get suggestion
    const api_start = std.time.milliTimestamp();
    const suggestion = send_to_llm(prompt, context_lines.items, provider, allocator) catch {
        nvim.nvim_out_write("Failed to get suggestion from LLM");
        return -1;
    };
    defer allocator.free(suggestion);
    const api_end = std.time.milliTimestamp();
    const api_duration = api_end - api_start;

    // Parse the suggestion to extract just the code lines
    var fixed_lines = std.ArrayList([]const u8).empty;
    defer fixed_lines.deinit(allocator);

    // First, check if the response contains markdown code blocks
    const has_code_blocks = std.mem.indexOf(u8, suggestion, "```") != null;

    var suggestion_lines = std.mem.splitScalar(u8, suggestion, '\n');
    var in_code_block = false;

    while (suggestion_lines.next()) |line| {
        // Check for markdown code block markers
        if (has_code_blocks and line.len >= 3 and std.mem.startsWith(u8, line, "```")) {
            in_code_block = !in_code_block;
            continue; // Skip the ``` line itself
        }

        // If we have code blocks, only process lines inside them
        if (has_code_blocks and !in_code_block) {
            continue;
        }

        // Process the line
        var actual_line = line;

        // Remove line numbers if present (handle "+1", "  1", etc.)
        // if (line.len > 0) {
        //     var i: usize = 0;
        //
        //     // Skip leading spaces
        //     while (i < line.len and line[i] == ' ') : (i += 1) {}
        //
        //     // Check for + followed by digits
        //     if (i < line.len and line[i] == '+') {
        //         i += 1;
        //         const digit_start = i;
        //         while (i < line.len and line[i] >= '0' and line[i] <= '9') : (i += 1) {}
        //
        //         // If we found +digits followed by space, remove this prefix
        //         if (i > digit_start and i < line.len and line[i] == ' ') {
        //             actual_line = line[i + 1 ..];
        //         }
        //     }
        // }

        // Clean trailing \r if present
        const cleaned = if (actual_line.len > 0 and actual_line[actual_line.len - 1] == '\r')
            actual_line[0 .. actual_line.len - 1]
        else
            actual_line;

        // Copy and add the line
        const line_copy = allocator.dupe(u8, cleaned) catch continue;
        fixed_lines.append(allocator, line_copy) catch {
            allocator.free(line_copy);
            continue;
        };
    }
    defer {
        for (fixed_lines.items) |line| {
            allocator.free(line);
        }
    }

    // Replace the entire visible area with the fixed code
    if (fixed_lines.items.len > 0) {
        // Replace the visible area
        nvim.nvim_buf_set_lines(0, start, end, false, fixed_lines.items);
    }

    // Return the API execution time in milliseconds
    return @intCast(api_duration);
}
