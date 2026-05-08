import argparse
import os
import json
import time
import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F
import torch.optim as optim
from torch.utils.data import Dataset, DataLoader
from sklearn.metrics import accuracy_score, f1_score

from mamba_model import create_model

# Optimizations for RTX 4090
torch.set_float32_matmul_precision('high')

# ==========================================
# 1. INSTANCE-WEIGHTED FOCAL LOSS & DATASET
# ==========================================
class InstanceWeightedFocalLoss(nn.Module):
    def __init__(self, gamma=3.0):
        super(InstanceWeightedFocalLoss, self).__init__()
        self.gamma = gamma

    def forward(self, inputs, targets, sample_weights):
        ce_loss = F.cross_entropy(inputs, targets, reduction='none')
        pt = torch.exp(-ce_loss)
        focal_loss = ((1 - pt) ** self.gamma) * ce_loss
        weighted_loss = focal_loss * sample_weights
        return weighted_loss.mean()

class WESADTensorDataset(Dataset):
    def __init__(self, X, y, sub, wesad_stress_w=2.0):
        self.X = torch.tensor(X, dtype=torch.float32)
        self.y = torch.tensor(y, dtype=torch.float32)
        self.sample_weights = torch.zeros(len(y), dtype=torch.float32)
        
        # Mapping logic
        for i in range(len(y)):
            subject = str(sub[i]).strip()
            is_stress = np.argmax(y[i]) == 1
            
            if subject.endswith('_S'): # StressPredict
                self.sample_weights[i] = 1.0
            else: # WESAD
                if is_stress:
                    self.sample_weights[i] = wesad_stress_w
                else:
                    self.sample_weights[i] = 0.5
                    
    def __len__(self):
        return len(self.y)

    def __getitem__(self, idx):
        return self.X[idx], self.y[idx], self.sample_weights[idx]

# ==========================================
# 2. TRAINING & EVALUATION LOOPS
# ==========================================
def train_one_epoch(model, loader, criterion, optimizer, scheduler, device):
    model.train()
    total_loss, correct, total = 0, 0, 0
    start_time = time.time()

    for X_batch, y_batch, w_batch in loader:
        X_batch, y_batch, w_batch = X_batch.to(device), y_batch.to(device), w_batch.to(device)

        optimizer.zero_grad()
        logits = model(X_batch)
        loss = criterion(logits, y_batch, w_batch)
        loss.backward()
        nn.utils.clip_grad_norm_(model.parameters(), max_norm=1.0)
        optimizer.step()
        
        if scheduler is not None:
            scheduler.step()

        total_loss += loss.item() * len(y_batch)
        correct += (logits.argmax(1) == y_batch.argmax(1)).sum().item()
        total += len(y_batch)

    epoch_time = time.time() - start_time
    return total_loss / total, correct / total, epoch_time

@torch.no_grad()
def evaluate(model, loader, criterion, device):
    model.eval()
    total_loss, all_preds, all_labels = 0, [], []

    for X_batch, y_batch, w_batch in loader:
        X_batch, y_batch, w_batch = X_batch.to(device), y_batch.to(device), w_batch.to(device)
        logits = model(X_batch)
        loss = criterion(logits, y_batch, w_batch)

        total_loss += loss.item() * len(y_batch)
        all_preds.extend(logits.argmax(1).cpu().numpy())
        all_labels.extend(y_batch.argmax(1).cpu().numpy())

    all_preds, all_labels = np.array(all_preds), np.array(all_labels)
    f1 = f1_score(all_labels, all_preds, pos_label=1, average='binary', zero_division=0)
    return (total_loss / len(all_labels), accuracy_score(all_labels, all_preds), f1)

# ==========================================
# 3. DEPLOYMENT PIPELINE
# ==========================================
def run_deployment(args):
    # Ensure Save Dir exists early
    os.makedirs(args.save_dir, exist_ok=True)
    
    print(f"--- Initialization ---")
    X = np.load(os.path.join(args.data_dir, 'Merged_X_binary.npy'))
    y = np.load(os.path.join(args.data_dir, 'Merged_y_binary.npy'))
    sub = np.load(os.path.join(args.data_dir, 'Merged_sub_binary.npy'), allow_pickle=True)

    device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
    
    holdout_list = [s.strip() for s in args.holdout_subs.split(',')]
    
    train_idx, val_idx = [], []
    for i, s in enumerate(sub):
        if str(s).strip() in holdout_list:
            val_idx.append(i)
        else:
            train_idx.append(i)
            
    # CRITICAL SANITY CHECK
    if len(train_idx) == 0 or len(val_idx) == 0:
        raise ValueError(f"FATAL: Split failed. Train: {len(train_idx)}, Val: {len(val_idx)}. Check holdout_subs names.")

    print(f"Samples -> Train: {len(train_idx)} | Val: {len(val_idx)}")
    
    X_train, y_train, sub_train = X[train_idx], y[train_idx], sub[train_idx]
    X_val, y_val, sub_val = X[val_idx], y[val_idx], sub[val_idx]

    train_ds = WESADTensorDataset(X_train, y_train, sub_train, wesad_stress_w=args.wesad_stress_w)
    
    # Weight Sanity Check
    unique_w, counts_w = np.unique(train_ds.sample_weights.numpy(), return_counts=True)
    print(f"Weight Distribution: {dict(zip(unique_w, counts_w))}")

    train_loader = DataLoader(train_ds, batch_size=args.batch_size, shuffle=True, num_workers=4) 
    val_loader = DataLoader(WESADTensorDataset(X_val, y_val, sub_val, wesad_stress_w=args.wesad_stress_w), 
                            batch_size=args.batch_size, shuffle=False, num_workers=4)

    model_config = {
        'enc_in': X.shape[1], 'seq_len': X.shape[2], 'num_class': 2,
        'projected_space': args.projected_space, 'd_state': args.d_state,
        'dconv': args.dconv, 'e_fact': args.e_fact, 'num_mambas': args.num_mambas,
        'dropout': args.dropout, 'patch_len': args.patch_len,
        'only_forward_scan': 0 if args.tango else 1, 'reverse_flip': args.reverse_flip, 'max_pooling': 0,
    }
    
    model, _ = create_model(model_config)
    model = model.to(device)

    criterion = InstanceWeightedFocalLoss(gamma=3.0)
    checkpoint_path = os.path.join(args.save_dir, 'deployment_master_weights.pt')

    optimizer = optim.AdamW(model.parameters(), lr=args.lr, weight_decay=args.wd)
    scheduler = optim.lr_scheduler.OneCycleLR(
        optimizer, max_lr=args.lr, steps_per_epoch=len(train_loader), epochs=args.epochs, pct_start=0.1 
    )

    best_f1, best_epoch = 0, 0

    print(f"\n--- Training Started ---")
    for epoch in range(1, args.epochs + 1):
        t_loss, t_acc, t_time = train_one_epoch(model, train_loader, criterion, optimizer, scheduler, device)
        v_loss, v_acc, v_f1 = evaluate(model, val_loader, criterion, device)

        if v_f1 > best_f1:
            best_f1, best_epoch = v_f1, epoch
            torch.save(model.state_dict(), checkpoint_path)

        print(f"Ep {epoch:>3d}/{args.epochs} | "
              f"Train [Loss: {t_loss:.4f} Acc: {t_acc:.3f}] | "
              f"Val [Loss: {v_loss:.4f} Acc: {v_acc:.3f} F1: {v_f1:.3f}] | "
              f"Time: {t_time:.2f}s | "
              f"★ Best [Ep: {best_epoch:<3d} F1: {best_f1:.3f}]")

def main():
    SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
    PROJECT_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, '..'))

    parser = argparse.ArgumentParser(description='MeltdownGuard-Mamba Final Deployment Model')
    
    parser.add_argument('--data_dir', type=str, default=os.path.join(PROJECT_ROOT, 'data', 'galaxy', 'Merged'))
    parser.add_argument('--save_dir', type=str, default=os.path.join(PROJECT_ROOT, 'checkpoints', 'deployment'))
    parser.add_argument('--holdout_subs', type=str, required=True, help="Comma-separated subjects to hold out (e.g., 'S8_W,11_S,26_S')")
    
    parser.add_argument('--wesad_stress_w', type=float, default=2.0)
    parser.add_argument('--epochs', type=int, default=150)
    parser.add_argument('--batch_size', type=int, default=64) 
    parser.add_argument('--lr', type=float, default=5e-4)
    parser.add_argument('--wd', type=float, default=1e-2)
    parser.add_argument('--dropout', type=float, default=0.3)
    parser.add_argument('--gpu', type=int, default=0)
    parser.add_argument('--projected_space', type=int, default=64)
    parser.add_argument('--d_state', type=int, default=16)
    parser.add_argument('--dconv', type=int, default=4)
    parser.add_argument('--e_fact', type=int, default=2)
    parser.add_argument('--num_mambas', type=int, default=1)
    parser.add_argument('--patch_len', type=int, default=50)
    parser.add_argument('--tango', action='store_true')
    parser.add_argument('--reverse_flip', type=int, default=1)

    args = parser.parse_args()
    os.environ["CUDA_VISIBLE_DEVICES"] = str(args.gpu)
    run_deployment(args)

if __name__ == '__main__':
    main()
