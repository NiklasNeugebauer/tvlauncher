// Launcher: the light value of every cell of the diamond grid, one pixel per cell, for diamonds.frag.
//
// A round spotlight just above the focused tile, plus a faint ambient shimmer, gives every grid cell a light value
// v at its centre. Evaluated here once per cell instead of in every pixel of the cell; v goes out as two 8-bit
// channels (high and low byte), the diamond's size factor pow(v, 0.8) as the third. All lengths are device pixels.

#version 460 core

#include <flutter/runtime_effect.glsl>

precision highp float;

uniform vec2 uFocus;     // spotlight centre (x springs, y follows the tile)
uniform float uTileW;    // focused tile width
uniform float uPulse;    // 1 when focus lands, decaying to 0
uniform float uStrength;
uniform float uTime;     // seconds, for the shimmer
uniform float uGrid;     // cell size
uniform float uAmbient;  // 1 shimmer on, 0 off

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
  vec2 centre = (floor(FlutterFragCoord().xy) + 0.5) * uGrid;
  float v = light(centre);
  float high = floor(v * 255.0);
  fragColor = vec4(high / 255.0, v * 255.0 - high, pow(v, 0.8), 1.0);
}
