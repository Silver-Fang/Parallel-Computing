function V = Version
V.Me='v7.1.2';
V.MatlabExtension=MATLAB.Version;
V.MATLAB='R2022b';
persistent NewVersion
try
	if isempty(NewVersion)
		NewVersion=TextAnalytics.CheckUpdateFromGitHub('https://github.com/Silver-Fang/Parallel-Computing/releases','埃博拉酱的并行计算工具箱',V.Me);
	end
catch ME
	if ME.identifier~="MATLAB:undefinedVarOrClass"
		ME.rethrow;
	end
end