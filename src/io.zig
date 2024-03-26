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
    try editor.writer.writeAll("\x1B[2J");
    try editor.writer.writeAll("\x1B[H");

    try drawRows(editor);

    try editor.writer.writeAll("\x1B[H");
}

fn drawRows(editor: *Editor) !void {
    for (0..editor.screen.ws_row) |row| {
        try editor.writer.writeByte('~');
        if (row < editor.screen.ws_row - 1) {
            try editor.writer.writeAll("\r\n");
        }
    }
}
