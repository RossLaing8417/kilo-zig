const std = @import("std");

pub const Reader = std.io.Reader(std.fs.File, std.fs.File.ReadError, std.fs.File.read);
pub const Writer = std.io.BufferedWriter(4096, std.io.Writer(std.fs.File, std.fs.File.WriteError, std.fs.File.write)).Writer;

pub const WinSize = std.os.system.winsize;

allocator: std.mem.Allocator,
reader: Reader,
writer: Writer,
orig_termios: std.os.termios,
screen: WinSize,
