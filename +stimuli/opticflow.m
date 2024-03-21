classdef opticflow < stimuli.stimulus
  % Optic flow stimulus using dots, basing format on stimuli.gratings and
  % Jake's demo code. See also Penny's stimuli.dotspatial for VR
  % application

  % Matlab class for drawing an optic flow field using the psych. toolbox.
  %
  % The class constructor can be called with a range of arguments:
  %   position - center of FOV in 
  %   focal length
  %   depth
  %   size       - dot size (pixels)
  %   speed      - flow speed vxyz (pixels/frame),
  %   nDots    - number of dots
  %   color

  
  % 19-03-2024 - Declan Rowley
  
  properties (Access = public)
    position double = [0.0, 0.0]; % [x,y] (pixels, from top left)
    f double = 0.01;
    depth double = 2;
    dotdepth double = 1;
    size double = 1;
    vxyz double = [0 0 1]; %flow speed [x,y,z]
    nDots double = 500;
    transparent double = 0.5;  % from 0 to 1, how transparent
    pixperdeg double = 0;  % set non-zero to use for CPD computation
    screenRect = [];   % if radius Inf, then fill whole area
    colour = [1 1 1];
    bkgd double = 127;  
    % could add an aperture radius, for now fullscreen 
    maxRadius double; % maximum radius (pixels), default to Inf
    Xtop double; % max X (pixels) screenRect(3)
    Xbot double; % min X (pixels) screenRect(1);
    %Switching these
    Ytop double; % max Y (pixels) screenRect(2); More negative counting down from top
    Ybot double; % min Y (pixels) screenRect(4);

    % framecount to give dots a lifetime?
    frameCnt double;
    lifetime double = Inf;

    % cartessian coordinates (relative to center of screen/aperture?)
    x; % x coords (pixels) (nDots, 1)
    y; % y coords (pixels)
    z; 
    
    % cartesian displacements
    dx; % pixels per frame?
    dy; % pixels per frame?

  end
        
  properties (Access = private)
    winPtr; % ptb window
    fs
    zs
  end
  
  methods (Access = public)
    function o = opticflow(winPtr,varargin) % marmoview's initCmd?
      o.winPtr = winPtr;

      if nargin == 1
        return
      end

      % initialise input parser
      args = varargin;
      p = inputParser;
      p.StructExpand = true;
      
      p.addParameter('position',o.position, isfloat); % [x,y] (pixels)
    p.addParameter('f',o.f, isfloat); % focus
    p.addParameter('depth',o.depth, isfloat); % depth of focus
    p.addParameter('dotdepth',o.dotdepth, isfloat); % depth of dots

    p.addParameter('size',o.size, isfloat); % dotsize
    p.addParameter('vxyz',o.vxyz, isfloat); % speed xyz of dots
    p.addParameter('nDots',o.nDots, isfloat); % number of dots
    p.addParameter('transparent',o.transparent, isfloat); % from 0 to 1, how transparent
    %p.addParameter('pixperdeg',o.pixperdeg, isfloat); % [x,y] (pixels)
    p.addParameter('colour',o.colour, isfloat); % dot colour
    p.addParameter('bkgd',o.bkgd, isfloat); % 
    p.addParameter('maxRadius',o.maxRadius, isfloat); % maximum radius (pixels), default to Inf
    p.addParameter('Xtop',o.Xtop, isfloat); % max X (pixels)
    p.addParameter('Xbot',o.Xbot, isfloat); % min X (pixels)
    p.addParameter('Ytop',o.Ytop, isfloat); % max Y (pixels)
    p.addParameter('Ybot',o.Ybot, isfloat); % min Y (pixels)

                  
      try
        p.parse(args{:});
      catch
        warning('Failed to parse name-value arguments.');
        return;
      end
      
      args = p.Results;
    
      o.position = args.position;
      o.f = args.f;
      o.depth = args.depth;
      o.size = args.size;
      o.vxyz = args.vxyz;
      o.nDots = args.nDots;
      o.transparent = args.transparent;
      o.colour = args.colour;
      o.bkgd = args.bkgd;
      o.maxRadius = args.maxRadius;
      o.Xtop = args.Xtop;
      o.Xbot = args.Xbot;
      o.Ytop = args.Ytop;
      o.Ybot = args.Ybot;

    end
    

    function beforeTrial(o)
     
      o.fs = repmat(-o.f,o.nDots,1);
      o.zs = zeros(o.nDots, 1);
 
      o.initDots([1:o.nDots]); % all dots!

      % initialise dots' lifetime
      if o.lifetime ~= Inf
        o.frameCnt = randi(o.rng, o.lifetime,o.nDots,1); % 1:nDots
      else
        o.frameCnt = inf(o.nDots,1);
      end
    end
    
    function beforeFrame(o)
      o.drawDots();
    end
        

    function afterFrame(o)
        % Update positions
        Ax = [o.fs o.zs o.x-o.position(1)];
        Ay = [o.zs o.fs o.y-o.position(2)];
        o.dx = Ax*o.vxyz'./o.z;
        o.dy = Ay*o.vxyz'./o.z;
        
         % decrement frame counters
        o.frameCnt = o.frameCnt - 1;

        o.moveDots();
    end
    
    
    function CloseUp(o)
    end
    
  end % methods
    


    
  methods (Access = public)        
    function initDots(o,idx)
      % initialises dot positions
      n = length(idx); % the number of dots to (re-)place
      
      o.frameCnt(idx) = o.lifetime; % default: Inf
      
      if isinf(o.maxRadius)
          x_=o.position(1);
          y_=o.position(2);
          %Redraw any that start too close to the center
          while sum(hypot(x_-o.position(1), y_-o.position(2)) < 2.5*o.size)>0
              x_ = (rand(o.rng, n,1) * (o.Xtop - o.Xbot)) + o.Xbot;
              y_ = (rand(o.rng, n,1) * (o.Ytop - o.Ybot)) + o.Ybot; %counting from top
          end
          o.x(idx,1) = x_;
          o.y(idx,1) = y_;
      else
          % dot positions (polar coordinates, r and theta) - store this?
          r = sqrt(rand(o.rng, n,1).*o.maxRadius.*o.maxRadius); % pixels
          th = rand(o.rng, n,1).*360.0; % deg.

          % convert r and theta to x and y
          [x_,y_] = pol2cart(th.*(pi/180.0),r);
          o.x(idx,1) = x_;
          o.y(idx,1) = y_;
      end
      
      o.z = o.dotdepth + o.depth;

      % set displacements (dx and dy) for each dot
%      [o.dx(idx),o.dy(idx)] = pol2cart(o.direction.*(pi/180),o.speed);
%       o.dx(idx) = dx_;
%       o.dy(idx) = dy_;

        Ax = [o.fs o.zs o.x-o.position(1)];
        Ay = [o.zs o.fs o.y-o.position(2)];
        o.dx = Ax*o.vxyz'./o.z;
        o.dy = Ay*o.vxyz'./o.z;
      
    end
                
    function moveDots(o)

      % calculate future position
      x_ = o.x + o.dx;
      y_ = o.y + o.dy;

      if isinf(o.maxRadius)
          o.x = x_;
          o.y = y_;
          %***** replace 
           iireplace = (o.x > o.Xtop) | (o.x < o.Xbot) | (o.y < o.Ytop) | (o.y > o.Ybot) ; %Leaving Y inverted for now  
           
           %also replace dots below a min radius, this is a placeholder
           %until we can do this with a probabilty function depending on
           %distance from center
           tooclose=hypot(o.x-o.position(1), o.y-o.position(2)) < .5*o.size;
           indclose1=find(tooclose);
           
           % Start culling further out
            tooclose=hypot(o.x-o.position(1), o.y-o.position(2)) < 1.5*o.size;
           indclose2=find(tooclose); %remove 1/15
           indclose2=indclose2(1:5:end);

           tooclose=hypot(o.x-o.position(1), o.y-o.position(2)) < 2.5*o.size;
           indclose3=find(tooclose); %remove 1/15
           indclose3=indclose3(1:15:end);

           tooclose=hypot(o.x-o.position(1), o.y-o.position(2)) < 5*o.size;
           indclose4=find(tooclose);%remove 1/30
           indclose4=indclose4(1:30:end);

           indcloseall = unique([indclose1; indclose2; indclose3; indclose4]);
           o.initDots(union(find(iireplace),indcloseall));

          %***********
      else
         o.x = x_;
         o.y = y_;

         r = sqrt(x_.^2 + y_.^2);
         iireplace = find(r > o.maxRadius); % dots that have exited the aperture  
         o.initDots(iireplace);

      end
      
      idx = find(o.frameCnt == 0); % dots that have exceeded their lifetime
      if ~isempty(idx)
        % (re-)place dots randomly within the aperture
        o.initDots(idx);
      end

    end
    
    function drawDots(o)     
      dotColour = o.colour; %zeros([1,3]); %repmat(0,1,3);
      
      % dotType:
      %
      %   0 - square dots (default)
      %   1 - round, anit-aliased dots (fvour performance)
      %   2 - round, anti-aliased dots (favour quality)
      %   3 - round, anti-aliased dots (built-in shader)
      %   4 - square dots (built-in shader)
      dotType = 1;
      

        colmat = dotColour';

%         Screen('DrawDots',o.winPtr,[o.x(:), -1*o.y(:)]', o.size, colmat', o.position, dotType);

        % Place dots in screen coordinates, left and down from top left
        % corner, do positional math elsewhere
        Screen('DrawDots',o.winPtr,[o.x(:), o.y(:)]', o.size, colmat', [0,0], dotType);

    end
  end % methods
  
  methods (Static)
    function [xx, yy] = rotate(x,y,th)
      % rotate (x,y) by angle th

      for ii = 1:length(th)
        % calculate rotation matrix
        R = [cos(th(ii)) -sin(th(ii)); ...
             sin(th(ii))  cos(th(ii))];

        tmp = R * [x(ii), y(ii)]';
        xx(ii) = tmp(1,:);
        yy(ii) = tmp(2,:);
      end
    end
  end % methods

end % classdef
