import os
import pickle
import numpy as np
from scipy.interpolate import interp1d
from scipy.signal import lfilter, lfilter_zi

# ==========================================
# 1. CONFIGURATION & HYPERPARAMETERS
# ==========================================
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, '..'))

DATA_DIR = os.path.join(PROJECT_ROOT, 'data', 'raw', 'WESAD')
SAVE_DIR = os.path.join(PROJECT_ROOT, 'data', 'processed')

os.makedirs(SAVE_DIR, exist_ok=True)

TARGET_HZ = 64
WINDOW_SECONDS = 60
STRIDE_SECONDS = 5

WINDOW_STEPS = WINDOW_SECONDS * TARGET_HZ
STRIDE_STEPS = STRIDE_SECONDS * TARGET_HZ

# Algorithm & Context Parameters
LOOKBACK_MINUTES = 10
SUSTAIN_SECONDS = 10
FAST_WINDOW_SEC = 10
SLOW_WINDOW_SEC = 60
CONTEXT_WINDOW_SEC = 300  # 5-minute global context for EMA

# Optimized INT8 Quantization Thresholds
EDA_THRESH = 1.0
BVP_THRESH = 0.5
ACC_THRESH = 1.5

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
    This perfectly mirrors the exact deployment logic for Flutter:
    y[t] = alpha * x[t] + (1 - alpha) * y[t-1]
    Requires only 1 float of memory per channel on the edge device.
    """
    alpha = 2.0 / (span + 1.0)
    b = [alpha]
    a = [1.0, -(1.0 - alpha)]
    
    # Initialize the filter state to match the first value (prevents startup transients/spikes)
    zi = lfilter_zi(b, a) * arr[0]
    ema, _ = lfilter(b, a, arr, zi=zi)
    return ema

# ==========================================
# 3. MAIN PREPROCESSING PIPELINE
# ==========================================
def main():
    if not os.path.exists(DATA_DIR):
        raise FileNotFoundError(f"Cannot find dataset at {DATA_DIR}.")

    subject_folders = [f for f in os.listdir(DATA_DIR) if f.startswith('S') and os.path.isdir(os.path.join(DATA_DIR, f))]
    subject_folders.sort(key=lambda x: int(x[1:]))

    all_X, all_y, all_sub = [], [], []

    print(f"Starting Multi-Sensor 3-Class Preprocessing (9-Channel Input)")
    print(f"Window: {WINDOW_SECONDS}s | Stride: {STRIDE_SECONDS}s")

    for subject in subject_folders:
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

        # 3.3 Calibration
        baseline_indices = np.where(labels_raw == 1)[0]
        if len(baseline_indices) < WINDOW_STEPS:
            print("Skipped (Insufficient Baseline)", end="")
            continue
            
        b_start, b_end = baseline_indices[0], baseline_indices[0] + WINDOW_STEPS
        
        eda_calib = (eda_raw - np.mean(eda_raw[b_start:b_end])) / (np.std(eda_raw[b_start:b_end]) + 1e-8)
        bvp_calib = (bvp_raw - np.mean(bvp_raw[b_start:b_end])) / (np.std(bvp_raw[b_start:b_end]) + 1e-8)
        
        acc_mag_raw = np.sqrt(np.sum(acc_raw**2, axis=1))
        acc_mag_calib = (acc_mag_raw - np.mean(acc_mag_raw[b_start:b_end])) / (np.std(acc_mag_raw[b_start:b_end]) + 1e-8)

        acc_3d_mean = np.mean(acc_raw[b_start:b_end], axis=0)
        acc_3d_std = np.std(acc_raw[b_start:b_end], axis=0) + 1e-8
        acc_3d_calib = (acc_raw - acc_3d_mean) / acc_3d_std
        
        # 3.4 Explicit Feature Computation (EMA & MACD)
        fast_win = FAST_WINDOW_SEC * TARGET_HZ
        slow_win = SLOW_WINDOW_SEC * TARGET_HZ
        context_win = CONTEXT_WINDOW_SEC * TARGET_HZ
        
        ema_eda_fast = compute_ema(eda_calib, fast_win)
        ema_eda_slow = compute_ema(eda_calib, slow_win)
        ema_bvp_fast = compute_ema(np.abs(bvp_calib), fast_win)
        ema_bvp_slow = compute_ema(np.abs(bvp_calib), slow_win)
        ema_acc_fast = compute_ema(acc_mag_calib, fast_win)
        
        eda_ema_context = compute_ema(eda_calib, context_win)
        bvp_ema_context = compute_ema(np.abs(bvp_calib), context_win)
        
        eda_macd_delta = ema_eda_fast - ema_eda_slow
        bvp_macd_delta = ema_bvp_fast - ema_bvp_slow
        
        # Stack all 9 channels
        continuous_X_calib = np.column_stack([
            bvp_calib, acc_3d_calib[:, 0], acc_3d_calib[:, 1], acc_3d_calib[:, 2], 
            eda_calib, eda_ema_context, bvp_ema_context, eda_macd_delta, bvp_macd_delta
        ])
        
        # 3.5 Deployment-Ready 3-Class Mapping
        # Initialize everything as 0 (Baseline). Amusement and Cooldown organically become Baseline.
        mapped_labels = np.zeros_like(labels_raw)
        mapped_labels[labels_raw == 2] = 2  # Map Stress
        
        # 3.6 Causal MACD Pre-Stress Detection
        stress_indices = np.where(labels_raw == 2)[0]
        if len(stress_indices) > 0:
            stress_start = stress_indices[0]
            search_start = max(0, stress_start - (LOOKBACK_MINUTES * 60 * TARGET_HZ))
            
            # Use the explicitly calculated MACD channels for thresholding
            spike_mask = (eda_macd_delta[search_start:stress_start] > EDA_THRESH) | \
                         (bvp_macd_delta[search_start:stress_start] > BVP_THRESH) | \
                         (ema_acc_fast[search_start:stress_start] > ACC_THRESH)
            
            sustain_steps = SUSTAIN_SECONDS * TARGET_HZ
            if len(spike_mask) >= sustain_steps:
                sustained = np.convolve(spike_mask.astype(int), np.ones(sustain_steps), mode='valid')
                hits = np.where(sustained == sustain_steps)[0]
                if len(hits) > 0:
                    onset = search_start + hits[0]
                    mapped_labels[onset:stress_start] = 1 # Mapping to Class 1
                    print(f"[{((stress_start - onset) / TARGET_HZ / 60):.1f}m Warning]", end=" ")
                else:
                    mapped_labels[max(0, stress_start - (3 * 60 * TARGET_HZ)):stress_start] = 1
                    print("[3.0m Fallback]", end=" ")
            else:
                mapped_labels[max(0, stress_start - (3 * 60 * TARGET_HZ)):stress_start] = 1

        # 3.7 Sliding Window Extraction
        chunks = 0
        for i in range(0, min_len - WINDOW_STEPS, STRIDE_STEPS):
            window_end = i + WINDOW_STEPS
            # Horizon lookback (5s before window end)
            target_labels = mapped_labels[window_end - (5 * TARGET_HZ) : window_end]
            
            # Using minlength=3 for the 3-class system
            soft_label = np.bincount(target_labels.astype(int), minlength=3) / len(target_labels)
            
            all_X.append(continuous_X_calib[i:window_end, :].T)
            all_y.append(soft_label)
            all_sub.append(subject)
            chunks += 1
            
        print(f"Extracted {chunks} chunks.", flush=True)

    # 4. Final Tensor Generation
    final_X = np.array(all_X, dtype=np.float32)
    final_y = np.array(all_y, dtype=np.float32)
    final_sub = np.array(all_sub)

    np.save(os.path.join(SAVE_DIR, 'WESAD_X_calibrated.npy'), final_X)
    np.save(os.path.join(SAVE_DIR, 'WESAD_y_labeled.npy'), final_y)
    np.save(os.path.join(SAVE_DIR, 'WESAD_sub_labeled.npy'), final_sub)
    print(f"\nPreprocessing Complete. Tensors saved to {SAVE_DIR}.")
    print(f"X: {final_X.shape} | y: {final_y.shape}")

if __name__ == "__main__":
    main()
