import os
import pickle
import numpy as np
import scipy.signal as signal
from scipy.interpolate import interp1d
from scipy.signal import lfilter, lfilter_zi

# ==========================================
# 1. CONFIGURATION & HYPERPARAMETERS
# ==========================================
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
AI_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, '..', '..'))

DATA_DIR = os.path.join(AI_ROOT, 'data', 'raw', 'WESAD')
SAVE_DIR = os.path.join(AI_ROOT, 'data', 'galaxy', 'WESAD')
os.makedirs(SAVE_DIR, exist_ok=True)

# FEMALE_SUBJECTS = ['S8', 'S11', 'S17']

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

def resample_labels(labels, orig_hz, target_hz):
    duration = len(labels) / orig_hz
    target_len = int(duration * target_hz)
    orig_indices = np.linspace(0, len(labels) - 1, target_len)
    return labels[np.round(orig_indices).astype(int)]

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
# 3. MAIN PREPROCESSING PIPELINE
# ==========================================
def main():
    if not os.path.exists(DATA_DIR):
        raise FileNotFoundError(f"Cannot find dataset at {DATA_DIR}.")

    subject_folders = [f for f in os.listdir(DATA_DIR) if f.startswith('S') and os.path.isdir(os.path.join(DATA_DIR, f))]
    subject_folders.sort(key=lambda x: int(x[1:]))

    all_X, all_y, all_sub = [], [], []

    for subject in subject_folders:
        # if subject not in FEMALE_SUBJECTS:
        #     continue

        # print(f"Starting Emulated Galaxy Watch 8 Preprocessing (FEMALE ONLY)")
        # print(f"Targeting: {FEMALE_SUBJECTS}")

        pkl_path = os.path.join(DATA_DIR, subject, f'{subject}.pkl')
        if not os.path.exists(pkl_path): continue
            
        print(f"\nProcessing {subject}...", end=" ", flush=True)
        
        with open(pkl_path, 'rb') as f:
            data = pickle.load(f, encoding='latin1')
            
        bvp_native = data['signal']['wrist']['BVP'].flatten()
        eda_native = data['signal']['wrist']['EDA'].flatten()
        acc_native = data['signal']['wrist']['ACC']
        
        bvp_25 = emulate_galaxy_watch_ppg(bvp_native, 64, TARGET_HZ)
        eda_25 = emulate_and_sync_eda(eda_native, 4, 1, TARGET_HZ)
        acc_25 = emulate_galaxy_watch_acc(acc_native, 32, TARGET_HZ)
        labels_25 = resample_labels(data['label'], 700, TARGET_HZ)
        
        min_len = min(len(bvp_25), len(eda_25), len(acc_25), len(labels_25))
        bvp_raw, eda_raw, acc_raw, labels_raw = bvp_25[:min_len], eda_25[:min_len], acc_25[:min_len], labels_25[:min_len]
        
        valid_starts = np.where(labels_raw > 0)[0]
        if len(valid_starts) == 0: continue
        first_valid_idx = valid_starts[0]
        
        bvp_raw = bvp_raw[first_valid_idx:]; eda_raw = eda_raw[first_valid_idx:]
        acc_raw = acc_raw[first_valid_idx:]; labels_raw = labels_raw[first_valid_idx:]
        min_len = len(labels_raw)

        # BASELINE CALIBRATION (Using BASELINE_STEPS)
        baseline_indices = np.where(labels_raw == 1)[0]
        if len(baseline_indices) < BASELINE_STEPS:
            print("Skipped (Insufficient Baseline)", end="")
            continue
            
        b_start, b_end = baseline_indices[0], baseline_indices[0] + BASELINE_STEPS
        
        eda_calib = (eda_raw - np.mean(eda_raw[b_start:b_end])) / (np.std(eda_raw[b_start:b_end]) + 1e-8)
        bvp_calib = (bvp_raw - np.mean(bvp_raw[b_start:b_end])) / (np.std(bvp_raw[b_start:b_end]) + 1e-8)
    
        CLIP_MIN, CLIP_MAX = -35.0, 35.0
        eda_calib = np.clip(eda_calib, CLIP_MIN, CLIP_MAX)
        bvp_calib = np.clip(bvp_calib, CLIP_MIN, CLIP_MAX)
        
        acc_mag_raw = np.sqrt(np.sum(acc_raw**2, axis=1))
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

        ema_acc_fast = compute_ema(acc_mag_global, fast_win) 

        trail_win = TRAILING_BASE_MINUTES * 60 * TARGET_HZ
        _, std_eda = causal_rolling_stats(eda_macd_delta, trail_win)
        _, std_bvp = causal_rolling_stats(bvp_macd_delta, trail_win)
        
        log_std_eda, log_std_bvp = np.log1p(std_eda), np.log1p(std_bvp)
        norm_std_eda = (log_std_eda - np.mean(log_std_eda[b_start:b_end])) / (np.std(log_std_eda[b_start:b_end]) + 1e-8)
        norm_std_bvp = (log_std_bvp - np.mean(log_std_bvp[b_start:b_end])) / (np.std(log_std_bvp[b_start:b_end]) + 1e-8)

        continuous_X_calib = np.column_stack([
            bvp_calib, eda_calib, acc_mag_global,
            eda_ema_context, bvp_ema_context,
            eda_macd_delta, bvp_macd_delta,
            norm_std_eda, norm_std_bvp
        ])

        mapped_labels = np.zeros_like(labels_raw)
        mapped_labels[labels_raw == 2] = 1  

        # MODEL CHUNK EXTRACTION (Using CHUNK_STEPS)
        chunks = 0
        for i in range(0, min_len - CHUNK_STEPS, STRIDE_STEPS):
            window_end = i + CHUNK_STEPS
            target_labels = mapped_labels[window_end - (5 * TARGET_HZ) : window_end]
            
            hard_label = int(np.bincount(target_labels.astype(int), minlength=2).argmax())
            one_hot_label = np.zeros(2, dtype=np.float32)
            one_hot_label[hard_label] = 1.0
            
            all_X.append(continuous_X_calib[i:window_end, :].T)
            all_y.append(one_hot_label)
            all_sub.append(subject)
            chunks += 1
            
        print(f"Extracted {chunks} chunks.", flush=True)

    final_X = np.array(all_X, dtype=np.float32)
    final_y = np.array(all_y, dtype=np.float32)
    final_sub = np.array(all_sub)

    np.save(os.path.join(SAVE_DIR, 'WESAD_X_binary.npy'), final_X)
    np.save(os.path.join(SAVE_DIR, 'WESAD_y_binary.npy'), final_y)
    np.save(os.path.join(SAVE_DIR, 'WESAD_sub_binary.npy'), final_sub)
    print(f"\nPreprocessing Complete. Binary Tensors saved to {SAVE_DIR}.")
    print(f"X: {final_X.shape} | y: {final_y.shape}")

if __name__ == "__main__":
    main()
