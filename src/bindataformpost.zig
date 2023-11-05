const std = @import("std");
const zap = @import("zap");

const Handler = struct {
    var alloc: std.mem.Allocator = undefined;
    pub fn on_request(r: zap.SimpleRequest) void {
        r.parseBody() catch |err| {
            std.log.err("Parse body error: {any}, Expected if body is empty", .{err});
        };

        if (r.body) |body| {
            std.log.info("Body length is {any} \n", .{body.len});
        }
        r.parseQuery();
        var param_count = r.getParamCount();
        std.log.info("param_count: {}", .{param_count});

        const params = r.parametersToOwnedList(Handler.alloc, false) catch unreachable;
        defer params.deinit();
        for (params.items) |kv| {
            if (kv.value) |v| {
                std.debug.print("\n", .{});
                std.log.info("Param `{s}` in owned list is {any}\n", .{ kv.key.str, v });
                switch (v) {
                    zap.HttpParam.Hash_Binfile => |*file| {
                        const filename = file.filename orelse "{no filename}";
                        const mimetype = file.mimetype orelse "{no mimetype}";
                        const data = file.data orelse "";
                        std.log.debug("   filename: `{s}`\n", .{filename});
                        std.log.debug("   mimetype: `{s}`\n", .{mimetype});
                        std.log.debug("   data: `{s}`\n", .{data});
                    },
                    zap.HttpParam.Array_Binfile => |*files| {
                        for (files.*.items) |file| {
                            const filename = file.filename orelse "{no filename}";
                            const mimetype = file.mimetype orelse "{no mimetype}";
                            const data = file.data orelse "";
                            std.log.debug("   filename: `{s}`\n", .{filename});
                            std.log.debug("   mimetype: `{s}`\n", .{mimetype});
                            std.log.debug("   data: `{s}`\n", .{data});
                        }
                        files.*.deinit();
                    },
                    else => {
                        if (r.getParamStr(kv.key.str, Handler.alloc, false)) |maybe_str| {
                            const value: []const u8 = if (maybe_str) |s| s.str else "{no value}";
                            std.log.debug("   {s} = {s}", .{ kv.key.str, value });
                        } else |err| {
                            std.log.err("Error: {any}\n", .{err});
                        }
                    },
                }
            }
        }
        if (r.getParamStr("terminate", Handler.alloc, false)) |maybe_str| {
            if (maybe_str) |*s| {
                defer s.deinit();
                std.log.info("?terminate={s}\n", .{s.str});
                if (std.mem.eql(u8, s.str, "true")) {
                    zap.fio_stop();
                }
            }
        } else |err| {
            std.log.err("cannot check for terminate param: {any}\n", .{err});
        }
        r.sendJson("{ \"ok\": true}") catch unreachable;
    }
};
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{
        .thread_safe = true,
    }){};
    var allocator = gpa.allocator();
    Handler.alloc = allocator;
    var listener = zap.SimpleHttpListener.init(
        .{
            .port = 3000,
            .on_request = Handler.on_request,
            .log = true,
            .max_clients = 10,
            .max_body_size = 10 * 1024 * 1024,
            .public_folder = ".",
        },
    );
    zap.enableDebugLog();
    try listener.listen();
    std.log.info("\n\nURL is http://localhost:3000\n", .{});
    std.log.info("\ncurl -v --request POST -F img=@test0123345.bin http://127.0.0.1:3000\n", .{});
    std.log.info("\n\nTerminate with CTRL-c or by sending query param terminate=true\n", .{});
    zap.start(.{
        .threads = 1,
        .workers = 0,
    });
}
