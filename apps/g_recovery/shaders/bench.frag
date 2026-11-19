// Graphics test scene. Each pixel iterates a moving complex map uIters times,
// so the work per frame is pixels x uIters and the frame rate it holds tells
// how much work the graphics chip does per second.
#version 460 core

#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uTime;
uniform float uIters;
uniform vec3 uBase;
uniform vec3 uTint;

out vec4 fragColor;

void main() {
  vec2 p = (FlutterFragCoord().xy - 0.5 * uSize) / uSize.y * 2.2;
  vec2 c = vec2(sin(uTime * 0.31) * 0.72, cos(uTime * 0.23) * 0.38);
  vec2 z = p;
  float glow = 0.0;
  for (int i = 0; i < 2048; i++) {
    if (float(i) >= uIters) {
      break;
    }
    z = vec2(z.x * z.x - z.y * z.y, 2.0 * z.x * z.y) + c;
    float d = dot(z, z);
    glow += exp(-d * 3.0);
    if (d > 16.0) {
      z *= 0.25;
    }
  }
  float v = clamp(glow / max(uIters, 1.0) * 6.0, 0.0, 1.0);
  fragColor = vec4(mix(uBase, uTint, v * 0.55), 1.0);
}
