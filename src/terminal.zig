const std = @import("std");

var orig_termios: std.os.termios = undefined;

pub fn enableRawMode() !void {
    orig_termios = try std.os.tcgetattr(std.os.STDIN_FILENO);
    var raw = orig_termios;

    raw.iflag &= ~(std.os.system.BRKINT | std.os.system.ICRNL | std.os.system.INPCK | std.os.system.ISTRIP | std.os.system.IXON);
    raw.oflag &= ~(std.os.system.OPOST);
    raw.cflag &= ~(std.os.system.CS8);
    raw.lflag &= ~(std.os.system.ECHO | std.os.system.ICANON | std.os.system.IEXTEN | std.os.system.ISIG);

    // raw.cc[std.os.system.VMIN] = 0;
    // raw.cc[std.os.system.VTIME] = 1;

    try std.os.tcsetattr(std.os.STDIN_FILENO, std.os.system.TCSA.FLUSH, raw);
}

pub fn disableRawMode() void {
    std.os.tcsetattr(std.os.STDIN_FILENO, std.os.system.TCSA.FLUSH, orig_termios) catch |err| {
        std.debug.panic("Error setting termios back to original state:\n{}\n", .{err});
    };
}
