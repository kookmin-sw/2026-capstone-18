import os
import pickle
import numpy as np
from scipy.interpolate import interp1d
from scipy.signal import lfilter, lfilter_zi

# ==========================================
# 1. CONFIGURATION & HYPERPARAMETERS
# ==========================================
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
AI_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, '..', '..'))

DATA_DIR = os.path.join(AI_ROOT, 'data', 'raw', 'WESAD')
SAVE_DIR = os.path.join(AI_ROOT, 'data', 'processed', 'WESAD')
os.makedirs(SAVE_DIR, exist_ok=True)

FEMALE_SUBJECTS = ['S8', 'S11', 'S17']

TARGET_HZ = 64
WINDOW_SECONDS = 180
STRIDE_SECONDS = 5

WINDOW_STEPS = WINDOW_SECONDS * TARGET_HZ
STRIDE_STEPS = STRIDE_SECONDS * TARGET_HZ

# Algorithm & Context Parameters
FAST_WINDOW_SEC = 10
SLOW_WINDOW_SEC = 60
CONTEXT_WINDOW_SEC = 300  # 5-minute global context for EMA
TRAILING_BASE_MINUTES = 5

# ==========================================
# 2. HELPER FUNCTIONS
# ==========================================
def resample_signal(signal, orig_hz, target_hz):
    duration = len(signal) / orig_hz
    target_len = int(duration * target_hz)
    orig_time = np.linspace(0, duration, len(signal))
    target_time = np.linspace(0, duration, target_len)
    
    if signal.ndim == 1:
        f = interp1d(orig_time, signal.flatten(), kind='linear', fill_value="extrapolate")
        return f(target_time).reshape(-1, 1)
    else:
        resampled = np.zeros((target_len, signal.shape[1]))
        for i in range(signal.shape[1]):
            f = interp1d(orig_time, signal[:, i], kind='linear', fill_value="extrapolate")
            resampled[:, i] = f(target_time)
        return resampled

def resample_labels(labels, orig_hz, target_hz):
    duration = len(labels) / orig_hz
    target_len = int(duration * target_hz)
    orig_indices = np.linspace(0, len(labels) - 1, target_len)
    return labels[np.round(orig_indices).astype(int)]

def compute_ema(arr, span):
    """
    Computes an Exponential Moving Average (EMA) using an IIR filter.
    Mirrors the exact deployment logic for Edge inference.
    """
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
    
    cum_sum = np.cumsum(padded, dtype=float)
    cum_sum[window_size:] = cum_sum[window_size:] - cum_sum[:-window_size]
    rolling_mean = cum_sum[window_size - 1:] / window_size
    
    cum_sq_sum = np.cumsum(padded**2, dtype=float)
    cum_sq_sum[window_size:] = cum_sq_sum[window_size:] - cum_sq_sum[:-window_size]
    rolling_sq_mean = cum_sq_sum[window_size - 1:] / window_size
    
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
        
        if subject not in FEMALE_SUBJECTS:
            continue

        print(f"Starting Optimized 9-Channel Preprocessing (FEMALE ONLY)")
        print(f"Targeting: {FEMALE_SUBJECTS}")

        pkl_path = os.path.join(DATA_DIR, subject, f'{subject}.pkl')
        if not os.path.exists(pkl_path): continue
            
        print(f"\nProcessing {subject}...", end=" ", flush=True)
        
        with open(pkl_path, 'rb') as f:
            data = pickle.load(f, encoding='latin1')
            
        # 3.1 Extract & Resample
        bvp_raw = resample_signal(data['signal']['wrist']['BVP'], 64, TARGET_HZ).flatten()
        eda_raw = resample_signal(data['signal']['wrist']['EDA'], 4, TARGET_HZ).flatten()
        acc_raw = resample_signal(data['signal']['wrist']['ACC'], 32, TARGET_HZ)
        labels_raw = resample_labels(data['label'], 700, TARGET_HZ)
        
        min_len = min(len(bvp_raw), len(eda_raw), len(acc_raw), len(labels_raw))
        bvp_raw, eda_raw, acc_raw, labels_raw = bvp_raw[:min_len], eda_raw[:min_len], acc_raw[:min_len], labels_raw[:min_len]
        
        # 3.2 Sensor Settlement Cutoff
        valid_starts = np.where(labels_raw > 0)[0]
        if len(valid_starts) == 0: continue
        first_valid_idx = valid_starts[0]
        
        bvp_raw = bvp_raw[first_valid_idx:]; eda_raw = eda_raw[first_valid_idx:]
        acc_raw = acc_raw[first_valid_idx:]; labels_raw = labels_raw[first_valid_idx:]
        min_len = len(labels_raw)

        # 3.3 Initial Standardization (Z-Score from 60s baseline for autonomic signals)
        baseline_indices = np.where(labels_raw == 1)[0]
        if len(baseline_indices) < WINDOW_STEPS:
            print("Skipped (Insufficient Baseline)", end="")
            continue
            
        b_start, b_end = baseline_indices[0], baseline_indices[0] + WINDOW_STEPS
        
        eda_calib = (eda_raw - np.mean(eda_raw[b_start:b_end])) / (np.std(eda_raw[b_start:b_end]) + 1e-8)
        bvp_calib = (bvp_raw - np.mean(bvp_raw[b_start:b_end])) / (np.std(bvp_raw[b_start:b_end]) + 1e-8)
    
        CLIP_MIN = -35.0
        CLIP_MAX = 35.0
        eda_calib = np.clip(eda_calib, CLIP_MIN, CLIP_MAX)
        bvp_calib = np.clip(bvp_calib, CLIP_MIN, CLIP_MAX)
        
        # 3.4 Global Accelerometer Standardization (Replaces per-subject Z-Score)
        acc_mag_raw = np.sqrt(np.sum(acc_raw**2, axis=1))
        GLOBAL_ACC_MEAN = 64.0  # Approx 1g resting magnitude on E4
        GLOBAL_ACC_SCALE = 64.0 
        
        # Globally scaled and bounded to prevent INT8 scale stretching (-3g to +3g)
        acc_mag_global = np.clip((acc_mag_raw - GLOBAL_ACC_MEAN) / GLOBAL_ACC_SCALE, -3.0, 3.0)
        
        # 3.5 Explicit Feature Computation (EMA & MACD)
        fast_win = FAST_WINDOW_SEC * TARGET_HZ
        slow_win = SLOW_WINDOW_SEC * TARGET_HZ
        context_win = CONTEXT_WINDOW_SEC * TARGET_HZ
        
        ema_eda_fast = compute_ema(eda_calib, fast_win)
        ema_eda_slow = compute_ema(eda_calib, slow_win)
        ema_bvp_fast = compute_ema(np.abs(bvp_calib), fast_win)
        ema_bvp_slow = compute_ema(np.abs(bvp_calib), slow_win)
        
        eda_ema_context = compute_ema(eda_calib, context_win)
        bvp_ema_context = compute_ema(np.abs(bvp_calib), context_win)
        
        eda_macd_delta = ema_eda_fast - ema_eda_slow
        bvp_macd_delta = ema_bvp_fast - ema_bvp_slow
        
        # 3.6 Compute Continuous Trailing Baseline Arrays
        # (Re-computing ACC EMA solely for the noise floor variance block if needed)
        ema_acc_fast = compute_ema(acc_mag_global, fast_win) 

        trail_win = TRAILING_BASE_MINUTES * 60 * TARGET_HZ
        _, std_eda = causal_rolling_stats(eda_macd_delta, trail_win)
        _, std_bvp = causal_rolling_stats(bvp_macd_delta, trail_win)
        
        # 3.7 Log-Compression and Standardization of Variance (For Neural Network Input)
        log_std_eda = np.log1p(std_eda)
        log_std_bvp = np.log1p(std_bvp)
        
        # Normalize the variance using the first 60 seconds of the variance array itself.
        norm_std_eda = (log_std_eda - np.mean(log_std_eda[b_start:b_end])) / (np.std(log_std_eda[b_start:b_end]) + 1e-8)
        norm_std_bvp = (log_std_bvp - np.mean(log_std_bvp[b_start:b_end])) / (np.std(log_std_bvp[b_start:b_end]) + 1e-8)

        # 3.8 Optimal 9-Channel Stack Assembly
        continuous_X_calib = np.column_stack([
            bvp_calib,                  # 1: High-freq raw
            eda_calib,                  # 2: Absolute state
            acc_mag_global,             # 3: Global physical exertion (Fixed Scale)
            eda_ema_context,            # 4: 5-min slow trend EDA
            bvp_ema_context,            # 5: 5-min slow trend BVP
            eda_macd_delta,             # 6: Phasic derivative EDA
            bvp_macd_delta,             # 7: Phasic derivative BVP
            norm_std_eda,               # 8: Trailing EDA noise floor
            norm_std_bvp                # 9: Trailing BVP noise floor
        ])

        # 3.9 Deployment-Ready Binary Mapping
        mapped_labels = np.zeros_like(labels_raw)
        mapped_labels[labels_raw == 2] = 1  # Map WESAD Stress (2) to Binary Target (1)
        # All other states (Amusement, Baseline, Meditation) organically collapse to 0.

        # 3.10 Sliding Window Extraction (Hard Labels)
        chunks = 0
        for i in range(0, min_len - WINDOW_STEPS, STRIDE_STEPS):
            window_end = i + WINDOW_STEPS
            # Horizon lookback (5s before window end)
            target_labels = mapped_labels[window_end - (5 * TARGET_HZ) : window_end]
            
            # Determine majority class to create a Hard Label for Binary Loss
            hard_label = int(np.bincount(target_labels.astype(int), minlength=2).argmax())
            
            # Convert to float32 one-hot vector (Shape: [2])
            one_hot_label = np.zeros(2, dtype=np.float32)
            one_hot_label[hard_label] = 1.0
            
            all_X.append(continuous_X_calib[i:window_end, :].T)
            all_y.append(one_hot_label)
            all_sub.append(subject)
            chunks += 1
            
        print(f"Extracted {chunks} chunks.", flush=True)

    # 4. Final Tensor Generation
    final_X = np.array(all_X, dtype=np.float32)
    final_y = np.array(all_y, dtype=np.float32)
    final_sub = np.array(all_sub)

    np.save(os.path.join(SAVE_DIR, 'WESAD_X_binary.npy'), final_X)
    np.save(os.path.join(SAVE_DIR, 'WESAD_y_binary.npy'), final_y)
    np.save(os.path.join(SAVE_DIR, 'WESAD_sub_binary.npy'), final_sub)
    print(f"\nPreprocessing Complete. Binary Tensors saved to {SAVE_DIR}.")
    print(f"X: {final_X.shape} | y: {final_y.shape}")
    print(f"Class Balance (0 vs 1): {np.sum(final_y, axis=0)}")

if __name__ == "__main__":
    main()
