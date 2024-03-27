const std = @import("std");

const Editor = @import("editor.zig");
const terminal = @import("terminal.zig");

const keyFromEnum = Editor.Key.intFromEnum;

pub fn ctrlKey(key: u32) u32 {
    return key & 0x1F;
}

pub fn processKeypress(editor: *Editor) !bool {
    const key = try terminal.readKey(editor.reader);

    switch (key) {
        ctrlKey('q') => return false,

        keyFromEnum(.ARROW_UP),
        keyFromEnum(.ARROW_DOWN),
        keyFromEnum(.ARROW_LEFT),
        keyFromEnum(.ARROW_RIGHT),
        keyFromEnum(.HOME),
        keyFromEnum(.END),
        keyFromEnum(.PAGE_UP),
        keyFromEnum(.PAGE_DOWN),
        => moveCursor(editor, @enumFromInt(key)),

        else => {},
    }

    return true;
}

pub fn refreshScreen(editor: *Editor) !void {
    editor.scroll();

    try editor.writer.writeAll("\x1B[?25l");
    try editor.writer.writeAll("\x1B[H");

    try drawRows(editor);

    try editor.writer.print("\x1B[{};{}H", .{ editor.cursor.y - editor.row_offset, editor.cursor.x + 1 });

    try editor.writer.writeAll("\x1B[H");
    try editor.writer.writeAll("\x1B[?25h");
}

fn drawRows(editor: *Editor) !void {
    var writer = editor.writer;
    const rows = editor.rows orelse &[_][]u8{};

    for (0..editor.screen.ws_row, editor.row_offset..) |screen_row, file_row| {
        if (rows.len == 0 or file_row >= rows.len) {
            if (rows.len > 0 and screen_row == editor.screen.ws_row / 3) {
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
        } else if (rows.len > 0) {
            try writer.writeAll(rows[file_row][0..@min(rows[file_row].len, editor.screen.ws_col)]);
        }

        if (screen_row == 0) {
            try writer.print(" {d}:{d}", .{ editor.cursor.y, editor.cursor.x });
        }

        try writer.writeAll("\x1B[K");
        if (screen_row < editor.screen.ws_row - 1) {
            try writer.writeAll("\r\n");
        }
    }
}

fn moveCursor(editor: *Editor, key: Editor.Key) void {
    const rows = editor.rows orelse &[_][]u8{};
    switch (key) {
        .ARROW_LEFT => if (editor.cursor.x > 0) {
            editor.cursor.x -= 1;
        },
        .ARROW_DOWN => if (editor.cursor.y < rows.len) {
            editor.cursor.y += 1;
        },
        .ARROW_UP => if (editor.cursor.y > 0) {
            editor.cursor.y -= 1;
        },
        .ARROW_RIGHT => if (editor.cursor.x < editor.screen.ws_col - 1) {
            editor.cursor.x += 1;
        },

        .HOME => editor.cursor.x = 0,
        .END => editor.cursor.x = editor.screen.ws_col - 1,

        .PAGE_UP => editor.cursor.y = 0,
        .PAGE_DOWN => editor.cursor.y = editor.screen.ws_row - 1,

        else => {},
    }
}
