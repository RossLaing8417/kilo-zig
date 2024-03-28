const std = @import("std");

const Editor = @import("editor.zig");
const terminal = @import("terminal.zig");
const io = @import("io.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);

    var allocator = gpa.allocator();

    var out_stream = std.io.bufferedWriter(std.io.getStdOut().writer());
    defer out_stream.flush() catch {};

    var editor = try Editor.init(
        allocator,
        std.io.getStdIn().reader(),
        out_stream.writer(),
        try terminal.enableRawMode(),
        try terminal.getWindowSize(),
    );
    defer editor.deinit();

    var args = std.process.args();
    var filename: ?[]const u8 = null;
    if (args.skip()) {
        filename = args.next();
    }

    if (filename) |fname| {
        try editor.openFile(fname);
    }

    defer terminal.disableRawMode(editor.orig_termios) catch |err| {
        std.debug.panic("Error setting termios back to original state:\r\n{}\r\n", .{err});
    };

    defer io.refreshScreen(&editor) catch |err| {
        std.debug.panic("Error refreshing screen:\r\n{}\r\n", .{err});
    };

    try editor.setMessage("HELP: Ctrl-s = save | Ctrl-q = quit", .{});

    while (try io.processKeypress(&editor)) {
        try io.refreshScreen(&editor);
        try out_stream.flush();
    }
}
