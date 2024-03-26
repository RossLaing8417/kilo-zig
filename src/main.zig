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

    var editor: Editor = .{
        .allocator = allocator,
        .reader = std.io.getStdIn().reader(),
        .writer = out_stream.writer(),
        .orig_termios = try terminal.enableRawMode(),
        .screen = try terminal.getWindowSize(),
    };

    defer terminal.disableRawMode(editor.orig_termios) catch |err| {
        std.debug.panic("Error setting termios back to original state:\r\n{}\r\n", .{err});
    };

    defer io.refreshScreen(&editor) catch |err| {
        std.debug.panic("Error refreshing screen:\r\n{}\r\n", .{err});
    };

    // var file: std.fs.File = .{
    //     .handle = std.os.STDIN_FILENO,
    //     .capable_io_mode = .evented,
    //     .intended_io_mode = .evented,
    // };
    // var reader = file.reader();

    while (try io.processKeypress(&editor)) {
        try io.refreshScreen(&editor);
        try out_stream.flush();
    }
}
