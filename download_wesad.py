import kagglehub
import shutil
import os

def main():
    # 1. Dynamically find the project root (assuming download.py is in the 'src' folder)
    SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
    PROJECT_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, '..'))
    
    # Define the target directory relative to the project root
    target_dir = os.path.join(PROJECT_ROOT, 'data', 'raw', 'WESAD')

    # 2. Download the dataset
    print("Downloading WESAD dataset... (This may take 5-10 minutes. Please wait.)")
    cache_path = kagglehub.dataset_download("orvile/wesad-wearable-stress-affect-detection-dataset")
    print(f"\nDownload complete! Data is currently in cache: {cache_path}")

    # 3. Move the unzipped WESAD folder from the cache to your project directory
    source_wesad_dir = os.path.join(cache_path, "WESAD")
    
    if os.path.exists(target_dir):
        print(f"\nTarget directory {target_dir} already exists. Cleaning it up...")
        shutil.rmtree(target_dir)

    print(f"Moving files to {target_dir}...")
    shutil.move(source_wesad_dir, target_dir)
    
    # 4. Clean up the cache to free up storage
    print("Cleaning up cache...")
    shutil.rmtree(cache_path)

    print(f"\nSuccess! Your .pkl files are ready at {target_dir}")

if __name__ == "__main__":
    main()
