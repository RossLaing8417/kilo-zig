const std = @import("std");

const Editor = @This();

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
rows: [][]u8,
message_buffer: std.BoundedArray(u8, 512),
message_time: i64,

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
        .rows = try allocator.alloc([]u8, 0),
        .message_buffer = try std.BoundedArray(u8, 512).init(0),
        .message_time = std.time.timestamp(),
    };
}

pub fn deinit(self: *Editor) void {
    for (self.rows) |row| {
        self.allocator.free(row);
    }
    self.allocator.free(self.rows);
}

pub fn openFile(self: *Editor, file_name: []const u8) !void {
    const file = try std.fs.cwd().openFile(file_name, .{});
    defer file.close();

    const source = try file.readToEndAlloc(self.allocator, (try file.metadata()).size());
    defer self.allocator.free(source);

    self.file_name = file_name;

    const line_count = std.mem.count(u8, source, "\n") + 1;
    if (line_count < self.rows.len) {
        for (self.rows[line_count..]) |row| {
            self.allocator.free(row);
        }
    }

    self.rows = try self.allocator.realloc(self.rows, line_count);

    var i: usize = 0;
    var itr = std.mem.splitSequence(u8, source, "\n");
    while (itr.next()) |line| : (i += 1) {
        var len = line.len;
        if (std.mem.endsWith(u8, line, "\r")) {
            len -= 1;
        }
        self.rows[i] = try self.allocator.dupe(u8, line[0..len]);
    }
}

pub fn scroll(self: *Editor) void {
    self.render.x = 0;

    if (self.cursor.y < self.rows.len) {
        self.render = cursorToRender(self.rows[self.cursor.y], self.cursor);
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

fn cursorToRender(row: []const u8, cursor: Coord) Coord {
    var render: Coord = .{ .x = 0, .y = 0 };
    for (0..cursor.x) |x| {
        if (row[x] == '\t') {
            render.x += (TAB_STOP - 1) - (render.x % TAB_STOP);
        }
        render.x += 1;
    }
    return render;
}

pub fn setMessage(self: *Editor, comptime format: []const u8, args: anytype) !void {
    try self.message_buffer.resize(0);
    var writer = self.message_buffer.writer();
    try writer.print(format, args);
    self.message_time = std.time.timestamp();
}

fn rowInstertChar(allocator: std.mem.Allocator, row: []u8, at: usize, char: u8) ![]u8 {
    var new_row = try allocator.realloc(row, row.len + 1);

    std.mem.copyForwards(u8, new_row[at + 1 ..], new_row[at .. new_row.len - 1]);
    new_row[at] = char;

    return new_row;
}

pub fn insertChar(self: *Editor, char: u8) !void {
    if (self.cursor.y == self.rows.len) {
        self.rows = try self.allocator.realloc(self.rows, self.rows.len + 1);
        self.rows[self.cursor.y] = try self.allocator.alloc(u8, 0);
    }
    self.rows[self.cursor.y] = try rowInstertChar(self.allocator, self.rows[self.cursor.y], self.cursor.x, char);
    self.cursor.x += 1;
}

pub fn save(self: *Editor) !void {
    var file = try std.fs.cwd().createFile(self.file_name, .{});
    defer file.close();

    var bytes: usize = 0;

    var writer = file.writer();
    for (self.rows[0 .. self.rows.len - 1]) |row| {
        bytes += try writer.write(row);
        bytes += try writer.write("\n");
    }
    bytes += try writer.write(self.rows[self.rows.len - 1]);

    try self.setMessage("{} bytes written to disk", .{bytes});
}
