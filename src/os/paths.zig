//! Where the save file goes on each system, as pure functions of the profile directory the system
//! reports, so both layouts are tested on any machine.

const std = @import("std");

/// The directory the save file is kept in, named for the game.
pub const app_dir_name = "Dentro del cuerpo";
pub const save_file_name = "save.txt";
/// Longest path the helpers handle, in UTF-8 bytes.
pub const max_path = 1024;

/// macOS: `home` is the user's home directory.
pub fn macSaveDir(buf: []u8, home: []const u8) ?[:0]const u8 {
    if (home.len == 0) return null;
    return std.fmt.bufPrintSentinel(buf, "{s}/Library/Application Support/" ++ app_dir_name, .{home}, 0) catch null;
}

/// Windows: `appdata` is the roaming application-data directory (%APPDATA%). A trailing separator, which
/// a drive root would have, is not doubled.
pub fn winSaveDir(buf: []u8, appdata: []const u8) ?[:0]const u8 {
    if (appdata.len == 0) return null;
    const last = appdata[appdata.len - 1];
    const root = if (last == '\\' or last == '/') appdata[0 .. appdata.len - 1] else appdata;
    return std.fmt.bufPrintSentinel(buf, "{s}\\" ++ app_dir_name, .{root}, 0) catch null;
}

/// The save file inside the directory `saveDir` gave.
pub fn saveFile(buf: []u8, dir: []const u8, sep: u8) ?[:0]const u8 {
    return std.fmt.bufPrintSentinel(buf, "{s}{c}" ++ save_file_name, .{ dir, sep }, 0) catch null;
}

test "the save file is under Application Support on macOS" {
    var buf: [256]u8 = undefined;
    var buf2: [256]u8 = undefined;
    const dir = macSaveDir(&buf, "/Users/elena").?;
    try std.testing.expectEqualStrings("/Users/elena/Library/Application Support/Dentro del cuerpo", dir);
    try std.testing.expectEqualStrings("/Users/elena/Library/Application Support/Dentro del cuerpo/save.txt", saveFile(&buf2, dir, '/').?);
    try std.testing.expectEqual(@as(?[:0]const u8, null), macSaveDir(&buf, ""));
}

test "the save file is under %APPDATA% on Windows, whatever the user is called" {
    var buf: [256]u8 = undefined;
    var buf2: [256]u8 = undefined;
    const dir = winSaveDir(&buf, "C:\\Users\\Олена\\AppData\\Roaming").?;
    try std.testing.expectEqualStrings("C:\\Users\\Олена\\AppData\\Roaming\\Dentro del cuerpo", dir);
    try std.testing.expectEqualStrings("C:\\Users\\Олена\\AppData\\Roaming\\Dentro del cuerpo\\save.txt", saveFile(&buf2, dir, '\\').?);
    try std.testing.expectEqualStrings("D:\\Dentro del cuerpo", winSaveDir(&buf, "D:\\").?);
    try std.testing.expectEqual(@as(?[:0]const u8, null), winSaveDir(&buf, ""));
    var small: [20]u8 = undefined;
    try std.testing.expectEqual(@as(?[:0]const u8, null), winSaveDir(&small, "C:\\Users\\x\\AppData\\Roaming"));
}
