import os
import numpy as np
import pandas as pd
from scipy.interpolate import interp1d
from scipy.signal import lfilter, lfilter_zi

# ==========================================
# 1. CONFIGURATION & HYPERPARAMETERS
# ==========================================
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
AI_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, '..', '..'))

RAW_DIR = os.path.join(AI_ROOT, 'data', 'raw', 'StressPredict')
SAVE_DIR = os.path.join(AI_ROOT, 'data', 'processed')
os.makedirs(SAVE_DIR, exist_ok=True)

TARGET_HZ = 64
WINDOW_SECONDS = 60
STRIDE_SECONDS = 5

WINDOW_STEPS = WINDOW_SECONDS * TARGET_HZ
STRIDE_STEPS = STRIDE_SECONDS * TARGET_HZ

# Algorithm & Context Parameters
FAST_WINDOW_SEC = 10
SLOW_WINDOW_SEC = 60
CONTEXT_WINDOW_SEC = 300  # 5-minute global context for EMA
TRAILING_BASE_MINUTES = 5

# ==========================================
# 2. HELPER FUNCTIONS (Mirroring WESAD Logic)
# ==========================================
def compute_ema(arr, span):
    """
    Computes an Exponential Moving Average (EMA) using an IIR filter.
    Mirrors the exact deployment logic for Edge C++ inference.
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
# 3. MAIN PIPELINE
# ==========================================
def main():
    print("=" * 60)
    print("  Starting Stress-Predict Feature Extraction")
    print("  (9-Channel @ 64Hz, Binary Classification)")
    print("=" * 60)

    # Load the validated global label file
    combined_csv_path = os.path.join(RAW_DIR, 'Processed_data', 'Improved_All_Combined_hr_rsp_binary.csv')
    if not os.path.exists(combined_csv_path):
        print(f"❌ Cannot find labels at {combined_csv_path}")
        return
    
    print("[*] Loading global label timestamps...")
    global_labels = pd.read_csv(combined_csv_path)

    all_X = []
    all_y = []
    all_sub = []

    raw_data_dir = os.path.join(RAW_DIR, 'Raw_data')
    subject_folders = sorted([d for d in os.listdir(raw_data_dir) if d.startswith('S')])

    for sub_folder in subject_folders:
        sub_path = os.path.join(raw_data_dir, sub_folder)
        participant_id = int(sub_folder.replace('S', '')) # 'S01' -> 1
        
        # Filter global labels for this specific participant
        sub_labels = global_labels[global_labels['Participant'] == participant_id].copy()
        if sub_labels.empty:
            print(f"  Warning: No labels found for {sub_folder}. Skipping.")
            continue
            
        sub_labels = sub_labels.sort_values('Time(sec)')

        print(f"\nProcessing Subject {sub_folder}...", flush=True)

        try:
            # 1. Load Raw Hardware Files
            eda_df = pd.read_csv(os.path.join(sub_path, 'EDA.csv'), header=None)
            bvp_df = pd.read_csv(os.path.join(sub_path, 'BVP.csv'), header=None)
            acc_df = pd.read_csv(os.path.join(sub_path, 'ACC.csv'), header=None)
            
            # 2. Extract Timestamps and Rates
            eda_start, eda_hz = eda_df.iloc[0, 0], eda_df.iloc[1, 0]
            bvp_start, bvp_hz = bvp_df.iloc[0, 0], bvp_df.iloc[1, 0]
            acc_start, acc_hz = acc_df.iloc[0, 0], acc_df.iloc[1, 0]
            
            eda_raw = eda_df.iloc[2:, 0].values.astype(np.float32)
            bvp_raw = bvp_df.iloc[2:, 0].values.astype(np.float32)
            acc_raw = acc_df.iloc[2:, :].values.astype(np.float32)

            # Generate native timestamps
            eda_times = eda_start + np.arange(len(eda_raw)) / eda_hz
            bvp_times = bvp_start + np.arange(len(bvp_raw)) / bvp_hz
            acc_times = acc_start + np.arange(len(acc_raw)) / acc_hz
            
            # 3. Create Unified 64Hz Target Timeline
            t_start = max(eda_times[0], bvp_times[0], acc_times[0], sub_labels['Time(sec)'].min())
            t_end = min(eda_times[-1], bvp_times[-1], acc_times[-1], sub_labels['Time(sec)'].max())
            
            target_times = np.arange(t_start, t_end, 1.0 / TARGET_HZ)
            
            # 4. Interpolate everything to 64Hz Target Timeline
            eda_64 = interp1d(eda_times, eda_raw, kind='linear', fill_value="extrapolate")(target_times)
            bvp_64 = interp1d(bvp_times, bvp_raw, kind='linear', fill_value="extrapolate")(target_times)
            acc_64 = interp1d(acc_times, acc_raw, axis=0, kind='linear', fill_value="extrapolate")(target_times)
            
            # The global labels are natively binary (0=Baseline, 1=Stress)
            labels_64 = interp1d(sub_labels['Time(sec)'], sub_labels['Label'], kind='nearest', fill_value="extrapolate")(target_times)

            # 5. Baseline Calibration (Find the first continuous block of 0 labels)
            baseline_mask = labels_64 == 0
            if not np.any(baseline_mask):
                print(f"  Warning: No baseline found for {sub_folder}. Skipping.")
                continue

            baseline_eda = eda_64[baseline_mask][:TARGET_HZ * 60] # First 60 seconds
            baseline_bvp = bvp_64[baseline_mask][:TARGET_HZ * 60]
            
            # Find the actual indices where the baseline occurred to calibrate variance later
            b_start_idx = np.where(baseline_mask)[0][0]
            b_end_idx = b_start_idx + (60 * TARGET_HZ)

            eda_mean, eda_std = np.mean(baseline_eda), np.std(baseline_eda)
            bvp_mean, bvp_std = np.mean(baseline_bvp), np.std(baseline_bvp)

            # Feature 1-3: Base Calibration & Global ACC Scaling
            eda_calib = (eda_64 - eda_mean) / (eda_std + 1e-8)
            bvp_calib = (bvp_64 - bvp_mean) / (bvp_std + 1e-8)
            
            acc_mag_raw = np.sqrt(acc_64[:, 0]**2 + acc_64[:, 1]**2 + acc_64[:, 2]**2)
            GLOBAL_ACC_MEAN = 64.0  # Approx 1g resting magnitude on E4
            GLOBAL_ACC_SCALE = 64.0 
            acc_mag_global = np.clip((acc_mag_raw - GLOBAL_ACC_MEAN) / GLOBAL_ACC_SCALE, -3.0, 3.0)

            # Feature 4-5: Slow EMA (Tonic context)
            fast_win = FAST_WINDOW_SEC * TARGET_HZ
            slow_win = SLOW_WINDOW_SEC * TARGET_HZ
            context_win = CONTEXT_WINDOW_SEC * TARGET_HZ
            
            ema_eda_fast = compute_ema(eda_calib, fast_win)
            ema_eda_slow = compute_ema(eda_calib, slow_win)
            ema_bvp_fast = compute_ema(np.abs(bvp_calib), fast_win)
            ema_bvp_slow = compute_ema(np.abs(bvp_calib), slow_win)
            
            eda_ema_context = compute_ema(eda_calib, context_win)
            bvp_ema_context = compute_ema(np.abs(bvp_calib), context_win)

            # Feature 6-7: MACD Deltas (Phasic shifts)
            eda_macd_delta = ema_eda_fast - ema_eda_slow
            bvp_macd_delta = ema_bvp_fast - ema_bvp_slow

            # Feature 8-9: Continuous Trailing Baseline Variance (Log-Compressed)
            trail_win = TRAILING_BASE_MINUTES * 60 * TARGET_HZ
            _, std_eda = causal_rolling_stats(eda_macd_delta, trail_win)
            _, std_bvp = causal_rolling_stats(bvp_macd_delta, trail_win)
            
            log_std_eda = np.log1p(std_eda)
            log_std_bvp = np.log1p(std_bvp)
            
            norm_std_eda = (log_std_eda - np.mean(log_std_eda[b_start_idx:b_end_idx])) / (np.std(log_std_eda[b_start_idx:b_end_idx]) + 1e-8)
            norm_std_bvp = (log_std_bvp - np.mean(log_std_bvp[b_start_idx:b_end_idx])) / (np.std(log_std_bvp[b_start_idx:b_end_idx]) + 1e-8)

            # Stack the 9 Channels
            continuous_X = np.column_stack([
                bvp_calib, eda_calib, acc_mag_global,
                eda_ema_context, bvp_ema_context,
                eda_macd_delta, bvp_macd_delta,
                norm_std_eda, norm_std_bvp
            ])

            # 6. Windowing and Chunk Extraction (BINARY MAPPING)
            chunks = 0
            for i in range(0, len(continuous_X) - WINDOW_STEPS, STRIDE_STEPS):
                window_end = i + WINDOW_STEPS
                target_labels = labels_64[window_end - (5 * TARGET_HZ) : window_end]
                
                # Majority rule over the last 5 seconds of the window
                hard_label = int(np.bincount(target_labels.astype(int), minlength=2).argmax())
                
                # Binary one-hot encoding (Shape: [2])
                one_hot_label = np.zeros(2, dtype=np.float32)
                one_hot_label[hard_label] = 1.0
                
                all_X.append(continuous_X[i:window_end, :].T) # Shape [9, 3840]
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
    print("✅ Preprocessing Complete!")
    print(f"Data Shape (X): {final_X.shape}")
    print(f"Label Shape (y): {final_y.shape}")
    print(f"Total Chunks: {len(final_X)}")
    print(f"Class Balance (0 vs 1): {np.sum(final_y, axis=0)}")
    print("=" * 55)

if __name__ == '__main__':
    main()