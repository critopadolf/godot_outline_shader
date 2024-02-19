
shader_type spatial;
#include "noise.gdshaderinc"
uniform sampler2D DEPTH_TEXTURE : source_color, hint_depth_texture;
uniform sampler2D NORMAL_TEXTURE : source_color, hint_normal_roughness_texture;
uniform sampler2D SCREEN_TEXTURE : source_color, hint_screen_texture;

varying mat4 CAMERA;
void vertex() {
  POSITION = vec4(VERTEX, 1.0);
  CAMERA = INV_VIEW_MATRIX;
}

vec3 getNDC(sampler2D sampler, vec2 coords)
{
	float depth = texture(sampler, coords).x;
	vec3 ndc = vec3(coords * 2.0 - 1.0, depth);
	return ndc;
}

float getLinearDepth(sampler2D sampler, vec2 coords, mat4 ipm)
{	
	vec3 ndc = getNDC(sampler, coords);
	vec4 view = ipm * vec4(ndc, 1.0);
	view.xyz /= view.w;
	float linear_depth = -view.z;
	return linear_depth;
}

vec3 getWorldPos(sampler2D sampler, vec2 coords, mat4 ipm)
{
	vec3 ndc = getNDC(sampler, coords);
	vec4 world = CAMERA * ipm * vec4(ndc, 1.0);
    vec3 world_position = world.xyz / world.w;
	return world_position;
}

vec3 gaussian5x5( sampler2D tex, vec2 uv, vec2 pix_size )
{
	vec3 p = vec3( 0.0, 0.0, 0.0 );
	float coef[25] = { 0.00390625, 0.015625, 0.0234375, 0.015625, 0.00390625, 0.015625, 0.0625, 0.09375, 0.0625, 0.015625, 0.0234375, 0.09375, 0.140625, 0.09375, 0.0234375, 0.015625, 0.0625, 0.09375, 0.0625, 0.015625, 0.00390625, 0.015625, 0.0234375, 0.015625, 0.00390625 };

	for( int y=-2; y<=2; y++ ) {
		for( int x=-2; x<=2; x ++ ) {
			p += ( texture( tex, uv + vec2( float( x ), float( y ) ) * pix_size ).rgb ) * coef[(y+2)*5 + (x+2)];
		}
	}

	return p;
}

void fragment() {
	vec4 color = texture(SCREEN_TEXTURE, SCREEN_UV);
	
	vec2 SCREEN_PIXEL_SIZE = 1.0/VIEWPORT_SIZE;
	float[9] sobel = {1.,0.,-1., 
					  2.,0.,-2., 
					  1.,0.,-1.};
	
	float depth_sobel_x = 0.;
	float depth_sobel_y = 0.;
	float norm_sobel_x = 0.;
	float norm_sobel_y = 0.;
	float alpha_sobel_x = 0.;
	float alpha_sobel_y = 0.;
	vec4 at_normal = texture(NORMAL_TEXTURE, SCREEN_UV); 
	for(int i = 0; i < 3; i++)
	{
		for(int j = 0; j < 3; j+=2) // skip zeros in sobel matrix (sparse conv)
		{
			vec2 sample_uv = SCREEN_UV + vec2(float(i-1),float(j-1)) * SCREEN_PIXEL_SIZE;
			float d = getLinearDepth(DEPTH_TEXTURE, sample_uv, INV_PROJECTION_MATRIX);
			vec4 n = texture(NORMAL_TEXTURE, sample_uv); 
			float a = texture(SCREEN_TEXTURE, sample_uv).a;
			n.xyz = gaussian5x5( NORMAL_TEXTURE, sample_uv, SCREEN_PIXEL_SIZE );
			float norm_dist = length(n-at_normal);
			
			float s = sobel[i*3+j]; 
			float st = sobel[3*j+i];

			depth_sobel_x += s * d;
			depth_sobel_y += st * d; 
			norm_sobel_x += s * norm_dist;
			norm_sobel_y += st * norm_dist;
			alpha_sobel_x += s * a;
			alpha_sobel_y += st * a;
		}
	}
	depth_sobel_x = max(depth_sobel_x, depth_sobel_y);
	norm_sobel_x = max(norm_sobel_x, norm_sobel_y);
	depth_sobel_x = max(depth_sobel_x, norm_sobel_x);
	
	depth_sobel_x = max(depth_sobel_x, alpha_sobel_x);
	depth_sobel_x = max(depth_sobel_x, alpha_sobel_y);

	vec3 world_pos = getWorldPos(DEPTH_TEXTURE, SCREEN_UV, INV_PROJECTION_MATRIX);

	int is_outline = int(depth_sobel_x > 0.4);
	vec3 gradient;
	float noise_sample = snoise(world_pos*10.+0.3*TIME, gradient);
	ALBEDO = vec3(gradient)*vec3(ivec3(255*is_outline));//vec3(ivec3(255*is_outline));//*world_pos;//+color.rgb;
	
	ALPHA = color.a;
}
