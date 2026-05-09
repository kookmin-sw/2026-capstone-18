"""Env-driven settings for the ML demo service."""
from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict

_REPO_ROOT = Path(__file__).resolve().parents[2]
_DEFAULT_ONNX = _REPO_ROOT / "AI" / "checkpoints_final" / "wesad_w2.0" / "wesad_mamba_v1.onnx"


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="ML_DEMO_", extra="ignore")

    onnx_path: Path = _DEFAULT_ONNX
    max_upload_bytes: int = 5 * 1024 * 1024
