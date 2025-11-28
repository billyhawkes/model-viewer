const std = @import("std");
const Gltf = @import("gltf").Gltf;
const sokol = @import("sokol");
const sg = sokol.gfx;
const sglue = sokol.glue;
const slog = sokol.log;
const shader = @import("./shader.zig");

const Vertex = extern struct {
    position: [3]f32,
    normal: [3]f32,
};

pub fn parseGltf(allocator: std.mem.Allocator, path: []const u8) !Mesh {
    const gltfPath =
        try std.mem.concat(allocator, u8, &.{ path, ".gltf" });
    const binPath = try std.mem.concat(allocator, u8, &.{ path, ".bin" });

    const buffer = try std.fs.cwd().readFileAllocOptions(allocator, gltfPath, 512_000, null, std.mem.Alignment.@"4", null);
    defer allocator.free(buffer);
    const bin = try std.fs.cwd().readFileAllocOptions(allocator, binPath, 5_000_000, null, std.mem.Alignment.@"4", null);
    defer allocator.free(bin);

    var parsedMesh: Mesh = .{};

    var gltf = Gltf.init(allocator);
    defer gltf.deinit();

    try gltf.parse(buffer);

    for (gltf.data.meshes) |mesh| {
        for (mesh.primitives) |primitive| {
            if (primitive.indices) |index| {
                const indiceAccessor = gltf.data.accessors[index];
                const index_slice = try gltf.getDataFromBufferView(u16, allocator, indiceAccessor, bin);
                try parsedMesh.indices.appendSlice(allocator, index_slice);
            }
            for (primitive.attributes) |attribute| {
                switch (attribute) {
                    .position => |index| {
                        const vertexAccessor = gltf.data.accessors[index];
                        var it = vertexAccessor.iterator(f32, &gltf, bin);
                        while (it.next()) |v| {
                            try parsedMesh.vertices.append(allocator, .{
                                .position = .{ v[0], v[1], v[2] },
                                .normal = .{ 0.0, 0.0, 0.0 },
                            });
                        }
                    },
                    .normal => |index| {
                        const normalAccessor = gltf.data.accessors[index];
                        var it = normalAccessor.iterator(f32, &gltf, bin);
                        var i: u32 = 0;
                        while (it.next()) |n| : (i += 1) {
                            parsedMesh.vertices.items[i].normal = .{ n[0], n[1], n[2] };
                        }
                    },
                    else => {},
                }
            }
        }
    }

    return parsedMesh;
}

pub const Mesh = struct {
    vertices: std.ArrayList(Vertex) = .empty,
    indices: std.ArrayList(u16) = .empty,

    pub fn parse(allocator: std.mem.Allocator, path: []const u8) !Mesh {
        return try parseGltf(allocator, path);
    }
};

pub const Renderer = struct {
    passAction: sg.PassAction = .{},
    bindings: sg.Bindings = .{},
    pipeline: sg.Pipeline = .{},
    mesh: *Mesh = undefined,

    pub fn init() Renderer {
        var renderer = Renderer{};
        sg.setup(.{
            .environment = sglue.environment(),
            .logger = .{ .func = slog.func },
        });

        renderer.passAction.colors[0] = .{
            .load_action = .CLEAR,
            .clear_value = .{ .r = 0.5, .g = 0.5, .b = 1.0, .a = 1.0 },
        };

        var layout: sg.VertexLayoutState = .{};
        layout.attrs[shader.ATTR_shader_position].format = sg.VertexFormat.FLOAT3;
        layout.attrs[shader.ATTR_shader_normal].format = sg.VertexFormat.FLOAT3;
        renderer.pipeline = sg.makePipeline(.{
            .shader = sg.makeShader(shader.shaderShaderDesc(sg.queryBackend())),
            .layout = layout,
            .index_type = .UINT16,
            .depth = .{
                .compare = .LESS_EQUAL,
                .write_enabled = true,
            },
        });

        return renderer;
    }

    pub fn submit(self: *Renderer, mesh: *Mesh) void {
        self.mesh = mesh;
        self.bindings.vertex_buffers[0] = sg.makeBuffer(.{ .data = sg.asRange(self.mesh.vertices.items) });
        self.bindings.index_buffer = sg.makeBuffer(.{ .data = sg.asRange(self.mesh.indices.items), .usage = .{ .index_buffer = true } });
    }

    pub fn beginScene(self: *Renderer) void {
        sg.beginPass(.{
            .action = self.passAction,
            .swapchain = sglue.swapchain(),
        });
    }

    pub fn render(self: *Renderer, vertexParams: shader.VsParams) void {
        sg.applyPipeline(self.pipeline);
        sg.applyBindings(self.bindings);
        sg.applyUniforms(shader.UB_vs_params, sg.asRange(&vertexParams));
        sg.draw(0, @intCast(self.mesh.indices.items.len), 1);
    }

    pub fn endScene(_: *Renderer) void {
        sg.endPass();
        sg.commit();
    }
};
