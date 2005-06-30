function handles = BatchOutputImportMySQL(handles)

% Help for the Batch Ouput Import to MySQL module:
% Category: File Handling
%
% This module creates SQL files from batch run output files.
%
% It does not make sense to run this module in conjunction with other
% modules.  It should be the only module in the pipeline.
%
% See also: CREATEBATCHSCRIPTS.

% CellProfiler is distributed under the GNU General Public License.
% See the accompanying file LICENSE for details.
%
% Developed by the Whitehead Institute for Biomedical Research.
% Copyright 2003,2004,2005.
%
% Authors:
%   Anne Carpenter <carpenter@wi.mit.edu>
%   Thouis Jones   <thouis@csail.mit.edu>
%   In Han Kang    <inthek@mit.edu>
%
% $Revision$

% PROGRAMMING NOTE
% HELP:
% The first unbroken block of lines will be extracted as help by
% CellProfiler's 'Help for this analysis module' button as well as Matlab's
% built in 'help' and 'doc' functions at the command line. It will also be
% used to automatically generate a manual page for the module. An example
% image demonstrating the function of the module can also be saved in tif
% format, using the same name as the module, and it will automatically be
% included in the manual page as well.  Follow the convention of: purpose
% of the module, description of the variables and acceptable range for
% each, how it works (technical description), info on which images can be
% saved, and See also CAPITALLETTEROTHERMODULES. The license/author
% information should be separated from the help lines with a blank line so
% that it does not show up in the help displays.  Do not change the
% programming notes in any modules! These are standard across all modules
% for maintenance purposes, so anything module-specific should be kept
% separate.

% PROGRAMMING NOTE
% DRAWNOW:
% The 'drawnow' function allows figure windows to be updated and
% buttons to be pushed (like the pause, cancel, help, and view
% buttons).  The 'drawnow' function is sprinkled throughout the code
% so there are plenty of breaks where the figure windows/buttons can
% be interacted with.  This does theoretically slow the computation
% somewhat, so it might be reasonable to remove most of these lines
% when running jobs on a cluster where speed is important.
drawnow

%%%%%%%%%%%%%%%%
%%% VARIABLES %%%
%%%%%%%%%%%%%%%%
drawnow

% PROGRAMMING NOTE
% VARIABLE BOXES AND TEXT:
% The '%textVAR' lines contain the variable descriptions which are
% displayed in the CellProfiler main window next to each variable box.
% This text will wrap appropriately so it can be as long as desired.
% The '%defaultVAR' lines contain the default values which are
% displayed in the variable boxes when the user loads the module.
% The line of code after the textVAR and defaultVAR extracts the value
% that the user has entered from the handles structure and saves it as
% a variable in the workspace of this module with a descriptive
% name. The syntax is important for the %textVAR and %defaultVAR
% lines: be sure there is a space before and after the equals sign and
% also that the capitalization is as shown.
% CellProfiler uses VariableRevisionNumbers to help programmers notify
% users when something significant has changed about the variables.
% For example, if you have switched the position of two variables,
% loading a pipeline made with the old version of the module will not
% behave as expected when using the new version of the module, because
% the settings (variables) will be mixed up. The line should use this
% syntax, with a two digit number for the VariableRevisionNumber:
% '%%%VariableRevisionNumber = 01'  If the module does not have this
% line, the VariableRevisionNumber is assumed to be 00.  This number
% need only be incremented when a change made to the modules will affect
% a user's previously saved settings. There is a revision number at
% the end of the license info at the top of the m-file for revisions
% that do not affect the user's previously saved settings files.

%%% Reads the current module number, because this is needed to find
%%% the variable values that the user entered.
CurrentModule = handles.Current.CurrentModuleNumber;
CurrentModuleNum = str2double(CurrentModule);

%textVAR01 = What is the path to the directory where the batch files were saved? Leave a period (.) to retrieve images from the default output directory #LongBox#
%defaultVAR01 = ../Batch
BatchPath = char(handles.Settings.VariableValues{CurrentModuleNum,1});

%textVAR02 = What was the prefix of the batch files? #LongBox#
%defaultVAR02 = Batch_
BatchFilePrefix = char(handles.Settings.VariableValues{CurrentModuleNum,2});

%textVAR03 = What is the name of the database to use?
%defaultVAR03 = Slide07
DatabaseName = char(handles.Settings.VariableValues{CurrentModuleNum,3});

%%%VariableRevisionNumber = 01
% The variables have changed for this module.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% PRELIMINARY CALCULATIONS & FILE HANDLING %%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

if strcmp(BatchPath, '.') == 1
    BatchPath = handles.Current.DefaultOutputDirectory;
end

%%% If this isn't the first image set, we're probably running on the
%%% cluster, and should just continue.
if (handles.Current.SetBeingAnalyzed > 1),
    return;
end

%%% Load the data file
BatchData = load(fullfile(BatchPath,[BatchFilePrefix 'data.mat']));


%%% Create the SQL script
SQLMainFileName = sprintf('%s/%sdata.SQL', BatchPath, BatchFilePrefix);
SQLMainFile = fopen(SQLMainFileName, 'wt');
if SQLMainFile == -1,
    error(['Could not open ' SQLMainFileName ' for writing.']);
end
fprintf(SQLMainFile, 'USE %s;\n', DatabaseName);

% temp fix
BatchData.handles.Measurements.ImageThresholdNuclei = BatchData.handles.Measurements.GeneralInfo.ImageThresholdNuclei;
BatchData.handles.Measurements.ImageThresholdCells = BatchData.handles.Measurements.GeneralInfo.ImageThresholdCells;
BatchData.handles.Measurements = rmfield(BatchData.handles.Measurements, 'GeneralInfo');

%%% get the list of measurements
Fieldnames = fieldnames(BatchData.handles.Measurements);

%%% create tables
ImageFieldNames = Fieldnames(strncmp(Fieldnames, 'Image', 5));
fprintf(SQLMainFile, 'DROP TABLE IF EXISTS spots;\n');
fprintf(SQLMainFile, 'CREATE TABLE spots (spotnumber INTEGER PRIMARY KEY');
for i = 1:length(ImageFieldNames),
    fprintf(SQLMainFile, ', %s FLOAT', char(ImageFieldNames{i}));
end
OtherFieldNames = Fieldnames((~ strncmp(Fieldnames, 'Image', 5)) & (~ strncmp(Fieldnames, 'Object', 6)) & (~ strncmp(Fieldnames, 'Pathname', 8)));
for i = 1:length(OtherFieldNames),
    fprintf(SQLMainFile, ', %s CHAR(50)', char(OtherFieldNames{i}));
end
% Should also handle imported headings
% HeadingFieldNames = BatchData.handles.Measurements.headings
fprintf(SQLMainFile, ');\n');

ObjectFieldNames = Fieldnames(strncmp(Fieldnames, 'Object', 6));
fprintf(SQLMainFile, 'DROP TABLE IF EXISTS cells;\n');
fprintf(SQLMainFile, 'CREATE TABLE cells (spotnumber integer, cellnumber integer');
for i = 1:length(ObjectFieldNames),
    fprintf(SQLMainFile, ', %s FLOAT', char(ObjectFieldNames{i}));
end
fprintf(SQLMainFile, ', PRIMARY KEY (spotnumber, cellnumber));\n');

%%% write a data file for the first spot
SQLSubFileName = sprintf('%s/%s1_to_1.Image.SQL', BatchPath, BatchFilePrefix);
SQLSubFile = fopen(SQLSubFileName, 'wt');
if SQLSubFile == -1,
    fclose(SQLMainFile);
    error(['Could not open ' SQLSubFileName ' for writing.']);
end
fprintf(SQLSubFile, '1');
for i = 1:length(ImageFieldNames),
    fprintf(SQLSubFile, '|%d', BatchData.handles.Measurements.(char(ImageFieldNames{i})){1});
end
for i = 1:length(OtherFieldNames),
    fprintf(SQLSubFile, '|%s', BatchData.handles.Measurements.(char(OtherFieldNames{i})){1});
end
fprintf(SQLSubFile, '\n');
fclose(SQLSubFile);
SQLSubFileName = sprintf('%s1_to_1.Image.SQL', BatchFilePrefix);
fprintf(SQLMainFile, 'LOAD DATA LOCAL INFILE ''%s'' REPLACE INTO TABLE spots FIELDS TERMINATED BY ''|'';\n', SQLSubFileName);

if (length(ObjectFieldNames) > 0),
    SQLSubFileName = sprintf('%s/%s1_to_1.Object.SQL', BatchPath, BatchFilePrefix);
    SQLSubFile = fopen(SQLSubFileName, 'wt');
    if SQLSubFile == -1,
        fclose(SQLMainFile);
        error(['Could not open ' SQLSubFileName ' for writing.']);
    end
    for cellcount = 1:length(BatchData.handles.Measurements.(char(ObjectFieldNames{1})){1}),
        fprintf(SQLSubFile, '1|%d', cellcount);
        for i = 1:length(ObjectFieldNames),
            msr = BatchData.handles.Measurements.(char(ObjectFieldNames{i})){1};
            fprintf(SQLSubFile, '|%d', msr(cellcount));
        end
        fprintf(SQLSubFile, '\n');
    end
    fclose(SQLSubFile);
    SQLSubFileName = sprintf('%s1_to_1.Object.SQL', BatchFilePrefix);
    fprintf(SQLMainFile, 'LOAD DATA LOCAL INFILE ''%s'' REPLACE INTO TABLE cells FIELDS TERMINATED BY ''|'';\n', SQLSubFileName);
end


%%% Write files for the other batches
FileList = dir(BatchPath);
Matches = ~ cellfun('isempty', regexp({FileList.name}, ['^' BatchFilePrefix '[0-9]+_to_[0-9]+_OUT.mat$']));
FileList = FileList(Matches);

WaitbarHandle = waitbar(0,'Writing SQL files');
for filenum = 1:length(FileList),
    SubsetData = load(fullfile(BatchPath,FileList(filenum).name));

    SubsetData.handles.Measurements.ImageThresholdNuclei = SubsetData.handles.Measurements.GeneralInfo.ImageThresholdNuclei;
    SubsetData.handles.Measurements.ImageThresholdCells = SubsetData.handles.Measurements.GeneralInfo.ImageThresholdCells;
    SubsetData.handles.Measurements = rmfield(SubsetData.handles.Measurements, 'GeneralInfo');

    if (isfield(SubsetData.handles, 'BatchError')),
        fclose(SQLMainFile);
        error(['Error writing SQL data from batch file output.  File ' BatchPath '/' FileList(i).name ' encountered an error during batch processing.  The error was ' SubsetData.handles.BatchError '.  Please re-run that batch file.']);
    end

    matches = regexp(FileList(filenum).name, '[0-9]+', 'match');
    lo = str2num(matches{end-1});
    hi = str2num(matches{end});


    SubSetMeasurements = SubsetData.handles.Measurements;
    SQLSubFileName = sprintf('%s/%s%d_to_%d.Image.SQL', BatchPath, BatchFilePrefix, lo, hi);
    SQLSubFile = fopen(SQLSubFileName, 'wt');
    if SQLSubFile == -1,
        fclose(SQLMainFile);
        error(['Could not open ' SQLSubFileName ' for writing.']);
    end

    for spotnum = lo:hi,
        %%% write a data file for the spotnum-th spot
        fprintf(SQLSubFile, '%d', spotnum);
        for i = 1:length(ImageFieldNames),
            if (length(SubSetMeasurements.(char(ImageFieldNames{i}))) >= spotnum),
                fprintf(SQLSubFile, '|%d', SubSetMeasurements.(char(ImageFieldNames{i})){spotnum});
            else
                fprintf(SQLSubFile, '|');
            end
        end
        for i = 1:length(OtherFieldNames),
            if (length(SubSetMeasurements.(char(OtherFieldNames{i}))) >= spotnum),
                fprintf(SQLSubFile, '|%s', SubSetMeasurements.(char(OtherFieldNames{i})){spotnum});
            else
                fprintf(SQLSubFile, '|');
            end
        end
        fprintf(SQLSubFile, '\n');
    end
    fclose(SQLSubFile);
    SQLSubFileName = sprintf('%s%d_to_%d.Image.SQL', BatchFilePrefix, lo, hi);
    fprintf(SQLMainFile, 'LOAD DATA LOCAL INFILE ''%s'' REPLACE INTO TABLE spots FIELDS TERMINATED BY ''|'';\n', SQLSubFileName);


    if (length(ObjectFieldNames) > 0),
        SQLSubFileName = sprintf('%s/%s%d_to_%d.Object.SQL', BatchPath, BatchFilePrefix, lo, hi);
        SQLSubFile = fopen(SQLSubFileName, 'wt');
        if SQLSubFile == -1,
            fclose(SQLMainFile);
            error(['Could not open ' SQLSubFileName ' for writing.']);
        end
        for spotnum = lo:hi,
            if (length(SubSetMeasurements.(char(ObjectFieldNames{1}))) >= spotnum),
                for cellcount = 1:length(SubSetMeasurements.(char(ObjectFieldNames{1})){spotnum}),
                    fprintf(SQLSubFile, '%d|%d', spotnum, cellcount);
                    for i = 1:length(ObjectFieldNames),
                        fprintf(SQLSubFile, '|%d', SubSetMeasurements.(char(ObjectFieldNames{i})){spotnum}(cellcount));
                    end
                    fprintf(SQLSubFile, '\n');
                end
            end
        end
        fclose(SQLSubFile);
        SQLSubFileName = sprintf('%s%d_to_%d.Object.SQL', BatchFilePrefix, lo, hi);
        fprintf(SQLMainFile, 'LOAD DATA LOCAL INFILE ''%s'' REPLACE INTO TABLE cells FIELDS TERMINATED BY ''|'';\n', SQLSubFileName);
    end

    waitbar(filenum/length(FileList), WaitbarHandle);
end

fclose(SQLMainFile);
close(WaitbarHandle);

% PROGRAMMING NOTE
% TO TEMPORARILY SHOW IMAGES DURING DEBUGGING:
% figure, imshow(BlurredImage, []), title('BlurredImage')
% TO TEMPORARILY SAVE IMAGES DURING DEBUGGING:
% imwrite(BlurredImage, FileName, FileFormat);
% Note that you may have to alter the format of the image before
% saving.  If the image is not saved correctly, for example, try
% adding the uint8 command:
% imwrite(uint8(BlurredImage), FileName, FileFormat);
% To routinely save images produced by this module, see the help in
% the SaveImages module.

%%%%%%%%%%%%%%%%%%%%%%
%%% DISPLAY RESULTS %%%
%%%%%%%%%%%%%%%%%%%%%%

%%% The figure window display is unnecessary for this module, so the figure
%%% window is closed if it was previously open.
%%% Determines the figure number.
fieldname = ['FigureNumberForModule',CurrentModule];
ThisModuleFigureNumber = handles.Current.(fieldname);
%%% If the window is open, it is closed.
if any(findobj == ThisModuleFigureNumber) == 1;
    delete(ThisModuleFigureNumber)
end

% PROGRAMMING NOTES THAT ARE UNNECESSARY FOR THIS MODULE:
% PROGRAMMING NOTE
% DISPLAYING RESULTS:
% Some calculations produce images that are used only for display or
% for saving to the hard drive, and are not used by downstream
% modules. To speed processing, these calculations are omitted if the
% figure window is closed and the user does not want to save the
% images.

% PROGRAMMING NOTE
% DRAWNOW BEFORE FIGURE COMMAND:
% The "drawnow" function executes any pending figure window-related
% commands.  In general, Matlab does not update figure windows until
% breaks between image analysis modules, or when a few select commands
% are used. "figure" and "drawnow" are two of the commands that allow
% Matlab to pause and carry out any pending figure window- related
% commands (like zooming, or pressing timer pause or cancel buttons or
% pressing a help button.)  If the drawnow command is not used
% immediately prior to the figure(ThisModuleFigureNumber) line, then
% immediately after the figure line executes, the other commands that
% have been waiting are executed in the other windows.  Then, when
% Matlab returns to this module and goes to the subplot line, the
% figure which is active is not necessarily the correct one. This
% results in strange things like the subplots appearing in the timer
% window or in the wrong figure window, or in help dialog boxes.
%
% PROGRAMMING NOTE
% HANDLES STRUCTURE:
%       In CellProfiler (and Matlab in general), each independent
% function (module) has its own workspace and is not able to 'see'
% variables produced by other modules. For data or images to be shared
% from one module to the next, they must be saved to what is called
% the 'handles structure'. This is a variable, whose class is
% 'structure', and whose name is handles. The contents of the handles
% structure are printed out at the command line of Matlab using the
% Tech Diagnosis button. The only variables present in the main
% handles structure are handles to figures and gui elements.
% Everything else should be saved in one of the following
% substructures:
%
% handles.Settings:
%       Everything in handles.Settings is stored when the user uses
% the Save pipeline button, and these data are loaded into
% CellProfiler when the user uses the Load pipeline button. This
% substructure contains all necessary information to re-create a
% pipeline, including which modules were used (including variable
% revision numbers), their setting (variables), and the pixel size.
%   Fields currently in handles.Settings: PixelSize, ModuleNames,
% VariableValues, NumbersOfVariables, VariableRevisionNumbers.
%
% handles.Pipeline:
%       This substructure is deleted at the beginning of the
% analysis run (see 'Which substructures are deleted prior to an
% analysis run?' below). handles.Pipeline is for storing data which
% must be retrieved by other modules. This data can be overwritten as
% each image set is processed, or it can be generated once and then
% retrieved during every subsequent image set's processing, or it can
% be saved for each image set by saving it according to which image
% set is being analyzed, depending on how it will be used by other
% modules. Any module which produces or passes on an image needs to
% also pass along the original filename of the image, named after the
% new image name, so that if the SaveImages module attempts to save
% the resulting image, it can be named by appending text to the
% original file name.
%   Example fields in handles.Pipeline: FileListOrigBlue,
% PathnameOrigBlue, FilenameOrigBlue, OrigBlue (which contains the actual image).
%
% handles.Current:
%       This substructure contains information needed for the main
% CellProfiler window display and for the various modules to
% function. It does not contain any module-specific data (which is in
% handles.Pipeline).
%   Example fields in handles.Current: NumberOfModules,
% StartupDirectory, DefaultOutputDirectory, DefaultImageDirectory,
% FilenamesInImageDir, CellProfilerPathname, ImageToolHelp,
% DataToolHelp, FigureNumberForModule01, NumberOfImageSets,
% SetBeingAnalyzed, TimeStarted, CurrentModuleNumber.
%
% handles.Preferences:
%       Everything in handles.Preferences is stored in the file
% CellProfilerPreferences.mat when the user uses the Set Preferences
% button. These preferences are loaded upon launching CellProfiler.
% The PixelSize, DefaultImageDirectory, and DefaultOutputDirectory
% fields can be changed for the current session by the user using edit
% boxes in the main CellProfiler window, which changes their values in
% handles.Current. Therefore, handles.Current is most likely where you
% should retrieve this information if needed within a module.
%   Fields currently in handles.Preferences: PixelSize, FontSize,
% DefaultModuleDirectory, DefaultOutputDirectory,
% DefaultImageDirectory.
%
% handles.Measurements
%      Data extracted from input images are stored in the
% handles.Measurements substructure for exporting or further analysis.
% This substructure is deleted at the beginning of the analysis run
% (see 'Which substructures are deleted prior to an analysis run?'
% below). The Measurements structure is organized in two levels. At
% the first level, directly under handles.Measurements, there are
% substructures (fields) containing measurements of different objects.
% The names of the objects are specified by the user in the Identify
% modules (e.g. 'Cells', 'Nuclei', 'Colonies').  In addition to these
% object fields is a field called 'Image' which contains information
% relating to entire images, such as filenames, thresholds and
% measurements derived from an entire image. That is, the Image field
% contains any features where there is one value for the entire image.
% As an example, the first level might contain the fields
% handles.Measurements.Image, handles.Measurements.Cells and
% handles.Measurements.Nuclei.
%      In the second level, the measurements are stored in matrices
% with dimension [#objects x #features]. Each measurement module
% writes its own block; for example, the MeasureAreaShape module
% writes shape measurements of 'Cells' in
% handles.Measurements.Cells.AreaShape. An associated cell array of
% dimension [1 x #features] with suffix 'Features' contains the names
% or descriptions of the measurements. The export data tools, e.g.
% ExportData, triggers on this 'Features' suffix. Measurements or data
% that do not follow the convention described above, or that should
% not be exported via the conventional export tools, can thereby be
% stored in the handles.Measurements structure by leaving out the
% '....Features' field. This data will then be invisible to the
% existing export tools.
%      Following is an example where we have measured the area and
% perimeter of 3 cells in the first image and 4 cells in the second
% image. The first column contains the Area measurements and the
% second column contains the Perimeter measurements.  Each row
% contains measurements for a different cell:
% handles.Measurements.Cells.AreaShapeFeatures = {'Area' 'Perimeter'}
% handles.Measurements.Cells.AreaShape{1} = 	40		20
%                                               100		55
%                                              	200		87
% handles.Measurements.Cells.AreaShape{2} = 	130		100
%                                               90		45
%                                               100		67
%                                               45		22
%
% Which substructures are deleted prior to an analysis run?
%       Anything stored in handles.Measurements or handles.Pipeline
% will be deleted at the beginning of the analysis run, whereas
% anything stored in handles.Settings, handles.Preferences, and
% handles.Current will be retained from one analysis to the next. It
% is important to think about which of these data should be deleted at
% the end of an analysis run because of the way Matlab saves
% variables: For example, a user might process 12 image sets of nuclei
% which results in a set of 12 measurements ("ImageTotalNucArea")
% stored in handles.Measurements. In addition, a processed image of
% nuclei from the last image set is left in the handles structure
% ("SegmNucImg"). Now, if the user uses a different algorithm which
% happens to have the same measurement output name "ImageTotalNucArea"
% to analyze 4 image sets, the 4 measurements will overwrite the first
% 4 measurements of the previous analysis, but the remaining 8
% measurements will still be present. So, the user will end up with 12
% measurements from the 4 sets. Another potential problem is that if,
% in the second analysis run, the user runs only a module which
% depends on the output "SegmNucImg" but does not run a module that
% produces an image by that name, the module will run just fine: it
% will just repeatedly use the processed image of nuclei leftover from
% the last image set, which was left in handles.Pipeline.
