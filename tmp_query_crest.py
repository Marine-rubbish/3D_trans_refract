import scipy.io
import numpy as np
from datetime import datetime, timedelta
import sys

mat_path = r'c:\Users\10335\Documents\code\research\SCS_IW_RS\3D_trans_refract\TMP\matched_results_with_flip_833.mat'
mat = scipy.io.loadmat(mat_path, squeeze_me=True, struct_as_record=False)

print('=== .mat 文件中的变量 ===')
for k in sorted(mat.keys()):
    if not k.startswith('__'):
        v = mat[k]
        if hasattr(v, 'shape'):
            print(f'  {k}: shape={v.shape}, dtype={v.dtype if hasattr(v, "dtype") else type(v).__name__}')
        else:
            print(f'  {k}: type={type(v).__name__}')

crest_idx = None
mode = None
mooring_time = None
crest_time = None
dir_diff = None
speed_diff = None
peak_lon = None
peak_lat = None
K_mooring = None

for k in ['crest_idx', 'out_crest_idx', 'global_crest_idx']:
    if k in mat:
        crest_idx = np.array(mat[k]).flatten().astype(int)
        print(f'\n使用字段: {k}, 共有 {len(crest_idx)} 条匹配')
        break

for k in ['mode', 'out_mode']:
    if k in mat:
        mode = np.array(mat[k]).flatten()
        break
for k in ['mooring_time', 'out_mooring_time']:
    if k in mat:
        mooring_time = np.array(mat[k]).flatten()
        break
for k in ['crest_time', 'out_crest_time']:
    if k in mat:
        crest_time = np.array(mat[k]).flatten()
        break
for k in ['dir_diff', 'out_dir_diff']:
    if k in mat:
        dir_diff = np.array(mat[k]).flatten()
        break
for k in ['speed_diff', 'out_speed_diff']:
    if k in mat:
        speed_diff = np.array(mat[k]).flatten()
        break
for k in ['peak_lon', 'out_peak_lon']:
    if k in mat:
        peak_lon = np.array(mat[k]).flatten()
        break
for k in ['peak_lat', 'out_peak_lat']:
    if k in mat:
        peak_lat = np.array(mat[k]).flatten()
        break
for k in ['K_mooring', 'out_K_mooring']:
    if k in mat:
        K_mooring = np.array(mat[k]).flatten()
        break

def matlab_datenum_to_dt(x):
    try:
        val = float(x)
        if np.isfinite(val):
            return datetime.fromordinal(int(val) - 366) + timedelta(days=val % 1)
    except:
        pass
    return None

targets = [196, 300, 1223]
print('\n' + '='*70)
print(f'查询目标 global_crest_idx: {targets}')
print('='*70)

if crest_idx is not None:
    for t in targets:
        matches = np.where(crest_idx == t)[0]
        if len(matches) > 0:
            print(f'\n[OK] global_crest_idx = {t}: MATCHED! {len(matches)} record(s)')
            for m in matches:
                print(f'  --- Match #{m} ---')
                if mode is not None and m < len(mode):
                    print(f'    Mode: {int(mode[m])}')
                if crest_time is not None and m < len(crest_time):
                    dt = matlab_datenum_to_dt(crest_time[m])
                    if dt: print(f'    Crest time: {dt.strftime("%Y-%m-%d %H:%M:%S")}')
                if mooring_time is not None and m < len(mooring_time):
                    dt = matlab_datenum_to_dt(mooring_time[m])
                    if dt: print(f'    Mooring time: {dt.strftime("%Y-%m-%d %H:%M:%S")}')
                if dir_diff is not None and m < len(dir_diff):
                    print(f'    Dir diff: {dir_diff[m]:.2f} deg')
                if speed_diff is not None and m < len(speed_diff):
                    print(f'    Speed diff: {speed_diff[m]:.4f}')
                if peak_lon is not None and m < len(peak_lon) and np.isfinite(peak_lon[m]):
                    print(f'    Peak pos: ({peak_lat[m]:.4f}N, {peak_lon[m]:.4f}E)')
                if K_mooring is not None and m < len(K_mooring) and np.isfinite(K_mooring[m]):
                    print(f'    K_mooring: {K_mooring[m]:.4f}')
        else:
            print(f'\n[X]  global_crest_idx = {t}: NOT matched')
else:
    print('\ncrest_idx field not found. Dumping numeric info for all vars...')
    for k in sorted(mat.keys()):
        if not k.startswith('__'):
            v = mat[k]
            if hasattr(v, '__len__') and len(v) > 0 and not isinstance(v, str):
                try:
                    arr = np.array(v).flatten()
                    if arr.size > 0 and np.issubdtype(arr.dtype, np.number):
                        finite_arr = arr[np.isfinite(arr)]
                        if len(finite_arr) > 0:
                            print(f'  {k}: min={np.min(finite_arr):.3f}, max={np.max(finite_arr):.3f}, first5={finite_arr[:min(5,len(finite_arr))]}')
                except Exception as e:
                    print(f'  {k}: err={e}')