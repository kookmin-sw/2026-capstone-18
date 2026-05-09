from pathlib import Path

from AI.serve.settings import Settings


def test_settings_default_onnx_path_relative_to_repo() -> None:
    settings = Settings()
    assert settings.onnx_path.name == "wesad_mamba_v1.onnx"
    assert settings.onnx_path.parent.name == "wesad_w2.0"


def test_settings_max_upload_default_is_5mb() -> None:
    settings = Settings()
    assert settings.max_upload_bytes == 5 * 1024 * 1024


def test_settings_reads_env_overrides(tmp_path: Path, monkeypatch) -> None:
    fake_onnx = tmp_path / "fake.onnx"
    fake_onnx.write_bytes(b"")
    monkeypatch.setenv("ML_DEMO_ONNX_PATH", str(fake_onnx))
    monkeypatch.setenv("ML_DEMO_MAX_UPLOAD_BYTES", "1024")
    settings = Settings()
    assert settings.onnx_path == fake_onnx
    assert settings.max_upload_bytes == 1024
