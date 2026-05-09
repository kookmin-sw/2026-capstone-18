# ML Demo Service — Design

## 1. Problem

The on-device Mamba stress-detection model is being handed off to the watch team to port into Kotlin/ONNX Runtime Mobile (Linear LIT-60). Two needs follow from the handoff:

1. **End-to-end verification.** We need to confirm the trained ONNX model, the preprocessing pipeline, and the upstream watch capture format all line up — before anyone integrates with the watch app or the production backend.
2. **Live demo.** We want to show reviewers the model producing real probabilities from real Galaxy Watch sensor data, without requiring a watch on someone's wrist at demo time.

The existing production backend ([backend/README.md:63](../../backend/README.md)) explicitly does not run ML inference — that's the watch's job — and any biosignals reaching the server are end-to-end encrypted with user-held keys. So we cannot bolt the model into the production FastAPI app without breaking the privacy model.

## 2. Approach

A **separate FastAPI service** under `AI/serve/` that wraps the existing [AI/src/pipeline.py](../../AI/src/pipeline.py) and exposes a single endpoint accepting a Galaxy Watch capture bundle (the zip format already produced by [watch/sensor-capture](../../watch/sensor-capture/)). The service runs the same `RealTimeStressPipeline` as `simulate_live_stream`, captures per-chunk results into JSON, and returns them.

Why a separate service:
- The pipeline pulls in `onnxruntime`, `scipy`, `pandas`, `numpy` (~150 MB of deps). The production backend image is intentionally lean.
- This is demo / dev tooling, not a user-facing product feature. Different lifecycle, different deploy cadence.
- Keeps the backend's "no ML inference on the server" architectural commitment intact.

`AI/src/pipeline.py` is **not modified**. The AI team owns it. The serve layer is a thin shell on top.

## 3. Scope

**In scope:**
- `AI/serve/` Python package — FastAPI app, preprocessing, run-loop driver, schemas
- One endpoint: `POST /api/v1/ml-demo/run` accepting a multipart upload of the Galaxy capture zip
- One endpoint: `GET /health` returning `{status: "ok"}`
- Local Docker container that runs the service end-to-end against the committed fixture
- Parity test asserting outputs match [AI/data/raw/Galaxy_Test/expected_pipeline_log.txt](../../AI/data/raw/Galaxy_Test/expected_pipeline_log.txt) within 1e-2

**Out of scope (explicitly deferred):**
- AWS Terraform deployment (separate ECR/ECS/ALB rule). Track as a follow-up issue.
- Auth — the demo service is unauthenticated; deploy behind staging URL only when it ships to AWS.
- Streaming response (SSE/WebSocket). The current `expected_pipeline_log.txt` is 5 lines for a 10-min capture; one JSON response is fine.
- Rate limiting, request quotas. Capstone-scale traffic.
- Multi-tenant calibration state. Each request is self-contained; calibration is derived from the uploaded data's first 180 s.

## 4. API contract

### `POST /api/v1/ml-demo/run`

**Request:** `multipart/form-data` with field `capture` containing the zip produced by the watch sensor-capture app. The zip must contain at least:
- `ppg_green.csv` — columns `timestamp_ms`, `ppg_green`
- `eda.csv` — columns `timestamp_ms`, `skin_conductance`
- `accel.csv` — columns `timestamp_ms`, `x`, `y`, `z`

**Constraints:**
- Total upload size ≤ 5 MB (rejected with 413 above)
- Synced recording must be at least `BASELINE_SEC` (180 s) after timestamp alignment, else 400

**Response (200):**

```json
{
  "calibration": {
    "duration_seconds": 180,
    "samples_used": 4500
  },
  "chunks": [
    {
      "time_seconds": 300,
      "time_label": "5m 00s",
      "prob_stress": 0.441,
      "state": "Baseline",
      "should_notify": false,
      "in_stress_event": false
    }
  ],
  "model": {
    "onnx_path": "checkpoints_final/wesad_w2.0/wesad_mamba_v1.onnx",
    "target_hz": 25,
    "chunk_seconds": 60,
    "buffer_seconds": 300
  }
}
```

The `chunks` array is the structured form of `expected_pipeline_log.txt`: one entry per 60-second inference step. `time_seconds` matches `current_time_sec` in [AI/src/pipeline.py:199](../../AI/src/pipeline.py).

**Errors:**
- 400 — missing CSV in zip, malformed columns, or recording shorter than baseline
- 413 — upload too large
- 500 — ONNX runtime error (logged with request id)

### `GET /health`

Returns `{"status": "ok", "model_loaded": true}`. ALB liveness target.

## 5. Architecture & files

```
AI/
├── src/
│   └── pipeline.py                 # UNCHANGED (AI team owns)
├── checkpoints_final/wesad_w2.0/
│   └── wesad_mamba_v1.onnx         # already committed
├── data/raw/Galaxy_Test/           # gitignored fixture (parity tests)
├── serve/                          # NEW — this spec
│   ├── __init__.py
│   ├── main.py                     # FastAPI factory + lifespan (model preflight)
│   ├── router.py                   # /api/v1/ml-demo/run, /health
│   ├── preprocess.py               # zip → 25 Hz numpy arrays (factored from simulate_live_stream)
│   ├── runner.py                   # drives RealTimeStressPipeline through chunks → list[ChunkResult]
│   ├── schemas.py                  # Pydantic request/response models
│   ├── settings.py                 # env-driven paths (ONNX, upload size cap)
│   ├── requirements.txt            # fastapi, uvicorn[standard], python-multipart, onnxruntime, scipy, pandas, numpy<2
│   ├── Dockerfile
│   ├── README.md
│   └── tests/
│       ├── __init__.py
│       ├── conftest.py             # fixture-path resolver, skips e2e tests if fixture absent
│       ├── fixtures/
│       │   └── synthetic_capture.zip   # tiny synthetic capture (180s + 60s) for unit tests
│       ├── test_preprocess.py      # synthetic fixture
│       ├── test_runner.py          # parity vs expected_pipeline_log.txt (skipped if Galaxy_Test absent)
│       └── test_router.py          # FastAPI TestClient
```

### Why these boundaries

- `preprocess.py` and `runner.py` are pure functions — easy to test, no FastAPI coupling.
- `router.py` is thin: parse upload, call `preprocess` then `runner`, return.
- `main.py` does only app wiring + lifespan checks (verify ONNX file exists at startup, fail fast if not).
- `settings.py` reads `ML_DEMO_ONNX_PATH` and `ML_DEMO_MAX_UPLOAD_BYTES` from env, with defaults that match `pipeline.py`'s expectations.

### Pipeline reuse

`AI/src/pipeline.py` is imported, not edited. The serve layer:
1. Imports `RealTimeStressPipeline`, `TARGET_HZ`, `CHUNK_SEC`, `BUFFER_SEC`, `BASELINE_SEC`, `CHUNK_STEPS`, `BUFFER_STEPS`, `BASELINE_STEPS` from `AI.src.pipeline`.
2. Replicates the preprocessing block from `simulate_live_stream` (CSV reading + interp1d + butter + savgol + accel magnitude) inside `serve/preprocess.py`. Reason: the original function couples preprocessing with the print-driven simulation loop; we need the arrays without the loop.
3. Replicates the chunk loop in `serve/runner.py`, calling `pipeline.process_buffer(...)` and collecting `(time, prob, state, notify)` tuples instead of printing.

A new `RealTimeStressPipeline` is instantiated per request (each upload has its own calibration). ONNX session creation cost on a 327 KB model is negligible (~50 ms) and demo traffic is single-digit RPS. We can revisit caching if it ever becomes a bottleneck.

## 6. Data flow

```
Demo client (curl / phone)
  → POST /api/v1/ml-demo/run  (multipart, capture=galaxy_test.zip)
  → router parses upload → temp dir, validates size
  → preprocess.py:
       open zip → read 3 CSVs → interp1d to 25 Hz → butter+savgol on PPG → accel magnitude
  → runner.py:
       RealTimeStressPipeline(onnx_path)
       calibrate on first BASELINE_STEPS samples
       for current_step in range(BUFFER_STEPS, len, CHUNK_STEPS):
           process_buffer(...)  → append ChunkResult
  → router builds RunResponse JSON
  → 200
```

## 7. Error handling

Boundary-only validation, in keeping with backend conventions ([backend/README.md](../../backend/README.md)):
- Upload size: enforced before reading zip body, 413
- Zip integrity: `zipfile.BadZipFile` → 400
- Missing CSV: explicit check, 400 with which file is missing
- Column schema: `pandas.read_csv` validates expected columns, 400 otherwise
- Recording too short: `len(synced) < BASELINE_STEPS` → 400 with `recording_too_short`
- ONNX errors: bubble up, 500, logged with request id

No retries, no fallbacks. Demo service: fail loud, fix the upload.

## 8. Testing

- **`test_preprocess.py`** — uses committed `synthetic_capture.zip` (~10 KB, 4 minutes of synthetic PPG/EDA/ACC). Asserts output array shapes, dtype, sampling rate.
- **`test_runner.py`** — uses real `AI/data/raw/Galaxy_Test/` fixture + real ONNX model. Skipped via `pytest.mark.skipif` when fixture path absent (CI without LFS). Asserts:
  - `len(chunks) == 5`
  - For each i, `abs(chunks[i].prob_stress - expected[i]) < 0.01`
  - All chunks have `state == "Baseline"` and `should_notify == False`
  - The numbers come from [AI/data/raw/Galaxy_Test/expected_pipeline_log.txt](../../AI/data/raw/Galaxy_Test/expected_pipeline_log.txt): `0.441, 0.691, 0.450, 0.289, 0.280`.
- **`test_router.py`** — `httpx.AsyncClient` against the FastAPI app, posts a zip, asserts response shape and 400/413 paths.
- **Smoke test** — `make demo-smoke` builds the Docker image, starts the container, curls `/health` and the run endpoint with the fixture, diffs against `expected_pipeline_log.txt` lines.

## 9. Local & demo workflow

```bash
# Local development
cd AI/serve
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
ML_DEMO_ONNX_PATH=../checkpoints_final/wesad_w2.0/wesad_mamba_v1.onnx \
  uvicorn AI.serve.main:app --reload --port 8001
# Then:
curl -F "capture=@AI/data/raw/Galaxy_Test/galaxy_test.zip" \
  http://localhost:8001/api/v1/ml-demo/run | jq

# Docker (demo day)
docker build -f AI/serve/Dockerfile -t little-signals-ml-demo AI/
docker run --rm -p 8001:8001 little-signals-ml-demo
```

## 10. Open questions / follow-ups

1. **AWS deployment** — separate ECR repo + ECS task + ALB rule on `/api/v1/ml-demo/*` (or new subdomain). Out of scope for this spec; track separately once the local service is solid.
2. **Watch-port verification mode** — once the Kotlin port emits a debug tensor, this service can grow a `/run-with-tensor-diff` endpoint that compares to the upload. Not needed yet.
3. **Streaming responses** — if a real-time progress UI is wanted in the demo, add SSE later. The current 10-minute fixture produces 5 chunks; one JSON response is fine.
