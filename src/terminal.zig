const std = @import("std");

const Editor = @import("editor.zig");

pub fn enableRawMode() !std.os.termios {
    const orig_termios = try std.os.tcgetattr(std.os.STDIN_FILENO);
    var raw = orig_termios;

    raw.iflag &= ~(std.os.system.BRKINT | std.os.system.ICRNL | std.os.system.INPCK | std.os.system.ISTRIP | std.os.system.IXON);
    raw.oflag &= ~(std.os.system.OPOST);
    raw.cflag &= ~(std.os.system.CS8);
    raw.lflag &= ~(std.os.system.ECHO | std.os.system.ICANON | std.os.system.IEXTEN | std.os.system.ISIG);

    raw.cc[std.os.system.V.MIN] = 0;
    raw.cc[std.os.system.V.TIME] = 1;

    try std.os.tcsetattr(std.os.STDIN_FILENO, .FLUSH, raw);

    return orig_termios;
}

pub fn disableRawMode(orig_termios: std.os.termios) !void {
    try std.os.tcsetattr(std.os.STDIN_FILENO, .FLUSH, orig_termios);
}

pub fn readKey(reader: Editor.Reader) !u8 {
    while (true) {
        return reader.readByte() catch |err| switch (err) {
            error.WouldBlock,
            error.EndOfStream,
            => return '0',
            else => return err,
        };
    }
}

pub fn getWindowSize() !Editor.WinSize {
    var size: Editor.WinSize = undefined;
    switch (std.os.errno(std.os.system.ioctl(std.os.STDOUT_FILENO, std.os.system.T.IOCGWINSZ, @intFromPtr(&size)))) {
        .SUCCESS => {},
        else => |err| return std.os.unexpectedErrno(err),
    }
    return size;
}
