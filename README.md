# 3D_trans_refract

这是从 `3D_trans` 中提取出的最小可运行子集。

## 目录结构

- `pipeline/`：当前主要的匹配方案。
- `legacy_reproduce_855/`：用于复现 `matched_crests_params_855.mat` 的旧版脚本。
- `diagnostics/`：用于检查和可视化审查匹配结果的脚本。
- `visualization/`：从 `utils/viusalize` 复制的实用绘图脚本。
- `utils/`：匹配和诊断所使用的核心辅助函数。
- `data/`：供诊断脚本使用的少量现有结果文件。

## 主要入口

- 推荐的匹配方案：`pipeline/simu_all_crests_trans_dir_pro.m`
- 旧版 855 结果复现：`legacy_reproduce_855/test_all_crests_trans.m`
- 当前诊断检查：`diagnostics/test_mat_corr.m`

## 注意事项

部分复制过来的 MATLAB 脚本仍包含原项目中硬编码的 `F:\research\...` 路径。在当前计算机上，应将其修改为 `F:\research\...`；更理想的做法是在下一轮整理前，将这些路径移入一个共享配置文件。

部分可视化脚本依赖 MATLAB Mapping Toolbox 和/或 M_Map 函数（`m_proj`、`m_plot`、`m_grid` 等）。保留这些脚本是因为它们有助于诊断，但运行时仍需确保相应的外部工具箱可用。

未复制 `visualization/plot_crest_trans.m` 是有意为之，因为原函数引用了未定义变量，目前并不可靠。

