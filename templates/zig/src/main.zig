const std = @import("std");

// Zig 0.16 hands `main` a `std.process.Init`, which carries the arguments and an `Io` for every
// write. That replaces the old `std.process.args()` and the unparameterised stdout writer.
pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    var args = init.minimal.args.iterate();
    _ = args.skip();
    if (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            try printHelp(stdout);
            try stdout.flush();
            return;
        }
        if (std.mem.eql(u8, arg, "--version") or std.mem.eql(u8, arg, "-V")) {
            try stdout.print("0.1.0\n", .{});
            try stdout.flush();
            return;
        }
        try stdout.print("unknown command: {s}\n", .{arg});
        try stdout.flush();
        std.process.exit(2);
    }

    try printHelp(stdout);
    try stdout.flush();
}

fn printHelp(writer: anytype) !void {
    try writer.print(
        \\{{PROJECT_NAME}}
        \\
        \\Usage:
        \\  {{kebab_name}} [--help] [--version]
        \\
    , .{});
}

test "basic help renders" {
    try std.testing.expect(std.mem.eql(u8, "{{kebab_name}}", "{{kebab_name}}"));
}
