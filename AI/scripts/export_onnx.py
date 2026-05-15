import os
import sys
import torch

import os
import sys
import torch

# ==========================================
# 1. DYNAMIC PATH RESOLUTION
# ==========================================
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
AI_DIR = os.path.dirname(SCRIPT_DIR) # Moves up one level from AI/scripts to AI/

SRC_DIR = os.path.join(AI_DIR, 'src')
if SRC_DIR not in sys.path:
    sys.path.append(SRC_DIR)

from mamba_model import create_model

WEIGHTS_PATH = os.path.join(AI_DIR, 'checkpoints_final', 'wesad_w2.0', 'deployment_master_weights.pt')
ONNX_SAVE_PATH = os.path.join(AI_DIR, 'checkpoints_final', 'wesad_w2.0', 'wesad_mamba_v1.onnx')

def export_mamba_to_onnx():
    print("=" * 60)
    print(" STARTING ONNX EXPORT PROCESS (PURE PYTORCH)")
    print("=" * 60)
    
    device = torch.device('cpu') 

    print("[*] Initializing Model Architecture...")
    model_config = {
        'enc_in': 9, 'seq_len': 1500, 'num_class': 2,
        'projected_space': 64, 'd_state': 16, 'dconv': 4, 'e_fact': 2,
        'num_mambas': 1, 'patch_len': 50, 'dropout': 0.3,
        'only_forward_scan': 1, 'reverse_flip': 1, 'max_pooling': 0,
    }

    model, _ = create_model(model_config)
    
    print("[*] Loading Master Weights...")
    state_dict = torch.load(WEIGHTS_PATH, map_location=device, weights_only=True)
    clean_state_dict = {k.replace('_orig_mod.', ''): v for k, v in state_dict.items()}
    model.load_state_dict(clean_state_dict)
    
    model.to(device)
    model.eval() # CRITICAL: Disables dropout

    # ==========================================
    # 2. CREATE DUMMY INPUT TENSOR
    # ==========================================
    # ONNX export requires a physical tensor to trace the computational graph.
    # Shape: [Batch_Size=1, Channels=9, Seq_Len=1500]
    dummy_input = torch.randn(1, 9, 1500, dtype=torch.float32).to(device)

    # ==========================================
    # 3. EXECUTE EXPORT
    # ==========================================
    print(f"[*] Tracing Computational Graph to Opset 17...")
    torch.onnx.export(
        model, 
        dummy_input, 
        ONNX_SAVE_PATH,
        export_params=True,        
        opset_version=17,          # Highest opset for complex control flow/math
        do_constant_folding=True,  
        input_names=['input_tensor'],
        output_names=['stress_logits'],
        dynamic_axes={
            'input_tensor': {0: 'batch_size'},
            'stress_logits': {0: 'batch_size'}
        }
    )
    
    print("\n" + "=" * 60)
    print(f"✅ SUCCESS: Model successfully exported to ONNX format!")
    print(f"📁 Path: {ONNX_SAVE_PATH}")
    print("=" * 60)

if __name__ == '__main__':
    export_mamba_to_onnx()