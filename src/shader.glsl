@header const Mat4 = @import("math").Mat4
@ctype mat4 Mat4

@vs vs

in vec3 position;

out vec3 color;

layout(binding=0) uniform vs_params {
	mat4 mvp;
};

void main() {
	gl_Position = mvp * vec4(position, 1.0);
	color = vec3(0.5, 1.0, 0.5);
}

@end

@fs fs

in vec3 color;
out vec4 out_color;

void main() {
	out_color = vec4(color, 1.0);
}

@end

@program shader vs fs
