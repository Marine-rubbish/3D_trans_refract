# 最小子集说明

## 保留：匹配核心

- `pipeline/simu_all_crests_trans_dir_pro.m`：当前采用方向约束的匹配方案。
- `legacy_reproduce_855/test_all_crests_trans.m`：复现旧版 `matched_crests_params_855.mat` 的处理行为。
- `utils/tools/getTimeFromFilename.m`：从文件名中解析 MODIS 观测时间。
- `utils/trans/calcDirection.m`：估算波峰传播方向。
- `utils/trans/maybeFlipCrestDir.m`：用于平直波峰的可选方向翻转逻辑。
- `utils/trans/isCrestPassMooring_bin.m`：旧版候选波峰通过测试。
- `utils/trans/isCrestPassMooring_bin_dir.m`：采用方向和位置约束的候选波峰通过测试。
- `utils/trans/reachMooringByTranslation.m`：平移几何计算及与 K 相关的命中位置计算。
- `utils/trans/calcPropagation.m`、`calcDisLinePoint.m`、`calcCrestLen.m`、`calcCrestLenPro.m`：几何辅助函数。

## 保留：诊断与绘图

- `diagnostics/test_mat_corr.m`：对 855/808 结果进行比较和可视化审查，后续需要加入时空投影检查。
- `diagnostics/test_matched_all_crests.m`：绘制所有已匹配的波峰。
- `diagnostics/test_matched_crests.m`：为每项匹配生成图像。
- `diagnostics/test_maybeFlipCrestDir.m`：方向翻转的可视化测试。
- `visualization/plot_MODIS_and_crest.m`：叠加显示 MODIS 图像和波峰。
- `visualization/plot_MODIS_and_crest_prop.m`：可视化传播后的波峰。
- `visualization/plot_matched_crests*.m`：已匹配波峰的地图和密度视图。
- `visualization/plot_crest_dens*.m`：波峰密度视图。
- `visualization/plot_crest_direction*.m`：波峰方向视图。
- `visualization/plot_MODIS_img*.m`：单幅图像或单项匹配的可视化。
- `visualization/search_crest_by_coord.m`、`SCS_Map.m`：可视化搜索和地图辅助函数。

## 后续整理事项

1. 使用统一的配置文件替代硬编码路径。
2. 合并 `isCrestPassMooring_bin` 和 `isCrestPassMooring_bin_dir`，或为二者采用含义清晰的名称。
3. 在诊断流程中加入自动时空投影验证。
4. 将绘图逻辑与匹配脚本分离。
5. 在将方向约束作为可靠依据之前，修复 `cDir` / `dirDeg` 的翻转赋值问题。

