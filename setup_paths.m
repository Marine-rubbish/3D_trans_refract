function setup_paths()
%SETUP_PATHS Add the minimal project folders to the MATLAB path.
% Run this from the repository root before running pipeline/diagnostic scripts.

rootDir = fileparts(mfilename('fullpath'));
addpath(genpath(fullfile(rootDir, 'utils')));
addpath(fullfile(rootDir, 'pipeline'));
addpath(fullfile(rootDir, 'diagnostics'));
addpath(fullfile(rootDir, 'visualization'));
end
