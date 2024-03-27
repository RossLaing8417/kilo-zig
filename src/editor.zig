const std = @import("std");

const Editor = @This();

pub const Reader = std.io.Reader(std.fs.File, std.fs.File.ReadError, std.fs.File.read);
pub const Writer = std.io.BufferedWriter(4096, std.io.Writer(std.fs.File, std.fs.File.WriteError, std.fs.File.write)).Writer;

pub const WinSize = std.os.system.winsize;

pub const VERSION = "0.0.1";
pub const TAB_STOP = 4;

pub const Key = enum(u32) {
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
reader: Reader,
writer: Writer,
orig_termios: std.os.termios,
screen: WinSize,
cursor: Coord,
render: Coord,
row_offset: usize,
col_offset: usize,
rows: ?[][]u8,

pub fn init(
    allocator: std.mem.Allocator,
    reader: Reader,
    writer: Writer,
    orig_termios: std.os.termios,
    screen: WinSize,
) Editor {
    return .{
        .allocator = allocator,
        .reader = reader,
        .writer = writer,
        .orig_termios = orig_termios,
        .screen = screen,
        .cursor = .{ .x = 0, .y = 0 },
        .render = .{ .x = 0, .y = 0 },
        .row_offset = 0,
        .col_offset = 0,
        .rows = null,
    };
}

pub fn deinit(self: *Editor) void {
    self.freeRows();
}

fn freeRows(self: *Editor) void {
    if (self.rows) |rows| {
        for (rows) |row| {
            self.allocator.free(row);
        }
        self.allocator.free(rows);
    }
}

pub fn openFile(self: *Editor, file_name: []const u8) !void {
    const file = try std.fs.cwd().openFile(file_name, .{});
    defer file.close();

    const source = try file.readToEndAlloc(self.allocator, (try file.metadata()).size());
    defer self.allocator.free(source);

    self.freeRows();

    self.rows = try self.allocator.alloc([]u8, std.mem.count(u8, source, "\n") + 1);
    var rows = self.rows.?;

    var i: usize = 0;
    var itr = std.mem.splitSequence(u8, source, "\n");
    while (itr.next()) |line| : (i += 1) {
        var len = line.len;
        if (std.mem.endsWith(u8, line, "\r")) {
            len -= 1;
        }
        rows[i] = try self.allocator.dupe(u8, line[0..len]);
    }
}

pub fn scroll(self: *Editor) void {
    self.render.x = 0;

    if (self.rows != null and self.cursor.y < self.rows.?.len) {
        self.render = cursorToRender(self.rows.?[self.cursor.y], self.cursor);
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
