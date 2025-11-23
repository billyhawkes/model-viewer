const std = @import("std");
const cimgui = @import("cimgui");
const sokol = @import("sokol");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const dep_sokol = b.dependency("sokol", .{ .target = target, .optimize = optimize, .with_sokol_imgui = true });
    const dep_shdc = dep_sokol.builder.dependency("shdc", .{});
    const dep_cimgui = b.dependency("cimgui", .{
        .target = target,
        .optimize = optimize,
    });
    const dep_zmath = b.dependency("zalgebra", .{});
    const dep_zgltf = b.dependency("zgltf", .{});

    const shdc_step = try sokol.shdc.createSourceFile(b, .{
        .shdc_dep = dep_shdc,
        .input = "src/shader.glsl",
        .output = "src/shader.zig",
        .slang = .{ .metal_macos = true },
    });

    const cimgui_conf = cimgui.getConfig(true);

    dep_sokol.artifact("sokol_clib").addIncludePath(dep_cimgui.path(cimgui_conf.include_dir));

    const root_module = b.createModule(.{
        .optimize = optimize,
        .target = target,
        .root_source_file = b.path("src/main.zig"),
        .imports = &.{
            .{ .name = "sokol", .module = dep_sokol.module("sokol") },
            .{ .name = cimgui_conf.module_name, .module = dep_cimgui.module(cimgui_conf.module_name) },
            .{ .name = "math", .module = dep_zmath.module("zalgebra") },
            .{ .name = "gltf", .module = dep_zgltf.module("zgltf") },
        },
    });
    const exe = b.addExecutable(.{ .name = "triangle", .root_module = root_module });

    b.installArtifact(exe);

    exe.step.dependOn(shdc_step);

    const run = b.addRunArtifact(exe);
    b.step("run", "Run Triangle").dependOn(&run.step);
}
