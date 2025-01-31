const std = @import("std");
const net = std.net;
const mem = std.mem;
const posix = std.posix;
const io = std.io;
const time = std.time;
const heap = std.heap;

const PingError = error{
    Timeout,
    NetworkError,
};

const TARGET = "8.8.8.8";
const PACKET_SIZE = 64;
const TIMEOUT_MS: i64 = 5000;

inline fn calculateChecksum(data: []const u8) u16 {
    var sum: u32 = 0;
    var i: usize = 0;

    while (i + 3 < data.len) : (i += 4) sum += @as(u32, data[i]) << 24 |
        @as(u32, data[i + 1]) << 16 |
        @as(u32, data[i + 2]) << 8 |
        data[i + 3];

    while (i < data.len) : (i += 1) sum += @as(u32, data[i]) << @as(u5, @intCast((data.len - i - 1) * 8));
    while (sum >> 16 != 0) sum = (sum & 0xFFFF) + (sum >> 16);

    return ~@as(u16, @truncate(sum));
}

inline fn createIcmpPacket(buffer: []u8) void {
    @memset(buffer, 0);
    buffer[0] = 8;
    buffer[1] = 0;
    
    const cs = calculateChecksum(buffer);
    buffer[2] = @as(u8, @truncate(cs >> 8));
    buffer[3] = @as(u8, @truncate(cs & 0xFF));
}

noinline fn ping(buffer: []u8, ip_address: []const u8) !i64 {
    const socket = try posix.socket(posix.AF.INET, posix.SOCK.DGRAM, posix.IPPROTO.ICMP);
    defer posix.close(socket);

    const timeout = posix.timeval{
        .tv_sec = @intCast(TIMEOUT_MS / 1000),
        .tv_usec = @intCast((TIMEOUT_MS % 1000) * 1000),
    };

    try posix.setsockopt(socket, posix.SOL.SOCKET, posix.SO.RCVTIMEO, mem.asBytes(&timeout));

    const addr = try net.Address.parseIp4(ip_address, 0);

    const start_time = time.milliTimestamp();
    
    _ = try posix.sendto(socket, buffer, 0, &addr.any, addr.getOsSockLen());
    _ = try posix.recvfrom(socket, buffer, 0, null, null);

    const latency = time.milliTimestamp() - start_time;
    return if (latency >= 0 and latency <= TIMEOUT_MS) latency else PingError.Timeout;
}

pub fn main() !void {
    var buffer: [PACKET_SIZE]u8 = undefined;

    var bw = io.bufferedWriter(io.getStdOut().writer());
    const writer = bw.writer();

    createIcmpPacket(&buffer);

    const latency = ping(&buffer, TARGET) catch |err| switch (err) {
        error.Timeout, error.NetworkError => {
            try writer.print("{{\"text\":\"\", \"tooltip\":\"\", \"class\":\"hidden\"}}", .{});
            try bw.flush();
            return;
        },
        else => |e| return e,
    };

    try writer.print("{{\"text\":\"  {d}ms\", \"tooltip\":\"Target: {s}\"}}", .{ latency, TARGET });
    try bw.flush();
}
