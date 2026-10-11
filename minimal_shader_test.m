function HartleyShader_OpenGL_Ortho()
    % HartleyShader_OpenGL_Ortho.m
    % Renders a Hartley basis pattern using OpenGL + explicit vertex shader.
    % Assumes hard-coded GL constants are defined locally.

    sca; close all;

    try
        % --- Spatial parameters (cycles per screen) ---
        kx = 5.0;
        ky = 3.0;
        signVal = 1.0;
        contrast = 0.5;

        % --- Write vertex + fragment shaders ---
        [scriptPath,~,~] = fileparts(mfilename('fullpath'));
        if isempty(scriptPath), scriptPath = pwd; end
        vertFile = fullfile(scriptPath,'HartleyTest.vert');
        fragFile = fullfile(scriptPath,'HartleyTest.frag');

        % Vertex shader: pass normalized coords
        fid = fopen(vertFile,'w');
        fprintf(fid, [
            'attribute vec2 position;\n' ...
            'varying vec2 uv;\n' ...
            'void main(void) {\n' ...
            '    uv = 0.5 * (position + 1.0);\n' ...
            '    gl_Position = vec4(position, 0.0, 1.0);\n' ...
            '}\n']);
        fclose(fid);

        % Fragment shader: Hartley combination of sin + cos
        fid = fopen(fragFile,'w');
        fprintf(fid, [
            'uniform float kx;\n' ...
            'uniform float ky;\n' ...
            'uniform float contrast;\n' ...
            'uniform float signVal;\n' ...
            'varying vec2 uv;\n' ...
            'const float PI = 3.1415926535;\n' ...
            'void main(void) {\n' ...
            '  float phase = 2.0 * PI * (kx * uv.x + ky * uv.y);\n' ...
            '  float hartley_val = signVal * (cos(phase) + sin(phase));\n' ...
            '  float deviation = hartley_val / 1.41421356; // normalize RMS\n' ...
            '  float val = 0.5 + contrast * deviation;\n' ...
            '  gl_FragColor = vec4(val, val, val, 1.0);\n' ...
            '}\n']);
        fclose(fid);

        % --- PTB + OpenGL setup ---
        PsychDefaultSetup(2);
        InitializeMatlabOpenGL;
        GL_QUADS  = 0x0007;
        GL_FLOAT  = 0x1406;
        GL_FALSE  = 0;
        Screen('Preference','SkipSyncTests',1);
        screenNumber = max(Screen('Screens'));
        [window, windowRect] = PsychImaging('OpenWindow',screenNumber,0.5);
        shaderHandle = LoadGLSLProgramFromFiles({vertFile,fragFile});
        if shaderHandle <= 0, error('Shader compile/link failed.'); end

        % --- Draw once ---
        Screen('BeginOpenGL',window);
        glUseProgram(shaderHandle);
        glUniform1f(glGetUniformLocation(shaderHandle,'kx'),kx);
        glUniform1f(glGetUniformLocation(shaderHandle,'ky'),ky);
        glUniform1f(glGetUniformLocation(shaderHandle,'contrast'),contrast);
        glUniform1f(glGetUniformLocation(shaderHandle,'signVal'),signVal);

        attrLoc = glGetAttribLocation(shaderHandle,'position');
        glBegin(GL_QUADS);
            glVertexAttrib2f(attrLoc,-1,-1);
            glVertexAttrib2f(attrLoc, 1,-1);
            glVertexAttrib2f(attrLoc, 1, 1);
            glVertexAttrib2f(attrLoc,-1, 1);
        glEnd;
        glUseProgram(0);
        Screen('EndOpenGL',window);

        Screen('Flip',window);
        fprintf('Hartley basis rendered. Press any key to exit.\n');
        KbStrokeWait;

        sca;
        delete(vertFile);
        delete(fragFile);

    catch ME
        sca;
        rethrow(ME);
    end
end
