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
    try drawStatusBar(editor);

    try editor.writer.print("\x1B[{};{}H", .{
        (editor.cursor.y - editor.row_offset) + 1,
        (editor.render.x - editor.col_offset) + 1,
    });

    try editor.writer.writeAll("\x1B[H");
    try editor.writer.writeAll("\x1B[?25h");
}

fn drawRows(editor: *Editor) !void {
    var writer = editor.writer;
    const rows = editor.rows orelse &[_][]u8{};
    const drawable = editor.screen.ws_row - 1;

    for (0..drawable, editor.row_offset..) |screen_row, file_row| {
        if (rows.len == 0 or file_row >= rows.len) {
            if (rows.len > 0 and screen_row == drawable / 3) {
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
            const row = rows[file_row];
            if (row.len > 0 and editor.col_offset < row.len) {
                const start = @min(row.len - 1, editor.col_offset);
                const end = @min(row.len, editor.screen.ws_col);
                // try writer.print("{d} -- {d}:{d} ({d}:{d}) -- ", .{
                //     editor.col_offset,
                //     start,
                //     end,
                //     row.len,
                //     @min(row.len - 1, editor.col_offset),
                // });
                try terminal.render(writer, row[start..end]);
            }
        }

        if (screen_row == 0) {
            try writer.print(" {d}:{d}", .{ editor.cursor.y, editor.cursor.x });
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
        if (editor.rows) |rows| rows.len else 0,
    });

    const fstat_len = blk: {
        var slice = buffer.constSlice();
        try writer.writeAll(slice);
        break :blk slice.len;
    };

    try buffer.resize(0);

    try buf_writer.print("{d}/{d}", .{
        editor.cursor.y + 1,
        if (editor.rows) |rows| rows.len else 0,
    });

    var slice = buffer.constSlice();

    try writer.writeByteNTimes(' ', if (fstat_len + slice.len > editor.screen.ws_col) 0 else editor.screen.ws_col - fstat_len - slice.len);

    try writer.writeAll(slice);

    try writer.writeAll("\x1B[m");
}

fn moveCursor(editor: *Editor, key: Editor.Key) void {
    const rows = editor.rows orelse &[_][]u8{};
    var row = if (editor.cursor.y >= rows.len) &[_]u8{} else rows[editor.cursor.y];

    switch (key) {
        .ARROW_LEFT => if (editor.cursor.x > 0) {
            editor.cursor.x -= 1;
        } else if (editor.cursor.y > 0) {
            editor.cursor.y -= 1;
            editor.cursor.x = rows[editor.cursor.y].len;
        },
        .ARROW_DOWN => if (editor.cursor.y < rows.len) {
            editor.cursor.y += 1;
        },
        .ARROW_UP => if (editor.cursor.y > 0) {
            editor.cursor.y -= 1;
        },
        .ARROW_RIGHT => if (editor.cursor.x < row.len) {
            editor.cursor.x += 1;
        } else if (editor.cursor.y < rows.len and editor.cursor.x == row.len) {
            editor.cursor.y += 1;
            editor.cursor.x = 0;
        },

        .HOME => editor.cursor.x = 0,
        .END => editor.cursor.x = row.len,

        .PAGE_UP => {
            editor.cursor.y = editor.row_offset;
            editor.row_offset -= if (editor.screen.ws_row > editor.row_offset) editor.row_offset else editor.screen.ws_row;
        },
        .PAGE_DOWN => {
            editor.cursor.y = @min(editor.row_offset + editor.screen.ws_row - 1, editor.screen.ws_row);
            editor.row_offset = @min(editor.row_offset + editor.screen.ws_row - 1, rows.len);
        },

        else => {},
    }

    row = if (editor.cursor.y >= rows.len) &[_]u8{} else rows[editor.cursor.y];
    if (editor.cursor.x > row.len) {
        editor.cursor.x = row.len;
    }
}
