import argparse
import os
import json
import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F
import torch.optim as optim
from torch.utils.data import Dataset, DataLoader
from sklearn.metrics import accuracy_score, f1_score, classification_report
from sklearn.utils.class_weight import compute_class_weight

from mamba_model import create_model

# speed-up for 4090 / 3090
torch.set_float32_matmul_precision('high')

# ==========================================
# 1. FOCAL LOSS & DATASET
# ==========================================
class FocalLoss(nn.Module):
    def __init__(self, weight=None, gamma=3.0):
        super(FocalLoss, self).__init__()
        self.weight = weight 
        self.gamma = gamma

    def forward(self, inputs, targets):
        ce_loss = F.cross_entropy(inputs, targets, weight=self.weight, reduction='none')
        pt = torch.exp(-ce_loss)
        focal_loss = ((1 - pt) ** self.gamma) * ce_loss
        return focal_loss.mean()

class WESADTensorDataset(Dataset):
    def __init__(self, X, y):
        self.X = torch.tensor(X, dtype=torch.float32)
        self.y = torch.tensor(y, dtype=torch.float32)

    def __len__(self):
        return len(self.y)

    def __getitem__(self, idx):
        return self.X[idx], self.y[idx]

# ==========================================
# 2. TRAINING & EVALUATION LOOPS
# ==========================================
def train_one_epoch(model, loader, criterion, optimizer, scheduler, device):
    model.train()
    total_loss, correct, total = 0, 0, 0

    for X_batch, y_batch in loader:
        X_batch, y_batch = X_batch.to(device), y_batch.to(device)

        optimizer.zero_grad()
        logits = model(X_batch)
        
        loss = criterion(logits, y_batch)
        loss.backward()
        nn.utils.clip_grad_norm_(model.parameters(), max_norm=1.0)
        optimizer.step()
        
        if scheduler is not None:
            scheduler.step()

        total_loss += loss.item() * len(y_batch)
        correct += (logits.argmax(1) == y_batch.argmax(1)).sum().item()
        total += len(y_batch)

    return total_loss / total, correct / total

@torch.no_grad()
def evaluate(model, loader, criterion, device):
    model.eval()
    total_loss, all_preds, all_labels = 0, [], []

    for X_batch, y_batch in loader:
        X_batch, y_batch = X_batch.to(device), y_batch.to(device)
        logits = model(X_batch)
        loss = criterion(logits, y_batch)

        total_loss += loss.item() * len(y_batch)
        all_preds.extend(logits.argmax(1).cpu().numpy())
        all_labels.extend(y_batch.argmax(1).cpu().numpy())

    all_preds, all_labels = np.array(all_preds), np.array(all_labels)
    return (total_loss / len(all_labels),
            accuracy_score(all_labels, all_preds),
            f1_score(all_labels, all_preds, average='macro'),
            all_labels, all_preds)

def save_incremental_log(log_path, fold_metrics):
    with open(log_path, 'w') as f:
        json.dump(fold_metrics, f, indent=4)

# ==========================================
# 3. SINGLE FOLD TRAINING PIPELINE
# ==========================================
def run_single_fold(args):
    X = np.load(os.path.join(args.data_dir, 'WESAD_X_calibrated.npy'))
    y = np.load(os.path.join(args.data_dir, 'WESAD_y_labeled.npy'))
    sub = np.load(os.path.join(args.data_dir, 'WESAD_sub_labeled.npy'), allow_pickle=True)

    device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
    print(f"Device: {device} | Total Samples: {X.shape[0]}")

    # Explicitly define test subjects for Fold 1
    target_test_subs = ['S6', 'S7', 'S10']
    test_mask = np.isin(sub, target_test_subs)
    
    train_idx = np.where(~test_mask)[0]
    test_idx = np.where(test_mask)[0]

    train_subs = np.unique(sub[train_idx])
    test_subs = np.unique(sub[test_idx])

    log_path = os.path.join(args.save_dir, 'cv_summary_fold1.json')
    fold_metrics = []

    print(f"\n{'='*60}")
    print(f"Deterministic Single Fold Execution")
    print(f"Train on 12 Subjects: {train_subs.tolist()}")
    print(f"Test on 3 Subjects:  {test_subs.tolist()}")
    print(f"{'='*60}")

    X_train, y_train = X[train_idx], y[train_idx]
    X_test, y_test = X[test_idx], y[test_idx]

    y_train_hard = y_train.argmax(axis=1)
    cw = compute_class_weight('balanced', classes=np.array([0, 1, 2]), y=y_train_hard)
    cw = np.sqrt(cw)
    cw = torch.tensor(cw, dtype=torch.float32).to(device)

    train_loader = DataLoader(WESADTensorDataset(X_train, y_train), batch_size=args.batch_size, shuffle=True, num_workers=8, pin_memory=True)
    test_loader = DataLoader(WESADTensorDataset(X_test, y_test), batch_size=args.batch_size, shuffle=False, num_workers=8, pin_memory=True)

    model_config = {
        'enc_in': X.shape[1], 'seq_len': X.shape[2], 'num_class': 3,
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

    criterion = FocalLoss(weight=cw, gamma=2.0)
    checkpoint_path = os.path.join(args.save_dir, 'fold_1_best.pt')

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
        train_loss, train_acc = train_one_epoch(model, train_loader, criterion, optimizer, scheduler, device)
        val_loss, val_acc, val_f1, _, _ = evaluate(model, test_loader, criterion, device)

        if val_f1 > best_fold_f1:
            best_fold_f1 = val_f1
            best_fold_acc = val_acc
            best_fold_epoch = epoch
            torch.save(model.state_dict(), checkpoint_path)

        print(f"Ep {epoch:>3d}/{args.epochs} | "
              f"Train [Loss: {train_loss:.4f} Acc: {train_acc:.3f}] | "
              f"Val [Loss: {val_loss:.4f} Acc: {val_acc:.3f} F1: {val_f1:.3f}] | "
              f"★ Best [Ep: {best_fold_epoch:<3d} Acc: {best_fold_acc:.3f} F1: {best_fold_f1:.3f}]")

    print(f"\n★ Fold 1 Complete: Best F1 = {best_fold_f1:.4f} (Achieved at Epoch {best_fold_epoch})")
    
    fold_metrics.append({
        'fold': 1, 
        'train_subjects': train_subs.tolist(),
        'test_subjects': test_subs.tolist(), 
        'best_f1': float(best_fold_f1), 
        'best_acc': float(best_fold_acc),
        'best_epoch': int(best_fold_epoch)
    })
    save_incremental_log(log_path, fold_metrics)

    split_data = {'train_idx': train_idx.tolist(), 'test_idx': test_idx.tolist(), 'test_subjects': test_subs.tolist()}
    with open(os.path.join(args.save_dir, 'best_qat_split.json'), 'w') as f:
        json.dump(split_data, f, indent=4)

    print(f">>> Locked Baseline Split for QAT saved to: best_qat_split.json")
    print(f">>> Weights saved to: {checkpoint_path}")

def main():
    SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
    PROJECT_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, '..'))

    parser = argparse.ArgumentParser(description='MeltdownGuard-Mamba Single Fold Execution')
    
    parser.add_argument('--data_dir', type=str, default=os.path.join(PROJECT_ROOT, 'data', 'processed'))
    parser.add_argument('--save_dir', type=str, default=os.path.join(PROJECT_ROOT, 'checkpoints'))
    
    parser.add_argument('--epochs', type=int, default=50)
    
    parser.add_argument('--projected_space', type=int, default=64)
    parser.add_argument('--d_state', type=int, default=16)
    parser.add_argument('--dconv', type=int, default=4)
    parser.add_argument('--e_fact', type=int, default=2)
    parser.add_argument('--num_mambas', type=int, default=1)
    parser.add_argument('--patch_len', type=int, default=32)
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
    
    run_single_fold(args)

if __name__ == '__main__':
    main()
