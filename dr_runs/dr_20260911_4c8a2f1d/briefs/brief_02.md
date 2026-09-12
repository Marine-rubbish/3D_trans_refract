# 方法与公式

## 1. 两层长波与连续层化模态

- 刚盖、无背景流、静力长波的两层界面模态相速为 \(c_0^2=g'h_1h_2/(h_1+h_2)\)，其中 \(g'=g(\rho_2-\rho_1)/\rho_0\)；不作 Boussinesq 密度惯性近似时可写为 \(c_0^2=g(\rho_2-\rho_1)h_1h_2/(\rho_1h_2+\rho_2h_1)\)。\(h_1,h_2\)[m]、\(g'\)[m s⁻²]、\(c_0\)[m s⁻¹]；自由表面、有限波长、旋转或剪切均会改变该式 | https://doi.org/10.1146/annurev.fluid.38.050304.092129 | 二手（P1 权威综述，证据 A） | 2006 | Helfrich & Melville, “Long Nonlinear Internal Waves”, Annual Review of Fluid Mechanics 38:395–425；弱非线性长内波框架，摘要明确以 KdV 为主并指出强非线性需全非线性模型；公式为该框架下标准两层刚盖长波极限 | 方法与公式/适用边界
- 连续层化、静止背景、Boussinesq、刚盖、非旋转、静力长波的垂向位移模态满足 Sturm–Liouville 问题 \(\phi_n''+N^2(z)\phi_n/c_n^2=0\)，\(\phi_n(0)=\phi_n(-H)=0\)；\(N\)[s⁻¹]、\(z,H,\phi\)[m（若按位移归一化）]、本征值 \(c_n\)[m s⁻¹]，归一化任意但后续非线性系数必须与之相容 | https://arxiv.org/abs/1808.02248 | 一手（P0 论文原文，证据 A） | 2018/2019 | Liang & Li, “Generation of second-mode internal solitary waves during winter in the northern South China Sea”, Ocean Dynamics 69:313–321, DOI 10.1007/s10236-019-01246-6；预印本 §2、式(4)，式前一段定义 \(c_n,N,h_b,\phi_n\) | 方法与公式
- 有背景剪切时不能把静水本征值简单加一个表层流速；长波极限需解含 \(U(z)\) 的 Taylor–Goldstein 型本征问题，典型无临界层形式为 \(\phi''+N^2\phi/(U-c)^2=0\)（完整形式随选取变量及 \(U''\) 项而变），地速相速 \(c\) 已包含模态加权多普勒效应 | https://doi.org/10.1175/2010JPO4388.1 | 一手（P0 论文摘要/元数据，证据 B） | 2010 | Alford, Lien, Simmons, Klymak, Ramp, Yang, Tang & Chang, “Speed and Evolution of Nonlinear Internal Waves Transiting the South China Sea”, Journal of Physical Oceanography 40(6):1338–1355；摘要末段：用观测流场求 Taylor–Goldstein 方程解释上坡 B 波更快 | 方法与公式/背景流

## 2. KdV、Gardner/eKdV 与 DJL

- 常系数 KdV 可写为 \(\eta_t+c_0\eta_x+\alpha\eta\eta_x+\beta\eta_{xxx}=0\)；若 \(\eta\)[m]、\(x\)[m]、\(t\)[s]，则 \(c_0\)[m s⁻¹]、\(\alpha\)[s⁻¹]、\(\beta\)[m³ s⁻¹]；孤立波 \(\eta=A\,\mathrm{sech}^2[(x-Vt)/\Delta]\)，\(V=c_0+\alpha A/3\)，\(\Delta=\sqrt{12\beta/(\alpha A)}\)，要求 \(\alpha A/\beta>0\) | https://doi.org/10.1146/annurev.fluid.38.050304.092129 | 二手（P1 权威综述，证据 A） | 2006 | Helfrich & Melville, Annual Review of Fluid Mechanics 38:395–425；弱非线性、弱色散、长波、单向、单模态，摘要明确 KdV 是最常用模型 | 方法与公式/KdV
- 变系数 KdV 在缓变波导中可写为 \(Z_t+cZ_x+(cQ_x/2Q)Z+\alpha ZZ_x+\beta Z_{xxx}=0\)，其中 \(QZ^2\) 是线性长波波作用通量密度；\(c,Q,\alpha,\beta\) 随路径坐标变化，不能把起点系数固定用于全路径 | https://arxiv.org/abs/1808.02248 | 一手（P0 论文原文，证据 A） | 2018/2019 | Liang & Li, Ocean Dynamics 69:313–321，预印本 §3 “Theoretical Prediction”、式(6)及式后首段；式(7)给 Boussinesq 下 \(\alpha_n,\beta_n\) 的模态积分；Fig.1 为冬季南海非线性系数沿坡架变化，Fig.2 为 Ursell 数沿程变化 | 方法与公式/缓变环境
- Gardner/eKdV 在 KdV 上加入三次非线性：\(\eta_t+c_0\eta_x+\alpha\eta\eta_x+\alpha_1\eta^2\eta_x+\beta\eta_{xxx}=0\)；\(\alpha_1\)[m⁻¹ s⁻¹]，孤立波速度修正为 \(V-c_0=\alpha A/3+\alpha_1A^2/6\)；当 \(\alpha\) 接近零、二次非线性失效而幅度仍为弱到中等时比 KdV 合理，但仍是长波、单向、弱/中等非线性渐近模型 | https://doi.org/10.5194/npg-9-221-2002 | 一手（P0 论文元数据由 Jackson 2009 参考文献核定，证据 B） | 2002 | Grimshaw, Pelinovsky, Poloukhina & Talipova, “Higher-order Korteweg-de Vries models for internal solitary waves in a stratified shear flow with a free surface”, Nonlinear Processes in Geophysics 9:221–235；Gardner/高阶 KdV 适用背景 | 方法与公式/Gardner
- DJL 稳态全非线性位移方程在静止背景、二维、不可压、无黏、Boussinesq、非旋转条件下可写为 \(\nabla^2\eta+[N^2(z-\eta)/c^2]\eta=0\)，上下边界 \(\eta=0\)，并以孤立条件 \(\eta\to0\) 闭合；\(\eta,z,x\)[m]、\(N\)[s⁻¹]、\(c\)[m s⁻¹]，\(c\) 是随给定波能量/振幅求出的非线性本征值，不是把 KdV 修正项外加到固定 \(c_0\) | https://doi.org/10.1017/S0022112067001041 | 一手（P0 经典论文元数据，证据 B） | 1967 | Davis & Acrivos, “Solitary internal waves in deep water”, Journal of Fluid Mechanics 29:593–607；DOI 与页码由 Cai et al. 2012 参考文献核定；DJL 方法的经典源头 | 方法与公式/DJL
- DJL 数值解显示大振幅相速与结构对近表层层化敏感；开流线波可由“最大水平流速等于传播速度”的破碎极限约束，加入薄表层混合层后可转由共轭流极限约束，因此单用振幅—速度经验关系无法跨季节/跨层化外推 | https://doi.org/10.1017/S002211200100636X | 一手（P0 论文页面/摘要，证据 A） | 2002 | Kevin G. Lamb, “A numerical investigation of solitary internal waves with trapped cores formed via shoaling”, Journal of Fluid Mechanics 451:109–144；Abstract；论文研究 shoaling、trapped cores、breaking/conjugate-flow limits | 因果机制/适用边界
- 南海冬季 mode-2 算例中，前导波数值平均速度 0.67 m s⁻¹，沿程平均线性 mode-2 速度 0.56 m s⁻¹，加入非线性修正得 0.65 m s⁻¹；说明有限振幅修正可达约 16%，但该数值仅适用于文中 21.625°N、90 km 通道、12 月 WOA2013 层化及所设波幅 | https://arxiv.org/abs/1808.02248 | 一手（P0 论文原文，证据 A） | 2018/2019 | Liang & Li，预印本 §4.1，Fig.4 后第2段、Fig.5 前；具体数字位于该段，Fig.5 展示 A/B 波组放大图 | 因果机制/有限振幅修正

# 因果机制

## 3. 背景流、多普勒、二维折射与缓变环境

- 均匀背景流下观测频率与本征频率满足 \(\omega=\Omega_n+\mathbf{k}\!\cdot\!\mathbf U\)，传播方向单位向量 \(\hat{\mathbf k}\) 上的地速可写 \(c_g^{obs}=c_g^{int}+\hat{\mathbf k}\!\cdot\!\mathbf U\)；垂向剪切、临界层或强模态结构变化时必须改解 Taylor–Goldstein/DJL-with-shear，不能使用单一“表流加法” | https://doi.org/10.1175/2010JPO4388.1 | 一手（P0，证据 B） | 2010 | Alford et al., JPO 40:1338–1355；摘要关于观测流场 Taylor–Goldstein 解与内潮调制的段落 | 因果机制/背景流
- 二维/水平变化环境的射线哈密顿方程为 \(d\mathbf x/dt=\nabla_{\mathbf k}\omega\)、\(d\mathbf k/dt=-\nabla_{\mathbf x}\omega\)，局地色散关系取 \(\omega(\mathbf x,\mathbf k)=\mathbf k\cdot\mathbf U(\mathbf x)+\Omega_n(\mathbf k;H,N,A)\)；静止、各向同性、无色散极限退化为程函方程 \(|\nabla T|=1/c(\mathbf x)\)，相速梯度转动波矢，群速决定能量路径 | https://doi.org/10.1175/2009JTECHO638.1 | 一手（P0 论文摘要/元数据，证据 B） | 2009 | Christopher R. Jackson, “An Empirical Model for Estimating the Geographic Location of Nonlinear Internal Solitary Waves”, Journal of Atmospheric and Oceanic Technology 26(10):2243–2255；Abstract：相速图建立传播时间与路径、等传播时线给波位置 | 方法与公式/二维折射
- 三维全非线性模拟表明，局部海丘/洼地造成波前凹凸和沿波峰能量再分配；凹波前像透镜聚焦能量并可能提前破碎，故仅沿一条预设断面累计走时不能表达横向聚焦、散焦和绕射 | https://doi.org/10.1029/2007JC004107 | 一手（P0 论文摘要/元数据，证据 B） | 2007 | Vlasenko & Stashchuk, “Three-dimensional shoaling of large-amplitude internal waves”, Journal of Geophysical Research: Oceans 112(C11), article 2007JC004107；Abstract；结论性机制在摘要中完整陈述 | 因果机制/二维折射
- 缓变地形与层化可采用“逐格求局地模态 \(c_n,\phi_n,\alpha_n,\beta_n\) + 波作用守恒/变系数演化 + 射线”处理；核心假设是环境尺度 \(L_e\gg\) 波长/波宽且模态谱分离，若坡度陡、出现转向点/临界层、模态接近或强散射，则需耦合模态、非静力数值模型或全三维模型 | https://doi.org/10.1007/s10236-019-01246-6 | 一手（P0 论文原文，证据 A） | 2019 | Liang & Li, Ocean Dynamics 69:313–321；§2 用 ETOPO1 与 WOA2013 构造沿程波导，§3 式(6)–(7)为变系数 KdV，摘要与结论强调 intermodal coupling；Fig.1–2 展示系数/Ursell 数空间变化 | 因果机制/缓变环境
- 北南海跨盆传播观测显示：深盆 B 波起始约比线性 mode-1 半日潮相速快 5%，A 波又比 B 波快约 5%–10%；上陆坡后 B 波反而比 A 波快 8%–12%，Taylor–Goldstein 诊断归因于日内潮调制背景流；相速不是仅由水深或起点振幅单调决定 | https://doi.org/10.1175/2010JPO4388.1 | 一手（P0 论文摘要/元数据，证据 A） | 2010 | Alford et al., JPO 40(6):1338–1355；Abstract 中部至末段；样本为 14 个波、10 个锚系、Luzon Strait 至西侧上坡约 560 km | 因果机制/南海反例

# 适用边界

## 4. “一个点真值外推全路径”的南海经验公式：证据判定

- 确有专门应用于北南海的经验传播模型：Jackson (2009) 用卫星影像中的多条/多时相内波签名拟合“相速—水深”模型参数，再由相速图计算源点到区域各点的传播路径与走时；其报告误差为水深 >1000 m 时 ±1.32 h（1σ），全观测水深范围 ±2.55 h（1σ） | https://doi.org/10.1175/2009JTECHO638.1 | 一手（P0 论文摘要/元数据，证据 A） | 2009 | Christopher R. Jackson；Journal of Atmospheric and Oceanic Technology 26(10):2243–2255；Abstract 全段；非“单点标定”，而是用多条卫星波迹/观测传播时间反演参数 | 适用边界/经验模型证据
- “只给一个点的真值（一次相速或到时）即可可靠外推任意全路径”的强命题证据不成立：Jackson 模型需要多波迹/多传播时间来最小化计算与观测走时差；一个标量观测最多校准一个组合参数，不能同时识别源时刻、源位置、相速—水深函数、季节层化、背景流和有限振幅修正 | https://doi.org/10.1175/2009JTECHO638.1 | 一手（P0 论文摘要/元数据，证据 A） | 2009 | Jackson 2009，Abstract 第2–6句描述参数化相速图与最小化反演；第7–8句给北南海验证误差 | 综合判断/证伪
- Zhao & Alford (2006) 的南海传播解释依赖“两锚系到时 + 吕宋海峡正压潮流 + 区域水深 + 气候态层化”，得到 S7/Y 对应时滞 57.6±0.9 h 与 55.1±1.0 h，并非一点真值；大波更早到只支持非线性振幅—速度因果，不支持通用单点外推 | https://doi.org/10.1029/2006JC003644 | 一手（P0 论文摘要/元数据，证据 A） | 2006 | Zhongxiang Zhao & Matthew H. Alford, “Source and propagation of internal solitary waves in the northeastern South China Sea”, Journal of Geophysical Research: Oceans 111(C11), article 2006JC003644；Abstract 全段 | 适用边界/观测约束
- Cai & Xie (2010) 确有“北南海传播模型”，但它是二维 regularized long-wave 数值模型，需给定初始孤子、不同源点/时滞/振幅与地形；模型显示极性反转、波峰线改变、合并、岛屿反射/绕射/再连接，不能等同于一个点真值驱动的封闭经验公式 | https://doi.org/10.1029/2010JC006341 | 一手（P0 论文摘要/元数据，证据 A） | 2010 | Shuqun Cai & Jieshuo Xie, “A propagation model for the internal solitary waves in the northern South China Sea”, Journal of Geophysical Research: Oceans 115(C12), article 2010JC006341；Abstract 全段 | 适用边界/模型类别
- 最低可行外推方案应是“单点真值仅作偏差校准”：全路径仍需水深、逐时/逐月层化、背景流场和波幅/模态；逐格解本征问题得到 \(c_n\)，用观测点校准一个低维偏置或幅度参数，再按射线/程函积分，并以集合方法传播环境误差；不得把单点比值 \(c_{obs}/c_{model}\) 无条件乘遍全域 | https://doi.org/10.1175/2010JPO4388.1 | 一手（P0 观测论文，证据 A） | 2010 | Alford et al., JPO 40:1338–1355；跨盆 560 km 中相对线性相速的偏差会随波型、地形区段与时变背景流反转，直接构成常比例外推的反例 | 适用边界/工程建议

## 5. 模型选择边界

- 线性两层/连续模态：适合小振幅、长波、已知局地层化的基准相速；输出是本征模态相速，不含有限振幅、强剪切、耗散、破碎和跨模态能量交换 | https://arxiv.org/abs/1808.02248 | 一手（P0，证据 A） | 2018/2019 | Liang & Li，§2 式(4)及 §3 式(6)–(7) | 适用边界
- KdV：要求 \(\epsilon=A/H\ll1\)、\(\mu=(H/L)^2\ll1\) 且通常 \(\epsilon=O(\mu)\)，单向单模态；近临界 \(\alpha\approx0\)、大振幅、平顶/共轭流、破碎、强旋转长距离和强剪切临界层均越界 | https://doi.org/10.1146/annurev.fluid.38.050304.092129 | 二手（P1 权威综述，证据 A） | 2006 | Helfrich & Melville, Annual Review of Fluid Mechanics 38:395–425；Abstract 明确弱非线性模型无法覆盖失稳/破碎，强非线性波需全非线性模型 | 适用边界
- Gardner/eKdV：补足 \(\alpha\) 近零或中等振幅的三次非线性，但仍不自动包含旋转、耗散、二维折射、背景流剪切、模态耦合和破碎；若这些效应与非线性同阶，需在控制方程中显式加入而非事后修正相速 | https://doi.org/10.5194/npg-9-221-2002 | 一手（P0 元数据，证据 B） | 2002 | Grimshaw et al., Nonlinear Processes in Geophysics 9:221–235 | 适用边界
- DJL：适合给定层化下的稳态二维有限振幅孤立波及其相速/结构；不描述生成、沿程时变、耗散破碎、显著旋转和一般三维折射，逐路径套用 DJL 还要求环境变化慢于波宽且每格解支连续 | https://doi.org/10.1017/S002211200100636X | 一手（P0，证据 A） | 2002 | Lamb, JFM 451:109–144；Abstract 展示 DJL 类全非线性稳态波在 shoaling 及极限附近的敏感性 | 适用边界

# 待验证

- Jackson (2009) 正文的具体“相速—水深”函数形式、式号及图号：出版页受访问限制；当前仅由论文摘要与 Crossref 元数据核定，需获取 PDF 后补录。
- Helfrich & Melville (2006) 正文 KdV/Gardner 公式的精确式号与图号：出版页正文动态加载且受订阅限制；公式已按标准量纲核对，但式号待全文核验。
- DJL 含一般背景剪切的完整方程含 \(U''\)/背景涡度项，形式依流函数/位移变量约定；本 brief 仅给静止背景标准式，剪切情形应直接采用对应论文定义。
- “逐段段落号”多数期刊不提供；已以章节、式号、图号及相邻段落定位替代。
