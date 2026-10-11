/*
Hartley Stimulus Shader (Final Version)
- Reads spatial coordinates from a separate coordinate map texture.
- Accepts parameters (kx, ky, sign, amplitude) via uniforms.
- Designed for additive blending in a floating-point buffer.
*/

// Uniforms: Variables passed from your MATLAB script
uniform sampler2D Image; // The coordinate map texture
uniform float kx;
uniform float ky;
uniform float our_sign;
uniform float amplitude;

// Varying: Input from the GPU's rasterizer
varying vec2 texCoord;   // The coordinate used to look up a value in 'Image'

// Constants
const float PI = 3.1415926535;

void main() {
    // 1. Look up the true spatial coordinate from our map texture.
    // This bypasses the broken system 'texCoord'.
    vec2 realCoord = texture2D(Image, texCoord).xy;

    // 2. Calculate the Hartley phase using the correct coordinates.
    float phase = 2.0 * PI * (kx * realCoord.x + ky * realCoord.y);

    // 3. Calculate the 'cas' function value.
    float hartley_val = our_sign * (cos(phase) + sin(phase));

    // 4. Normalize the value to [-1, 1] to get the deviation from gray.
    float deviation = hartley_val / 1.41421356; // Divide by sqrt(2)

    // 5. Scale the deviation by the desired amplitude.
    float final_deviation = amplitude * deviation;

    // 6. Set the final pixel color. The additive blending in MATLAB will sum this
    //    value with the mid-gray background and other components.
    gl_FragColor = vec4(final_deviation, final_deviation, final_deviation, 1.0);
}