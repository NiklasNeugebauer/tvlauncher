// FLauncher: the focus-lit diamond background.
//
// A grid of small squares on a flat ground. A round spotlight just above the focused tile, plus a faint ambient
// shimmer, gives every grid cell a light value v; the cell's square grows and turns toward a diamond with v, and
// takes the light colour in four steps. Cells below 0.09 stay ground. All lengths are device pixels, so the grid
// and the shimmer keep their size at any pixel ratio.

#version 460 core

#include <flutter/runtime_effect.glsl>

precision highp float;

uniform float uDpr;
uniform vec2 uFocus;     // spotlight centre (x springs, y follows the tile)
uniform float uTileW;    // focused tile width
uniform float uPulse;    // 1 when focus lands, decaying to 0
uniform float uStrength;
uniform float uTime;     // seconds, for the shimmer
uniform float uGrid;     // cell size
uniform float uWarm;     // scales the colour step: 0.82 keeps warm light soft, 1 for app colour
uniform float uAmbient;  // 1 shimmer on, 0 off
uniform vec3 uGround;
uniform vec3 uBase;      // an unlit diamond
uniform vec3 uLight;

out vec4 fragColor;

float light(vec2 p) {
  vec2 c = vec2(uFocus.x, uFocus.y - uTileW * 0.3);
  float r = uTileW * (1.55 + 0.25 * uPulse);
  vec2 d = p - c;
  float d2 = dot(d, d) / (r * r);
  float spot = exp(-d2 * 1.6) * (0.9 + 0.3 * uPulse) + exp(-d2 * 0.45) * 0.22;
  float amb = uAmbient * (0.07 + 0.05 * sin(p.x * 0.021 + uTime * 0.7) * sin(p.y * 0.017 - uTime * 0.5));
  return min(1.0, (spot + amb) * uStrength);
}

void main() {
  vec2 p = FlutterFragCoord().xy * uDpr;
  vec2 centre = (floor(p / uGrid) + 0.5) * uGrid;
  float v = light(centre);
  vec3 colour = uGround;
  if (v >= 0.09) {
    // A square with half-diagonal r, rotated by up to 45 degrees.
    float r = uGrid * 0.5 * pow(v, 0.8);
    float angle = v * 0.78539816;
    float cs = cos(angle);
    float sn = sin(angle);
    vec2 q = p - centre;
    vec2 local = vec2(cs * q.x + sn * q.y, -sn * q.x + cs * q.y);
    float inside = clamp(0.5 - (max(abs(local.x), abs(local.y)) - r * 0.70710678), 0.0, 1.0);
    float level = (min(floor(v * 4.0), 3.0) + 0.5) / 4.0;
    vec3 fill = mix(uBase, uLight, level * uWarm);
    colour = mix(colour, fill, (0.45 + 0.5 * level) * inside);
  }
  fragColor = vec4(colour, 1.0);
}
