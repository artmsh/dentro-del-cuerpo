//! `util.zig` on the television: the POSIX file calls, with the save file in the application's private
//! data directory. Tizen gives an application that directory by a call into its framework, which the
//! entry point makes; it has no home directory and no variable naming one.

const std = @import("std");
const posix = @import("posix_files.zig");
const paths = @import("paths.zig");

pub const writeFileParts = posix.writeFileParts;
pub const writeStdout = posix.writeStdout;
pub const readFile = posix.readFile;
pub const makeDir = posix.makeDir;
pub const isDir = posix.isDir;
pub const writeFileAtomic = posix.writeFileAtomic;
pub const removeFile = posix.removeFile;
pub const removeDir = posix.removeDir;
pub const linkFile = posix.linkFile;
pub const env = posix.env;
pub const envIsSet = posix.envIsSet;
pub const setEnv = posix.setEnv;
pub const makeTempDir = posix.makeTempDir;
pub const profile_var = posix.profile_var;

var data_dir_buf: [paths.max_path]u8 = undefined;
var data_dir_len: usize = 0;

/// The application's data directory, as the framework reported it. Set once at startup, before the save
/// file is looked for.
pub fn setDataDir(path: []const u8) void {
    data_dir_len = if (path.len <= data_dir_buf.len) path.len else 0;
    @memcpy(data_dir_buf[0..data_dir_len], path[0..data_dir_len]);
}

pub fn profileRoot(buf: []u8) ?[]const u8 {
    if (data_dir_len == 0 or data_dir_len > buf.len) return null;
    @memcpy(buf[0..data_dir_len], data_dir_buf[0..data_dir_len]);
    return buf[0..data_dir_len];
}

pub fn saveDirIn(buf: []u8, root: []const u8) ?[:0]const u8 {
    return paths.tvSaveDir(buf, root);
}

pub const no_profile_reason = "the television did not name a data directory, so there is nowhere to keep a save file";
