const std = @import("std");
const sokol = @import("sokol");
const ig = @import("cimgui_docking");
const simgui = sokol.imgui;
const sg = sokol.gfx;
const sapp = sokol.app;
const sglue = sokol.glue;
const slog = sokol.log;
const shader = @import("shader.zig");
const math = @import("math");
const Gltf = @import("gltf").Gltf;

const Vec3 = math.Vec3;
const Mat4 = math.Mat4;

const allocator = std.heap.page_allocator;

const Vertex = extern struct {
    position: [3]f32,
    normal: [3]f32,
};

const Model = struct {
    transform: Vec3 = Vec3.zero(),
    rotation: Vec3 = Vec3.zero(),
    scale: Vec3 = Vec3.new(1.0, 1.0, 1.0),
    vertices: std.ArrayList(Vertex) = .empty,
    indices: std.ArrayList(u16) = .empty,
};

var state = struct {
    pass_action: sg.PassAction = .{},
    bindings: sg.Bindings = .{},
    pipeline: sg.Pipeline = .{},
    show_first_window: bool = true,
    show_second_window: bool = true,
    model: Model = .{},
    light_position: Vec3 = Vec3.new(2.0, 0.0, 0.0),
}{};

export fn init() void {
    sg.setup(.{
        .environment = sglue.environment(),
        .logger = .{ .func = slog.func },
    });
    simgui.setup(.{
        .logger = .{ .func = slog.func },
    });
    ig.igGetIO().*.ConfigFlags |= ig.ImGuiConfigFlags_DockingEnable;

    state.pass_action.colors[0] = .{
        .load_action = .CLEAR,
        .clear_value = .{ .r = 0.5, .g = 0.5, .b = 1.0, .a = 1.0 },
    };

    state.bindings.vertex_buffers[0] = sg.makeBuffer(.{ .data = sg.asRange(state.model.vertices.items) });
    state.bindings.index_buffer = sg.makeBuffer(.{ .data = sg.asRange(state.model.indices.items), .usage = .{ .index_buffer = true } });

    var layout: sg.VertexLayoutState = .{};
    layout.attrs[shader.ATTR_shader_position].format = sg.VertexFormat.FLOAT3;
    layout.attrs[shader.ATTR_shader_normal].format = sg.VertexFormat.FLOAT3;
    state.pipeline = sg.makePipeline(.{ .shader = sg.makeShader(shader.shaderShaderDesc(sg.queryBackend())), .layout = layout, .index_type = .UINT16, .depth = .{ .compare = .LESS_EQUAL, .write_enabled = true } });
}

export fn frame() void {
    simgui.newFrame(.{
        .width = sapp.width(),
        .height = sapp.height(),
        .delta_time = sapp.frameDuration(),
        .dpi_scale = sapp.dpiScale(),
    });

    //=== UI CODE STARTS HERE
    var open: bool = true;
    ig.igSetNextWindowSize(.{ .x = 400, .y = 100 }, ig.ImGuiCond_Once);
    if (ig.igBegin("Settings", &open, ig.ImGuiWindowFlags_None)) {
        _ = ig.igSliderFloat3("Transform", &state.model.transform.data[0], -10, 10);
        _ = ig.igSliderFloat3("Rotation", &state.model.rotation.data[0], -360, 360);
        _ = ig.igSliderFloat3("Scale", &state.model.scale.data[0], 0, 10);
        _ = ig.igSliderFloat3("Light", &state.light_position.data[0], -10, 10);
    }

    ig.igEnd();
    //=== UI CODE ENDS HERE

    const projection = math.perspective(90.0, sapp.widthf() / sapp.heightf(), 0.1, 100.0);
    const view = math.lookAt(Vec3.new(0.0, 0.0, -2.0), Vec3.zero(), Vec3.new(0.0, 1.0, 0.0));
    var model = Mat4.identity();
    // Scale -> Translation -> Rotation (right to left)
    model = model.scale(state.model.scale);
    model = Mat4.rotate(model, state.model.rotation.x(), Vec3.new(1.0, 0.0, 0.0));
    model = Mat4.rotate(model, state.model.rotation.y(), Vec3.new(0.0, 1.0, 0.0));
    model = Mat4.rotate(model, state.model.rotation.z(), Vec3.new(0.0, 0.0, 1.0));
    model = model.translate(state.model.transform);

    const mvp = Mat4.mul(projection, view.mul(model));

    const vertexParams = shader.VsParams{
        .mvp = mvp,
        .light_position = state.light_position.data,
        .model = model,
    };

    sg.beginPass(.{
        .action = state.pass_action,
        .swapchain = sglue.swapchain(),
    });
    sg.applyPipeline(state.pipeline);
    sg.applyBindings(state.bindings);
    sg.applyUniforms(shader.UB_vs_params, sg.asRange(&vertexParams));
    sg.draw(0, @intCast(state.model.indices.items.len), 1);
    simgui.render();
    sg.endPass();
    sg.commit();
}

export fn cleanup() void {
    simgui.shutdown();
    sg.shutdown();
}

export fn event(ev: [*c]const sapp.Event) void {
    // forward input events to sokol-imgui
    _ = simgui.handleEvent(ev.*);
}

pub fn parseGltf() !void {
    const buffer = try std.fs.cwd().readFileAllocOptions(allocator, "./mesh.gltf", 512_000, null, std.mem.Alignment.@"4", null);
    defer allocator.free(buffer);
    const bin = try std.fs.cwd().readFileAllocOptions(allocator, "./mesh.bin", 5_000_000, null, std.mem.Alignment.@"4", null);
    defer allocator.free(bin);

    var gltf = Gltf.init(allocator);
    defer gltf.deinit();

    try gltf.parse(buffer);

    for (gltf.data.meshes) |mesh| {
        for (mesh.primitives) |primitive| {
            if (primitive.indices) |index| {
                const indiceAccessor = gltf.data.accessors[index];
                const index_slice = try gltf.getDataFromBufferView(u16, allocator, indiceAccessor, bin);
                try state.model.indices.appendSlice(allocator, index_slice);
            }
            for (primitive.attributes) |attribute| {
                switch (attribute) {
                    .position => |index| {
                        const vertexAccessor = gltf.data.accessors[index];
                        var it = vertexAccessor.iterator(f32, &gltf, bin);
                        while (it.next()) |v| {
                            try state.model.vertices.append(allocator, .{
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
                            state.model.vertices.items[i].normal = .{ n[0], n[1], n[2] };
                        }
                    },
                    else => {},
                }
            }
        }
    }
}

pub fn main() !void {
    try parseGltf();

    sapp.run(.{
        .frame_cb = frame,
        .init_cb = init,
        .event_cb = event,
        .cleanup_cb = cleanup,
    });
}
