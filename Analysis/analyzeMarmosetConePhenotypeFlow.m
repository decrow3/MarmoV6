function analysis = analyzeMarmosetConePhenotypeFlow(dataSource,options)
% ANALYZEMARMOSETCONEPHENOTYPEFLOW Summarize and compare phenotype hypotheses.
% Genotype is intentionally not accepted by this function.

if nargin < 2 || isempty(options)
    options = struct();
end
options = setDefault(options,'BootstrapIterations',1000);
options = setDefault(options,'RandomSeed',260829);
options = setDefault(options,'MinimumClassificationConfidence',0.70);
options = setDefault(options,'MinimumValidTrials',20);
options = setDefault(options,'ConvergenceFractionThreshold',0.5);

trials = loadTrials(dataSource);
records = extractRecords(trials,options.ConvergenceFractionThreshold);
valid = [records.TrialValid] & isfinite([records.Response]);

analysis = struct();
analysis.SchemaVersion = 'MarmosetConePhenotypeAnalysis-1.0';
analysis.ValidTrialCount = nnz(valid);
analysis.TotalTrialCount = numel(records);
analysis.ConditionSummary = summarizeConditions(records,options);
analysis.RuleBasedInterpretation = ruleBasedInterpretation( ...
    analysis.ConditionSummary);
analysis.PhenotypeModel = comparePhenotypes(records(valid),options);
if analysis.ValidTrialCount < options.MinimumValidTrials || ...
        analysis.PhenotypeModel.Confidence < ...
        options.MinimumClassificationConfidence
    analysis.Classification = 'unclassified';
else
    analysis.Classification = analysis.PhenotypeModel.BestPhenotype;
end
analysis.InterpretationLimitations = { ...
    'Initial model is not validated against independently genotyped animals.' ...
    'Invalid eye trials are excluded rather than treated as unseen.' ...
    'Null conditions are receptor-silent, not necessarily isoluminant.'};
end


function trials = loadTrials(source)
if ischar(source) || (isstring(source) && isscalar(source))
    loaded = load(char(source));
else
    loaded = source;
end
if isstruct(loaded) && isfield(loaded,'D') && iscell(loaded.D)
    trials = loaded.D(:);
    return
end
if iscell(loaded)
    trials = loaded(:);
    return
end
if isstruct(loaded)
    names = fieldnames(loaded);
    trialNames = names(~cellfun(@isempty,regexp(names,'^D\d+$','once')));
    indices = cellfun(@(x) sscanf(x,'D%d'),trialNames);
    [~,order] = sort(indices);
    trialNames = trialNames(order);
    trials = cellfun(@(x) loaded.(x),trialNames,'UniformOutput',false);
    return
end
error('analyzeMarmosetConePhenotypeFlow:DataFormat', ...
    'Expected a MarmoV6 MAT file, loaded struct, or D cell array.');
end


function records = extractRecords(trials,convergenceThreshold)
template = struct('ConditionID','','ConditionType','','NullPeakNm',NaN, ...
    'TrialValid',false,'Response',NaN,'Converged',false, ...
    'Projection',NaN,'Distance',NaN,'Latency',NaN,'EyeQuality',NaN, ...
    'TrialIndex',NaN,'RealizedContrast',nan(2,4));
records = repmat(template,0,1);
for ii = 1:numel(trials)
    trial = trials{ii};
    if ~isstruct(trial) || ~isfield(trial,'PR') || ...
            ~isfield(trial.PR,'conditionID')
        continue
    end
    pr = trial.PR;
    record = template;
    record.ConditionID = char(pr.conditionID);
    record.ConditionType = char(pr.conditionType);
    record.NullPeakNm = pr.nullPeakNm;
    record.TrialValid = logical(pr.trialValid);
    record.Projection = pr.meanEyeVelocityProjectionTowardCentre;
    record.Distance = pr.medianGazeToFlowCentreDistanceDeg;
    record.Latency = pr.responseLatencySeconds;
    record.EyeQuality = pr.validEyeSampleCount/max(1,size(pr.Traces,1));
    record.Converged = pr.fractionInsideCentreWindow >= convergenceThreshold;
    record.Response = record.Projection;
    record.TrialIndex = ii;
    record.RealizedContrast = pr.realizedCandidateConeContrast;
    records(end+1,1) = record; %#ok<AGROW>
end
end


function summaries = summarizeConditions(records,options)
if isempty(records)
    summaries = struct([]);
    return
end
ids = unique({records.ConditionID},'stable');
template = struct('ConditionID','','ConditionType','','NullPeakNm',NaN, ...
    'ValidTrials',0,'TotalTrials',0,'ConvergenceProbability',NaN, ...
    'MeanPursuitProjection',NaN,'MedianPursuitProjection',NaN, ...
    'MedianCentreDistanceDeg',NaN,'MedianResponseLatencySeconds',NaN, ...
    'PursuitProjectionCI95',[NaN NaN], ...
    'ConvergenceProbabilityCI95',[NaN NaN]);
summaries = repmat(template,numel(ids),1);
stream = RandStream('mt19937ar','Seed',options.RandomSeed);
for ii = 1:numel(ids)
    selected = strcmp({records.ConditionID},ids{ii});
    subset = records(selected);
    valid = [subset.TrialValid] & isfinite([subset.Response]);
    values = [subset(valid).Response];
    convergence = double([subset(valid).Converged]);
    summaries(ii).ConditionID = ids{ii};
    summaries(ii).ConditionType = subset(1).ConditionType;
    summaries(ii).NullPeakNm = subset(1).NullPeakNm;
    summaries(ii).ValidTrials = nnz(valid);
    summaries(ii).TotalTrials = numel(subset);
    summaries(ii).ConvergenceProbability = mean(convergence,'omitnan');
    summaries(ii).MeanPursuitProjection = mean(values,'omitnan');
    summaries(ii).MedianPursuitProjection = median(values,'omitnan');
    summaries(ii).MedianCentreDistanceDeg = ...
        median([subset(valid).Distance],'omitnan');
    summaries(ii).MedianResponseLatencySeconds = ...
        median([subset(valid).Latency],'omitnan');
    summaries(ii).PursuitProjectionCI95 = bootstrapCI(values, ...
        options.BootstrapIterations,stream,@mean);
    summaries(ii).ConvergenceProbabilityCI95 = bootstrapCI(convergence, ...
        options.BootstrapIterations,stream,@mean);
end
end


function interpretation = ruleBasedInterpretation(summaries)
interpretation = 'insufficient null-condition evidence';
isNull = strcmp({summaries.ConditionType},'pigment-null');
nulls = summaries(isNull);
if numel(nulls) < 3
    return
end
peaks = [nulls.NullPeakNm];
responses = [nulls.MedianPursuitProjection];
uniquePeaks = unique(peaks);
peakResponse = nan(size(uniquePeaks));
for ii = 1:numel(uniquePeaks)
    peakResponse(ii) = median(responses(peaks == uniquePeaks(ii)),'omitnan');
end
if any(~isfinite(peakResponse))
    return
end
[weakest,weakIndex] = min(peakResponse);
others = peakResponse;
others(weakIndex) = [];
if weakest < 0.5*median(others)
    interpretation = sprintf('candidate %d dichromat pattern', ...
        uniquePeaks(weakIndex));
elseif all(peakResponse > 0)
    interpretation = 'candidate trichromat pattern; subtype unresolved';
else
    interpretation = 'unclassified response pattern';
end
end


function model = comparePhenotypes(records,options)
labels = {'D_543','D_556','D_563','T_543_556','T_556_563','T_543_563'};
receptors = {[543],[556],[563],[543 556],[556 563],[543 563]};
model = struct('Phenotypes',{labels},'Posterior',nan(1,6), ...
    'BestPhenotype','unclassified','Confidence',NaN, ...
    'LogEvidence',nan(1,6),'BootstrapBestFraction',nan(1,6));
if numel(records) < 5
    return
end
logEvidence = fitAll(records,receptors);
posterior = exp(logEvidence-max(logEvidence));
posterior = posterior/sum(posterior);
[confidence,best] = max(posterior);

stream = RandStream('mt19937ar','Seed',options.RandomSeed+1);
bestCounts = zeros(1,numel(labels));
for iteration = 1:options.BootstrapIterations
    sample = records(randi(stream,numel(records),[1 numel(records)]));
    [~,winner] = max(fitAll(sample,receptors));
    bestCounts(winner) = bestCounts(winner)+1;
end
model.Posterior = posterior;
model.BestPhenotype = labels{best};
model.Confidence = confidence;
model.LogEvidence = logEvidence;
model.BootstrapBestFraction = bestCounts/options.BootstrapIterations;
end


function evidence = fitAll(records,receptorSets)
y = [records.Response]';
trial = normalizeColumn([records.TrialIndex]');
quality = normalizeColumn([records.EyeQuality]');
candidatePeaks = [563 556 543 423];
evidence = zeros(1,numel(receptorSets));
for hypothesis = 1:numel(receptorSets)
    receptorIndex = find(ismember(candidatePeaks,receptorSets{hypothesis}));
    predictor = zeros(numel(records),1);
    for trialIndex = 1:numel(records)
        contrast = records(trialIndex).RealizedContrast(:,receptorIndex);
        predictor(trialIndex) = max(abs(contrast),[],'all');
    end
    predictor = normalizeColumn(predictor);
    X = [ones(size(y)) predictor trial quality];
    beta = X\y;
    residual = y-X*beta;
    variance = max(eps,mean(residual.^2));
    evidence(hypothesis) = -0.5*numel(y)*log(variance) - ...
        0.5*size(X,2)*log(numel(y));
end
end


function values = normalizeColumn(values)
scale = std(values,'omitnan');
if ~isfinite(scale) || scale == 0
    values = zeros(size(values));
else
    values = (values-mean(values,'omitnan'))/scale;
end
end


function interval = bootstrapCI(values,iterations,stream,statistic)
values = values(isfinite(values));
if isempty(values)
    interval = [NaN NaN];
    return
end
estimates = zeros(iterations,1);
for ii = 1:iterations
    sample = values(randi(stream,numel(values),[1 numel(values)]));
    estimates(ii) = statistic(sample);
end
interval = percentile(estimates,[2.5 97.5]);
end


function result = percentile(values,percentages)
values = sort(values(:));
positions = 1+(numel(values)-1)*percentages/100;
lower = floor(positions);
upper = ceil(positions);
fraction = positions-lower;
result = values(lower).*(1-fraction) + values(upper).*fraction;
end


function value = setDefault(value,name,defaultValue)
if ~isfield(value,name) || isempty(value.(name))
    value.(name) = defaultValue;
end
end
