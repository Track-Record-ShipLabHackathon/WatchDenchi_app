"""Go -> HTTP/JSON -> independently running Python inference service."""

from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, Request
from pydantic import BaseModel, ConfigDict, Field

from predictor import PredictionError, Predictor


class PredictionInput(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    started_at: str = Field(min_length=10, max_length=40)
    type: str = Field(min_length=1, max_length=30)
    chemical: str = Field(min_length=1, max_length=30)
    battery_quantity: int = Field(strict=True, ge=1, le=100)
    manufacturer: str = Field(min_length=1, max_length=100)


@asynccontextmanager
async def lifespan(app: FastAPI):
    app.state.predictor = Predictor()
    yield


app = FastAPI(
    title="WatchDenchi Mouse Inference", version="1.0.0", lifespan=lifespan,
    description="公開仕様を学習したデモ用交換日推定。実際の交換日での精度は未検証です。",
)


@app.get("/healthz")
def health(request: Request):
    return {"status": "ok", "model_version": request.app.state.predictor.model["model_version"]}


@app.get("/model")
def model_info(request: Request):
    model = request.app.state.predictor.model
    return {key: value for key, value in model.items() if key != "tree"}


@app.post("/predict")
def predict(payload: PredictionInput, request: Request):
    try:
        return request.app.state.predictor.predict(
            started_at=payload.started_at, battery_type=payload.type, chemical=payload.chemical,
            battery_quantity=payload.battery_quantity, manufacturer=payload.manufacturer,
        )
    except PredictionError as error:
        raise HTTPException(status_code=422, detail={"code": error.code, "message": str(error)}) from error
