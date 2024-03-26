const std = @import("std");

pub const Reader = std.io.Reader(std.fs.File, std.fs.File.ReadError, std.fs.File.read);
pub const Writer = std.io.BufferedWriter(4096, std.io.Writer(std.fs.File, std.fs.File.WriteError, std.fs.File.write)).Writer;

pub const WinSize = std.os.system.winsize;

pub const VERSION = "0.0.1";

pub const Key = enum(u32) {
    ARROW_UP = 1000,
    ARROW_DOWN,
    ARROW_LEFT,
    ARROW_RIGHT,
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
