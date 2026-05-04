import os
import subprocess
import sys

def main():
    # 1. Define Paths
    SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
    PROJECT_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, '..',  '..')) 
    RAW_DIR = os.path.join(PROJECT_ROOT, 'data', 'raw')
    
    stress_predict_dir = os.path.join(RAW_DIR, 'StressPredict')
    empatica_dir = os.path.join(RAW_DIR, 'EmpaticaE4Stress')

    os.makedirs(RAW_DIR, exist_ok=True)

    print("=" * 60)
    print("  Dataset Acquisition: Stress-Predict & EmpaticaE4Stress")
    print("=" * 60)

    # 2. Download Stress-Predict (Automated via Git)
    if os.path.exists(stress_predict_dir):
        print(f"[*] Stress-Predict directory already exists at {stress_predict_dir}. Skipping clone.")
    else:
        print("[*] Cloning Stress-Predict dataset from GitHub...")
        try:
            # We clone directly into the target directory
            subprocess.check_call([
                "git", "clone", 
                "https://github.com/italha-d/Stress-Predict-Dataset.git", 
                stress_predict_dir
            ])
            print("✅ Stress-Predict downloaded successfully.")
        except subprocess.CalledProcessError as e:
            print(f"❌ Failed to clone Stress-Predict: {e}")
            sys.exit(1)

    # 3. Instructions for EmpaticaE4Stress (Manual intervention required)
    print("\n" + "=" * 60)
    print("  ACTION REQUIRED: EmpaticaE4Stress Download")
    print("=" * 60)
    print("Because Mendeley Data generates zip files dynamically via JavaScript,")
    print("it blocks automated terminal downloads.")
    print("\nPlease follow these exact steps to obtain the remaining dataset:")
    print("1. Open your local web browser and navigate to:")
    print("   https://data.mendeley.com/datasets/kb42z77m2g/2")
    print("2. Click the 'Download All' button (top right).")
    print(f"3. Move the downloaded .zip file into your Docker container at:\n   {RAW_DIR}/")
    print(f"4. Run the following commands in your terminal to unpack it:")
    print(f"   cd {RAW_DIR}")
    print(f"   mkdir -p EmpaticaE4Stress")
    print(f"   unzip <name_of_downloaded_file>.zip -d EmpaticaE4Stress")
    print("============================================================")

if __name__ == "__main__":
    main()