/**
 * The orb's shaders, ported line for line from the Metal source in the Mac's `OrbRenderer.swift`, so the
 * sphere, the thinking knot, the syllable rings and the seal look the same on every desktop.
 */
export const ORB_VERTEX = `#version 300 es
precision highp float;
uniform float uCount, uTime, uLevel, uSwirl, uHold, uAspect, uScale, uBurst, uJitter, uDrain, uPull, uGlow, uBounce, uKnot, uSeal;
uniform vec4 uRingHeights, uRingFades;
out vec4 vColor;
out float vSpark;

float hash(vec3 p) {
  p = fract(p * 0.3183099 + 0.1);
  p *= 17.0;
  return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 x) {
  vec3 i = floor(x);
  vec3 f = fract(x);
  f = f * f * (3.0 - 2.0 * f);
  return mix(mix(mix(hash(i + vec3(0,0,0)), hash(i + vec3(1,0,0)), f.x),
                 mix(hash(i + vec3(0,1,0)), hash(i + vec3(1,1,0)), f.x), f.y),
             mix(mix(hash(i + vec3(0,0,1)), hash(i + vec3(1,0,1)), f.x),
                 mix(hash(i + vec3(0,1,1)), hash(i + vec3(1,1,1)), f.x), f.y), f.z);
}

void main() {
  float i = float(gl_VertexID) + 0.5;
  float share = i / uCount;
  float phi = acos(1.0 - 2.0 * share);
  float theta = 3.14159265 * (1.0 + sqrt(5.0)) * i;
  vec3 p = vec3(cos(theta) * sin(phi), sin(theta) * sin(phi), cos(phi));
  float tau = 6.2831853;

  float spin = uTime * (0.12 + 0.5 * uSwirl);
  mat3 turn = mat3(vec3(cos(spin), 0, -sin(spin)), vec3(0, 1, 0), vec3(sin(spin), 0, cos(spin)));
  float tilt = 0.35;
  mat3 lean = mat3(vec3(1, 0, 0), vec3(0, cos(tilt), sin(tilt)), vec3(0, -sin(tilt), cos(tilt)));
  p = lean * (turn * p);

  float around = share * tau * 3.0 + uTime * 0.57;
  float braid = share * tau * 8.0 - uTime * 0.48;
  float tube = 0.71 + 0.21 * cos(braid) + 0.12 * sin(theta);
  float lift = 0.34 * sin(braid) + 0.09 * cos(phi);
  vec3 knot = vec3(tube * cos(around), lift * 0.77 - tube * sin(around) * 0.52, lift * 0.52 + tube * sin(around) * 0.77);
  p = mix(p, knot, uKnot);

  vec4 reach = (p.y - uRingHeights) / 0.15;
  float lit = min(1.0, dot(exp(-reach * reach), uRingFades));

  float wobble = noise(p * 2.3 + vec3(0, 0, uTime * 0.5)) - 0.5;
  float breathe = 0.025 * sin(uTime * 1.2);
  float fling = 0.25 + 0.75 * hash(vec3(i * 0.0131, i * 0.0071, i * 0.0113));
  float radius = 1.0 + breathe + wobble * (0.06 + 0.45 * uLevel) - 0.14 * uHold + 0.3 * uBurst * fling - 0.2 * uPull + 0.04 * lit;
  p *= radius;
  float beat = fract(uTime * 7.0) * 31.0;
  vec3 shiver = vec3(hash(p + beat), hash(p.yzx + beat * 1.3), hash(p.zxy + beat * 1.7)) - 0.5;
  p += shiver * 0.12 * uJitter;

  float ringShare = 0.65;
  vec3 seal;
  if (share < ringShare) {
    float q = share / ringShare * tau;
    float r = 0.9 + 0.047 * sin(theta);
    seal = vec3(cos(q) * r, sin(q) * r, 0.04 * sin(theta));
  } else {
    float q = (share - ringShare) / (1.0 - ringShare);
    vec2 corner = vec2(-0.12, -0.3);
    vec2 mark = q < 0.38 ? mix(vec2(-0.42, 0.0), corner, q / 0.38) : mix(corner, vec2(0.48, 0.4), (q - 0.38) / 0.62);
    seal = vec3(mark + 0.03 * vec2(sin(theta), cos(theta)), 0.0);
  }
  p = mix(p, seal, uSeal);

  float depth = p.z + 3.2;
  float hop = 0.08 * uBounce * abs(sin(uTime * 3.4));
  gl_Position = vec4(p.x * 2.1 / depth / max(uAspect, 0.01), p.y * 2.1 / depth + hop, 0.5, 1.0);
  float front = clamp((p.z + 1.2) / 2.4, 0.0, 1.0);
  vec3 sky = vec3(0.55, 0.80, 1.0);
  vec3 primary = vec3(0.118, 0.525, 0.933);
  vec3 deep = vec3(0.06, 0.28, 0.78);
  float shade = clamp(0.5 - p.y * 0.5 + wobble, 0.0, 1.0);
  vec3 tint = mix(mix(sky, primary, clamp(shade * 2.0, 0.0, 1.0)), deep, clamp(shade * 2.0 - 1.0, 0.0, 1.0));
  tint = mix(tint, vec3(1.0), 0.55 * uGlow);
  float grey = dot(tint, vec3(0.299, 0.587, 0.114));
  tint = mix(tint, vec3(grey) * 0.7, 0.85 * uDrain);
  vColor = vec4(tint, min(1.0, mix(0.32, 1.0, front) + lit));
  gl_PointSize = (1.8 + 2.4 * front) * (1.0 + 0.5 * lit) * uScale;
  vSpark = (max(0.0, front - 0.6) * 0.9 + 0.6 * lit) * (1.0 - uDrain);
}`;

export const ORB_FRAGMENT = `#version 300 es
precision highp float;
in vec4 vColor;
in float vSpark;
out vec4 outColor;

void main() {
  float d = length(gl_PointCoord - 0.5);
  float glow = smoothstep(0.5, 0.0, d);
  float core = 1.0 - smoothstep(0.06, 0.12, d);
  float a = glow * vColor.a;
  float s = core * vSpark;
  outColor = vec4(vColor.rgb * a + s, a + s);
}`;
