const std = @import("std");
const linux = std.os.linux;
const POSIX_S = std.posix.S;
const zeit = @import("zeit");

pub fn make_mode_human_readable(mode: u16) [10:0] u8 {
    var str: [10:0] u8 = std.mem.zeroes([10:0]u8);
    
    switch(mode & POSIX_S.IFMT) {
        POSIX_S.IFDIR => str[0] = 'd',
        POSIX_S.IFLNK => str[0] = 'l',
        POSIX_S.IFCHR => str[0] = 'c',
        POSIX_S.IFBLK => str[0] = 'b',
        POSIX_S.IFIFO => str[0] = 'p',
        POSIX_S.IFSOCK => str[0] = 's',
        else => str[0] = '-'
    }
    
    str[1] = if(mode & POSIX_S.IRUSR != 0) 'r' else '-';
    str[2] = if(mode & POSIX_S.IWUSR != 0) 'w' else '-';
    str[3] = if(mode & POSIX_S.IXUSR != 0) 'x' else '-';

    str[4] = if(mode & POSIX_S.IRGRP != 0) 'r' else '-';
    str[5] = if(mode & POSIX_S.IWGRP != 0) 'w' else '-';
    str[6] = if(mode & POSIX_S.IXGRP != 0) 'x' else '-';

    str[7] = if(mode & POSIX_S.IROTH != 0) 'r' else '-';
    str[8] = if(mode & POSIX_S.IWOTH != 0) 'w' else '-';
    str[9] = if(mode & POSIX_S.IXOTH != 0) 'x' else '-';

    return str;
}

pub fn format_unix_time(epoch_seconds: i64) ![16]u8 {
    const es: std.time.epoch.EpochSeconds = .{.secs = @intCast(epoch_seconds)};
    const day = es.getEpochDay().calculateYearDay();
    const md = day.calculateMonthDay();
    const ds = es.getDaySeconds();

    var buf: [16]u8 = undefined;
    _ = std.fmt.bufPrint(&buf, "{d}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}", .{day.year, md.month.numeric(), md.day_index + 1, ds.getHoursIntoDay(), ds.getMinutesIntoHour()}) catch unreachable;
    return buf;
}

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    var show_all = false;
    var show_long = false;
    var path: []const u8 = ".";

    for (args[1..]) |arg| {
        if (arg.len > 1 and arg[0] == '-') {
            for (arg[1..]) |flag| {
                switch(flag) {
                    'a' => { 
                        show_all = true;
                    },
                    'l' => {
                        show_long = true;
                    },
                    else => {
                        std.debug.print("usage: ls [-a] [path]\n", .{});
                        std.process.exit(1);
                        return;
                    }
                }
            }
        }  else {
            // First arg after flags is set as path, remaining args ignored
            path = arg;
            break;
        }
    }

    const dir = try std.Io.Dir.cwd().openDir(init.io, path, .{.iterate = true});
    defer dir.close(init.io); 

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_file_writer: std.Io.File.Writer = .init(.stdout(), init.io, &stdout_buffer);
    const stdout_writer = &stdout_file_writer.interface;

    var dir_iter = dir.iterateAssumeFirstIteration();
    while (try dir_iter.next(init.io)) |entry| {
        if (!show_all and entry.name[0] == '.') continue;
        if (show_long) {
            var statx: linux.Statx = undefined;
            switch(entry.kind) {
                .directory => {
                    const errno = linux.errno(linux.statx(
                            dir.handle,
                            "",
                            linux.AT.EMPTY_PATH,
                            .{ .MODE = true, .GID = true, .UID = true, .MTIME = true},
                            &statx
                            ));

                    switch (errno) {
                        .SUCCESS => {},
                        else => return error.StatFailed,
                    }
                    try stdout_writer.print("{s} {x} {x} {s} {s}\n", .{make_mode_human_readable(statx.mode), statx.gid, statx.uid, try format_unix_time(statx.mtime.sec), entry.name});
                    try stdout_writer.flush();
                },
                .file => {
                    var name_buf: [std.fs.max_path_bytes]u8 = undefined;
                    const name_z = std.fmt.bufPrintSentinel(&name_buf, "{s}", .{entry.name}, 0) catch return error.NameTooLong;

                    const errno = linux.errno(linux.statx(
                            dir.handle,
                            name_z,
                            linux.AT.EMPTY_PATH,
                            .{ .MODE = true, .GID = true, .UID = true, .MTIME = true},
                            &statx
                            ));

                    switch (errno) {
                        .SUCCESS => {},
                        else => return error.StatFailed,
                    }
                    

                    try stdout_writer.print("{s} {x} {x} {s} {s}\n", .{make_mode_human_readable(statx.mode), statx.gid, statx.uid, try format_unix_time(statx.mtime.sec), entry.name});
                    try stdout_writer.flush();
                },
                else => {}
            }
        } else {
            try stdout_writer.print("{s}\n", .{entry.name});
            try stdout_writer.flush();
        }
    }
    return;
}
