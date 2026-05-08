import os
import sys
import numpy as np

def main():
    print("=" * 60)
    print("  TENSOR MERGER: WESAD + StressPredict (Binary)")
    print("=" * 60)
    
    # 1. Resolve Paths Dynamically
    SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
    AI_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, '..', '..'))    
    
    WESAD_DIR = os.path.join(AI_ROOT, 'data', 'galaxy', 'WESAD')
    STRESS_PREDICT_DIR = os.path.join(AI_ROOT, 'data', 'galaxy', 'StressPredict')
    MERGED_DIR = os.path.join(AI_ROOT, 'data', 'galaxy', 'Merged')

    os.makedirs(MERGED_DIR, exist_ok=True)
    
    if not os.path.exists(WESAD_DIR) or not os.path.exists(STRESS_PREDICT_DIR):
        print(f"❌ Error: Could not find galaxy dataset directories.")
        sys.exit(1)
        
    # 2. Load WESAD
    print("[*] Loading WESAD Tensors...")
    try:
        w_x = np.load(os.path.join(WESAD_DIR, 'WESAD_X_binary.npy'))
        w_y = np.load(os.path.join(WESAD_DIR, 'WESAD_y_binary.npy'))
        w_sub = np.load(os.path.join(WESAD_DIR, 'WESAD_sub_binary.npy')).astype(str)
    except FileNotFoundError as e:
        print(f"❌ Error loading WESAD arrays: {e}")
        sys.exit(1)
        
    # Append _W to WESAD subjects (e.g., '2' -> '2_W')
    w_sub = np.array([f"{s}_W" for s in w_sub])
    
    # 3. Load StressPredict
    print("[*] Loading StressPredict Tensors...")
    try:
        s_x = np.load(os.path.join(STRESS_PREDICT_DIR, 'StressPredict_X_binary.npy'))
        s_y = np.load(os.path.join(STRESS_PREDICT_DIR, 'StressPredict_y_binary.npy'))
        s_sub = np.load(os.path.join(STRESS_PREDICT_DIR, 'StressPredict_sub_binary.npy')).astype(str)
    except FileNotFoundError as e:
        print(f"❌ Error loading StressPredict arrays: {e}")
        sys.exit(1)
        
    # Append _S to StressPredict subjects (e.g., 'S01' or '1' -> '1_S')
    s_sub = np.array([f"{s}_S" for s in s_sub])
    
    # 4. Data Type and Dimension Verification Prior to Concatenation
    assert w_x.shape[1:] == s_x.shape[1:], f"Feature dimension mismatch: {w_x.shape[1:]} vs {s_x.shape[1:]}"
    assert w_y.shape[1] == s_y.shape[1], f"Label dimension mismatch: {w_y.shape[1]} vs {s_y.shape[1]}"
    
    # 5. Concatenate Tensors
    print("\n[*] Concatenating Arrays along Axis 0...")
    merged_X = np.concatenate([w_x, s_x], axis=0)
    merged_y = np.concatenate([w_y, s_y], axis=0)
    merged_sub = np.concatenate([w_sub, s_sub], axis=0)
    
    # 6. Save the Master Tensors
    print("[*] Saving Master Dataset to disk...")
    np.save(os.path.join(MERGED_DIR, 'Merged_X_binary.npy'), merged_X)
    np.save(os.path.join(MERGED_DIR, 'Merged_y_binary.npy'), merged_y)
    np.save(os.path.join(MERGED_DIR, 'Merged_sub_binary.npy'), merged_sub)

    # 7. Compute Final Statistics
    total_baseline = int(np.sum(merged_y[:, 0]))
    total_stress = int(np.sum(merged_y[:, 1]))
    
    print("\n" + "=" * 60)
    print("✅ MERGE COMPLETE!")
    print(f"Master X Shape:   {merged_X.shape} (float32)")
    print(f"Master y Shape:   {merged_y.shape} (float32)")
    print(f"Master sub Shape: {merged_sub.shape} (<U21 string array)")
    print(f"\nFinal Class Balance:")
    print(f"  Class 0 (Baseline): {total_baseline} chunks")
    print(f"  Class 1 (Stress):   {total_stress} chunks")
    print(f"  Baseline Ratio:     {(total_baseline / len(merged_y)) * 100:.2f}%")
    print("=" * 60)

if __name__ == "__main__":
    main()
