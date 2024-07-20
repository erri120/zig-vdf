const std = @import("std");
const lib = @import("./parser.zig");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    if (!args.skip()) {
        std.log.err("Unable to skip first argument!", .{});
        return;
    }

    const filePath = args.next();
    if (filePath == null) {
        std.log.err("Missing file path", .{});
        return;
    }

    const file = try std.fs.openFileAbsolute(filePath.?, .{ .mode = .read_only, .lock = .exclusive });
    defer file.close();

    const bytes = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(bytes);

    var parser = lib.Parser.init(allocator, bytes, null);
    const object = try parser.parse();

    const json = try std.json.stringifyAlloc(allocator, object, .{ .whitespace = .indent_4 });
    defer allocator.free(json);

    var stdOut = std.io.getStdOut();
    defer stdOut.close();

    _ = try stdOut.write(json);
}
