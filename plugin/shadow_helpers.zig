const std = @import("std");

pub const Provider = enum {
    openai,
    mistral,
};

pub const ReplacementLines = struct {
    lines: std.ArrayList([]const u8) = .empty,

    pub fn deinit(self: *ReplacementLines, allocator: std.mem.Allocator) void {
        for (self.lines.items) |line| {
            allocator.free(line);
        }
        self.lines.deinit(allocator);
    }
};

pub fn parseProvider(value: []const u8) !Provider {
    const trimmed = std.mem.trim(u8, value, " \t\r\n");
    if (std.ascii.eqlIgnoreCase(trimmed, "openai")) {
        return .openai;
    }
    if (std.ascii.eqlIgnoreCase(trimmed, "mistral")) {
        return .mistral;
    }
    return error.InvalidProvider;
}

pub fn normalizeNewlines(allocator: std.mem.Allocator, raw: []const u8) ![]u8 {
    if (std.mem.indexOfScalar(u8, raw, '\r') == null) {
        return allocator.dupe(u8, raw);
    }

    var builder = std.ArrayList(u8).empty;
    errdefer builder.deinit(allocator);

    for (raw) |ch| {
        if (ch != '\r') {
            try builder.append(allocator, ch);
        }
    }

    return builder.toOwnedSlice(allocator);
}

pub fn extractCodePayload(allocator: std.mem.Allocator, raw_output: []const u8) ![]u8 {
    const normalized = try normalizeNewlines(allocator, raw_output);
    errdefer allocator.free(normalized);

    if (std.mem.indexOf(u8, normalized, "```") == null) {
        return normalized;
    }

    var lines = std.ArrayList([]const u8).empty;
    defer lines.deinit(allocator);

    var split = std.mem.splitScalar(u8, normalized, '\n');
    while (split.next()) |line| {
        try lines.append(allocator, line);
    }

    var first_fence: ?usize = null;
    var second_fence: ?usize = null;

    for (lines.items, 0..) |line, idx| {
        if (!isFenceLine(line)) {
            continue;
        }

        if (first_fence == null) {
            first_fence = idx;
        } else if (second_fence == null) {
            second_fence = idx;
        } else {
            return error.MultipleCodeBlocks;
        }
    }

    if (first_fence == null or second_fence == null) {
        return error.InvalidCodeBlock;
    }

    const start_idx = first_fence.?;
    const end_idx = second_fence.?;

    // In strict mode, any prose outside the only fenced block is rejected.
    for (lines.items[0..start_idx]) |line| {
        if (!isBlankLine(line)) {
            return error.NonCodeTextAroundFence;
        }
    }
    for (lines.items[end_idx + 1 ..]) |line| {
        if (!isBlankLine(line)) {
            return error.NonCodeTextAroundFence;
        }
    }

    var code = std.ArrayList(u8).empty;
    errdefer code.deinit(allocator);

    const fenced_lines = lines.items[start_idx + 1 .. end_idx];
    for (fenced_lines, 0..) |line, idx| {
        try code.appendSlice(allocator, line);
        if (idx + 1 < fenced_lines.len) {
            try code.append(allocator, '\n');
        }
    }

    allocator.free(normalized);
    return code.toOwnedSlice(allocator);
}

pub fn parseReplacementLines(
    allocator: std.mem.Allocator,
    output: []const u8,
    input_line_count: usize,
    max_output_multiplier: usize,
    max_output_lines_min: usize,
) !ReplacementLines {
    const trimmed = trimTrailingNewlines(output);
    if (std.mem.trim(u8, trimmed, " \t\n").len == 0) {
        return error.EmptyOutput;
    }

    if (std.mem.indexOf(u8, trimmed, "```") != null) {
        return error.MarkdownFence;
    }

    if (std.mem.indexOfScalar(u8, trimmed, 0) != null) {
        return error.InvalidOutput;
    }

    const output_line_count = countLines(trimmed);
    if (output_line_count > maxAllowedOutputLines(input_line_count, max_output_multiplier, max_output_lines_min)) {
        return error.TooManyOutputLines;
    }

    var result = ReplacementLines{};
    errdefer result.deinit(allocator);

    var split = std.mem.splitScalar(u8, trimmed, '\n');
    while (split.next()) |line| {
        try result.lines.append(allocator, try allocator.dupe(u8, line));
    }

    if (result.lines.items.len == 0) {
        return error.EmptyOutput;
    }

    return result;
}

fn trimTrailingNewlines(input: []const u8) []const u8 {
    var end = input.len;
    while (end > 0 and input[end - 1] == '\n') {
        end -= 1;
    }
    return input[0..end];
}

fn countLines(input: []const u8) usize {
    if (input.len == 0) {
        return 0;
    }

    var count: usize = 1;
    for (input) |ch| {
        if (ch == '\n') {
            count += 1;
        }
    }
    return count;
}

fn maxAllowedOutputLines(input_line_count: usize, max_output_multiplier: usize, max_output_lines_min: usize) usize {
    const multiplied = std.math.mul(usize, input_line_count, max_output_multiplier) catch std.math.maxInt(usize);
    return @max(max_output_lines_min, multiplied);
}

fn isFenceLine(line: []const u8) bool {
    const trimmed = std.mem.trimLeft(u8, line, " \t");
    return std.mem.startsWith(u8, trimmed, "```");
}

fn isBlankLine(line: []const u8) bool {
    return std.mem.trim(u8, line, " \t").len == 0;
}

test "parse provider values" {
    try std.testing.expectEqual(Provider.openai, try parseProvider("openai"));
    try std.testing.expectEqual(Provider.openai, try parseProvider(" OpenAI "));
    try std.testing.expectEqual(Provider.mistral, try parseProvider("mistral"));
    try std.testing.expectError(error.InvalidProvider, parseProvider("anthropic"));
}

test "extract code from fenced response" {
    const allocator = std.testing.allocator;
    const extracted = try extractCodePayload(
        allocator,
        "```zig\nconst a = 1;\nconst b = 2;\n```",
    );
    defer allocator.free(extracted);

    try std.testing.expectEqualStrings("const a = 1;\nconst b = 2;", extracted);
}

test "reject prose around fenced response" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(
        error.NonCodeTextAroundFence,
        extractCodePayload(allocator, "Here is the fix:\n```\nconst a = 1;\n```"),
    );
}

test "enforce output line bounds" {
    const allocator = std.testing.allocator;

    const too_large = "a\nb\nc\nd\ne";
    try std.testing.expectError(
        error.TooManyOutputLines,
        parseReplacementLines(allocator, too_large, 2, 2, 2),
    );

    var ok = try parseReplacementLines(allocator, "a\nb\nc", 2, 2, 2);
    defer ok.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 3), ok.lines.items.len);
}
