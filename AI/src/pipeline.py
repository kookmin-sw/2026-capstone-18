import os
import numpy as np
import pandas as pd
import scipy.signal as signal
from scipy.interpolate import interp1d
from scipy.signal import lfilter, lfilter_zi
import onnxruntime as ort

# ==========================================
# 1. PIPELINE CONFIGURATION
# ==========================================
TARGET_HZ = 25
CHUNK_SEC = 60
BUFFER_SEC = 300  
BASELINE_SEC = 180

CHUNK_STEPS = CHUNK_SEC * TARGET_HZ
BUFFER_STEPS = BUFFER_SEC * TARGET_HZ
BASELINE_STEPS = BASELINE_SEC * TARGET_HZ

# ==========================================
# 2. STATEFUL PIPELINE CLASS
# ==========================================
class RealTimeStressPipeline:
    def __init__(self, onnx_path):
        print(f"[*] Initializing ONNX Runtime Engine...")
        self.session = ort.InferenceSession(onnx_path, providers=['CPUExecutionProvider'])
        
        self.is_calibrated = False
        self.mean_eda_base, self.std_eda_base = 0.0, 1.0
        self.mean_ppg_base, self.std_ppg_base = 0.0, 1.0
        self.acc_1g_baseline = 1.0
        self.mean_log_std_eda_base, self.std_log_std_eda_base = 0.0, 1.0
        self.mean_log_std_bvp_base, self.std_log_std_bvp_base = 0.0, 1.0
        
        self.CONF_THRESH = 0.60
        self.MAR_THRESH = 0.10
        self.MAX_GAP_CHUNKS = 2  
        self.COOLDOWN_SEC = 300  
        
        self.is_in_stress_event = False
        self.silent_chunks_since_stress = 0
        self.last_notification_sec = -99999

    def calibrate(self, raw_ppg, raw_eda, raw_acc_mag):
        valid_ppg = raw_ppg[250:]
        valid_eda = raw_eda[250:]
        
        self.mean_ppg_base, self.std_ppg_base = np.mean(valid_ppg), np.std(valid_ppg) + 1e-8
        self.mean_eda_base, self.std_eda_base = np.mean(valid_eda), np.std(valid_eda) + 1e-8
        self.acc_1g_baseline = np.mean(raw_acc_mag)
        
        eda_calib = (raw_eda - self.mean_eda_base) / self.std_eda_base
        ppg_calib = (raw_ppg - self.mean_ppg_base) / self.std_ppg_base
        
        fast_win, slow_win = 10 * TARGET_HZ, 60 * TARGET_HZ
        eda_macd = self._compute_ema(eda_calib, fast_win) - self._compute_ema(eda_calib, slow_win)
        bvp_macd = self._compute_ema(np.abs(ppg_calib), fast_win) - self._compute_ema(np.abs(ppg_calib), slow_win)
        
        trail_win = 300 * TARGET_HZ
        _, std_eda = self._causal_rolling_stats(eda_macd, trail_win)
        _, std_bvp = self._causal_rolling_stats(bvp_macd, trail_win)
        
        log_std_eda, log_std_bvp = np.log1p(std_eda), np.log1p(std_bvp)
        
        self.mean_log_std_eda_base, self.std_log_std_eda_base = np.mean(log_std_eda), np.std(log_std_eda) + 1e-8
        self.mean_log_std_bvp_base, self.std_log_std_bvp_base = np.mean(log_std_bvp), np.std(log_std_bvp) + 1e-8
        
        self.is_calibrated = True
        print("[*] Calibration Complete. Pipeline armed.")

    def process_buffer(self, buffer_ppg, buffer_eda, buffer_acc_mag, current_time_sec):
        if not self.is_calibrated:
            return False, 0.0

        eda_calib = np.clip((buffer_eda - self.mean_eda_base) / self.std_eda_base, -35.0, 35.0)
        ppg_calib = np.clip((buffer_ppg - self.mean_ppg_base) / self.std_ppg_base, -35.0, 35.0)
        acc_global = np.clip((buffer_acc_mag - self.acc_1g_baseline) / self.acc_1g_baseline, -3.0, 3.0)
        
        fast_win, slow_win, context_win = 10 * TARGET_HZ, 60 * TARGET_HZ, 300 * TARGET_HZ
        
        ema_eda_fast = self._compute_ema(eda_calib, fast_win)
        ema_eda_slow = self._compute_ema(eda_calib, slow_win)
        ema_bvp_fast = self._compute_ema(np.abs(ppg_calib), fast_win)
        ema_bvp_slow = self._compute_ema(np.abs(ppg_calib), slow_win)
        
        eda_ema_context = self._compute_ema(eda_calib, context_win)
        bvp_ema_context = self._compute_ema(np.abs(ppg_calib), context_win)

        eda_macd = ema_eda_fast - ema_eda_slow
        bvp_macd = ema_bvp_fast - ema_bvp_slow

        _, std_eda = self._causal_rolling_stats(eda_macd, context_win)
        _, std_bvp = self._causal_rolling_stats(bvp_macd, context_win)
        
        norm_std_eda = (np.log1p(std_eda) - self.mean_log_std_eda_base) / self.std_log_std_eda_base
        norm_std_bvp = (np.log1p(std_bvp) - self.mean_log_std_bvp_base) / self.std_log_std_bvp_base

        X_chunk = np.column_stack([
            ppg_calib[-CHUNK_STEPS:], eda_calib[-CHUNK_STEPS:], acc_global[-CHUNK_STEPS:],
            eda_ema_context[-CHUNK_STEPS:], bvp_ema_context[-CHUNK_STEPS:],
            eda_macd[-CHUNK_STEPS:], bvp_macd[-CHUNK_STEPS:],
            norm_std_eda[-CHUNK_STEPS:], norm_std_bvp[-CHUNK_STEPS:]
        ]).astype(np.float32).T  
        
        input_tensor = np.expand_dims(X_chunk, axis=0) 
        chunk_mean_acc = np.mean(acc_global[-CHUNK_STEPS:])

        ort_inputs = {'input_tensor': input_tensor}
        logits = self.session.run(None, ort_inputs)[0][0]
        prob_stress = np.exp(logits[1]) / np.sum(np.exp(logits))

        is_active = (prob_stress >= self.CONF_THRESH)
        if chunk_mean_acc > self.MAR_THRESH:
            is_active = False  
            
        should_notify = False
        
        if is_active:
            self.is_in_stress_event = True
            self.silent_chunks_since_stress = 0
            
            if (current_time_sec - self.last_notification_sec) >= self.COOLDOWN_SEC:
                should_notify = True
                self.last_notification_sec = current_time_sec
        else:
            if self.is_in_stress_event:
                self.silent_chunks_since_stress += 1
                if self.silent_chunks_since_stress > self.MAX_GAP_CHUNKS:
                    self.is_in_stress_event = False
                    self.silent_chunks_since_stress = 0

        return should_notify, prob_stress

    def _compute_ema(self, arr, span):
        alpha = 2.0 / (span + 1.0)
        b, a = [alpha], [1.0, -(1.0 - alpha)]
        zi = lfilter_zi(b, a) * arr[0]
        ema, _ = lfilter(b, a, arr, zi=zi)
        return ema

    def _causal_rolling_stats(self, arr, window_size):
        padded = np.pad(arr, (window_size - 1, 0), mode='edge')
        cum_sum = np.cumsum(padded, dtype=float)
        cum_sum[window_size:] = cum_sum[window_size:] - cum_sum[:-window_size]
        rolling_mean = cum_sum[window_size - 1:] / window_size
        
        cum_sq_sum = np.cumsum(padded**2, dtype=float)
        cum_sq_sum[window_size:] = cum_sq_sum[window_size:] - cum_sq_sum[:-window_size]
        rolling_sq_mean = cum_sq_sum[window_size - 1:] / window_size 
        
        rolling_var = np.clip(rolling_sq_mean - (rolling_mean**2), a_min=0, a_max=None)
        return rolling_mean, np.sqrt(rolling_var)

# ==========================================
# 3. STREAMING SIMULATION SCRIPT
# ==========================================
def simulate_live_stream(data_dir, onnx_path):
    print("[*] Loading and Synchronizing Galaxy CSVs to 25Hz...")
    df_ppg = pd.read_csv(os.path.join(data_dir, 'ppg_green.csv'))
    df_eda = pd.read_csv(os.path.join(data_dir, 'eda.csv'))
    df_acc = pd.read_csv(os.path.join(data_dir, 'accel.csv'))
    
    t0_ms = max(df_ppg['timestamp_ms'].iloc[0], df_eda['timestamp_ms'].iloc[0], df_acc['timestamp_ms'].iloc[0])
    tEnd_ms = min(df_ppg['timestamp_ms'].iloc[-1], df_eda['timestamp_ms'].iloc[-1], df_acc['timestamp_ms'].iloc[-1])
    
    max_sec = (tEnd_ms - t0_ms) / 1000.0
    target_times = np.arange(0, max_sec, 1.0 / TARGET_HZ)
    
    ppg_raw = interp1d((df_ppg['timestamp_ms'] - t0_ms)/1000.0, df_ppg['ppg_green'], kind='linear', fill_value="extrapolate")(target_times)
    eda_raw = interp1d((df_eda['timestamp_ms'] - t0_ms)/1000.0, df_eda['skin_conductance'], kind='previous', fill_value="extrapolate")(target_times)
    acc_x = interp1d((df_acc['timestamp_ms'] - t0_ms)/1000.0, df_acc['x'], kind='linear', fill_value="extrapolate")(target_times)
    acc_y = interp1d((df_acc['timestamp_ms'] - t0_ms)/1000.0, df_acc['y'], kind='linear', fill_value="extrapolate")(target_times)
    acc_z = interp1d((df_acc['timestamp_ms'] - t0_ms)/1000.0, df_acc['z'], kind='linear', fill_value="extrapolate")(target_times)
    
    b, a = signal.butter(4, [0.1 / (0.5 * TARGET_HZ), 10.0 / (0.5 * TARGET_HZ)], btype='bandpass', analog=False) 
    ppg_smooth = signal.filtfilt(b, a, ppg_raw)
    ppg_smooth = signal.savgol_filter(ppg_smooth, window_length=5, polyorder=2)
    acc_mag_raw = np.sqrt(acc_x**2 + acc_y**2 + acc_z**2)
    
    pipeline = RealTimeStressPipeline(onnx_path)
    
    if len(ppg_smooth) < BASELINE_STEPS:
        raise ValueError("Recording too short.")
    
    pipeline.calibrate(
        ppg_smooth[:BASELINE_STEPS], 
        eda_raw[:BASELINE_STEPS], 
        acc_mag_raw[:BASELINE_STEPS]
    )
    
    print("\n" + "="*50)
    print(" COMMENCING STREAMING SIMULATION")
    print("="*50)
    
    start_step = BUFFER_STEPS 
    
    for current_step in range(start_step, len(ppg_smooth), CHUNK_STEPS):
        current_time_sec = current_step / TARGET_HZ
        
        buffer_start = current_step - BUFFER_STEPS
        
        b_ppg = ppg_smooth[buffer_start:current_step]
        b_eda = eda_raw[buffer_start:current_step]
        b_acc = acc_mag_raw[buffer_start:current_step]
        
        notif, prob = pipeline.process_buffer(b_ppg, b_eda, b_acc, current_time_sec)
        
        state_str = "STRESS_EVENT" if pipeline.is_in_stress_event else "Baseline  "
        notif_str = "🌟 BUZZ WATCH" if notif else "Silent"
        print(f"Time: {int(current_time_sec//60)}m {int(current_time_sec%60):02d}s | Prob: {prob:.3f} | State: {state_str} | Action: {notif_str}")

if __name__ == '__main__':
    # Dynamic Path Resolution (Assuming script is inside AI/src/)
    SRC_DIR = os.path.dirname(os.path.abspath(__file__))
    AI_ROOT = os.path.abspath(os.path.join(SRC_DIR, '..'))
    
    DATA_DIR = os.path.join(AI_ROOT, 'data', 'raw', 'Galaxy_Test')
    ONNX_PATH = os.path.join(AI_ROOT, 'checkpoints_final', 'wesad_w2.0', 'wesad_mamba_v1.onnx')
    
    simulate_live_stream(DATA_DIR, ONNX_PATH)