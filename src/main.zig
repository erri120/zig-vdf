const std = @import("std");
const lib = @import("./parser.zig");
const clap = @import("clap");

pub fn main() !void {
    var stdOut = std.io.getStdOut();
    defer stdOut.close();

    const stdErr = std.io.getStdErr();
    defer stdErr.close();

    const params = comptime clap.parseParamsComptime(
        \\-h,   --help                      Display this help and exit.
        \\      --skip-empty-values         Whether to skip empty values.  
        \\      --pretty-print              Whether to pretty print with indendation.
        \\<FILE>...                         Files to parse.
        \\
    );

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const parsers = comptime .{ .FILE = clap.parsers.string };

    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, parsers, .{
        .diagnostic = &diag,
        .allocator = allocator,
    }) catch |err| {
        diag.report(std.io.getStdErr().writer(), err) catch {};
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0) {
        return clap.help(stdErr.writer(), clap.Help, &params, .{});
    }

    if (res.positionals.len == 0) {
        try stdErr.writeAll("Missing files\n");
        return clap.help(stdErr.writer(), clap.Help, &params, .{});
    }

    var options = lib.ParserOptions{};
    options.skip_empty_values = @field(res.args, "skip-empty-values") > 0;

    var stringifyOptions: std.json.StringifyOptions = .{ .whitespace = .minified };

    if (@field(res.args, "pretty-print") > 0) {
        stringifyOptions.whitespace = .indent_4;
    }

    for (res.positionals) |filePath| {
        const file = try std.fs.cwd().openFile(filePath, .{ .mode = .read_only, .lock = .exclusive });
        defer file.close();

        const maxSize: usize = 52_428_800; // 50 MB
        const bytes = try file.readToEndAlloc(allocator, maxSize);
        defer allocator.free(bytes);

        var parser = lib.Parser.init(allocator, bytes, options);
        const object = try parser.parse();

        const json = try std.json.stringifyAlloc(allocator, object, stringifyOptions);
        defer allocator.free(json);

        _ = try stdOut.write(json);
        try stdOut.writeAll("\n");
    }
}
