#!/usr/bin/env python3
"""Optional FastAPI server for Sidebeat Lanes automatic chart generation."""
from __future__ import annotations

import tempfile
from pathlib import Path

from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware

from generate_chart import DIFFICULTY, detect

app = FastAPI(title="Sidebeat Lanes Chartgen", version="0.1.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:5173", "http://127.0.0.1:5173"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.post("/generate")
async def generate(audio: UploadFile = File(...), difficulty: str = Form("normal")) -> dict:
    if difficulty not in DIFFICULTY:
        raise HTTPException(status_code=400, detail=f"difficulty must be one of: {', '.join(DIFFICULTY)}")
    suffix = Path(audio.filename or "song.wav").suffix or ".wav"
    with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as temp:
      path = Path(temp.name)
      while chunk := await audio.read(1024 * 1024):
          temp.write(chunk)
    try:
        chart = detect(path, difficulty)
        chart["audioFileName"] = audio.filename
        chart["generator"] = "tools/chartgen/server.py FastAPI librosa beat+onset draft"
        return chart
    finally:
        path.unlink(missing_ok=True)
