# syntax=docker/dockerfile:1.7
FROM python:3.12-slim AS base

WORKDIR /app

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

COPY AI/serve/requirements.txt /app/AI/serve/requirements.txt
RUN pip install --no-cache-dir -r /app/AI/serve/requirements.txt

COPY AI/__init__.py /app/AI/__init__.py
COPY AI/src /app/AI/src
COPY AI/serve /app/AI/serve
COPY AI/checkpoints_final /app/AI/checkpoints_final

ENV ML_DEMO_ONNX_PATH=/app/AI/checkpoints_final/wesad_w2.0/wesad_mamba_v1.onnx
ENV PYTHONPATH=/app

EXPOSE 8001

CMD ["uvicorn", "AI.serve.main:app", "--host", "0.0.0.0", "--port", "8001"]
