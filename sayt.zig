const std = @import("std");
const builtin = @import("builtin");

const DEFAULT_VERSION = "v0.0.7";
const MISE_VERSION = "v2025.11.11";
const MISE_URL_BASE = "https://github.com/jdx/mise/releases/download/" ++ MISE_VERSION ++ "/mise-" ++ MISE_VERSION ++ "-";


fn getEnvVar(alloc: std.mem.Allocator, key: []const u8) ?[]const u8 {
    return std.process.getEnvVarOwned(alloc, key) catch null;
}

fn getCacheDir(alloc: std.mem.Allocator) ![]const u8 {
    if (builtin.os.tag == .windows) {
        if (getEnvVar(alloc, "LOCALAPPDATA")) |v| {
            defer alloc.free(v);
            return std.fs.path.join(alloc, &.{ v, "sayt" });
        }
        return alloc.dupe(u8, "C:\\Temp\\sayt");
    }
    if (builtin.os.tag == .macos) {
        if (getEnvVar(alloc, "HOME")) |v| {
            defer alloc.free(v);
            return std.fs.path.join(alloc, &.{ v, "Library", "Caches", "sayt" });
        }
        return alloc.dupe(u8, "/tmp/sayt");
    }
    if (getEnvVar(alloc, "XDG_CACHE_HOME")) |v| {
        defer alloc.free(v);
        return std.fs.path.join(alloc, &.{ v, "sayt" });
    }
    if (getEnvVar(alloc, "HOME")) |v| {
        defer alloc.free(v);
        return std.fs.path.join(alloc, &.{ v, ".cache", "sayt" });
    }
    return alloc.dupe(u8, "/tmp/sayt");
}

fn getMiseUrl(alloc: std.mem.Allocator) ![]const u8 {
    const os = switch (builtin.os.tag) {
        .windows => "windows",
        .macos => "macos",
        else => "linux",
    };
    const arch = switch (builtin.cpu.arch) {
        .aarch64 => "arm64",
        .arm => "armv7",
        else => "x64",
    };
    const suffix: []const u8 = if (builtin.os.tag == .linux) "-musl" else "";
    return std.fmt.allocPrint(alloc, MISE_URL_BASE ++ "{s}-{s}{s}", .{ os, arch, suffix });
}

fn fileExists(path: []const u8) bool {
    std.fs.cwd().access(path, .{}) catch return false;
    return true;
}

fn normalizeVersion(alloc: std.mem.Allocator, raw: []const u8) ![]const u8 {
    if (std.mem.eql(u8, raw, "latest")) {
        return alloc.dupe(u8, raw);
    }
    if (raw.len > 0 and raw[0] != 'v') {
        return std.fmt.allocPrint(alloc, "v{s}", .{raw});
    }
    return alloc.dupe(u8, raw);
}

fn releaseUrlBase(alloc: std.mem.Allocator, version: []const u8) ![]const u8 {
    if (std.mem.eql(u8, version, "latest")) {
        return alloc.dupe(u8, "https://github.com/bonitao/sayt/releases/latest/download/");
    }
    return std.fmt.allocPrint(alloc, "https://github.com/bonitao/sayt/releases/download/{s}/", .{version});
}

fn fullDistStub(alloc: std.mem.Allocator, version: []const u8, url_base: []const u8) ![]const u8 {
    return std.fmt.allocPrint(
        alloc,
        \\version = "{s}"
        \\bin = "sayt"
        \\
        \\[platforms.linux-amd64]
        \\url = "{s}sayt-linux-x64.tar.gz"
        \\
        \\[platforms.linux-arm64]
        \\url = "{s}sayt-linux-arm64.tar.gz"
        \\
        \\[platforms.linux-armv7]
        \\url = "{s}sayt-linux-armv7.tar.gz"
        \\
        \\[platforms.darwin-amd64]
        \\url = "{s}sayt-macos-x64.tar.gz"
        \\
        \\[platforms.darwin-arm64]
        \\url = "{s}sayt-macos-arm64.tar.gz"
        \\
        \\[platforms.windows-amd64]
        \\url = "{s}sayt-windows-x64.zip"
        \\bin = "sayt.exe"
        \\
        \\[platforms.windows-arm64]
        \\url = "{s}sayt-windows-arm64.zip"
        \\bin = "sayt.exe"
        \\
    ,
        .{ version, url_base, url_base, url_base, url_base, url_base, url_base, url_base },
    );
}

fn writeFile(path: []const u8, contents: []const u8) !void {
    const file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(contents);
}

fn downloadFile(alloc: std.mem.Allocator, url: []const u8, dest: []const u8) !void {
    var client = std.http.Client{ .allocator = alloc };
    defer client.deinit();

    var buf: [8192]u8 = undefined;
    var req = try client.open(.GET, try std.Uri.parse(url), .{ .server_header_buffer = &buf });
    defer req.deinit();

    try req.send();
    try req.wait();

    if (req.response.status != .ok) return error.HttpError;

    const body = try req.reader().readAllAlloc(alloc, 50 * 1024 * 1024);
    defer alloc.free(body);

    const file = try std.fs.cwd().createFile(dest, .{});
    defer file.close();
    try file.writeAll(body);
    if (builtin.os.tag != .windows) try file.chmod(0o755);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();

    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);

    const cache = try getCacheDir(alloc);
    defer alloc.free(cache);

    const mise_dir = try std.fs.path.join(alloc, &.{ cache, "mise-" ++ MISE_VERSION });
    defer alloc.free(mise_dir);
    std.fs.cwd().makePath(mise_dir) catch {};

    const mise_bin = try std.fs.path.join(alloc, &.{ mise_dir, if (builtin.os.tag == .windows) "mise.exe" else "mise" });
    defer alloc.free(mise_bin);

    if (!fileExists(mise_bin)) {
        const url = try getMiseUrl(alloc);
        defer alloc.free(url);
        try downloadFile(alloc, url, mise_bin);
    }

    const env_ver = getEnvVar(alloc, "SAYT_VERSION");
    defer if (env_ver) |v| alloc.free(v);
    const raw_ver = env_ver orelse DEFAULT_VERSION;
    const ver = try normalizeVersion(alloc, raw_ver);
    defer alloc.free(ver);
    const url_base = try releaseUrlBase(alloc, ver);
    defer alloc.free(url_base);

    // Check for colocated scripts
    var exe_buf: [4096]u8 = undefined;
    const exe_path = std.fs.selfExePath(&exe_buf) catch "";
    const exe_dir = std.fs.path.dirname(exe_path) orelse ".";
    var install_dir = exe_dir;
    var found_local = false;

    const local_sayt_nu = try std.fs.path.join(alloc, &.{ install_dir, "sayt.nu" });
    defer alloc.free(local_sayt_nu);
    if (fileExists(local_sayt_nu)) {
        found_local = true;
    } else {
        const parent_dir = std.fs.path.dirname(exe_dir) orelse exe_dir;
        if (!std.mem.eql(u8, parent_dir, exe_dir)) {
            const parent_sayt_nu = try std.fs.path.join(alloc, &.{ parent_dir, "sayt.nu" });
            defer alloc.free(parent_sayt_nu);
            if (fileExists(parent_sayt_nu)) {
                install_dir = parent_dir;
                found_local = true;
            }
        }
    }

    var child_args = std.ArrayList([]const u8).init(alloc);
    defer child_args.deinit();
    try child_args.append(mise_bin);

    if (found_local) {
        const nu_toml = try std.fs.path.join(alloc, &.{ install_dir, "nu.toml" });
        const sayt_nu = try std.fs.path.join(alloc, &.{ install_dir, "sayt.nu" });
        try child_args.appendSlice(&.{ "tool-stub", nu_toml, sayt_nu });
    } else {
        const stub_name = try std.fmt.allocPrint(alloc, "sayt-full-{s}.toml", .{ver});
        const stub_path = try std.fs.path.join(alloc, &.{ cache, stub_name });
        if (!fileExists(stub_path)) {
            const stub = try fullDistStub(alloc, ver, url_base);
            defer alloc.free(stub);
            try writeFile(stub_path, stub);
        }
        try child_args.appendSlice(&.{ "tool-stub", stub_path });
    }

    for (args[1..]) |a| try child_args.append(a);

    var child = std.process.Child.init(child_args.items, alloc);
    child.stdin_behavior = .Inherit;
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;
    _ = try child.spawnAndWait();
}
