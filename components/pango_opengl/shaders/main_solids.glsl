@start vertex
#version 150 core

out vec2 v_tex;

const vec2 pos[4] = vec2[4](
  vec2( -1.0, +1.0), vec2( -1.0, -1.0),
  vec2( +1.0, +1.0), vec2( +1.0, -1.0)
);

void main()
{
  gl_Position = vec4(pos[gl_VertexID], 0.0, 1.0);
  v_tex = (pos[gl_VertexID] * vec2(1.0,-1.0) + vec2(1.0)) / 2.0;
}

@start fragment
#version 150 core

#include </components/pango_opengl/shaders/utils.glsl.h>
#include </components/pango_opengl/shaders/camera.glsl.h>
#include </components/pango_opengl/shaders/geom.glsl.h>
#include </components/pango_opengl/shaders/grid.glsl.h>

in vec2 v_tex;
out vec4 color;

uniform mat3 kinv;
uniform mat4 world_from_cam;
uniform vec2 image_size;
uniform vec2 znear_zfar;

vec4 color_sky = vec4(1.0,1.0,1.0,1.0);

// Sphere occlusion
float sphOcclusion( in vec3 pos, in vec3 nor, in vec4 sph )
{
    vec3  di = sph.xyz - pos;
    float l  = length(di);
    float nl = dot(nor,di/l);
    float h  = l/sph.w;
    float h2 = h*h;
    float k2 = 1.0 - h2*nl*nl;

    // above/below horizon
    // EXACT: Quilez - https://iquilezles.org/articles/sphereao
    float res = max(0.0,nl)/h2;

    // intersecting horizon
    if( k2 > 0.001 ) {
      // EXACT : Lagarde/de Rousiers - https://seblagarde.files.wordpress.com/2015/07/course_notes_moving_frostbite_to_pbr_v32.pdf
      res = nl*acos(-nl*sqrt( (h2-1.0)/(1.0-nl*nl) )) - sqrt(k2*(h2-1.0));
      res = res/h2 + atan( sqrt(k2/(h2-1.0)));
      res /= 3.141593;
    }
    return res;
}

vec4 xGround(vec3 c_w, vec3 dir_w)
{
  return vec4( intersectRayPlaneZ0(c_w, dir_w), vec3(0.0, 0.0, 1.0) );
}

vec4 xSphere(vec3 c_w, vec3 dir_w, vec4 sphere_w)
{
	vec3 oc = c_w - sphere_w.xyz;
	float b = dot( oc, dir_w );
	float c = dot( oc, oc ) - sphere_w.w * sphere_w.w;
	float h = b*b - c;
  float depth = h>=0.0 ? (-b - sqrt(h)) : -1;
	return vec4(depth, normalize(oc + depth * dir_w) );
}

void updateDepthNormal(
  inout vec4 albedo,  inout vec4 dnorm,
  vec4 sample_albedo, vec4 sample_dnorm
) {
  if (sample_dnorm.x >= 0 && sample_dnorm.x < dnorm.x) {
    dnorm = sample_dnorm;
    albedo = sample_albedo;
  }
}

vec4 material(vec4 albedo, vec4 depth_normal)
{
  return vec4(vec3(albedo), 1.0);

  // return vec4(depth_normal.yzw, 1.0);
}

vec4 sp1 = vec4(1.0,1.0,1.0,0.8);
vec4 sp2 = vec4(3.0,3.0,2.0,1.5);

void main()
{
  mat3 w_R_c = mat3(world_from_cam);
  vec3 c_w = world_from_cam[3].xyz;

  vec2 pixel = getCameraPixelCoord(image_size, v_tex);
  vec3 dir_c = normalize(unproj(kinv, pixel));
  vec3 dir_w = w_R_c * dir_c;

  vec4 albedo = color_sky;
  vec4 depth_normal = vec4(znear_zfar.y, 0, 0, 0);

  vec4 depth_normal_ground = xGround(c_w, dir_w);
  vec4 depth_normal_sp1 = xSphere(c_w, dir_w, sp1);
  vec4 depth_normal_sp2 = xSphere(c_w, dir_w, sp2);

  vec3 ground_pos = c_w + dir_w * depth_normal_ground.x;
  vec4 albedo_ground =
    vec4(0.8+0.2*vec3(checkerFilteredFaded(ground_pos.xy, depth_normal_ground.x, 50.0)),1.0) *
    (1.0 - sphOcclusion(ground_pos, depth_normal_ground.yzw, sp1)) *
    (1.0 - sphOcclusion(ground_pos, depth_normal_ground.yzw, sp2));

  vec4 albedo_sp1 = vec4(vec3(0.6 + 0.4 * depth_normal_sp1.yzw.z), 1.0);
  vec4 albedo_sp2 = vec4(vec3(0.6 + 0.4 * depth_normal_sp2.yzw.z), 1.0);

  updateDepthNormal(albedo, depth_normal, albedo_ground, depth_normal_ground );
  updateDepthNormal(albedo, depth_normal, albedo_sp1, depth_normal_sp1);
  updateDepthNormal(albedo, depth_normal, albedo_sp2, depth_normal_sp2);

  color = material(albedo, depth_normal);
  gl_FragDepth = fragDepthFromSceneDepth(depth_normal.x, znear_zfar.x, znear_zfar.y);
}