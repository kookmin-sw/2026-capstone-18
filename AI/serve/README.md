# Little Signals — ML Demo Service

A small FastAPI service that wraps the ONNX stress-detection pipeline (`AI/src/pipeline.py`) and runs it against an uploaded Galaxy Watch capture zip. Two purposes:

1. **End-to-end verification** — feed the canonical `Galaxy_Test` capture in, get back the same probabilities as `expected_pipeline_log.txt`. Confirms the watch-format capture, preprocessing, ONNX model, and runtime agree.
2. **Live demo** — show the model producing real outputs without a watch on a wrist. Upload a recorded zip, get a JSON list of per-minute probabilities.

The production backend deliberately does not run ML — see [`backend/README.md`](../../backend/README.md). This service is dev/demo tooling only.

## Endpoints

| Method | Path | Purpose |
| :--- | :--- | :--- |
| `GET` | `/health` | `{"status": "ok", "model_loaded": true}` |
| `POST` | `/api/v1/ml-demo/run` | Multipart upload (`capture=<zip>`); returns 5 chunks of probabilities for the 10-min `Galaxy_Test` fixture. |

The capture zip must contain `ppg_green.csv`, `eda.csv`, and `accel.csv` matching the column shapes the watch sensor-capture app produces.

## Local dev

```bash
cd AI/serve
python3.12 -m venv .venv && source .venv/bin/activate
pip install -r requirements-dev.txt   # runtime + pytest
cd ../..
ML_DEMO_ONNX_PATH="$(pwd)/AI/checkpoints_final/wesad_w2.0/wesad_mamba_v1.onnx" \
  python -m uvicorn AI.serve.main:app --reload --port 8001
```

```bash
( cd AI/data/raw/Galaxy_Test && zip -j /tmp/galaxy_test.zip ppg_green.csv eda.csv accel.csv )
curl -s -F "capture=@/tmp/galaxy_test.zip" \
  http://localhost:8001/api/v1/ml-demo/run | jq
```

Expected output: 5 chunks at `time_seconds` 300/360/420/480/540 with `prob_stress` ≈ 0.441 / 0.691 / 0.450 / 0.289 / 0.280 (within 0.01).

## Docker

Build from the **repo root** (Dockerfile uses repo-relative `COPY` paths):

```bash
docker build -f AI/serve/Dockerfile -t little-signals-ml-demo .
docker run --rm -p 8001:8001 little-signals-ml-demo
```

Image is ~576 MB. The ONNX model is baked into the image at `/app/AI/checkpoints_final/wesad_w2.0/wesad_mamba_v1.onnx`.

## Tests

```bash
AI/serve/.venv/bin/python -m pytest AI/serve -v
```

Expected: 18 passed locally with the `Galaxy_Test/` fixture present. The parity test (`test_runner_parity_with_galaxy_test`) requires `AI/data/raw/Galaxy_Test/` to be present locally — that folder is gitignored, so on a fresh CI runner the test will skip with a clear message instead of failing. See the LIT-60 handoff bundle for the artifacts.

## Configuration

| Env var | Default | Purpose |
| :--- | :--- | :--- |
| `ML_DEMO_ONNX_PATH` | `AI/checkpoints_final/wesad_w2.0/wesad_mamba_v1.onnx` | Path to the ONNX model file. |
| `ML_DEMO_MAX_UPLOAD_BYTES` | `5242880` (5 MB) | Reject larger uploads with 413. |

## Files

```
AI/serve/
├── main.py              # FastAPI factory + lifespan (fail-fast on missing ONNX)
├── router.py            # /health, /api/v1/ml-demo/run
├── preprocess.py        # zip → 25 Hz numpy arrays (mirrors simulate_live_stream)
├── runner.py            # drives RealTimeStressPipeline through chunks
├── schemas.py           # Pydantic request/response models
├── settings.py          # env-driven config
├── requirements.txt     # runtime deps (fastapi, onnxruntime, scipy, pandas, …)
├── requirements-dev.txt # adds pytest + pytest-asyncio for local testing
├── Dockerfile
├── Dockerfile.dockerignore
└── tests/
    ├── conftest.py
    ├── fixtures/
    │   ├── _make_synthetic.py    # regenerates synthetic_capture.zip
    │   └── synthetic_capture.zip # tiny deterministic fixture for unit tests
    ├── test_settings.py
    ├── test_fixture.py
    ├── test_preprocess.py
    ├── test_schemas.py
    ├── test_runner.py
    └── test_router.py
```

## Out of scope

- AWS deployment — track separately. The current service is local + Docker only.
- Auth — none. Deploy behind a staging-only ALB rule when it ships.
- Streaming responses — the 10-minute fixture is 5 chunks; one JSON response is fine.
