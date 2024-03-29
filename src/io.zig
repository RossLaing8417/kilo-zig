const std = @import("std");

const Editor = @import("editor.zig");
const terminal = @import("terminal.zig");

const keyFromEnum = Editor.Key.intFromEnum;

var quitting = false;

pub fn ctrlKey(key: u32) u32 {
    return key & 0x1F;
}

pub fn processKeypress(editor: *Editor) !bool {
    const key = try terminal.readKey(editor.reader);

    switch (key) {
        0 => {},
        ctrlKey('q') => {
            if (editor.dirty and !quitting) {
                quitting = true;
                try editor.setMessage("Quit without saving? (y/n)", .{});
            } else {
                return false;
            }
        },
        ctrlKey('s') => editor.saveFile() catch |err| {
            try editor.setMessage("Error saving file: {}", .{err});
        },

        keyFromEnum(.ARROW_UP),
        keyFromEnum(.ARROW_DOWN),
        keyFromEnum(.ARROW_LEFT),
        keyFromEnum(.ARROW_RIGHT),
        keyFromEnum(.HOME),
        keyFromEnum(.END),
        keyFromEnum(.PAGE_UP),
        keyFromEnum(.PAGE_DOWN),
        => moveCursor(editor, @enumFromInt(key)),

        '\r' => try editor.insertNewLine(),

        ctrlKey('h'),
        keyFromEnum(.BACKSPACE),
        keyFromEnum(.DELETE),
        => {
            if (key == keyFromEnum(.DELETE)) {
                moveCursor(editor, .ARROW_RIGHT);
            }
            try editor.deleteChar();
        },

        '\x1B',
        ctrlKey('l'),
        => {},

        else => {
            if (quitting) {
                if (key == 'y') {
                    return false;
                } else if (key == 'n') {
                    quitting = false;
                }
            } else {
                try editor.insertChar(@intCast(key));
            }
        },
    }

    return true;
}

pub fn refreshScreen(editor: *Editor) !void {
    editor.scroll();

    try editor.writer.writeAll("\x1B[?25l");
    try editor.writer.writeAll("\x1B[H");

    try drawRows(editor);
    try drawStatusBar(editor);
    try drawMessage(editor);

    try editor.writer.print("\x1B[{};{}H", .{
        (editor.cursor.y - editor.row_offset) + 1,
        (editor.render.x - editor.col_offset) + 1,
    });

    try editor.writer.writeAll("\x1B[?25h");
}

fn drawRows(editor: *Editor) !void {
    var writer = editor.writer;

    for (0..editor.screen.ws_row, editor.row_offset..) |screen_row, file_row| {
        if (editor.rows.items.len == 0 or file_row >= editor.rows.items.len) {
            if (editor.rows.items.len == 0 and screen_row == editor.screen.ws_row / 3) {
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
        } else if (editor.rows.items.len > 0) {
            const row = editor.rows.items[file_row];
            if (row.items.len > 0 and editor.col_offset < row.items.len) {
                const start = @min(row.items.len - 1, editor.col_offset);
                const end = @min(row.items.len, editor.screen.ws_col);
                try terminal.render(writer, row.items[start..end]);
            }
        }

        try writer.writeAll("\x1B[K");
        try writer.writeAll("\r\n");
    }
}

fn drawStatusBar(editor: *Editor) !void {
    var writer = editor.writer;
    var buffer = try std.BoundedArray(u8, 512).init(0);
    var buf_writer = buffer.writer();

    try writer.writeAll("\x1B[7m");

    // var itr = std.mem.splitBackwardsSequence(u8, editor.file_name, "/");
    // const name = itr.first();

    try buf_writer.print("{s} - {d} lines", .{
        if (editor.file_name.len > 0) editor.file_name else "[No Name]",
        editor.rows.items.len,
    });
    if (editor.dirty) {
        try buf_writer.writeAll(" (modified)");
    }

    const fstat_len = blk: {
        var slice = buffer.constSlice();
        try writer.writeAll(slice);
        break :blk slice.len;
    };

    try buffer.resize(0);

    try buf_writer.print("{d}/{d}", .{
        editor.cursor.y + 1,
        editor.rows.items.len,
    });

    var slice = buffer.constSlice();

    try writer.writeByteNTimes(' ', if (fstat_len + slice.len > editor.screen.ws_col) 0 else editor.screen.ws_col - fstat_len - slice.len);

    try writer.writeAll(slice);

    try writer.writeAll("\x1B[m");
}

fn drawMessage(editor: *Editor) !void {
    try editor.writer.writeAll("\x1B[K");
    const message = editor.message_buffer.constSlice();
    if (message.len > 0 and std.time.timestamp() - editor.message_time < 5) {
        try editor.writer.writeAll(message[0..@min(message.len, editor.screen.ws_col)]);
    }
}

fn moveCursor(editor: *Editor, key: Editor.Key) void {
    var row = if (editor.cursor.y >= editor.rows.items.len) &[_]u8{} else editor.rows.items[editor.cursor.y].items;

    switch (key) {
        .ARROW_LEFT => if (editor.cursor.x > 0) {
            editor.cursor.x -= 1;
        } else if (editor.cursor.y > 0) {
            editor.cursor.y -= 1;
            editor.cursor.x = editor.rows.items[editor.cursor.y].items.len;
        },
        .ARROW_DOWN => if (editor.cursor.y < editor.rows.items.len) {
            editor.cursor.y += 1;
        },
        .ARROW_UP => if (editor.cursor.y > 0) {
            editor.cursor.y -= 1;
        },
        .ARROW_RIGHT => if (editor.cursor.x < row.len) {
            editor.cursor.x += 1;
        } else if (editor.cursor.y < editor.rows.items.len and editor.cursor.x == row.len) {
            editor.cursor.y += 1;
            editor.cursor.x = 0;
        },

        .HOME => editor.cursor.x = 0,
        .END => editor.cursor.x = row.len,

        // TODO: Fix me!
        .PAGE_UP => {
            editor.cursor.y = editor.row_offset;
            editor.row_offset -= if (editor.screen.ws_row > editor.row_offset) editor.row_offset else editor.screen.ws_row;
        },
        // TODO: Fix me!
        .PAGE_DOWN => {
            editor.cursor.y = @min(editor.row_offset + editor.screen.ws_row - 1, editor.screen.ws_row);
            editor.row_offset = @min(editor.row_offset + editor.screen.ws_row - 1, editor.rows.items.len);
        },

        else => {},
    }

    row = if (editor.cursor.y >= editor.rows.items.len) &[_]u8{} else editor.rows.items[editor.cursor.y].items;
    if (editor.cursor.x > row.len) {
        editor.cursor.x = row.len;
    }
}
