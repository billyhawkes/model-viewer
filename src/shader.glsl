@header const Mat4 = @import("math").Mat4
@ctype mat4 Mat4

@vs vs

in vec3 position;
in vec3 normal;

out vec3 _color;
out vec3 _light_position;
out vec3 fragment_position;
out vec3 _normal;

layout(binding=0) uniform vs_params {
	mat4 mvp;
	mat4 model;
	vec3 light_position;
};

void main() {
	gl_Position = mvp * vec4(position, 1.0);
	_color = vec3(0.5, 1.0, 0.5);
	_light_position = light_position;
	fragment_position = vec3(model * vec4(position, 1.0));
	_normal = mat3(transpose(inverse(model))) * normal;  
}

@end

@fs fs

in vec3 _color;
in vec3 _light_position;
in vec3 fragment_position;
in vec3 _normal;

out vec4 out_color;

void main() {
	vec3 light_color = vec3(1.0, 1.0, 1.0);

	// Ambient
	vec3 ambient = vec3(0.2, 0.2, 0.2);

	// Diffuse
	vec3 light_direction =  normalize(_light_position - fragment_position);
	vec3 diffuse = max(dot(light_direction, normalize(_normal)), 0.0) * light_color;

	// Specular
	vec3 view_direction = normalize(vec3(0.0, 0.0, -2.0) - fragment_position);
	vec3 reflect_direction = reflect(-light_direction, _normal);
	float spec = pow(max(dot(view_direction, reflect_direction), 0.0), 32);
	vec3 specular = 0.5 * spec * light_color;

	vec3 lighting = ambient + diffuse + specular;

	out_color = vec4(_color * lighting, 1.0);
}

@end

@program shader vs fs
