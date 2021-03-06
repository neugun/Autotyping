function analysis = SOR(Info,varargin)
% Citation: Patel TP, Gullotti DM, et al (2014). 
% An open-source toolbox for automated phenotyping of mice in behavioral tasks. 
% Front. Behav. Neurosci. 8:349. doi: 10.3389/fnbeh.2014.00349
% www.seas.upenn.edu/~molneuro/autotyping.html
% Copyright 2014, Tapan Patel PhD, University of Pennsylvania
% Track the position of the mouse's head and compute how long it spends
% interacting with one of 2 objects.
% try
if(isempty(which('mmread')))
    addpath('../mmread');
end
[~,vidname] = fileparts(Info.filename);
hbar = waitbar(0,sprintf('Processing %s\n0%%', vidname));
set(findall(hbar,'type','text'),'Interpreter','none');

% Take care of variable inputs
DISPLAY = 0;
if nargin > 2
    for i = 1:2:length(varargin)-1
        if isnumeric(varargin{i+1})
            eval([varargin{i} '= [' num2str(varargin{i+1}) '];']);
        else
            eval([varargin{i} '=' char(39) varargin{i+1} char(39) ';']);
        end
    end
end
if(isfield(Info,'duration') && ~isempty(Info.duration))
    duration = Info.duration;
else
    duration = 600;
end
if(isfield(Info,'dimensions_L') && isfield(Info,'dimensions_W') ...
        && ~isempty(Info.dimensions_L) && ~isempty(Info.dimensions_W))
    box_dim = [Info.dimensions_L Info.dimensions_W];
else
    box_dim = [12 15];
end
abs_mv_path = Info.filename;

% ref_idx = 4;
% disp(['Processing ' abs_mv_path]);
if(isfield(Info,'frames') && ~isempty(Info.frames))
    frames = Info.frames;
else
    
    frames = mmcount(abs_mv_path);
    if(isnan(frames))
        vid = VideoReader(abs_mv_path);
        
        if(isempty(vid.NumberOfFrames))
            read(vid,inf);
        end
        
        frames = vid.NumberOfFrames;
    end
end
if(isempty(Info.start_idx))
    Info.start_idx = TimeToFrame(Info.filename,1,frames,Info.start_time);
end
start_idx = Info.start_idx;
% frames = start_idx + 200;
% end_idx = frames;
if(isfield(Info,'ref_frame') && ~isempty(Info.ref_frame))
    Bkg = Info.ref_frame;
else
    
    indices = randsample(frames-start_idx,min([100 frames-start_idx]))+(start_idx);
    indices(indices>frames) = [];
    V = mmread(abs_mv_path,indices); V = V(end);
    A = zeros(V.height,V.width,length(V.frames));
    for i=1:length(V.frames)
        A(:,:,i) = rgb2gray(V.frames(i).cdata);
    end
    Bkg = uint8(mode(double(A),3));
    
    % Fix any 0's - this arises if the mouse sits in one location for most of
    % the video and is incorporated as part of the background
    Bkg = double(Bkg);
    Bkg(Bkg==0) = nan;
    Bkg = uint8(inpaint_nans(Bkg,2));
end
if(length(size(Bkg))==3)
    Bkg = rgb2gray(Bkg);
end
Iref = Bkg;

px_per_inch_L = 0;
px_per_inch_R = 0;
magfactorL = 0;
magfactorR = 0;
if(isfield(Info,'LeftLabel'))
    Info.LeftLabel = ~strcmp(Info.LeftLabel,'na');
else
    Info.LeftMouse = ~isempty(Info.LeftTag) && ~strcmp(Info.LeftTag,'na');
end
if(isfield(Info,'RightLabel'))
    Info.RightMouse = ~strcmp(Info.RightLabel,'na');
else
    Info.RightMouse = ~isempty(Info.RightTag) && ~strcmp(Info.RightTag,'na');
end
if(Info.LeftMouse)
    C = regionprops(Info.ROIs.surface_left,'BoundingBox');
    px_per_inch_L = mean([C.BoundingBox(3)/box_dim(1) C.BoundingBox(4)/box_dim(2)]);
    magfactorL = ceil(px_per_inch_L*.5);
end
if(Info.RightMouse)
    C = regionprops(Info.ROIs.surface_right,'BoundingBox');
    px_per_inch_R = mean([C.BoundingBox(3)/box_dim(1) C.BoundingBox(4)/box_dim(2)]);
    magfactorR = ceil(px_per_inch_R*.5);
end


Gref = Iref;
Icomposite = zeros(size(Gref));
Ibouts = Icomposite;
ROIs = Info.ROIs;
if(Info.LeftMouse)
    mask_left = uint8(ROIs.mask_left);
    surface_left = uint8(ROIs.surface_left);
else
    mask_left = uint8(0);
    surface_left = uint8(0);
end
if(Info.RightMouse)
    mask_right = uint8(ROIs.mask_right);
    surface_right = uint8(ROIs.surface_right);
else
    mask_right = uint8(0);
    surface_right = uint8(0);
end
% Initialize all variables to 0 (needed for parfor loop)
BWobject1 = 0;
BWobject2 = 0;
BWobject3 = 0;
BWobject4 = 0;
BWobject5 = 0;
BWobject6 = 0;
Mouse1COM = zeros(frames,2);
Mouse2COM = zeros(frames,2);

% Is there a mouse in the left or right box? 1=yes, 0=no. If no, don't try
% to process that half
LeftMouse = Info.LeftMouse;
RightMouse = Info.RightMouse;
if(~LeftMouse)
    Info.LeftObjects = 0;
end
if(~RightMouse)
    Info.RightObjects = 0;
end
% If there are objects and a mouse in each box, allocate space

if(LeftMouse && Info.LeftObjects)
    BWobject1 = ROIs.BWobject1;
    BWobject2 = ROIs.BWobject2;
    BWobject3 = ROIs.BWobject3;
    BWobject1 = imfill(BWobject1,'holes');
    BWobject2 = imfill(BWobject2,'holes');
    BWobject3 = imfill(BWobject3,'holes');
    
    Looking1 = false(frames,1);
    Looking2 = false(frames,1);
    Looking3 = false(frames,1);
    % Keep track of head, tail and Vision coordinates
    Head1 = single(zeros(frames,2));
    Tail1 = single(zeros(frames,2));
    Eyes1 = single(zeros(frames,2));
    Mouse1Area = single(zeros(frames,1));
    MAL = single(zeros(frames,1));
end
if(RightMouse && Info.RightObjects)
    BWobject4 = ROIs.BWobject4;
    BWobject5 = ROIs.BWobject5;
    BWobject6 = ROIs.BWobject6;
    BWobject4 = imfill(BWobject4,'holes');
    BWobject5 = imfill(BWobject5,'holes');
    BWobject6 = imfill(BWobject6,'holes');
    %         BWobject3 = imdilate(BWobject3,ones(ceil(px_per_inch_R/3)));
    %         BWobject4 = imdilate(BWobject4,ones(ceil(px_per_inch_R/3)));
    
    Looking4 = false(frames,1);
    Looking5 = false(frames,1);
    Looking6 = false(frames,1);
    
    Head2 = single(zeros(frames,2));
    Tail2 = single(zeros(frames,2));
    Eyes2 = single(zeros(frames,2));
    Mouse2Area = single(zeros(frames,1));
end
times = zeros(frames,1);
if(LeftMouse)
    Mouse1COM = zeros(frames,2);
    Head1 = single(zeros(frames,2));
    Tail1 = single(zeros(frames,2));
    Mouse1Area = single(zeros(frames,1));
end

if(RightMouse)
    Mouse2COM = zeros(frames,2);
    Head2 = single(zeros(frames,2));
    Tail2 = single(zeros(frames,2));
    Mouse2Area = single(zeros(frames,1));
    
end
global cancel;
cancel = 0;
if(DISPLAY)
    h=figure;
    hax = axes('Units','pixels');
    uicontrol('Style', 'pushbutton', 'String', 'Cancel',...
        'Position', [20 20 50 20],...
        'Callback', {@pushbutton_callback});
end
% % Read f frames at a time for speed
%
% vid_out = VideoWriter('demo_3obj.avi');
% open(vid_out);

f = 200;
T = [start_idx:f:frames frames];
[~,vidname] = fileparts(abs_mv_path);
disp(vidname);
fname = tempname(pwd);
parfor_progress(length(T),fname,vidname);
for k =1:length(T)-1
    if(cancel==1)
        delete(h);
        delete(hbar);
        return;
    end
    V = mmread(abs_mv_path,T(k):T(k+1)-1);
    V = V(end);
    n = length(V(end).frames);
    waitbar(T(k)/frames,hbar,sprintf('Processing %s\n%d %%',vidname,round(100*T(k)/frames)));
    set(findall(hbar,'type','text'),'Interpreter','none');
    for j=1:n
        if(cancel==1)
            delete(h);
            delete(hbar);
            return;
        end
        i = T(k)+j-1;
       
        
        if(V(end).times(j) > times(Info.start_idx)+duration)
            break;
        end
         times(i) = V(end).times(j);
        %         if(mod(i-start_idx,1000)==0)
        %             disp(['     ' Info.filename ': ' num2str(i-start_idx) ' of ' num2str(frames-start_idx) ' frames processed.']);
        %         end
        try
            I = rgb2gray(V.frames(j).cdata);
            %         I = double(I)-mean(mean(double(I)));
            D = imabsdiff(I,Bkg);
            D = imfill(D,'holes');
            %         D = imclose(D,ones(5));
            if(LeftMouse)
                Dleft = D.*(mask_left);
                thresh = max([40 255*graythresh(Dleft)]);
                %             [~,c] = kmeans(double(Dleft(:)),2,'start',[5;30]);
                Lleft = SegmentMouse(Dleft>thresh,Dleft,Info.LeftSessionValue-1);
                Icomposite = Icomposite + Lleft;
                
            end
            if(RightMouse)
                Dright = D.*(mask_right);
                thresh = max([40 255*graythresh(Dright)]);
                %             [~,c] = kmeans(double(Dright(:)),2,'start',[5;30]);
                Lright = SegmentMouse(Dright>thresh,Dright,Info.RightSessionValue-1);
                Icomposite = Icomposite + Lright;
            end
            if(LeftMouse && Info.LeftObjects)
                try
                    [xhead1, yhead1 , xtail1, ytail1,Vision1,COM1,mal] = GetHeadCoordinates(Lleft);
                    
                    Mouse1COM(i,:) = [COM1(1) COM1(2)];
                    Head1(i,:) = [xhead1 yhead1];
                    Tail1(i,:) = [xtail1 ytail1];
                    % Resize Vision vector to be length 20 pixels
                    Vision1 = Vision1*magfactorL/norm(Vision1);
                    Eyes1(i,:) = Vision1;
                    C = regionprops(Lleft,'Area');
                    Mouse1Area(i) = C.Area;
                    MAL(i) = mal;
                catch
                    Mouse1COM(i,:) = Mouse1COM(i-1,:);
                    Head1(i,:) = Head1(i-1,:);
                    Tail1(i,:) = Tail1(i-1,:);
                    Eyes1(i,:) = Eyes1(i-1,:);
                    Mouse1Area(i) = Mouse1Area(i-1);
                    MAL(i) = MAL(i-1);
                end
                
                try
                    Looking1(i) = IsLooking(Head1(i,1),Head1(i,2),Vision1,Mouse1COM(i,:),BWobject1);
                    Looking2(i) = IsLooking(Head1(i,1),Head1(i,2),Vision1,Mouse1COM(i,:),BWobject2);
                    Looking3(i) = IsLooking(Head1(i,1),Head1(i,2),Vision1,Mouse1COM(i,:),BWobject3);
                    if(Looking1(i) || Looking2(i) || Looking3(i))
                        Ibouts = Ibouts + double(Lleft);
                    end
                    
                end
            elseif(LeftMouse && ~Info.LeftObjects)
                try
                    C1 = regionprops(Lleft,'Centroid');
                    Mouse1COM(i,:) = C1.Centroid;
                catch
                    Mouse1COM(i,:) = Mouse1COM(i-1,:);
                end
            end
            if(RightMouse && Info.RightObjects)
                try
                    [xhead2, yhead2 , xtail2, ytail2,Vision2,COM2] = GetHeadCoordinates(Lright);
                    
                    Mouse2COM(i,:) = [COM2(1) COM2(2)];
                    
                    Head2(i,:) = [xhead2 yhead2];
                    Tail2(i,:) = [xtail2 ytail2];
                    % Resize Vision vector to be length 20 pixels
                    Vision2 = Vision2*magfactorR/norm(Vision2);
                    Eyes2(i,:) = Vision2;
                    C = regionprops(Lright,'Area');
                    Mouse2Area(i) = C.Area;
                catch
                    Mouse2COM(i,:) = Mouse2COM(i-1,:);
                    Head2(i,:) = Head2(i-1,:);
                    Tail2(i,:) = Tail2(i-1,:);
                    Eyes2(i,:) = Eyes2(i-1,:);
                    Mouse2Area(i) = Mouse2Area(i-1);
                end
                
                try
                    Looking4(i) = IsLooking(Head2(i,1),Head2(i,2),Vision2,Mouse2COM(i,:),BWobject4);
                    Looking5(i) = IsLooking(Head2(i,1),Head2(i,2),Vision2,Mouse2COM(i,:),BWobject5);
                    Looking6(i) = IsLooking(Head2(i,1),Head2(i,2),Vision2,Mouse2COM(i,:),BWobject6);
                    if(Looking4(i) || Looking5(i) || Looking6(i))
                        Ibouts = Ibouts + double(Lright);
                    end
                    
                end
                
            elseif(RightMouse && ~Info.RightObjects)
                try
                    C2 = regionprops(Lright,'Centroid');
                    Mouse2COM(i,:) = C2.Centroid;
                catch
                    Mouse2COM(i,:) = Mouse2COM(i-1,:);
                end
            end
            if(DISPLAY)
                imshow(V.frames(j).cdata,'Parent',hax);
                hold on
                plot(Mouse1COM(i,1),Mouse1COM(i,2),'ro','MarkerFaceColor','r');
                plot(Mouse2COM(i,1),Mouse2COM(i,2),'ro','MarkerFaceColor','r');
                if(Looking1(i))
                    B = bwboundaries(BWobject1);
                    for q=1:length(B)
                        plot(B{q}(:,2),B{q}(:,1),'b','LineWidth',3);
                    end
                end
                
                if(Looking2(i))
                    B = bwboundaries(BWobject2);
                    for q=1:length(B)
                        plot(B{q}(:,2),B{q}(:,1),'b','LineWidth',3);
                    end
                end
                if(Looking3(i))
                    B = bwboundaries(BWobject3);
                    for q=1:length(B)
                        plot(B{q}(:,2),B{q}(:,1),'b','LineWidth',3);
                    end
                end
                if(Looking4(i))
                    B = bwboundaries(BWobject4);
                    for q=1:length(B)
                        plot(B{q}(:,2),B{q}(:,1),'b','LineWidth',3);
                    end
                end
                if(Looking5(i))
                    B = bwboundaries(BWobject5);
                    for q=1:length(B)
                        plot(B{q}(:,2),B{q}(:,1),'b','LineWidth',3);
                    end
                end
                if(Looking6(i))
                    B = bwboundaries(BWobject6);
                    for q=1:length(B)
                        plot(B{q}(:,2),B{q}(:,1),'b','LineWidth',3);
                    end
                end
                hold off
                title(['Elapsed time = ' num2str(floor(times(i)-times(start_idx+1))) ' (s)']);
                pause(1e-3);
            end
            
            %
            %         pause(1e-3);
            %         drawnow;
            %         fr = getframe;
            %         writeVideo(vid_out,fr);
            %
            %         hold off
            %             end
        end
    end
    parfor_progress(-1,fname,vidname);
end
try
    delete(h);
end
%% If the mouse is sitting in a corner for >10, it is likely grooming
% remove these frames from the "interacting label"
start_idx = find(times,1,'first');

% Find the index of end time
end_idx = find(times,1,'last');
fitresult = createFit1(start_idx:end_idx,times(start_idx:end_idx)');
fps = 1/fitresult.p1;
analysis.fps = fps;

if(LeftMouse && Info.LeftObjects)
    Looking1 = Looking1(1:end_idx);
    Looking2 = Looking2(1:end_idx);
    Looking3 = Looking3(1:end_idx);
    total_time1 = nnz(Looking1)/fps;
    total_time2 = nnz(Looking2)/fps;
    total_time3 = nnz(Looking3)/fps;
    
end

if(RightMouse && Info.RightObjects)
    Looking4 = Looking4(1:end_idx);
    Looking5 = Looking5(1:end_idx);
    Looking6 = Looking6(1:end_idx);
    total_time4 = nnz(Looking4)/fps;
    total_time5 = nnz(Looking5)/fps;
    total_time6 = nnz(Looking6)/fps;
    
end
% Save to an analysis struct
analysis.filename = abs_mv_path;
analysis.duration = times(end_idx)-times(start_idx);
analysis.times = times;
analysis.Iref = Bkg;
% analysis.LeftLabel = Info.LeftLabel;
% analysis.RightLabel = Info.RightLabel;
Ibouts = Ibouts./fps;
analysis.Ibouts = Ibouts;


if(LeftMouse && Info.LeftObjects)
    analysis.GlassLeft = Looking1;
    analysis.MetalLeft = Looking2;
    analysis.CylinderLeft = Looking3;
    analysis.TimeGlassLeft = total_time1;
    analysis.TimeMetalLeft = total_time2;
    analysis.TimeCylinderLeft = total_time3;
    % Replace 0s with NaNs
    
    analysis.Mouse1COM = Mouse1COM;
    
    analysis.Head1 = Head1;
    analysis.Tail1 = Tail1;
    analysis.Eyes1 = Eyes1;
    analysis.Mouse1Area = Mouse1Area;
end

if(RightMouse && Info.RightObjects)
    
    analysis.GlassRight = Looking4;
    analysis.MetalRight = Looking5;
    analysis.CylinderRight = Looking6;
    analysis.TimeGlassRight = total_time4;
    analysis.TimeMetalRight = total_time5;
    analysis.TimeCylinderRight = total_time6;
    
    analysis.Mouse2COM = Mouse2COM;
    analysis.Head2 = Head2;
    analysis.Tail2 = Tail2;
    analysis.Eyes2 = Eyes2;
    analysis.Mouse2Area = Mouse2Area;
end

% Make a summary figure
if(LeftMouse && Info.LeftObjects)
    Obj1COM = regionprops(BWobject1,'Centroid');
    Obj2COM = regionprops(BWobject2,'Centroid');
    Obj3COM = regionprops(BWobject3,'Centroid');
end
if(RightMouse && Info.RightObjects)
    Obj4COM = regionprops(BWobject4,'Centroid');
    Obj5COM = regionprops(BWobject5,'Centroid');
    Obj6COM = regionprops(BWobject6,'Centroid');
end


Icomposite = Icomposite./fps;
if(isfield(Info,'perimeter') && ~isempty(Info.perimeter))
    periphery = Info.perimeter;
else
    periphery = 2.0; % 2 inches from the walls is the periphery
end

%%
hsum=figure('Visible','off');

Bkg_rgb = zeros([size(Bkg),3],'uint8');
Bkg_rgb(:,:,1) = Bkg;
Bkg_rgb(:,:,2) = Bkg;
Bkg_rgb(:,:,3) = Bkg;

subplot(2,3,1); imshow(Bkg_rgb); axis image
title(abs_mv_path,'Interpreter','none');

hold all
if(LeftMouse)
    plot(Mouse1COM(start_idx:end-1,1),Mouse1COM(start_idx:end-1,2),'k');
    
    
    C = regionprops(Info.ROIs.surface_left,'BoundingBox');
    px_per_inch_L = mean([C.BoundingBox(3)/box_dim(1) C.BoundingBox(4)/box_dim(1)]);
    center_BW_L = imerode(Info.ROIs.surface_left,ones(ceil(2*periphery*px_per_inch_L)));
    periphery_BW_L = Info.ROIs.surface_left - center_BW_L;
    
    % Show the boundaries
    
    B = bwboundaries(Info.ROIs.surface_left);
    plot(B{1}(:,2),B{1}(:,1),'b','LineWidth',4)
    B = bwboundaries(center_BW_L);
    plot(B{1}(:,2),B{1}(:,1),'r','LineWidth',4)
    
    if(Info.LeftObjects)
        text(Obj1COM(1).Centroid(1)-40,Obj1COM(1).Centroid(2),[num2str(total_time1) ' s'],'BackgroundColor',[.7 .9 .7]);
        text(Obj2COM(1).Centroid(1)-40,Obj2COM(1).Centroid(2),[num2str(total_time2) ' s'],'BackgroundColor',[.7 .9 .7]);
        text(Obj3COM(1).Centroid(1)-40,Obj3COM(1).Centroid(2),[num2str(total_time3) ' s'],'BackgroundColor',[.7 .9 .7]);
    end
end
if(RightMouse)
    plot(Mouse2COM(start_idx:end-1,1),Mouse2COM(start_idx:end-1,2),'k');
    C = regionprops(Info.ROIs.surface_right,'BoundingBox');
    px_per_inch_R = mean([C.BoundingBox(3)/box_dim(1) C.BoundingBox(4)/box_dim(2)]);
    center_BW_R = imerode(Info.ROIs.surface_right,ones(ceil(2*periphery*px_per_inch_R)));
    periphery_BW_R = Info.ROIs.surface_right - center_BW_R;
    
    % Show the boundaries
    B = bwboundaries(Info.ROIs.surface_right);
    plot(B{1}(:,2),B{1}(:,1),'b','LineWidth',4)
    B = bwboundaries(center_BW_R);
    plot(B{1}(:,2),B{1}(:,1),'r','LineWidth',4)
    
    
    if(Info.RightObjects)
        text(Obj4COM(1).Centroid(1)-40,Obj4COM(1).Centroid(2),[num2str(total_time4) ' s'],'BackgroundColor',[.7 .9 .7]);
        text(Obj5COM(1).Centroid(1)-40,Obj5COM(1).Centroid(2),[num2str(total_time5) ' s'],'BackgroundColor',[.7 .9 .7]);
        text(Obj6COM(1).Centroid(1)-40,Obj6COM(1).Centroid(2),[num2str(total_time6) ' s'],'BackgroundColor',[.7 .9 .7]);
    end
end
if(LeftMouse)
    subplot(2,3,2);
    C = regionprops(Info.ROIs.surface_left,'BoundingBox');
    I1 = imcrop(Icomposite,C.BoundingBox);
    imagesc(I1); axis image; colormap('jet'); colorbar;drawnow;
    set(gca,'YTickLabel',[]); set(gca,'XTickLabel',[]);
    title(sprintf('Left mouse, tag# %s\nTotal time spent in arena',Info.LeftTag));
    
    if(Info.LeftObjects)
        subplot(2,3,3);
        I1 = imcrop(Ibouts,C.BoundingBox);
        imagesc(I1); axis image; colorbar; drawnow; colormap('jet');
        set(gca,'YTickLabel',[]); set(gca,'XTickLabel',[]);
        title(sprintf('Left mouse, tag# %s\nInteraction bouts ONLY',Info.LeftTag));
    end
end

if(RightMouse)
    subplot(2,3,4);
    C = regionprops(Info.ROIs.surface_right,'BoundingBox');
    I1 = imcrop(Icomposite,C.BoundingBox);
    imagesc(I1); axis image; colormap('jet'); colorbar;drawnow;
    set(gca,'YTickLabel',[]); set(gca,'XTickLabel',[]);
    title(sprintf('Right mouse, tag# %s\n.Total time spent in arena',Info.RightTag));
    
    if(Info.RightObjects)
        subplot(2,3,5);
        I1 = imcrop(Ibouts,C.BoundingBox);
        imagesc(I1); axis image; colorbar; drawnow; colormap('jet');
        set(gca,'YTickLabel',[]); set(gca,'XTickLabel',[]);
        title(sprintf('Right mouse, tag# %s\nInteraction bouts ONLY',Info.RightTag));
    end
end

if(Info.LeftMouse)
    
    % Compute the amount of time spent in corners, center and periphery
    [TimeSitting, TimeCorners, TimeOuter, TimeCenter,TimeInner,path_length,thigmotaxis,~,TimeSitting_in_corner,Motion]...
        = OpenField_L(Mouse1COM,start_idx,end_idx,Info,fps,Tail1,duration,box_dim);
    
    analysis.LeftOuter = TimeOuter;
    analysis.LeftInner = TimeInner;
    analysis.Left_pathl = Motion;
    analysis.LeftTotalDistance = path_length;
    
end

if(Info.RightMouse)
    
    [TimeSitting, TimeCorners, TimeOuter, TimeCenter,TimeInner,path_length,thigmotaxis,~,TimeSitting_in_corner,Motion]...
        = OpenField_R(Mouse2COM,start_idx,end_idx,Info,fps,Tail2,duration,box_dim);
    
    analysis.RightOuter = TimeOuter;
    analysis.RightInner = TimeInner;
    analysis.Right_pathl = Motion;
    analysis.RightTotalDistance = path_length;
    
    
end

subplot(2,3,6);
legendtxt = [];

if(LeftMouse)
    plot(times(start_idx:end_idx),cumsum(analysis.Left_pathl(start_idx:end)),'b');
    legendtxt = [legendtxt {'Left Mouse'}];
end

hold on

if(RightMouse)
    plot(times(start_idx:end_idx),cumsum(analysis.Right_pathl(start_idx:end)),'r');
    legendtxt = [legendtxt {'Right Mouse'}];
end


legend(legendtxt,'Location','Best');

xlabel('Times (s)');
ylabel('Cumulative ambulation (inches)');

analysis.Info = Info;
analysis.Icomposite = Icomposite;



set(gcf,'Units','Normalized','Position',[0 0 1 1],'PaperPositionMode','auto','PaperSize',[14 14]);

folder_name = fileparts(abs_mv_path);
% If SOR_results directory does not exist, create it
if(~exist([folder_name '/SOR_results'],'dir'))
    mkdir([folder_name '/SOR_results']);
end
[~,vidname] = fileparts(abs_mv_path);
imgfilename = [folder_name '/SOR_results/' vidname '_summary'];
print(gcf,[imgfilename '.tif'],'-dtiff','-r300');
delete(hsum);

save([folder_name '/SOR_results/' vidname '.mat'],'analysis');
% disp(['Finished processing ' abs_mv_path]);
parfor_progress(0,fname,vidname);
try
    delete(hbar);
end


intervals = duration/(60*5);
% Output results to a txt file in /SOR_results directory
fid = fopen([folder_name '/SOR_results/' vidname '.txt'],'w');
fprintf(fid,'Filename \t Mouse Tag \t Glass Time (s) \t Metal Time (s) \t Cylinder Time (s) \t Total Ambulation (inch)');
for i=1:intervals
    fprintf(fid,'\tTime in outer %i',i);
end
for i=1:intervals
    fprintf(fid,'\tTime in inner %i',i);
end

fprintf(fid,'\n');

s = analysis;
%         try
%         Ambulation = sum(s.PathLength);
if(s.Info.LeftMouse && s.Info.LeftObjects)
    if(isfield(s.Info,'Novel') && ~isempty(s.Info.Novel))
        Novel = zeros(6,1);
        for m=1:length(s.Info.Novel)
            Novel(m) = s.Info.Novel(m);
        end
        if(Novel(1))
            TimeGlassLeft = sprintf('%.2f**',s.TimeGlassLeft);
        else
            TimeGlassLeft = sprintf('%.2f',s.TimeGlassLeft);
        end
        if(Novel(2))
            TimeMetalLeft = sprintf('%.2f**',s.TimeMetalLeft);
        else
            TimeMetalLeft = sprintf('%.2f',s.TimeMetalLeft);
        end
        if(Novel(3))
            TimeCylinderLeft = sprintf('%.2f**',s.TimeCylinderLeft);
        else
            TimeCylinderLeft = sprintf('%.2f',s.TimeCylinderLeft);
        end
        
        fprintf(fid,'%s \t %s \t %s \t %s \t %s \t% .2f',s.filename,s.Info.LeftTag,TimeGlassLeft,TimeMetalLeft,TimeCylinderLeft,...
            s.LeftTotalDistance);
    else
        fprintf(fid,'%s \t %s \t %.2f \t %.2f \t %.2f \t %.2f',s.filename,s.Info.LeftTag,s.TimeGlassLeft,s.TimeMetalLeft,s.TimeCylinderLeft,...
            s.LeftTotalDistance);
    end
    
    for k=1:length(s.LeftOuter)
        fprintf(fid,'\t%.2f',s.LeftOuter(k));
    end
    for k=1:length(s.LeftInner)
        fprintf(fid,'\t%.2f',s.LeftInner(k));
    end
    
    
    fprintf(fid,'\n');
end
if(s.Info.RightMouse && s.Info.RightObjects)
    if(isfield(s.Info,'Novel') && ~isempty(s.Info.Novel))
        Novel = zeros(6,1);
        for m=1:length(s.Info.Novel)
            Novel(m) = s.Info.Novel(m);
        end
        if(Novel(4))
            TimeGlassRight = sprintf('%.2f**',s.TimeGlassRight);
        else
            TimeGlassRight = sprintf('%.2f',s.TimeGlassRight);
        end
        if(Novel(5))
            TimeMetalRight = sprintf('%.2f**',s.TimeMetalRight);
        else
            TimeMetalRight = sprintf('%.2f',s.TimeMetalRight);
        end
        if(Novel(6))
            TimeCylinderRight = sprintf('%.2f**',s.TimeCylinderRight);
        else
            TimeCylinderRight = sprintf('%.2f',s.TimeCylinderRight);
        end
        fprintf(fid,'%s \t %s \t %s \t %s \t%s \t %.2f',s.filename,s.Info.RightTag,TimeGlassRight,TimeMetalRight,TimeCylinderRight,...
            s.RightTotalDistance);
    else
        fprintf(fid,'%s \t %s \t %.2f \t %.2f \t%.2f\t%.2f',s.filename,s.Info.RightTag,s.TimeGlassRight,s.TimeMetalRight,s.TimeCylinderRight,...
            s.RightTotalDistance);
    end
    
    for k=1:length(s.RightOuter)
        fprintf(fid,'\t%.2f',s.RightOuter(k));
    end
    for k=1:length(s.RightInner)
        fprintf(fid,'\t%.2f',s.RightInner(k));
    end
    
    fprintf(fid,'\n');
    
end
if(s.Info.LeftMouse && ~s.Info.LeftObjects)
    
    fprintf(fid,'%s \t %s \t -1\t -1\t%.2f',s.filename,s.Info.LeftTag,s.LeftTotalDistance);
    
    for k=1:length(s.LeftOuter)
        fprintf(fid,'\t%.2f',s.LeftOuter(k));
    end
    for k=1:length(s.LeftInner)
        fprintf(fid,'\t%.2f',s.LeftInner(k));
    end
    
    fprintf(fid,'\n');
    
end
if(s.Info.RightMouse && ~s.Info.RightObjects)
    
    fprintf(fid,'%s \t %s \t -1 \t -1\t%.2f',s.filename,s.Info.RightTag,s.RightTotalDistance);
    
    for k=1:length(s.RightOuter)
        fprintf(fid,'\t%.2f',s.RightOuter(k));
    end
    for k=1:length(s.RightInner)
        fprintf(fid,'\t%.2f',s.RightInner(k));
    end
    
    fprintf(fid,'\n');
end
fclose(fid);