const std = @import("std");

const Editor = @import("editor.zig");

const keyFromEnum = Editor.Key.intFromEnum;

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

pub fn readKey(reader: Editor.Reader) !u32 {
    while (true) {
        const key = reader.readByte() catch |err| switch (err) {
            error.WouldBlock,
            error.EndOfStream,
            => return '0',
            else => return err,
        };

        if (key == '\x1B') {
            const bytes = try reader.readBoundedBytes(3);

            switch (bytes.get(0)) {
                '[' => switch (bytes.get(1)) {
                    'A' => return keyFromEnum(.ARROW_UP),
                    'B' => return keyFromEnum(.ARROW_DOWN),
                    'C' => return keyFromEnum(.ARROW_RIGHT),
                    'D' => return keyFromEnum(.ARROW_LEFT),
                    '0'...'9' => if (bytes.get(2) == '~') switch (bytes.get(1)) {
                        '3' => return keyFromEnum(.DELETE),

                        '1', '7' => return keyFromEnum(.HOME),
                        '4', '8' => return keyFromEnum(.END),

                        '5' => return keyFromEnum(.PAGE_UP),
                        '6' => return keyFromEnum(.PAGE_DOWN),
                        else => {},
                    },
                    else => {},
                },
                'O' => switch (bytes.get(1)) {
                    'H' => return keyFromEnum(.HOME),
                    'F' => return keyFromEnum(.END),
                    else => {},
                },
                else => {},
            }
        }

        return key;
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

pub fn render(writer: Editor.Writer, buffer: []const u8) !void {
    for (buffer) |byte| {
        switch (byte) {
            '\t' => try writer.writeByteNTimes(' ', Editor.TAB_STOP),
            else => try writer.writeByte(byte),
        }
    }
}
