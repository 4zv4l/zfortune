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
    var datfile_br = std.io.bufferedReader(datfile.reader());
    var file = try fs.cwd().openFile(path[0 .. path.len - 4], .{});
    defer file.close();
    var file_br = std.io.bufferedReader(file.reader());

    const header = Strfile{
        .str_version = try datfile_br.reader().readInt(u32, .big),
        .str_numstr = try datfile_br.reader().readInt(u32, .big),
        .str_longlen = try datfile_br.reader().readInt(u32, .big),
        .str_shortlen = try datfile_br.reader().readInt(u32, .big),
        .str_flags = try datfile_br.reader().readInt(u32, .big),
        .str_delim = @truncate(try datfile_br.reader().readInt(u32, .little)),
    };
    if (header.str_version > 2) return error.BadDatStrFile;
    log.info("header: {}\n", .{header});

    // load quote ptr table
    const quotes_ptr = try ally.alloc(u32, header.str_numstr - 1);
    defer ally.free(quotes_ptr);
    for (quotes_ptr) |*quote| quote.* = try datfile_br.reader().readInt(u32, .big);
    log.info("quotes table: {d}", .{quotes_ptr});

    // choose random quote and go to quote ptr
    const quote_idx = random.intRangeLessThan(usize, 0, quotes_ptr.len);
    log.info("quote_idx: {d} => {d}", .{ quote_idx, quotes_ptr[quote_idx] });
    try file.seekTo(quotes_ptr[quote_idx]);
    var quote = try std.ArrayList(u8).initCapacity(ally, header.str_longlen + 1);
    // read twice if ptr points to delimiter
    try file_br.reader().streamUntilDelimiter(quote.writer(), header.str_delim, header.str_longlen + 1);
    if (quote.items.len == 0) {
        quote.clearRetainingCapacity();
        try file_br.reader().streamUntilDelimiter(quote.writer(), header.str_delim, header.str_longlen + 1);
    }
    return quote.toOwnedSlice();
}

pub fn main() !void {
    // setup allocator
    var arena = std.heap.ArenaAllocator.init(std.heap.smp_allocator);
    defer arena.deinit();
    const ally = arena.allocator();
    _ = try ally.alloc(u8, 5 * 1024); // pre allocate 5kb
    _ = arena.reset(.retain_capacity);

    const FORTUNE_PATH = posix.getenv("FORTUNE_PATH") orelse "/usr/share/fortune";
    var dir = fs.cwd().openDir(FORTUNE_PATH, .{ .iterate = true }) catch |err| {
        std.debug.print("{s}: {s} (set via FORTUNE_PATH)\n", .{ FORTUNE_PATH, if (err == error.FileNotFound) "Directory not found" else @errorName(err) });
        posix.exit(1);
    };
    defer dir.close();

    // load all path from FORTUNE_PATH
    var files = std.ArrayList([]const u8).init(ally);
    defer {
        for (files.items) |filepath| ally.free(filepath);
        files.deinit();
    }
    var fileit = dir.iterateAssumeFirstIteration();
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

    // randomly choose one file and a quote from that file
    const path = files.items[random.intRangeLessThan(usize, 0, files.items.len)];
    const quote = try getRandomQuote(ally, path);
    defer ally.free(quote);

    // print quote
    var out = std.io.bufferedWriter(std.io.getStdOut().writer());
    try out.writer().writeAll(quote);
    try out.flush();
}
