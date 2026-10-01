#include <flutter/runtime_effect.glsl>

// A "liquid glass" backdrop filter: refracts/lenses the content behind a
// rounded-rect surface near its edges (like light bending through a thick
// glass rim) and adds a soft moving specular sheen plus a bright edge rim.
// Used as the material for the floating pill nav bar.

uniform vec2 u_size;        // widget size in px
uniform float u_radius;     // corner radius in px
uniform float u_refraction; // refraction band width in px
uniform float u_time;       // seconds, drives the sheen animation
uniform float u_sheen;      // 0..1, sheen animation strength (0 = static)
uniform float u_tint_r;     // premultiplied tint color
uniform float u_tint_g;
uniform float u_tint_b;
uniform float u_tint_a;     // tint mix strength (0..1)

uniform sampler2D u_texture_input;

out vec4 frag_color;

float roundedRectSDF(vec2 p, vec2 halfSize, float r) {
  vec2 q = abs(p) - halfSize + r;
  return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void main() {
  vec2 fragCoord = FlutterFragCoord().xy;
  vec2 halfSize = u_size * 0.5;
  vec2 p = fragCoord - halfSize;

  float dist = roundedRectSDF(p, halfSize, u_radius);

  // Surface normal at this point, via central differences of the SDF.
  float eps = 1.0;
  float dx = roundedRectSDF(p + vec2(eps, 0.0), halfSize, u_radius)
           - roundedRectSDF(p - vec2(eps, 0.0), halfSize, u_radius);
  float dy = roundedRectSDF(p + vec2(0.0, eps), halfSize, u_radius)
           - roundedRectSDF(p - vec2(0.0, eps), halfSize, u_radius);
  vec2 normal = normalize(vec2(dx, dy) + 1e-5);

  // Bend the sample point inward near the edge, like a thick glass rim.
  float edgeBand = smoothstep(0.0, 1.0, clamp(1.0 - (-dist) / u_refraction, 0.0, 1.0));
  vec2 refractOffset = normal * edgeBand * u_refraction;

  vec2 sampleUv = (fragCoord - refractOffset) / u_size;
#ifdef IMPELLER_TARGET_OPENGLES
  sampleUv.y = 1.0 - sampleUv.y;
#endif
  sampleUv = clamp(sampleUv, 0.0, 1.0);

  vec4 backdrop = texture(u_texture_input, sampleUv);

  vec3 tint = vec3(u_tint_r, u_tint_g, u_tint_b);
  vec3 color = mix(backdrop.rgb, tint, u_tint_a);

  // Soft diagonal sheen drifting slowly across the surface.
  float sheenAxis = (p.x + p.y) / (u_size.x + u_size.y);
  float sheen = sin(sheenAxis * 6.2831853 + u_time * 0.6) * 0.5 + 0.5;
  float topFade = smoothstep(-halfSize.y, -halfSize.y * 0.2, p.y)
      * (1.0 - smoothstep(-halfSize.y * 0.2, halfSize.y, p.y));
  color += sheen * topFade * 0.05 * u_sheen;

  // Bright fresnel-like highlight right at the glass edge. Kept narrow and
  // faint on purpose: at a wide band this washes most of a short pill to
  // near-white, and the blurred backdrop stops being visible at all.
  float rim = 1.0 - smoothstep(0.0, u_refraction * 0.6, abs(dist));
  color += rim * 0.06;

  float alphaMask = 1.0 - smoothstep(-1.0, 1.0, dist);
  frag_color = vec4(color * alphaMask, alphaMask);
}
