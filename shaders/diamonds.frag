// Launcher: the focus-lit diamond background.
//
// A grid of small squares on a flat ground. Every grid cell has a light value v (diamond_light.frag, from the
// spotlight above the focused tile and the ambient shimmer); the cell's square grows and turns toward a diamond
// with v, and takes the light colour in four steps. Cells below 0.09 stay ground. All lengths are device pixels,
// so the grid and the shimmer keep their size at any pixel ratio.

#version 460 core

#include <flutter/runtime_effect.glsl>

precision highp float;

uniform float uDpr;
uniform float uGrid;     // cell size
uniform vec2 uCells;     // columns and rows of the grid
uniform float uWarm;     // scales the colour step: 0.82 keeps warm light soft, 1 for app colour
uniform vec3 uGround;
uniform vec3 uBase;      // an unlit diamond
uniform vec3 uLight;
uniform float uDim;      // brightness of the whole background, 1 for full
uniform sampler2D uCellLight;  // v of every cell from diamond_light.frag (high and low byte) and pow(v, 0.8)

out vec4 fragColor;

void main() {
  vec2 p = FlutterFragCoord().xy * uDpr;
  vec2 cell = floor(p / uGrid);
  vec2 centre = (cell + 0.5) * uGrid;
  vec4 texel = texture(uCellLight, (cell + 0.5) / uCells);
  float v = texel.r + texel.g / 255.0;
  vec3 colour = uGround;
  if (v >= 0.09) {
    // A square with half-diagonal r, rotated by up to 45 degrees.
    float r = uGrid * 0.5 * texel.b;
    // cos and sin of up to 45 degrees as Taylor polynomials (error below 3e-4): plain multiply-adds instead of
    // the GPU's slow transcendental unit, in every lit pixel.
    float a = v * 0.78539816;
    float a2 = a * a;
    float cs = 1.0 - a2 * (0.5 - a2 * (1.0 / 24.0 - a2 / 720.0));
    float sn = a * (1.0 - a2 * (1.0 / 6.0 - a2 / 120.0));
    vec2 q = p - centre;
    vec2 local = vec2(cs * q.x + sn * q.y, -sn * q.x + cs * q.y);
    float inside = clamp(0.5 - (max(abs(local.x), abs(local.y)) - r * 0.70710678), 0.0, 1.0);
    float level = (min(floor(v * 4.0), 3.0) + 0.5) / 4.0;
    vec3 fill = mix(uBase, uLight, level * uWarm);
    colour = mix(colour, fill, (0.45 + 0.5 * level) * inside);
  }
  fragColor = vec4(colour * uDim, 1.0);
}
