const std = @import("std");

const Editor = @import("editor.zig");
const terminal = @import("terminal.zig");

pub fn ctrlKey(key: u8) u8 {
    return key & 0x1F;
}

pub fn processKeypress(editor: *Editor) !bool {
    const key = try terminal.readKey(editor.reader);

    switch (key) {
        ctrlKey('q') => return false,
        else => {},
    }

    return true;
}

pub fn refreshScreen(editor: *Editor) !void {
    try editor.writer.writeAll("\x1b[?25l");
    try editor.writer.writeAll("\x1B[H");

    try drawRows(editor);

    try editor.writer.writeAll("\x1B[H");
    try editor.writer.writeAll("\x1b[?25h");
}

fn drawRows(editor: *Editor) !void {
    var writer = editor.writer;

    for (0..editor.screen.ws_row) |row| {
        try writer.writeAll("\x1B[K");

        if (row == editor.screen.ws_row / 3) {
            const message = "Kilo editor -- version " ++ Editor.VERSION;
            const length = @min(message.len, editor.screen.ws_col);
            const padding = (editor.screen.ws_col - length) / 2;

            if (padding > 0) {
                try writer.writeByte('~');
            }

            try writer.writeByteNTimes(' ', if (padding > 0) padding - 1 else padding);
            try writer.writeAll(message[0..length]);
        } else {
            try writer.writeByte('~');
        }

        if (row < editor.screen.ws_row - 1) {
            try editor.writer.writeAll("\r\n");
        }
    }
}
