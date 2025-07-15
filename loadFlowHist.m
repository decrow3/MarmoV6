%% load the Flowhistory
flowhis = zeros(71,600,6,300);

for i = 1:71
    flowhis(i,:,:,:) = D{i,1}.PR.FlowHistory(1:600,:,:);
end 
save('FlowHis','flowhis');