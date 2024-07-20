const std = @import("std");

pub const ArrayIterator = struct {
    object: Object,
    index: usize = 0,
    previous: ?usize = null,

    pub fn next(self: *@This()) ?Object {
        defer self.index += 1;
        for (self.object.members.items[self.index..]) |current| {
            return switch (current.value) {
                .object => |object| {
                    var required: usize = 0;
                    if (self.previous) |previousKey| {
                        required = previousKey + 1;
                    }

                    const parsedKey = std.fmt.parseUnsigned(usize, object.key, 0);
                    if (parsedKey) |key| {
                        if (key != required) {
                            return null;
                        }

                        self.previous = key;
                        return object;
                    } else |_| {
                        return null;
                    }
                },
                .string => return null,
            };
        }

        return null;
    }
};

pub const Object = struct {
    key: []const u8,
    members: Members,

    pub fn jsonStringify(self: @This(), jw: anytype) !void {
        try jw.beginObject();
        try jw.objectField(self.key);
        try writeMembers(self.members, jw);
        try jw.endObject();
    }

    pub fn arrayIterator(self: @This()) ArrayIterator {
        return .{ .object = self };
    }
};

fn writeMembers(members: Members, jw: anytype) !void {
    try jw.beginObject();
    for (members.items, 0..) |member, i| {
        var duplicate = false;
        for (members.items[i + 1 ..]) |other| {
            if (!std.mem.eql(u8, member.key, other.key)) {
                continue;
            }

            duplicate = true;
            break;
        }

        if (duplicate) {
            continue;
        }

        try jw.objectField(member.key);
        try jw.write(member.value);
    }
    try jw.endObject();
}

pub const Members = std.ArrayList(KeyValuePair);

pub const ValueTag = enum { object, string };

pub const Value = union(ValueTag) {
    object: Object,
    string: []const u8,

    pub fn jsonStringify(self: @This(), jw: anytype) !void {
        try switch (self) {
            .object => |object| writeMembers(object.members, jw),
            .string => |string| jw.write(string),
        };
    }
};

pub const KeyValuePair = struct {
    key: []const u8,
    value: Value,
};

pub const ParserOptions = struct {
    skip_empty_values: bool = false,
};

pub const Parser = struct {
    allocator: std.mem.Allocator,
    bytes: []const u8,
    pos: usize = 0,
    options: ParserOptions,

    const Self = @This();
    const Error = error{ EndOfFile, UnexpectedByte, ExpectedEoL } || std.mem.Allocator.Error;

    pub fn init(allocator: std.mem.Allocator, bytes: []const u8, options: ?ParserOptions) Self {
        return .{ .allocator = allocator, .bytes = bytes, .options = options orelse ParserOptions{} };
    }

    fn peek(self: *Self) Error!u8 {
        const pos = self.pos;
        if (pos >= self.bytes.len)
            return error.EndOfFile;
        return self.bytes[pos];
    }

    fn advance(self: *Self) void {
        self.pos += 1;
    }

    fn read(self: *Self) Error!u8 {
        const byte = try self.peek();
        self.advance();
        return byte;
    }

    fn expect(self: *Self, expected: u8) Error!void {
        const byte = try self.read();
        if (byte != expected) {
            // std.debug.print("expected '{c}' but found '{c}'\n", .{ expected, byte });
            return error.UnexpectedByte;
        }
    }

    fn expectEoL(self: *Self) Error!void {
        var byte = try self.read();
        if (byte != '\r' and byte != '\n') {
            return error.ExpectedEoL;
        }

        if (byte == '\n') {
            return;
        }

        byte = try self.read();
        if (byte != '\n') {
            return error.ExpectedEoL;
        }
    }

    fn expectNesting(self: *Self, depth: u16) Error!void {
        // std.debug.print("depth={d}\n", .{depth});
        if (depth == 0) return;
        var i: usize = 0;
        while (i != depth) {
            i += 1;
            try self.expect('\t');
        }
    }

    fn expectOpen(self: *Self, depth: u16) Error!void {
        try self.expectNesting(depth);
        try self.expect('{');
        try self.expectEoL();
    }

    fn expectClose(self: *Self, depth: u16) Error!void {
        try self.expectNesting(depth);
        try self.expect('}');
        try self.expectEoL();
    }

    fn parseString(self: *Self) Error![]const u8 {
        try self.expect('"');

        const start = self.pos;
        var previous: u8 = 0;
        while (self.read()) |value| {
            if (value != '"' or previous == '\\') {
                previous = value;
                continue;
            }

            const end = self.pos - 1;
            const string = self.bytes[start..end];

            // std.debug.print("{s}\n", .{string});
            return string;
        } else |err| {
            return err;
        }
    }

    fn parseKeyValuePair(self: *Self, depth: u16) Error!?KeyValuePair {
        try self.expectNesting(depth);

        const key = try self.parseString();

        const peeked = try self.peek();
        if (peeked == '\t') {
            try self.expect('\t');
            try self.expect('\t');

            const string = try self.parseString();
            try self.expectEoL();

            if (string.len == 0 and self.options.skip_empty_values) {
                return null;
            }

            return .{ .key = key, .value = Value{ .string = string } };
        }

        try self.expectEoL();

        const members = try self.parseObjectMembers(depth);
        const object = Object{
            .key = key,
            .members = members,
        };

        return .{ .key = key, .value = Value{ .object = object } };
    }

    fn parseObjectMembers(self: *Self, depth: u16) Error!Members {
        try self.expectOpen(depth);

        var members = Members.init(self.allocator);
        while (true) {
            try self.expectNesting(depth);
            const peeked = try self.peek();
            self.pos -= depth;

            if (peeked == '}') {
                break;
            }

            const pair = try self.parseKeyValuePair(depth + 1);
            if (pair) |actualPair| {
                try members.append(actualPair);
            } else {
                continue;
            }
        }

        try self.expectClose(depth);
        return members;
    }

    fn parseObject(self: *Self, depth: u16) Error!Object {
        try self.expectNesting(depth);
        const key = try self.parseString();

        try self.expectEoL();

        const members = try self.parseObjectMembers(depth);
        const object = Object{
            .key = key,
            .members = members,
        };

        return object;
    }

    pub fn parse(self: *Self) Error!Object {
        return try self.parseObject(0);
    }
};

test "parsing" {
    var testFilesDir = try std.fs.cwd().openDir("test-data", .{});
    defer testFilesDir.close();

    var testFile = try testFilesDir.openFile("libraryfolders.vdf", .{});
    defer testFile.close();

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const bytes = try testFile.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(bytes);

    var parser = Parser.init(allocator, bytes, null);
    const object = try parser.parse();

    const json = try std.json.stringifyAlloc(allocator, object, .{ .whitespace = .indent_4 });
    defer allocator.free(json);

    const expected =
        \\{
        \\    "libraryfolders": {
        \\        "0": {
        \\            "path": "/home/user/.local/share/Steam",
        \\            "label": "",
        \\            "contentid": "4129378406094616110",
        \\            "totalsize": "0",
        \\            "update_clean_bytes_tally": "7739471951",
        \\            "time_last_update_corruption": "0",
        \\            "apps": {
        \\                "228980": "482069544",
        \\                "365670": "1519822497",
        \\                "1391110": "646598402",
        \\                "1493710": "1209309065",
        \\                "1628350": "739531978",
        \\                "1826330": "274110",
        \\                "2348590": "1224814506"
        \\            }
        \\        },
        \\        "1": {
        \\            "path": "/mnt/ssd1/SteamLibrary",
        \\            "label": "",
        \\            "contentid": "1259597520406792897",
        \\            "totalsize": "500106788864",
        \\            "update_clean_bytes_tally": "69020165529",
        \\            "time_last_update_corruption": "0",
        \\            "apps": {
        \\                "2280": "455495300",
        \\                "2300": "520634979",
        \\                "32370": "3603240375",
        \\                "208580": "4809665211",
        \\                "262060": "3984039082",
        \\                "365670": "1276661950",
        \\                "1426210": "48085653354"
        \\            }
        \\        }
        \\    }
        \\}
    ;

    try std.testing.expectEqualStrings(expected, json);

    var buffer = [_]u8{0} ** 10;
    var stream = std.io.fixedBufferStream(&buffer);

    var i: usize = 0;
    var iterator = object.arrayIterator();
    while (iterator.next()) |obj| {
        try std.fmt.format(stream.writer(), "{d}", .{i});
        i += 1;

        try std.testing.expectEqualStrings(stream.getWritten(), obj.key);
        stream.reset();
    }

    try std.testing.expectEqual(2, i);
}
