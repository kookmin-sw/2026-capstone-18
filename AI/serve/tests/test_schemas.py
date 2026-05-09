from AI.serve.schemas import CalibrationInfo, ChunkResult, ModelInfo, RunResponse


def test_chunk_result_round_trip() -> None:
    chunk = ChunkResult(
        time_seconds=300,
        time_label="5m 00s",
        prob_stress=0.441,
        state="Baseline",
        should_notify=False,
        in_stress_event=False,
    )
    payload = chunk.model_dump()
    assert payload["time_seconds"] == 300
    assert payload["state"] == "Baseline"
    assert ChunkResult.model_validate(payload) == chunk


def test_run_response_serializes() -> None:
    resp = RunResponse(
        calibration=CalibrationInfo(duration_seconds=180, samples_used=4500),
        chunks=[
            ChunkResult(
                time_seconds=300,
                time_label="5m 00s",
                prob_stress=0.441,
                state="Baseline",
                should_notify=False,
                in_stress_event=False,
            )
        ],
        model=ModelInfo(
            onnx_path="checkpoints_final/wesad_w2.0/wesad_mamba_v1.onnx",
            target_hz=25,
            chunk_seconds=60,
            buffer_seconds=300,
        ),
    )
    payload = resp.model_dump()
    assert payload["chunks"][0]["prob_stress"] == 0.441
    assert payload["model"]["target_hz"] == 25
