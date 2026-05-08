import os
import numpy as np
import pandas as pd
import scipy.signal as signal
from scipy.interpolate import interp1d
from scipy.signal import lfilter, lfilter_zi

# ==========================================
# 1. CONFIGURATION & HYPERPARAMETERS
# ==========================================
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
AI_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, '..', '..'))

RAW_DIR = os.path.join(AI_ROOT, 'data', 'raw', 'StressPredict')
SAVE_DIR = os.path.join(AI_ROOT, 'data', 'galaxy', 'StressPredict')
os.makedirs(SAVE_DIR, exist_ok=True)

TARGET_HZ = 25

# Decoupled Time Variables
BASELINE_SECONDS = 180  # For Z-Score Calibration
CHUNK_SECONDS = 60      # For Mamba Model Input Tensor
STRIDE_SECONDS = 5      # For Sliding Window

BASELINE_STEPS = BASELINE_SECONDS * TARGET_HZ
CHUNK_STEPS = CHUNK_SECONDS * TARGET_HZ
STRIDE_STEPS = STRIDE_SECONDS * TARGET_HZ

FAST_WINDOW_SEC = 10
SLOW_WINDOW_SEC = 60
CONTEXT_WINDOW_SEC = 300  
TRAILING_BASE_MINUTES = 5

# ==========================================
# 2. HARDWARE EMULATION FUNCTIONS
# ==========================================
def emulate_galaxy_watch_ppg(e4_ppg_array, original_fs=64, target_fs=25):
    nyquist = 0.5 * original_fs
    normal_cutoff = 10.0 / nyquist
    b, a = signal.butter(4, normal_cutoff, btype='low', analog=False)
    filtered_ppg = signal.filtfilt(b, a, e4_ppg_array)
    resampled_ppg = signal.resample_poly(filtered_ppg, up=target_fs, down=original_fs)
    emulated_ppg = signal.savgol_filter(resampled_ppg, window_length=5, polyorder=2)
    return emulated_ppg

def emulate_and_sync_eda(e4_eda_array, original_fs=4, watch_fs=1, target_model_fs=25):
    nyquist = 0.5 * original_fs
    normal_cutoff = 0.4 / nyquist
    b, a = signal.butter(4, normal_cutoff, btype='low', analog=False)
    filtered_eda = signal.filtfilt(b, a, e4_eda_array)
    degraded_1hz_eda = signal.resample_poly(filtered_eda, up=watch_fs, down=original_fs)
    smoothed_1hz_eda = signal.savgol_filter(degraded_1hz_eda, window_length=3, polyorder=1)
    synced_25hz_eda = np.repeat(smoothed_1hz_eda, target_model_fs)
    return synced_25hz_eda

def emulate_galaxy_watch_acc(e4_acc_array, original_fs=32, target_fs=25):
    nyquist = 0.5 * original_fs
    normal_cutoff = 12.0 / nyquist
    b, a = signal.butter(4, normal_cutoff, btype='low', analog=False)
    filtered_acc = signal.filtfilt(b, a, e4_acc_array, axis=0)
    resampled_acc = signal.resample_poly(filtered_acc, up=target_fs, down=original_fs, axis=0)
    emulated_acc = signal.savgol_filter(resampled_acc, window_length=5, polyorder=2, axis=0)
    return emulated_acc

def compute_ema(arr, span):
    alpha = 2.0 / (span + 1.0)
    b = [alpha]
    a = [1.0, -(1.0 - alpha)]
    zi = lfilter_zi(b, a) * arr[0]
    ema, _ = lfilter(b, a, arr, zi=zi)
    return ema

def causal_rolling_stats(arr, window_size):
    """
    O(N) causal rolling mean and standard deviation using Cumulative Sums.
    """
    padded = np.pad(arr, (window_size - 1, 0), mode='edge')
    
    # 1. Rolling Mean
    cum_sum = np.cumsum(padded, dtype=float)
    cum_sum[window_size:] = cum_sum[window_size:] - cum_sum[:-window_size]
    rolling_mean = cum_sum[window_size - 1:] / window_size
    
    # 2. Rolling Squared Mean
    cum_sq_sum = np.cumsum(padded**2, dtype=float)
    cum_sq_sum[window_size:] = cum_sq_sum[window_size:] - cum_sq_sum[:-window_size]
    rolling_sq_mean = cum_sq_sum[window_size - 1:] / window_size # <-- Restored Line
    
    # 3. Variance & Std Dev
    rolling_var = np.clip(rolling_sq_mean - (rolling_mean**2), a_min=0, a_max=None)
    rolling_std = np.sqrt(rolling_var)
    
    return rolling_mean, rolling_std

# ==========================================
# 3. MAIN PIPELINE
# ==========================================
def main():
    print("=" * 60)
    print(f"  Starting Galaxy Watch 8 Emulation (StressPredict)")
    print(f"  (9-Channel @ {TARGET_HZ}Hz, Chunk: {CHUNK_SECONDS}s, Baseline: {BASELINE_SECONDS}s)")
    print("=" * 60)

    combined_csv_path = os.path.join(RAW_DIR, 'Processed_data', 'Improved_All_Combined_hr_rsp_binary.csv')
    if not os.path.exists(combined_csv_path):
        print(f"❌ Cannot find labels at {combined_csv_path}")
        return
    
    global_labels = pd.read_csv(combined_csv_path)

    all_X, all_y, all_sub = [], [], []
    raw_data_dir = os.path.join(RAW_DIR, 'Raw_data')
    subject_folders = sorted([d for d in os.listdir(raw_data_dir) if d.startswith('S')])

    for sub_folder in subject_folders:
        sub_path = os.path.join(raw_data_dir, sub_folder)
        participant_id = int(sub_folder.replace('S', ''))
        
        sub_labels = global_labels[global_labels['Participant'] == participant_id].copy()
        if sub_labels.empty:
            continue
            
        sub_labels = sub_labels.sort_values('Time(sec)')
        print(f"\nProcessing Subject {sub_folder}...", flush=True)

        try:
            eda_df = pd.read_csv(os.path.join(sub_path, 'EDA.csv'), header=None)
            bvp_df = pd.read_csv(os.path.join(sub_path, 'BVP.csv'), header=None)
            acc_df = pd.read_csv(os.path.join(sub_path, 'ACC.csv'), header=None)
            
            eda_start, eda_hz = eda_df.iloc[0, 0], eda_df.iloc[1, 0]
            bvp_start, bvp_hz = bvp_df.iloc[0, 0], bvp_df.iloc[1, 0]
            acc_start, acc_hz = acc_df.iloc[0, 0], acc_df.iloc[1, 0]
            
            eda_raw = eda_df.iloc[2:, 0].values.astype(np.float32)
            bvp_raw = bvp_df.iloc[2:, 0].values.astype(np.float32)
            acc_raw = acc_df.iloc[2:, :].values.astype(np.float32)

            eda_times = eda_start + np.arange(len(eda_raw)) / eda_hz
            bvp_times = bvp_start + np.arange(len(bvp_raw)) / bvp_hz
            acc_times = acc_start + np.arange(len(acc_raw)) / acc_hz
            
            t_start = max(eda_times[0], bvp_times[0], acc_times[0], sub_labels['Time(sec)'].min())
            t_end = min(eda_times[-1], bvp_times[-1], acc_times[-1], sub_labels['Time(sec)'].max())
            
            # STEP 1: Interpolate to uniform NATIVE hardware speeds first
            eda_native = interp1d(eda_times, eda_raw, kind='linear', fill_value="extrapolate")(np.arange(t_start, t_end, 1.0 / 4.0))
            bvp_native = interp1d(bvp_times, bvp_raw, kind='linear', fill_value="extrapolate")(np.arange(t_start, t_end, 1.0 / 64.0))
            acc_native = interp1d(acc_times, acc_raw, axis=0, kind='linear', fill_value="extrapolate")(np.arange(t_start, t_end, 1.0 / 32.0))
            
            # STEP 2: Emulate Galaxy Watch Degradation & Sync to 25Hz Target
            eda_25 = emulate_and_sync_eda(eda_native, original_fs=4, watch_fs=1, target_model_fs=TARGET_HZ)
            bvp_25 = emulate_galaxy_watch_ppg(bvp_native, original_fs=64, target_fs=TARGET_HZ)
            acc_25 = emulate_galaxy_watch_acc(acc_native, original_fs=32, target_fs=TARGET_HZ)
            
            min_len = min(len(eda_25), len(bvp_25), len(acc_25))
            eda_25, bvp_25, acc_25 = eda_25[:min_len], bvp_25[:min_len], acc_25[:min_len]

            target_times_25 = t_start + (np.arange(min_len) / TARGET_HZ)
            labels_25 = interp1d(sub_labels['Time(sec)'], sub_labels['Label'], kind='nearest', fill_value="extrapolate")(target_times_25)

            # STEP 3: BASELINE CALIBRATION (Using BASELINE_STEPS)
            baseline_mask = labels_25 == 0
            if not np.any(baseline_mask):
                continue

            # Extracts exactly 180 seconds for robust baseline calculation
            baseline_eda = eda_25[baseline_mask][:BASELINE_STEPS] 
            baseline_bvp = bvp_25[baseline_mask][:BASELINE_STEPS]

            b_start_idx = np.where(baseline_mask)[0][0]
            b_end_idx = b_start_idx + BASELINE_STEPS

            eda_mean, eda_std = np.mean(baseline_eda), np.std(baseline_eda)
            bvp_mean, bvp_std = np.mean(baseline_bvp), np.std(baseline_bvp)

            eda_calib = (eda_25 - eda_mean) / (eda_std + 1e-8)
            bvp_calib = (bvp_25 - bvp_mean) / (bvp_std + 1e-8)

            CLIP_MIN, CLIP_MAX = -35.0, 35.0
            eda_calib = np.clip(eda_calib, CLIP_MIN, CLIP_MAX)
            bvp_calib = np.clip(bvp_calib, CLIP_MIN, CLIP_MAX)
            
            acc_mag_raw = np.sqrt(acc_25[:, 0]**2 + acc_25[:, 1]**2 + acc_25[:, 2]**2)
            GLOBAL_ACC_MEAN, GLOBAL_ACC_SCALE = 64.0, 64.0 
            acc_mag_global = np.clip((acc_mag_raw - GLOBAL_ACC_MEAN) / GLOBAL_ACC_SCALE, -3.0, 3.0)

            fast_win, slow_win = FAST_WINDOW_SEC * TARGET_HZ, SLOW_WINDOW_SEC * TARGET_HZ
            context_win = CONTEXT_WINDOW_SEC * TARGET_HZ
            
            ema_eda_fast = compute_ema(eda_calib, fast_win)
            ema_eda_slow = compute_ema(eda_calib, slow_win)
            ema_bvp_fast = compute_ema(np.abs(bvp_calib), fast_win)
            ema_bvp_slow = compute_ema(np.abs(bvp_calib), slow_win)
            
            eda_ema_context = compute_ema(eda_calib, context_win)
            bvp_ema_context = compute_ema(np.abs(bvp_calib), context_win)

            eda_macd_delta = ema_eda_fast - ema_eda_slow
            bvp_macd_delta = ema_bvp_fast - ema_bvp_slow

            trail_win = TRAILING_BASE_MINUTES * 60 * TARGET_HZ
            _, std_eda = causal_rolling_stats(eda_macd_delta, trail_win)
            _, std_bvp = causal_rolling_stats(bvp_macd_delta, trail_win)
            
            log_std_eda, log_std_bvp = np.log1p(std_eda), np.log1p(std_bvp)
            
            norm_std_eda = (log_std_eda - np.mean(log_std_eda[b_start_idx:b_end_idx])) / (np.std(log_std_eda[b_start_idx:b_end_idx]) + 1e-8)
            norm_std_bvp = (log_std_bvp - np.mean(log_std_bvp[b_start_idx:b_end_idx])) / (np.std(log_std_bvp[b_start_idx:b_end_idx]) + 1e-8)

            continuous_X = np.column_stack([
                bvp_calib, eda_calib, acc_mag_global,
                eda_ema_context, bvp_ema_context,
                eda_macd_delta, bvp_macd_delta,
                norm_std_eda, norm_std_bvp
            ])

            # STEP 4: MODEL CHUNK EXTRACTION (Using CHUNK_STEPS)
            chunks = 0
            # Slices exactly 60 seconds (1500 points) per iteration
            for i in range(0, len(continuous_X) - CHUNK_STEPS, STRIDE_STEPS):
                window_end = i + CHUNK_STEPS
                target_labels = labels_25[window_end - (5 * TARGET_HZ) : window_end]
                
                hard_label = int(np.bincount(target_labels.astype(int), minlength=2).argmax())
                one_hot_label = np.zeros(2, dtype=np.float32)
                one_hot_label[hard_label] = 1.0
                
                all_X.append(continuous_X[i:window_end, :].T) # Shape [9, 1500]
                all_y.append(one_hot_label)
                all_sub.append(participant_id)
                chunks += 1
                
            print(f"  Extracted {chunks} chunks.")

        except Exception as e:
            print(f"  ❌ Error processing {sub_folder}: {e}")

    final_X = np.array(all_X, dtype=np.float32)
    final_y = np.array(all_y, dtype=np.float32)
    final_sub = np.array(all_sub)

    np.save(os.path.join(SAVE_DIR, 'StressPredict_X_binary.npy'), final_X)
    np.save(os.path.join(SAVE_DIR, 'StressPredict_y_binary.npy'), final_y)
    np.save(os.path.join(SAVE_DIR, 'StressPredict_sub_binary.npy'), final_sub)

    print("\n" + "=" * 55)
    print("✅ Emulated Preprocessing Complete!")
    print(f"Data Shape (X): {final_X.shape}") # Should show [N, 9, 1500]
    print(f"Total Chunks: {len(final_X)}")
    print("=" * 55)

if __name__ == '__main__':
    main()
