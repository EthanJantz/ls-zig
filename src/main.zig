const std = @import("std");
const linux = std.os.linux;

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
                    try stdout_writer.print("{x} {x} {x} {x} {s}\n", .{statx.mode, statx.gid, statx.uid, statx.mtime.sec, entry.name});
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
                    try stdout_writer.print("{x} {x} {x} {x} {s}\n", .{statx.mode, statx.gid, statx.uid, statx.mtime.sec, entry.name});
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
