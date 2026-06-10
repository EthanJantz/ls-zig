const std = @import("std");
const print = std.debug.print;

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    var show_all = false;
    var long_format = false;
    var path: []const u8 = ".";

    for (args[1..]) |arg| {
        if (arg.len > 1 and arg[0] == '-') {
            for (arg[1..]) |flag| {
                switch(flag) {
                    'a' => { 
                        show_all = true;
                    },
                    'l' => {
                        long_format = true;
                    },
                    else => {
                        print("usage: ls [-al] [path]\n", .{});
                        std.process.exit(1);
                        return;
                    }
                }
            }
        }  else {
            // First arg after flags is set as path, rest of command is ignored
            path = arg;
            break;
        }
    }
    const dir = try std.Io.Dir.cwd().openDir(init.io, path, .{.iterate = true});
    defer dir.close(init.io); 
    
    const allocator = init.gpa;
    var w1 = try dir.walk(allocator);
    defer w1.deinit();
    while (try w1.next(init.io)) |entry| {
        if (entry.depth() > 1) {
            continue;
        }
        switch(entry.kind) {
            .file, .directory => {
                if (!show_all and entry.basename[0] == '.') continue;
                print("{s}\n", .{entry.basename});
            },
            else => {},
        }
    }

    return;
}
