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

// ── V4A Diff Application ──────────────────────────────────────────────

pub const DiffChunk = struct {
    orig_index: usize,
    del_lines: std.ArrayList([]const u8),
    ins_lines: std.ArrayList([]const u8),

    pub fn deinit(self: *DiffChunk, allocator: std.mem.Allocator) void {
        for (self.del_lines.items) |l| allocator.free(l);
        self.del_lines.deinit(allocator);
        for (self.ins_lines.items) |l| allocator.free(l);
        self.ins_lines.deinit(allocator);
    }
};

pub const ParsedDiff = struct {
    chunks: std.ArrayList(DiffChunk),

    pub fn deinit(self: *ParsedDiff, allocator: std.mem.Allocator) void {
        for (self.chunks.items) |*c| {
            @constCast(c).deinit(allocator);
        }
        self.chunks.deinit(allocator);
    }
};

/// Apply a V4A diff to `input`, returning the patched text.
/// For create mode pass `is_create = true` and an empty input.
pub fn applyV4ADiff(allocator: std.mem.Allocator, input: []const u8, diff: []const u8, is_create: bool) ![]u8 {
    const norm_diff = try normalizeNewlines(allocator, diff);
    defer allocator.free(norm_diff);

    var diff_lines_list = std.ArrayList([]const u8).empty;
    defer diff_lines_list.deinit(allocator);
    {
        var sp = std.mem.splitScalar(u8, norm_diff, '\n');
        while (sp.next()) |l| try diff_lines_list.append(allocator, l);
        // drop trailing empty element (like Python pop)
        if (diff_lines_list.items.len > 0 and diff_lines_list.items[diff_lines_list.items.len - 1].len == 0) {
            _ = diff_lines_list.pop();
        }
    }
    const diff_lines = diff_lines_list.items;

    if (is_create) {
        return parseCreateDiff(allocator, diff_lines);
    }

    const norm_input = try normalizeNewlines(allocator, input);
    defer allocator.free(norm_input);

    var input_lines_list = std.ArrayList([]const u8).empty;
    defer input_lines_list.deinit(allocator);
    {
        var sp = std.mem.splitScalar(u8, norm_input, '\n');
        while (sp.next()) |l| try input_lines_list.append(allocator, l);
    }
    const input_lines = input_lines_list.items;

    var parsed = try parseUpdateDiff(allocator, diff_lines, input_lines);
    defer parsed.deinit(allocator);

    return applyChunks(allocator, input_lines, parsed.chunks.items);
}

fn parseCreateDiff(allocator: std.mem.Allocator, diff_lines: []const []const u8) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    var first = true;
    for (diff_lines) |line| {
        if (std.mem.startsWith(u8, line, "*** ")) break;
        if (!std.mem.startsWith(u8, line, "+")) return error.InvalidDiff;
        if (!first) try out.append(allocator, '\n');
        try out.appendSlice(allocator, line[1..]);
        first = false;
    }
    return out.toOwnedSlice(allocator);
}

const SectionResult = struct {
    context: std.ArrayList([]const u8),
    section_chunks: std.ArrayList(DiffChunk),
    end_index: usize,

    fn deinit(self: *SectionResult, allocator: std.mem.Allocator) void {
        self.context.deinit(allocator);
        for (self.section_chunks.items) |*c| @constCast(c).deinit(allocator);
        self.section_chunks.deinit(allocator);
    }
};

const DiffLineMode = enum { keep, add, delete };

fn readSection(allocator: std.mem.Allocator, diff_lines: []const []const u8, start_index: usize) !SectionResult {
    var context = std.ArrayList([]const u8).empty;
    errdefer context.deinit(allocator);
    var del_lines = std.ArrayList([]const u8).empty;
    defer {
        for (del_lines.items) |l| allocator.free(l);
        del_lines.deinit(allocator);
    }
    var ins_lines = std.ArrayList([]const u8).empty;
    defer {
        for (ins_lines.items) |l| allocator.free(l);
        ins_lines.deinit(allocator);
    }
    var section_chunks = std.ArrayList(DiffChunk).empty;
    errdefer {
        for (section_chunks.items) |*c| @constCast(c).deinit(allocator);
        section_chunks.deinit(allocator);
    }
    var last_mode: DiffLineMode = .keep;
    var idx = start_index;

    while (idx < diff_lines.len) {
        const raw = diff_lines[idx];
        if (std.mem.startsWith(u8, raw, "@@") or std.mem.startsWith(u8, raw, "*** ")) break;

        idx += 1;
        const prev_mode = last_mode;
        const effective: []const u8 = if (raw.len == 0) " " else raw;
        const prefix = effective[0];
        const content = effective[1..];

        const mode: DiffLineMode = switch (prefix) {
            '+' => .add,
            '-' => .delete,
            ' ' => .keep,
            else => return error.InvalidDiff,
        };

        // Switching back to context -> flush pending chunk
        const switching_to_context = (mode == .keep and prev_mode != .keep);
        if (switching_to_context and (del_lines.items.len > 0 or ins_lines.items.len > 0)) {
            try section_chunks.append(allocator, .{
                .orig_index = context.items.len - del_lines.items.len,
                .del_lines = try cloneStringList(allocator, del_lines.items),
                .ins_lines = try cloneStringList(allocator, ins_lines.items),
            });
            for (del_lines.items) |l| allocator.free(l);
            del_lines.clearRetainingCapacity();
            for (ins_lines.items) |l| allocator.free(l);
            ins_lines.clearRetainingCapacity();
        }

        if (mode == .delete) {
            try del_lines.append(allocator, try allocator.dupe(u8, content));
            try context.append(allocator, content); // points into diff_lines (stable)
        } else if (mode == .add) {
            try ins_lines.append(allocator, try allocator.dupe(u8, content));
        } else {
            try context.append(allocator, content);
        }
        last_mode = mode;
    }

    // Flush remaining
    if (del_lines.items.len > 0 or ins_lines.items.len > 0) {
        try section_chunks.append(allocator, .{
            .orig_index = context.items.len - del_lines.items.len,
            .del_lines = try cloneStringList(allocator, del_lines.items),
            .ins_lines = try cloneStringList(allocator, ins_lines.items),
        });
        for (del_lines.items) |l| allocator.free(l);
        del_lines.clearRetainingCapacity();
        for (ins_lines.items) |l| allocator.free(l);
        ins_lines.clearRetainingCapacity();
    }

    return .{ .context = context, .section_chunks = section_chunks, .end_index = idx };
}

fn parseUpdateDiff(allocator: std.mem.Allocator, diff_lines: []const []const u8, input_lines: []const []const u8) !ParsedDiff {
    var chunks = std.ArrayList(DiffChunk).empty;
    errdefer {
        for (chunks.items) |*c| @constCast(c).deinit(allocator);
        chunks.deinit(allocator);
    }
    var cursor: usize = 0;
    var idx: usize = 0;

    while (idx < diff_lines.len) {
        const raw = diff_lines[idx];
        // Stop at section terminators
        if (std.mem.startsWith(u8, raw, "*** ")) break;

        // Read @@ anchor
        var anchor: []const u8 = "";
        if (std.mem.startsWith(u8, raw, "@@ ")) {
            anchor = raw[3..];
            idx += 1;
        } else if (std.mem.eql(u8, raw, "@@")) {
            idx += 1;
        } else if (cursor != 0) {
            return error.InvalidDiff;
        }
        // else: first section may omit @@

        if (std.mem.trim(u8, anchor, " ").len > 0) {
            cursor = advanceCursorToAnchor(anchor, input_lines, cursor);
        }

        var section = try readSection(allocator, diff_lines, idx);
        defer section.deinit(allocator);

        // Find where this section's context matches in the input
        const match_pos = findContext(input_lines, section.context.items, cursor) orelse cursor;

        // Add section chunks with absolute orig_index
        for (section.section_chunks.items) |sc| {
            try chunks.append(allocator, .{
                .orig_index = sc.orig_index + match_pos,
                .del_lines = try cloneStringList(allocator, sc.del_lines.items),
                .ins_lines = try cloneStringList(allocator, sc.ins_lines.items),
            });
        }

        cursor = match_pos + section.context.items.len;
        idx = section.end_index;
    }

    return .{ .chunks = chunks };
}

fn advanceCursorToAnchor(anchor: []const u8, input_lines: []const []const u8, start: usize) usize {
    // Exact match first
    for (input_lines[start..], start..) |line, i| {
        if (std.mem.eql(u8, line, anchor)) return i + 1;
    }
    // Stripped match
    const stripped_anchor = std.mem.trim(u8, anchor, " \t");
    for (input_lines[start..], start..) |line, i| {
        if (std.mem.eql(u8, std.mem.trim(u8, line, " \t"), stripped_anchor)) return i + 1;
    }
    return start;
}

fn findContext(input_lines: []const []const u8, context: []const []const u8, start: usize) ?usize {
    if (context.len == 0) return start;
    if (start + context.len > input_lines.len) return null;
    var i = start;
    while (i + context.len <= input_lines.len) : (i += 1) {
        if (sliceEq(input_lines[i .. i + context.len], context)) return i;
    }
    return null;
}

fn sliceEq(a: []const []const u8, b: []const []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |x, y| {
        if (!std.mem.eql(u8, x, y)) return false;
    }
    return true;
}

fn cloneStringList(allocator: std.mem.Allocator, items: []const []const u8) !std.ArrayList([]const u8) {
    var list = std.ArrayList([]const u8).empty;
    errdefer {
        for (list.items) |l| allocator.free(l);
        list.deinit(allocator);
    }
    for (items) |item| {
        try list.append(allocator, try allocator.dupe(u8, item));
    }
    return list;
}

fn applyChunks(allocator: std.mem.Allocator, orig_lines: []const []const u8, chunks: []const DiffChunk) ![]u8 {
    var dest = std.ArrayList([]const u8).empty;
    defer dest.deinit(allocator);
    var cursor: usize = 0;

    for (chunks) |chunk| {
        if (chunk.orig_index > orig_lines.len) return error.InvalidDiff;
        if (cursor > chunk.orig_index) return error.InvalidDiff;
        // Copy unchanged lines before this chunk
        for (orig_lines[cursor..chunk.orig_index]) |l| {
            try dest.append(allocator, l);
        }
        cursor = chunk.orig_index;
        // Insert new lines
        for (chunk.ins_lines.items) |l| {
            try dest.append(allocator, l);
        }
        // Skip deleted lines
        cursor += chunk.del_lines.items.len;
    }
    // Copy remaining
    for (orig_lines[cursor..]) |l| {
        try dest.append(allocator, l);
    }

    // Join with newlines
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    for (dest.items, 0..) |line, i| {
        if (i > 0) try out.append(allocator, '\n');
        try out.appendSlice(allocator, line);
    }
    return out.toOwnedSlice(allocator);
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

test "v4a diff: simple replacement" {
    const allocator = std.testing.allocator;
    const input = "def fib(n):\n    if n <= 1:\n        return n\n    return fib(n-1) + fib(n-2)";
    const diff = "@@\n-def fib(n):\n+def fibonacci(n):\n     if n <= 1:\n         return n\n-    return fib(n-1) + fib(n-2)\n+    return fibonacci(n-1) + fibonacci(n-2)";
    const result = try applyV4ADiff(allocator, input, diff, false);
    defer allocator.free(result);
    try std.testing.expectEqualStrings(
        "def fibonacci(n):\n    if n <= 1:\n        return n\n    return fibonacci(n-1) + fibonacci(n-2)",
        result,
    );
}

test "v4a diff: create mode" {
    const allocator = std.testing.allocator;
    const diff = "+line one\n+line two\n+line three";
    const result = try applyV4ADiff(allocator, "", diff, true);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("line one\nline two\nline three", result);
}

test "v4a diff: addition only" {
    const allocator = std.testing.allocator;
    const input = "a\nb\nc";
    const diff = "@@\n a\n b\n+x\n+y\n c";
    const result = try applyV4ADiff(allocator, input, diff, false);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("a\nb\nx\ny\nc", result);
}

test "v4a diff: deletion only" {
    const allocator = std.testing.allocator;
    const input = "a\nb\nc\nd";
    const diff = "@@\n a\n-b\n-c\n d";
    const result = try applyV4ADiff(allocator, input, diff, false);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("a\nd", result);
}
