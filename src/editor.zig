const std = @import("std");

const Editor = @This();

pub const Reader = std.io.Reader(std.fs.File, std.fs.File.ReadError, std.fs.File.read);
pub const Writer = std.io.BufferedWriter(4096, std.io.Writer(std.fs.File, std.fs.File.WriteError, std.fs.File.write)).Writer;

pub const WinSize = std.os.system.winsize;

pub const VERSION = "0.0.1";

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

allocator: std.mem.Allocator,
reader: Reader,
writer: Writer,
orig_termios: std.os.termios,
screen: WinSize,
cursor: struct { x: usize, y: usize },
row_offset: usize,
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
        .row_offset = 0,
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
    if (self.cursor.y < self.row_offset) {
        self.row_offset = self.cursor.y;
    }
    if (self.cursor.y >= self.row_offset + self.screen.ws_row) {
        self.row_offset = self.cursor.y - self.screen.ws_row + 1;
    }
}
