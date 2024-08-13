classdef ringwedges < stimuli.stimulus % inherit stimulus to have tracking / random number generator
  % Matlab class for drawing a RF mapping stimulus for intrinsic imaging,
  % wedges, rings and ring segments
  %
  % The class constructor can be called with file name that is a .mat of images
  %  and what is the background gray scale (for Gauss windowing of image)
  %
  %   bkgd  - background gray
  %   gray  - true if gray only, else full color
  %
  %  Declan Rowley 2022, borrowing heavily from Jude Mitchell's gaussimages.m
  
  properties (Access = public)
    tex
    filt
    texDim
    saveline 
    %savesquare
    position double = [0.0, 0.0] % [x,y] (pixels)
   
    
    bkgd double = 127
    gray logical = true
    contrast double = 1;%0.5 
    sparsity double = 1 
    texnum double = 1
    orinum double = 1

    pxradius double  % size in pixels, must be set
    barwidth double      
    prefori 
    pixPerDeg double
    updateEveryNFrames % if the update should only run every 
    Ntex double = (120*20);% Max runtime, 20s, 120fps
  end
        
  properties (Access = private)
    winPtr % ptb window
  end
  
  methods (Access = public)
    function o = ringwedges(winPtr,varargin) % marmoview's initCmd?
      o.winPtr = winPtr;
      o.tex = [];
      o.filt =[];
      o.texDim = [];
      o.saveline = [];
      %o.savesquare = [];
      
      if nargin == 1
        return
      end

      % initialise input parser
      args = varargin;
      p = inputParser;
      p.StructExpand = true;
      
      p.addParameter('position',o.position,@isfloat); % [x,y] (pixels)
      p.addParameter('pxradius',o.pxradius,@isfloat); % [x,y] (pixels)
      p.addParameter('gray',o.gray,@islogical);
      p.addParameter('bkgd',o.bkgd,@isfloat);
      p.addParameter('contrast',o.contrast,@isfloat);
      p.addParameter('sparsity',o.sparsity,@isfloat); % 
      p.addParameter('barwidth',o.barwidth,@isfloat); % 
      p.addParameter('texnum',o.texnum,@isfloat); % 
      p.addParameter('Ntex',o.Ntex,@isfloat); % 
      p.addParameter('prefori',o.prefori,@isfloat); % 
      
      p.addParameter('pixPerDeg', [])
      p.addParameter('updateEveryNFrames', 1)
                  
      try
        p.parse(args{:});
      catch
        warning('Failed to parse name-value arguments.');
        return;
      end
      
      args = p.Results;
    
      o.position = args.position;
      o.pxradius = args.pxradius;
      o.gray = args.gray;
      o.bkgd = args.bkgd;
      o.contrast = args.contrast;

      o.sparsity = args.sparsity;
      o.barwidth = args.barwidth;
      o.texnum = args.texnum;
%       o.Ntex = args.Ntex;
      o.prefori = args.prefori;
      
%        o.P.fixRadius      = o.P.Radius;
%        o.P.faceradius     = o.P.Radius;
%        o.P.proberadius    = o.P.Radius;
%       
      
      if isempty(o.pixPerDeg)
            warning('oneDStim: I need the pixPerDeg to be accurate')
            o.pixPerDeg = 37.5048;
      end
      
    end
    
 
    function makeTex(o)
        %Initialise 1d stimulus
        barwidth_px = o.barwidth;
        diam_px     = o.pxradius*2; %actually using radius
        
        %Round up,
        pixperbar=ceil(barwidth_px);
        nbars=ceil(diam_px/barwidth_px);
        
        nTex=nbars*2;
        o.Ntex=nTex;
            %make cartesian matries
            [xx, yy] = meshgrid( linspace(-1, 1, diam_px), ...
                linspace(-1, 1, diam_px) );
        
            p.trial.(sn).srcRect = [0 0 size(xx,2)-1 size(xx,1)-1];
            
            stimCtr = p.trial.(sn).stimCtr(:);% + p.trial.(sn).stimOffset(:);
            
            for i = 1:2 % [x,y]
                p.trial.(sn).pos(i,:) = (stimCtr(i));
            end
            p.trial.(sn).pos = p.trial.(sn).pos  .* p.trial.display.ppd + p.trial.display.ctr(:,1:2)'; %now in pixels
           
            p.trial.(sn).destRect = CenterRectOnPoint(p.trial.(sn).srcRect,p.trial.(sn).pos(1,:)', p.trial.(sn).pos(2,:)');
        
            %make polar angle matrices, this is a strange method
        %     r = sqrt(xx.^2+yy.^2);
        %     a = atan2(yy,xx)/(2*pi)+.5;  % 0<=a<=1
        
            [a,r] = cart2pol(xx,yy);
            
            switch p.trial.(sn).stim
                case {'bar', 'full-field'}
                    newX = xx * cos(0) - yy * sin(0); % Initial drifting bar is horizontal top to bottom!!!!
                    newY = xx * sin(0) + yy * cos(0);
                    wedges = sign(2*round((sin(2*p.trial.(sn).nBar*pi*newX)+1)/2)-1);
                otherwise
                    %wedges = sign(2*round((sin(2*p.trial.(sn).nAng*pi*a)+1)/2)-1);
                    wedges = sign(round((sin(2*p.trial.(sn).nAng*a)+1)/2)-1);
            end
            rings = zeros(size(wedges));
            posWedges = find(wedges == 1);
            negWedges = find(wedges == -1);
        
            % rings = sign(2*round((sin(p.trial.(sn).nRad*pi*r)+1)/2)-1);
        
            %make the checkerboard
            radCheck   = zeros(size(rings,1),size(rings,2),p.trial.(sn).motionSteps);
            for i=1:p.trial.(sn).motionSteps
                switch p.trial.(sn).stim
                    case {'bar', 'full-field'}
                        tmprings1 = sign(2*round((sin(2*p.trial.(sn).nBar*pi*newY + (i-1)/p.trial.(sn).motionSteps*pi*2)+1)/2)-1);
                        tmprings2 = sign(2*round((sin(2*p.trial.(sn).nBar*pi*newY - (i-1)/p.trial.(sn).motionSteps*pi*2)+1)/2)-1);
                    otherwise
                        tmprings1 = sign(2*round((sin(2*p.trial.(sn).nRad*pi*r + (i-1)/p.trial.(sn).motionSteps*pi*2)+1)/2)-1);
                        tmprings2 = sign(2*round((sin(2*p.trial.(sn).nRad*pi*r - (i-1)/p.trial.(sn).motionSteps*pi*2)+1)/2)-1);
                end
                rings(posWedges)=tmprings1(posWedges);
                rings(negWedges)=tmprings2(negWedges);
        
                radCheck(:,:,i)= sign(wedges.*rings);
            end    
        
            % figure, imagesc(radCheck(:,:,1));
        
            str = sprintf('making %s textures', p.trial.(sn).stim);
            % h = waitbar(0,str);
            fprintf('\n\n%s', str);
        
            toggle = -1; 
            textureIndex=nan(1,p.trial.(sn).period*p.trial.(sn).tf*2);
            switch p.trial.(sn).stim
                case 'bar'
                    xLo = -1;
                    for i= 1:p.trial.(sn).period*p.trial.(sn).tf*2
                        %             flipTime=i/(p.trial.(sn).tf*2);
                        xInc = (2-p.trial.(sn).barWidth/p.trial.(sn).nBar)/(p.trial.(sn).period*p.trial.(sn).tf*2);
                        %                 phase = (rem(flipTime+ p.trial.(sn).startPhase*p.trial.(sn).period,p.trial.(sn).period)/p.trial.(sn).period);%each cycle goes from 0 to 1
                        img = radCheck(:,:,mod(i-1,p.trial.(sn).motionSteps)+1); %reset your image to the basic polar checkerboard each time
        
                        %determine where the ring should be
                        xLo = xLo + xInc;
                        xHi = xLo + p.trial.(sn).barWidth/p.trial.(sn).nBar;
        
                        %Zero out the areas of the image that you want grey
                        img(yy<xLo) = 0;
                        img(yy>xHi) = 0;
        
                        img(r<.04)=0;
                        img(r>1) = 0;
        
                        %make and draw your texture
                        textureIndex(i)=Screen('MakeTexture', p.trial.display.ptr, (img+1)*127.5);
            %             waitbar(i/(p.trial.(sn).period*p.trial.(sn).tf*2), h);
                        if ~mod(i,10)
                            fprintf('.');
                        end
                    end
                case 'full-field'
                    for i= 1:p.trial.(sn).period*p.trial.(sn).tf*2
                        img = radCheck(:,:,1); %reset your image to the basic polar checkerboard each time
                        img(r<.04)=0;
                        img(r>1) = 0;
                        img = (-1)^i*img;
                        if i > p.trial.(sn).stimPeriod*p.trial.(sn).tf*2
                            img = 0;
                        end
                        % make and draw your texture
                        textureIndex(i)=Screen('MakeTexture', p.trial.display.ptr, (img+1)*127.5);
            %             waitbar(i/(p.trial.(sn).period*p.trial.(sn).tf*2), h);
                        if ~mod(i,10)
                            fprintf('.');
                        end
                    end
                otherwise
                    for i= 1:p.trial.(sn).period*p.trial.(sn).tf*2
                        flipTime=i/(p.trial.(sn).tf*2);
                        phase = (rem(flipTime+p.trial.(sn).startPhase*p.trial.(sn).period, p.trial.(sn).period)/p.trial.(sn).period);%each cycle goes from 0 to 1
        %                 if i == 1
        %                     phase = p.trial.(sn).startPhase;
        %                 elseif ~mod(i-1,12) % 24 times...
        %                     phase = phase + 1/24;
        %                 end
                        phase=rem(phase,1+eps);
                        img = radCheck(:,:,mod(i-1,p.trial.(sn).motionSteps)+1); %reset your image to the basic polar checkerboard each time
                        if ~mod(i,48)
                            trigger = -1;
                            toggle = toggle * trigger;
                        end
        
                        if toggle > 0
                            img = radCheck(:,:,p.trial.(sn).motionSteps-mod(i-1,p.trial.(sn).motionSteps));
                        end
        
                        switch p.trial.(sn).stim
                            case 'ring'
                                %determine where the ring should be
                                radLo = phase - .5*p.trial.(sn).ringWidth/p.trial.(sn).nRad;
                                radHi = phase + .5*p.trial.(sn).ringWidth/p.trial.(sn).nRad;
                                radHi = min(radHi, 1); % To not show two eccentricities
        
                                %Zero out the areas of the image that you want grey
                                if radLo < 0  %ring is close to fovea
                                    img(r > radHi & r<radLo+1)=0;
                                elseif radHi > 1 %ring is outside of circle
                                    img(r>radHi-1 & r<radLo)=0;
                                else
                                    img(r<radLo) = 0;
                                    img(r>radHi) = 0;
                                end
                                img(r<p.trial.(sn).innerRad/p.trial.(sn).stimSize)=0;%img(r<.04)=0;
                                img(r>1) = 0;
        
                            case 'wedge'
                                %determine where the wedge should be
                                angLo = phase - .5*p.trial.(sn).wedgeWidth/p.trial.(sn).nAng;
                                angHi = phase + .5*p.trial.(sn).wedgeWidth/p.trial.(sn).nAng;
        
                                %Zero out the areas of the image that you want grey    
                                if angLo < 0  
                                    img(a > angHi & a<(angLo+1))=0;
                                elseif angLo > 1
                                    img(a>(angHi-1) | a<(angLo-1)) = 0;
                                elseif angHi > 1
                                    img(a>(angHi-1) & a<angLo) = 0;
                                else
                                    img(a<angLo) = 0;
                                    img(a>angHi) = 0;
                                end
                                %ring is close to fovea
                                img(r<p.trial.(sn).innerRad/p.trial.(sn).stimSize)=0;%img(r<.04)=0;
                                img(r>1) = 0;
        
                            case 'meridian'
                                %Zero out the areas of the image that you want grey
                                if phase>=.5 %horizontal meridian
                                    img(a> p.trial.(sn).meriThick/2 & a<.5-p.trial.(sn).meriThick/2)=0;
                                    img(a>.5+p.trial.(sn).meriThick/2 & a<1-p.trial.(sn).meriThick/2)=0;
                                else %vertical meridian
                                    img(a<= .25-p.trial.(sn).meriThick/2)=0;
                                    img(a>=.25+p.trial.(sn).meriThick/2 & a<=.75-p.trial.(sn).meriThick/2)=0;
                                    img(a>=.75+p.trial.(sn).meriThick/2 & a<=1)=0;
                                end
                                img(r<.04)=0;
                                img(r>1) = 0;
                        end
                        %make it switch between B/W and W/B
                    %     img = (-1)^i*img;
        
                        %make and draw your texture
        %                 textureIndex(i)=Screen('MakeTexture', p.trial.display.ptr, (img+1)*127.5);
                            textureIndex(i)=Screen('MakeTexture', p.trial.display.ptr, (img+1)/2);
            %             waitbar(i/(p.trial.(sn).period*p.trial.(sn).tf*2), h);
                        if ~mod(i,10)
                            fprintf('.');
                        end
                    end
            end % switch

        %% Make full 2D texture in one go (don't do this)
        %Filter with a gaussian window
%         dim=size(square,1);
%         [x,y] = meshgrid((1:dim)-dim/2);
%         g = exp(-(x.^2+y.^2)/(2*(dim/6)^2));
%         
%         im0 = ((g.*double(square)) + o.bkgd*(1-g)); 
%         %im0 = uint8((g.*double(square)) + o.bkgd*(1-g)); 
%         %im = ((g.*double(square)));
%         
        
        %Filter with a Raised Cosine instead
        %dim=size(square,1);
        dim=size(line,2);
        [x,y] = meshgrid((1:dim)-dim/2);
        [th,r] = cart2pol(x,y);
        
        edge=round(dim/10); %placeholder
        inner=dim/2-edge;
        outer=dim/2;
        raisedcosn=(.5*cosd((r-inner)/edge*180)+.5);
        
        z=zeros(dim);
        z(r<(inner))=1;
        z(r>=(inner))=raisedcosn(r>=(inner));
        z(r>(outer))=0;
        
        %Alpha channel only, paste into alpha channel
        g(:,:,4)=z*255;
        g(:,:,1:3)=ones(dim,dim,3)*o.bkgd;
        %g=repmat(z,1,1,3)*255;
        
        %Create a filter to blend with the oneD noise
        o.filt = Screen('MakeTexture',o.winPtr,g);  
        
        g=z;
        %im0 = ((g.*double(square)) + o.bkgd*(1-g)); 
        %im0 = uint8((g.*double(square)) + o.bkgd*(1-g)); 
        %im = ((g.*double(square)));
        
        if (o.contrast > 0)
            t1 = 255 * (squeeze(mean(g,3)) > 0.05);
        else
            t1 = 255 * squeeze(mean(g,3));
        end      


        for i=1:nTex
            o.texDim(i)=dim;
            o.tex(i) = Screen('MakeTexture',o.winPtr, ...
                line(i,:));        
        end
 
        
    end
    
    function CloseUp(o)
       if ~isempty(o.tex)
          for i = 1:size(o.tex,2) 
            Screen('Close',o.tex(i)); 
          end
          o.tex = [];
       end
    end
        
    function beforeTrial(o)
        o.setRandomSeed(); % set the random seed
    end
    
    function beforeFrame(o)
      if (o.texnum)
          
          o.drawTexImage(o.texnum);
      else
          %Textures are already random, do we need to shuffle here?
          rd = randi(o.rng, o.Ntex);  
          o.drawTexImage(rd);
       end
    end
        
    function afterFrame(o)
    end
    
    function drawTexImage(o,texnum)
       if ( (texnum>0) && (texnum <= size(o.tex,2)) ) 
         if (~isempty(o.tex(texnum)))
           rect = kron([1,1],o.position) + kron(o.pxradius,[-1, -1, +1, +1]);
           texrect = [0 0 o.texDim(texnum) o.texDim(texnum)];
           ori = o.prefori;
           %disp(o.tex(texnum))
           %Screen(o.winPtr,'BlendFunction', GL_ONE, GL_ZERO);%NO blending
           Screen(o.winPtr,'BlendFunction',GL_SRC_ALPHA,GL_ONE_MINUS_SRC_ALPHA);
           Screen('DrawTexture',o.winPtr,o.tex(texnum),texrect,rect,ori,[],o.contrast);
           
           %Set alpha blending to overwrite alpha channel only
           Screen(o.winPtr,'BlendFunction', GL_ONE_MINUS_SRC_ALPHA, GL_SRC_ALPHA, [1 1 1 1]);
           
           %Filter with overlayed cosine aperture
           Screen('DrawTexture',o.winPtr,o.filt,texrect,rect,ori);
           
           %Return alpha blending to standard form
           Screen(o.winPtr,'BlendFunction',GL_SRC_ALPHA,GL_ONE_MINUS_SRC_ALPHA);
         end
       end
    end
    
    function varargout = getImage(o, rect, binsize)
        
        if o.winPtr~=0
            warning('oneDnoise: getImage: only works if you constructed the object with winPtr=0')
        end
        
        if nargin < 3
            binsize = 1;
        end
        
        if nargin < 2
            rect = o.position([1 2 1 2]) + [-1 -1 1 1].*o.pxradius/2;
        end
        

        
        I = o.tex{o.texnum};
        I = double(I);
        alpha = squeeze(I(:,:,4))./255;
        I(:,:,4) = [];
        for i = 1:3
            I(:,:,i) = I(:,:,i).*alpha + 127.*(1-alpha);
        end
        
        texrect = kron([1,1],o.position) + kron(o.pxradius,[-1, -1, +1, +1]);
        I = imresize(I, [texrect(4)-texrect(2) texrect(3)-texrect(1)]);
        alpha = imresize(alpha, [texrect(4)-texrect(2) texrect(3)-texrect(1)]);
        
        % -- try to be a little quicker
        Iscreen = o.bkgd * ones(1080,1920); % bad that screensize is hardcoded
        Iscreen(texrect(2):texrect(4)-1, texrect(1):texrect(3)-1) = mean(I(:,:,1:3),3);
        Ascreen = zeros(1080,1920);
        Ascreen(texrect(2):texrect(4)-1, texrect(1):texrect(3)-1) = alpha;
        
        tmprect = rect;
        tmprect(3) = rect(3)-rect(1)-1;
        tmprect(4) = rect(4)-rect(2)-1;
        
        
        im = imcrop(Iscreen, tmprect); % requires the imaging processing toolbox
        alpha = imcrop(Ascreen, tmprect);
        
        if binsize~=1
            im = im(1:binsize:end,1:binsize:end);
            alpha = alpha(1:binsize:end,1:binsize:end);
        end
        

        
        
%         % -- works, but you have to draw
%         texax = texrect(1):binsize:texrect(3);
%         texay = texrect(2):binsize:texrect(4);
%         
%         
%         figure(9999); clf
%         if binsize ~=1
%             I = imresize(I, 1./binsize);
%         end
%         imagesc(texax, texay, I)
%         xlim([rect(1) rect(3)])
%         ylim([rect(2) rect(4)])
%         
%         frame = getframe(gca);
%         im = frame.cdata;
%         %
        
        if nargout > 0
            varargout{1} = im;
        end
        
        if nargout > 1
            varargout{2} = alpha;
        end
        
    end
    
  end % methods
  
end % classdef


