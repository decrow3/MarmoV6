uniform vec4 Uniform4fParameters;
varying vec2 texCoord;
const float PI = 3.1415926535;
void main(void) {
  float kx = Uniform4fParameters.x;
  float ky = Uniform4fParameters.y;
  float our_sign = Uniform4fParameters.z;
  float contrast = Uniform4fParameters.w;
  float phase = 2.0 * PI * (kx * texCoord.x + ky * texCoord.y);
  float hartley_val = our_sign * (cos(phase) + sin(phase));
  float deviation = hartley_val / 1.41421356;
  float final_gray = 0.5 + contrast * deviation;
  gl_FragColor = vec4(final_gray, final_gray, final_gray, 1.0);
}
