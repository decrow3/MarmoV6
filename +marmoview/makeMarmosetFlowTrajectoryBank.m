function bank = makeMarmosetFlowTrajectoryBank(options)
% MAKEMARMOSETFLOWTRAJECTORYBANK Reproducible bounded low-pass random walks.

required = {'FrameRate','StimulusDuration','TrajectoryCount','RandomSeed', ...
    'SpeedDegPerSecond','MaximumEccentricityDeg','FilterTimeConstantSeconds'};
for ii = 1:numel(required)
    if ~isfield(options,required{ii})
        error('makeMarmosetFlowTrajectoryBank:MissingOption', ...
            'Missing option %s.',required{ii});
    end
end
nFrames = max(2,ceil(options.FrameRate*options.StimulusDuration));
nTrajectories = round(options.TrajectoryCount);
if nTrajectories < 1 || options.FrameRate <= 0 || ...
        options.StimulusDuration <= 0 || ...
        options.SpeedDegPerSecond < 0 || ...
        options.MaximumEccentricityDeg <= 0 || ...
        options.FilterTimeConstantSeconds <= 0
    error('makeMarmosetFlowTrajectoryBank:TrajectoryCount', ...
        'Trajectory and timing parameters must be positive and finite.');
end

stream = RandStream('mt19937ar','Seed',round(options.RandomSeed));
alpha = exp(-1/(options.FrameRate*options.FilterTimeConstantSeconds));
x = zeros(nTrajectories,nFrames);
y = zeros(nTrajectories,nFrames);
for trajectory = 1:nTrajectories
    velocity = zeros(2,nFrames);
    noise = randn(stream,2,nFrames);
    for frame = 2:nFrames
        velocity(:,frame) = alpha*velocity(:,frame-1) + ...
            sqrt(1-alpha^2)*noise(:,frame);
    end
    speed = hypot(velocity(1,:),velocity(2,:));
    scale = options.SpeedDegPerSecond/max(eps,median(speed));
    velocity = velocity*scale;
    for frame = 2:nFrames
        proposed = [x(trajectory,frame-1);y(trajectory,frame-1)] + ...
            velocity(:,frame)/options.FrameRate;
        radius = norm(proposed);
        if radius > options.MaximumEccentricityDeg
            outward = proposed/radius;
            velocity(:,frame) = velocity(:,frame) - ...
                2*dot(velocity(:,frame),outward)*outward;
            proposed = [x(trajectory,frame-1);y(trajectory,frame-1)] + ...
                velocity(:,frame)/options.FrameRate;
            radius = norm(proposed);
            if radius > options.MaximumEccentricityDeg
                proposed = proposed*(options.MaximumEccentricityDeg/radius);
            end
        end
        x(trajectory,frame) = proposed(1);
        y(trajectory,frame) = proposed(2);
    end
end

bank = struct();
bank.SchemaVersion = 'MarmosetFlowTrajectoryBank-1.0';
bank.RandomSeed = round(options.RandomSeed);
bank.FrameRate = options.FrameRate;
bank.StimulusDuration = options.StimulusDuration;
bank.SpeedDegPerSecond = options.SpeedDegPerSecond;
bank.MaximumEccentricityDeg = options.MaximumEccentricityDeg;
bank.FilterTimeConstantSeconds = options.FilterTimeConstantSeconds;
bank.XDeg = x;
bank.YDeg = y;
end
