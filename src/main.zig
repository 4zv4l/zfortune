const std = @import("std");
const posix = std.posix;
const fs = std.fs;
const random = std.crypto.random;
const log = std.log;

// strfile header
const Strfile = extern struct {
    str_version: u32,
    str_numstr: u32, // n of strings
    str_longlen: u32, // len of longest string
    str_shortlen: u32, // len of shortest string
    str_flags: u32,
    str_delim: u8, // delim (should be % for this program)
};

fn getRandomQuote(ally: std.mem.Allocator, path: []const u8) ![]const u8 {
    log.info("path: '{s}'", .{path});
    log.info("path: '{s}'", .{path[0 .. path.len - 4]});

    var datfile = try fs.cwd().openFile(path, .{});
    defer datfile.close();
    var file = try fs.cwd().openFile(path[0 .. path.len - 4], .{});
    defer file.close();

    const header = Strfile{
        .str_version = try datfile.reader().readInt(u32, .big),
        .str_numstr = try datfile.reader().readInt(u32, .big),
        .str_longlen = try datfile.reader().readInt(u32, .big),
        .str_shortlen = try datfile.reader().readInt(u32, .big),
        .str_flags = try datfile.reader().readInt(u32, .big),
        .str_delim = @truncate(try datfile.reader().readInt(u32, .little)),
    };
    if (header.str_version > 2) return error.BadDatStrFile;
    log.info("header: {}\n", .{header});

    // load quote ptr table
    const quotes_ptr = try ally.alloc(u32, header.str_numstr - 1);
    defer ally.free(quotes_ptr);
    for (quotes_ptr) |*quote| quote.* = try datfile.reader().readInt(u32, .big);
    log.info("quotes table: {d}", .{quotes_ptr});

    // choose random quote and go to quote ptr
    const quote_idx = random.intRangeLessThan(usize, 0, quotes_ptr.len);
    log.info("quote_idx: {d} => {d}", .{ quote_idx, quotes_ptr[quote_idx] });
    try file.seekTo(quotes_ptr[quote_idx]);
    // sometimes ptr point to delimiter of previous quote
    if (try file.reader().readByte() == header.str_delim) {
        try file.seekTo(quotes_ptr[quote_idx] + 1);
    } else {
        try file.seekTo(quotes_ptr[quote_idx]);
    }
    return try file.reader().readUntilDelimiterAlloc(ally, header.str_delim, header.str_longlen);
}

pub fn main() !void {
    // setup allocator and rng
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const ally = gpa.allocator();
    defer _ = gpa.deinit();

    const FORTUNE_PATH = posix.getenv("FORTUNE_PATH") orelse "/usr/share/fortune";

    var dir = fs.cwd().openDir(FORTUNE_PATH, .{ .iterate = true }) catch |err| {
        std.debug.print("{s}: {s} (set via FORTUNE_PATH)\n", .{ FORTUNE_PATH, @errorName(err) });
        posix.exit(1);
    };
    defer dir.close();

    // load all path from FORTUNE_PATH
    var files = std.ArrayList([]const u8).init(ally);
    defer {
        for (files.items) |filepath| ally.free(filepath);
        files.deinit();
    }
    var fileit = dir.iterate();
    while (try fileit.next()) |entry| {
        switch (entry.kind) {
            .file => {
                if (std.mem.endsWith(u8, entry.name, ".dat")) {
                    try files.append(try std.fmt.allocPrint(ally, "{}", .{fs.path.fmtJoin(&[_][]const u8{ FORTUNE_PATH, entry.name })}));
                }
            },
            else => {},
        }
    }

    // randomly choose one path
    const path = files.items[random.intRangeLessThan(usize, 0, files.items.len)];
    const quote = try getRandomQuote(ally, path);
    defer ally.free(quote);

    // print quote
    var out = std.io.bufferedWriter(std.io.getStdOut().writer());
    try out.writer().writeAll(quote);
    try out.flush();
}
