function plan = makeMarmosetPhenotypeTrialPlan(conditionBank,options)
% MAKEMARMOSETPHENOTYPETRIALPLAN Balanced, reproducible condition schedule.

options = setDefault(options,'RepeatsPerCondition',10);
options = setDefault(options,'TrajectoryCount',5);
options = setDefault(options,'RandomSeed',1);
options = setDefault(options,'RewardAmount',1);
options = setDefault(options,'CatchTrialFraction',0.1);

conditions = conditionBank.Conditions;
ids = {conditions.ConditionID};
catchIndex = find(strcmp(ids,'catch'),1);
noncatchIndices = find(~strcmp(ids,'catch'));
repeats = round(options.RepeatsPerCondition);
trajectoryCount = round(options.TrajectoryCount);
if repeats < 1 || trajectoryCount < 1
    error('makeMarmosetPhenotypeTrialPlan:Counts', ...
        'RepeatsPerCondition and TrajectoryCount must be positive integers.');
end
if ~isscalar(options.CatchTrialFraction) || ...
        options.CatchTrialFraction < 0 || options.CatchTrialFraction >= 1
    error('makeMarmosetPhenotypeTrialPlan:CatchFraction', ...
        'CatchTrialFraction must be a scalar in [0,1).');
end

rows = zeros(numel(noncatchIndices)*repeats,6);
cursor = 0;
stream = RandStream('mt19937ar','Seed',round(options.RandomSeed));
for conditionIndex = noncatchIndices
    condition = conditions(conditionIndex);
    levelIndex = find(abs(conditionBank.ContrastLevels-condition.AxisScale) < 1e-12,1);
    if isempty(levelIndex)
        levelIndex = 0;
    end
    trajectoryOrder = zeros(1,0);
    while numel(trajectoryOrder) < repeats
        trajectoryOrder = [trajectoryOrder ...
            randperm(stream,trajectoryCount)]; %#ok<AGROW>
    end
    trajectoryOrder = trajectoryOrder(1:repeats);
    for repeatIndex = 1:repeats
        cursor = cursor+1;
        rows(cursor,:) = [conditionIndex levelIndex ...
            trajectoryOrder(repeatIndex) repeatIndex ...
            randi(stream,2^31-1) options.RewardAmount];
    end
end

rows = constrainedShuffle(rows,stream);
catchCount = round(options.CatchTrialFraction/(1-options.CatchTrialFraction)*size(rows,1));
if ~isempty(catchIndex) && catchCount > 0
    catchRows = zeros(catchCount,6);
    for ii = 1:catchCount
        catchRows(ii,:) = [catchIndex 0 mod(ii-1,trajectoryCount)+1 ii ...
            randi(stream,2^31-1) options.RewardAmount];
    end
    insertAfter = round(linspace(1,size(rows,1),catchCount+2));
    insertAfter = insertAfter(2:end-1);
    for ii = catchCount:-1:1
        rows = [rows(1:insertAfter(ii),:);catchRows(ii,:); ...
            rows(insertAfter(ii)+1:end,:)]; %#ok<AGROW>
    end
end

plan = struct();
plan.SchemaVersion = 'MarmosetPhenotypeTrialPlan-1.0';
plan.RandomSeed = round(options.RandomSeed);
plan.Columns = {'ConditionIndex','ContrastLevelIndex','TrajectoryIndex', ...
    'RepeatIndex','TrialRandomSeed','RewardAmount'};
plan.Rows = rows;
plan.ConditionIDs = ids;
end


function rows = constrainedShuffle(rows,stream)
original = rows;
for attempt = 1:1000
    remaining = original;
    candidate = zeros(size(original));
    success = true;
    for position = 1:size(candidate,1)
        permitted = 1:size(remaining,1);
        if position > 2 && ...
                candidate(position-1,1) == candidate(position-2,1)
            permitted = permitted(remaining(:,1) ~= candidate(position-1,1));
        end
        if isempty(permitted)
            success = false;
            break
        end
        selected = permitted(randi(stream,numel(permitted)));
        candidate(position,:) = remaining(selected,:);
        remaining(selected,:) = [];
    end
    if success
        rows = candidate;
        return
    end
end
error('makeMarmosetPhenotypeTrialPlan:Randomization', ...
    'Unable to satisfy the consecutive-condition constraint after 1000 attempts.');
end


function value = setDefault(value,name,defaultValue)
if ~isfield(value,name) || isempty(value.(name))
    value.(name) = defaultValue;
end
end
