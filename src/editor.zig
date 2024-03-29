const std = @import("std");

const Editor = @This();

const terminal = @import("terminal.zig");
const io = @import("io.zig");

const Row = std.ArrayList(u8);
const Rows = std.ArrayList(*Row);

pub const Reader = std.io.Reader(std.fs.File, std.fs.File.ReadError, std.fs.File.read);
pub const Writer = std.io.BufferedWriter(4096, std.io.Writer(std.fs.File, std.fs.File.WriteError, std.fs.File.write)).Writer;

pub const WinSize = std.os.system.winsize;

pub const VERSION = "0.0.1";
pub const TAB_STOP = 4;

pub const Key = enum(u32) {
    BACKSPACE = 127,
    ARROW_UP = 1000,
    ARROW_DOWN,
    ARROW_LEFT,
    ARROW_RIGHT,
    DELETE,
    HOME,
    END,
    PAGE_UP,
    PAGE_DOWN,

    /// This just makes life easier with .ENUM stuff
    pub fn intFromEnum(key: Key) u32 {
        return @intFromEnum(key);
    }
};

const Coord = struct { x: usize, y: usize };

allocator: std.mem.Allocator,
file_name: []const u8,
reader: Reader,
writer: Writer,
orig_termios: std.os.termios,
screen: WinSize,
cursor: Coord,
render: Coord,
row_offset: usize,
col_offset: usize,
rows: *Rows,
message_buffer: std.BoundedArray(u8, 512),
message_time: i64,
dirty: bool,
prompt_buffer: std.BoundedArray(u8, 512),

pub fn init(
    allocator: std.mem.Allocator,
    reader: Reader,
    writer: Writer,
    orig_termios: std.os.termios,
    screen: WinSize,
) !Editor {
    return .{
        .allocator = allocator,
        .file_name = "",
        .reader = reader,
        .writer = writer,
        .orig_termios = orig_termios,
        .screen = blk: {
            var tmp = screen;
            tmp.ws_row -= 2;
            break :blk tmp;
        },
        .cursor = .{ .x = 0, .y = 0 },
        .render = .{ .x = 0, .y = 0 },
        .row_offset = 0,
        .col_offset = 0,
        .rows = blk: {
            var rows = try allocator.create(Rows);
            rows.* = Rows.init(allocator);
            break :blk rows;
        },
        .message_buffer = try std.BoundedArray(u8, 512).init(0),
        .message_time = std.time.timestamp(),
        .dirty = false,
        .prompt_buffer = try std.BoundedArray(u8, 512).init(0),
    };
}

pub fn deinit(self: *Editor) void {
    for (self.rows.items) |row| {
        row.deinit();
        self.allocator.destroy(row);
    }
    self.rows.deinit();
    self.allocator.destroy(self.rows);
}

pub fn openFile(self: *Editor, file_name: []const u8) !void {
    const file = try std.fs.cwd().openFile(file_name, .{});
    defer file.close();

    const source = try file.readToEndAlloc(self.allocator, (try file.metadata()).size());
    defer self.allocator.free(source);

    self.file_name = file_name;

    const line_count = std.mem.count(u8, source, "\n") + 1;
    if (line_count < self.rows.items.len) {
        for (self.rows.items[line_count..]) |row| {
            row.deinit();
            self.allocator.destroy(row);
        }
        self.rows.shrinkRetainingCapacity(line_count);
    } else {
        try self.rows.ensureTotalCapacity(line_count);
    }

    var i: usize = 0;
    var itr = std.mem.splitSequence(u8, source, "\n");
    while (itr.next()) |line| : (i += 1) {
        var len = line.len;
        if (std.mem.endsWith(u8, line, "\r")) {
            len -= 1;
        }
        if (i < self.rows.items.len) {
            self.rows.items[i].shrinkRetainingCapacity(len);
            try self.rows.items[i].replaceRange(0, len, line[0..len]);
        } else {
            var row = try self.allocator.create(Row);
            row.* = try Row.initCapacity(self.allocator, len);
            row.appendSliceAssumeCapacity(line[0..len]);
            self.rows.appendAssumeCapacity(row);
        }
    }

    self.dirty = false;
}

pub fn scroll(self: *Editor) void {
    self.render.x = 0;

    if (self.cursor.y < self.rows.items.len) {
        self.render.x = cursorXToRenderX(self.rows.items[self.cursor.y].items, self.cursor.x);
    }

    if (self.cursor.y < self.row_offset) {
        self.row_offset = self.cursor.y;
    }
    if (self.cursor.y >= self.row_offset + self.screen.ws_row) {
        self.row_offset = self.cursor.y - self.screen.ws_row + 1;
    }
    if (self.cursor.x < self.col_offset) {
        self.col_offset = self.cursor.x;
    }
    if (self.cursor.x >= self.col_offset + self.screen.ws_col) {
        self.col_offset = self.cursor.x - self.screen.ws_col + 1;
    }
    if (self.render.x < self.col_offset) {
        self.col_offset = self.render.x;
    }
    if (self.render.x >= self.col_offset + self.screen.ws_col) {
        self.col_offset = self.render.x - self.screen.ws_col + 1;
    }
}

fn cursorXToRenderX(row: []const u8, cx: usize) usize {
    var rx: usize = 0;
    for (0..cx) |x| {
        if (row[x] == '\t') {
            rx += (TAB_STOP - 1) - (rx % TAB_STOP);
        }
        rx += 1;
    }
    return rx;
}

fn renderXToCursorX(row: []const u8, rx: usize) usize {
    var cur_rx: usize = 0;
    for (row, 0..) |char, cx| {
        if (char == '\t') {
            cur_rx = (TAB_STOP - 1) - (cur_rx % TAB_STOP);
        }
        cur_rx += 1;
        if (cur_rx > rx) {
            return cx;
        }
    }
    return row.len;
}

pub fn setMessage(self: *Editor, comptime format: []const u8, args: anytype) !void {
    try self.message_buffer.resize(0);
    var writer = self.message_buffer.writer();
    try writer.print(format, args);
    self.message_time = std.time.timestamp();
}

pub fn insertNewLine(self: *Editor) !void {
    var new_row = try self.allocator.create(Row);
    new_row.* = Row.init(self.allocator);
    if (self.cursor.x == 0) {
        try self.rows.insert(self.cursor.y, new_row);
        self.cursor.y += 1;
        self.dirty = true;
        return;
    }
    var cur_row = self.rows.items[self.cursor.y];
    try new_row.appendSlice(cur_row.items[self.cursor.x..]);
    cur_row.shrinkRetainingCapacity(self.cursor.x);
    try self.rows.insert(self.cursor.y + 1, new_row);
    self.cursor.y += 1;
    self.cursor.x = 0;
    self.dirty = true;
}

pub fn insertChar(self: *Editor, char: u8) !void {
    if (self.cursor.y == self.rows.items.len) {
        var row = try self.allocator.create(Row);
        row.* = Row.init(self.allocator);
        try self.rows.append(row);
    }
    try self.rows.items[self.cursor.y].insert(self.cursor.x, char);
    self.cursor.x += 1;
    self.dirty = true;
}

pub fn deleteChar(self: *Editor) !void {
    if (self.cursor.y >= self.rows.items.len) {
        return;
    }

    if (self.cursor.x == 0) {
        if (self.cursor.y == 0) {
            return;
        }
        var row = self.rows.orderedRemove(self.cursor.y);
        defer row.deinit();
        self.cursor.y -= 1;
        self.cursor.x = self.rows.items[self.cursor.y].items.len;
        try self.rows.items[self.cursor.y].appendSlice(row.items);
        return;
    }

    var row = self.rows.items[self.cursor.y];
    _ = row.orderedRemove(self.cursor.x - 1);
    self.cursor.x -= 1;
    self.dirty = true;
}

pub fn saveFile(self: *Editor) !void {
    if (!self.dirty) {
        return;
    }

    if (self.file_name.len == 0) {
        self.file_name = try self.prompt("Save as: {s}", null);
        if (self.file_name.len == 0) {
            try self.setMessage("Save aborted", .{});
            return;
        }
    }

    var file = try std.fs.cwd().createFile(self.file_name, .{});
    defer file.close();

    var bytes: usize = 0;

    var writer = file.writer();
    for (self.rows.items[0 .. self.rows.items.len - 1]) |row| {
        bytes += try writer.write(row.items);
        bytes += try writer.write("\n");
    }
    bytes += try writer.write(self.rows.items[self.rows.items.len - 1].items);

    self.dirty = false;
    try self.setMessage("{} bytes written to disk", .{bytes});
}

fn prompt(
    self: *Editor,
    comptime format: []const u8,
    callback: (?*const fn (*Editor, []const u8, u32) void),
) ![]const u8 {
    try self.prompt_buffer.resize(0);
    while (true) {
        const slice = self.prompt_buffer.constSlice();
        try self.setMessage(format, .{slice});
        try io.refreshScreen(self);

        const key = try terminal.readKey(self.reader);
        switch (key) {
            0 => continue,
            '\x1B' => {
                try self.message_buffer.resize(0);
                if (callback) |func| {
                    func(self, slice, key);
                }
                return "";
            },
            Key.intFromEnum(.BACKSPACE) => if (self.prompt_buffer.len > 0) {
                try self.prompt_buffer.resize(self.prompt_buffer.len - 1);
            },
            '\r' => {
                if (slice.len != 0) {
                    try self.message_buffer.resize(0);
                    if (callback) |func| {
                        func(self, slice, key);
                    }
                    return slice;
                }
            },
            else => if (key < 128 and !std.ascii.isControl(@intCast(key))) {
                try self.prompt_buffer.append(@intCast(key));
            },
        }

        if (callback) |func| {
            func(self, slice, key);
        }
    }
}

pub fn find(self: *Editor) !void {
    const cursor = self.cursor;
    const row_offset = self.row_offset;
    const col_offset = self.col_offset;

    const query = try self.prompt("Search: {s} (Use ESC/Arrow/Enter)", &findCallBack);

    if (query.len == 0) {
        self.cursor = cursor;
        self.row_offset = row_offset;
        self.col_offset = col_offset;
        return;
    }
    try self.prompt_buffer.resize(0);
}

fn findCallBack(self: *Editor, query: []const u8, char: u32) void {
    // NOTE: This could be changed to always start at the cursor position
    const state = struct {
        var last_match: isize = -1;
        var direction: i2 = 1;
    };

    switch (char) {
        '\r', '\x1B' => {
            state.last_match = -1;
            state.direction = 1;
            return;
        },
        Key.intFromEnum(.ARROW_UP),
        Key.intFromEnum(.ARROW_LEFT),
        => state.direction = -1,
        Key.intFromEnum(.ARROW_DOWN),
        Key.intFromEnum(.ARROW_RIGHT),
        => state.direction = 1,
        else => {
            state.last_match = -1;
            state.direction = 1;
        },
    }

    if (state.last_match == -1) {
        state.direction = 1;
    }
    var y = state.last_match;
    for (0..self.rows.items.len) |_| {
        y += state.direction;
        if (y == -1) {
            y = @intCast(self.rows.items.len - 1);
        } else if (y == self.rows.items.len) {
            y = 0;
        }
        const row = self.rows.items[@intCast(y)];
        if (std.mem.indexOf(u8, row.items, query)) |x| {
            state.last_match = y;
            self.cursor.y = @intCast(y);
            self.cursor.x = renderXToCursorX(row.items, x);
            self.row_offset = self.rows.items.len;
            return;
        }
    }
}
