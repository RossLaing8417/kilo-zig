const std = @import("std");

const terminal = @import("terminal.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);

    var allocator = gpa.allocator();
    _ = allocator;

    try terminal.enableRawMode();
    defer terminal.disableRawMode();

    var stdin = std.io.getStdIn().reader();
    while (true) {
        const byte = try stdin.readByte();
        if (std.ascii.isControl(byte)) {
            std.debug.print("{d}\r\n", .{byte});
        } else {
            std.debug.print("{d} ('{c}')\r\n", .{ byte, byte });
        }

        if (byte == 'q') {
            break;
        }
    }
}
