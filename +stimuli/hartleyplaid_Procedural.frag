uniform float kx;
uniform float ky;
uniform float signVal;
uniform float amplitude;
varying vec2 uv;
const float PI = 3.1415926535;
void main(void) {
  float phase = 2.0 * PI * (kx * uv.x + ky * uv.y);
  float cas = (cos(phase) + sin(phase)) * 0.7071067811865476;
  float dev = amplitude * signVal * cas;
  gl_FragColor = vec4(dev, dev, dev, 1.0);
}
