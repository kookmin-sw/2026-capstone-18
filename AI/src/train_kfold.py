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
from sklearn.model_selection import GroupKFold

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

def save_incremental_log(log_path, fold_metrics):
    with open(log_path, 'w') as f:
        json.dump(fold_metrics, f, indent=4)

# ==========================================
# 3. K-FOLD PIPELINE (ASYMMETRIC)
# ==========================================
def run_group_kfold(args):
    # Dynamic loading based on prefix
    X = np.load(os.path.join(args.data_dir, f'{args.prefix}_X_binary.npy'))
    y = np.load(os.path.join(args.data_dir, f'{args.prefix}_y_binary.npy'))
    sub = np.load(os.path.join(args.data_dir, f'{args.prefix}_sub_binary.npy'), allow_pickle=True)

    device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
    print(f"Device: {device} | Total Samples: {X.shape[0]} | Dataset: {args.prefix}")

    # ==========================================
    # CUSTOM ASYMMETRIC K-FOLD LOGIC
    # ==========================================
    WESAD_FEMALES = ['S8_W', 'S11_W', 'S17_W']
    
    target_indices = []
    aux_indices = []
    
    for i, s in enumerate(sub):
        if str(s).endswith('_S') or str(s) in WESAD_FEMALES:
            target_indices.append(i)
        else:
            aux_indices.append(i) # WESAD Males
            
    target_indices = np.array(target_indices)
    aux_indices = np.array(aux_indices)
    
    target_X = X[target_indices]
    target_y = y[target_indices]
    target_sub = sub[target_indices]
    
    print(f"Target Pool (Train/Test): {len(target_indices)} chunks")
    print(f"Auxiliary Pool (Train Only): {len(aux_indices)} chunks")

    # Configurable folds
    gkf = GroupKFold(n_splits=args.folds)
    
    log_path = os.path.join(args.save_dir, 'cv_summary.json')
    fold_metrics = []
    
    if args.resume and os.path.exists(log_path):
        print(f"[*] Found existing log file at {log_path}. Loading previous history...")
        with open(log_path, 'r') as f:
            fold_metrics = json.load(f)
            
    best_overall_f1 = max([m['best_f1'] for m in fold_metrics]) if fold_metrics else 0
    best_fold_idx = max(fold_metrics, key=lambda x:x['best_f1'])['fold'] if fold_metrics else 0

    for fold, (target_train_idx, test_idx) in enumerate(gkf.split(target_X, target_y, groups=target_sub)):
        current_fold_num = fold + 1
        
        # Map target subset indices back to absolute global indices
        global_target_train_idx = target_indices[target_train_idx]
        global_test_idx = target_indices[test_idx]
        
        # Inject Auxiliary (Male) indices exclusively into the train set
        global_train_idx = np.concatenate([global_target_train_idx, aux_indices])
        
        train_subs = np.unique(sub[global_train_idx])
        test_subs = np.unique(sub[global_test_idx])
        
        if any(m['fold'] == current_fold_num for m in fold_metrics):
            print(f"[*] Fold {current_fold_num} already exists in log file. Skipping...")
            continue
            
        print(f"\n{'='*60}")
        print(f"Fold {current_fold_num}/{args.folds}")
        print(f"Train on {len(train_subs)} Subjects (Includes Aux)")
        print(f"Test on {len(test_subs)} Subjects:  {test_subs.tolist()}")
        print(f"{'='*60}")

        X_train, y_train, sub_train = X[global_train_idx], y[global_train_idx], sub[global_train_idx]
        X_test, y_test, sub_test = X[global_test_idx], y[global_test_idx], sub[global_test_idx]

        train_ds = WESADTensorDataset(X_train, y_train, sub_train, wesad_stress_w=args.wesad_stress_w)
        
        # Weight Sanity Check
        if current_fold_num == 1:
            unique_w, counts_w = np.unique(train_ds.sample_weights.numpy(), return_counts=True)
            print(f"Weight Distribution: {dict(zip(unique_w, counts_w))}")

        train_loader = DataLoader(train_ds, batch_size=args.batch_size, shuffle=True, num_workers=4, pin_memory=True)
        test_loader = DataLoader(WESADTensorDataset(X_test, y_test, sub_test, wesad_stress_w=args.wesad_stress_w), 
                                 batch_size=args.batch_size, shuffle=False, num_workers=4, pin_memory=True)

        model_config = {
            'enc_in': X.shape[1], 'seq_len': X.shape[2], 'num_class': 2,
            'projected_space': args.projected_space, 'd_state': args.d_state,
            'dconv': args.dconv, 'e_fact': args.e_fact, 'num_mambas': args.num_mambas,
            'dropout': args.dropout, 'patch_len': args.patch_len,
            'only_forward_scan': 0 if args.tango else 1, 'reverse_flip': args.reverse_flip, 'max_pooling': 0,
        }
        
        model, _ = create_model(model_config)
        model = model.to(device)
        
        if hasattr(torch, 'compile'):
            try:
                model = torch.compile(model)
            except Exception as e:
                pass

        criterion = InstanceWeightedFocalLoss(gamma=3.0)
        checkpoint_path = os.path.join(args.save_dir, f'fold_{current_fold_num}_best.pt')

        if args.resume and os.path.exists(checkpoint_path):
            print(f"[Resume] Reconstructing metrics for Fold {current_fold_num} from checkpoint...")
            model.load_state_dict(torch.load(checkpoint_path, map_location=device, weights_only=True))
            val_loss, val_acc, val_f1 = evaluate(model, test_loader, criterion, device)
            
            print(f"★ Recovered Fold {current_fold_num} | Acc: {val_acc:.3f} | F1: {val_f1:.3f}")
            
            fold_metrics.append({
                'fold': current_fold_num, 
                'train_subjects': train_subs.tolist(),
                'test_subjects': test_subs.tolist(), 
                'best_f1': float(val_f1), 
                'best_acc': float(val_acc),
                'best_epoch': 'Recovered' 
            })
            save_incremental_log(log_path, fold_metrics)
            
            if val_f1 > best_overall_f1:
                best_overall_f1 = val_f1
                best_fold_idx = current_fold_num
                split_data = {'train_idx': global_train_idx.tolist(), 'test_idx': global_test_idx.tolist(), 'test_subjects': test_subs.tolist()}
                with open(os.path.join(args.save_dir, 'best_qat_split.json'), 'w') as f:
                    json.dump(split_data, f, indent=4)
            continue

        optimizer = optim.AdamW(model.parameters(), lr=args.lr, weight_decay=args.wd)
        scheduler = optim.lr_scheduler.OneCycleLR(
            optimizer, 
            max_lr=args.lr, 
            steps_per_epoch=len(train_loader), 
            epochs=args.epochs,
            pct_start=0.1 
        )

        best_fold_f1 = 0
        best_fold_epoch = 0
        best_fold_acc = 0

        for epoch in range(1, args.epochs + 1):
            t_loss, t_acc, t_time = train_one_epoch(model, train_loader, criterion, optimizer, scheduler, device)
            v_loss, v_acc, v_f1 = evaluate(model, test_loader, criterion, device)

            if v_f1 > best_fold_f1:
                best_fold_f1 = v_f1
                best_fold_acc = v_acc
                best_fold_epoch = epoch
                torch.save(model.state_dict(), checkpoint_path)

            print(f"Ep {epoch:>3d}/{args.epochs} | "
                  f"Train [Loss: {t_loss:.4f} Acc: {t_acc:.3f}] | "
                  f"Val [Loss: {v_loss:.4f} Acc: {v_acc:.3f} F1: {v_f1:.3f}] | "
                  f"Time: {t_time:.2f}s | "
                  f"★ Best [Ep: {best_fold_epoch:<3d} F1: {best_fold_f1:.3f}]")

        print(f"\n★ Fold {current_fold_num} Complete: Best F1 = {best_fold_f1:.4f} (Achieved at Epoch {best_fold_epoch})")
        
        fold_metrics.append({
            'fold': current_fold_num, 
            'train_subjects': train_subs.tolist(),
            'test_subjects': test_subs.tolist(), 
            'best_f1': float(best_fold_f1), 
            'best_acc': float(best_fold_acc),
            'best_epoch': int(best_fold_epoch)
        })
        save_incremental_log(log_path, fold_metrics)

        if best_fold_f1 > best_overall_f1:
            best_overall_f1 = best_fold_f1
            best_fold_idx = current_fold_num
            split_data = {'train_idx': global_train_idx.tolist(), 'test_idx': global_test_idx.tolist(), 'test_subjects': test_subs.tolist()}
            with open(os.path.join(args.save_dir, 'best_qat_split.json'), 'w') as f:
                json.dump(split_data, f, indent=4)

    print(f"\n{'='*60}")
    print(f"Asymmetric GroupKFold {args.folds}-Fold Final Summary")
    print(f"{'='*60}")
    f1_scores = [m['best_f1'] for m in fold_metrics]
    print(f"Average Stress F1: {np.mean(f1_scores):.4f} ± {np.std(f1_scores):.4f}")
    
    for m in fold_metrics:
        print(f"Fold {m['fold']} (Test Subs: {m['test_subjects']}): F1 = {m['best_f1']:.4f} | Epoch = {m['best_epoch']}")

def main():
    SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
    PROJECT_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, '..'))

    parser = argparse.ArgumentParser(description='MeltdownGuard-Mamba Universal Training Harness')
    
    parser.add_argument('--data_dir', type=str, default=os.path.join(PROJECT_ROOT, 'data', 'galaxy', 'Merged'))
    parser.add_argument('--prefix', type=str, default='Merged', help='Prefix of the numpy files')
    parser.add_argument('--save_dir', type=str, default=os.path.join(PROJECT_ROOT, 'checkpoints'))
    parser.add_argument('--wesad_stress_w', type=float, default=2.0)
    
    parser.add_argument('--epochs', type=int, default=150)
    parser.add_argument('--folds', type=int, default=5, help='Number of cross-validation folds')
    parser.add_argument('--resume', action='store_true')
    
    parser.add_argument('--projected_space', type=int, default=64)
    parser.add_argument('--d_state', type=int, default=16)
    parser.add_argument('--dconv', type=int, default=4)
    parser.add_argument('--e_fact', type=int, default=2)
    parser.add_argument('--num_mambas', type=int, default=1)
    parser.add_argument('--patch_len', type=int, default=50)
    parser.add_argument('--dropout', type=float, default=0.3)
    parser.add_argument('--tango', action='store_true')
    parser.add_argument('--reverse_flip', type=int, default=1)
    
    parser.add_argument('--batch_size', type=int, default=64) 
    parser.add_argument('--lr', type=float, default=5e-4)
    parser.add_argument('--wd', type=float, default=1e-2)
    parser.add_argument('--gpu', type=int, default=1)

    args = parser.parse_args()
    
    os.environ["CUDA_VISIBLE_DEVICES"] = str(args.gpu)
    os.makedirs(args.save_dir, exist_ok=True)
    
    run_group_kfold(args)

if __name__ == '__main__':
    main()
