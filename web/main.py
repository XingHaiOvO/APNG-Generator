import json
from io import BytesIO
from typing import List

from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.responses import Response
from fastapi.staticfiles import StaticFiles
from PIL import Image, UnidentifiedImageError

from apng_generator import generate_apng

app = FastAPI(title="APNG Generator Web")

MAX_FILE_SIZE = 20 * 1024 * 1024   # 单文件 20MB
MAX_FRAMES = 100


@app.post("/api/generate")
async def generate(
    files: List[UploadFile] = File(...),
    delays: str = Form(...),
    loop_count: int = Form(0),
):
    """
    接收多张图片，生成 APNG。

    - files: 按顺序上传的图片帧
    - delays: JSON 字符串，格式为 [[num, den], ...]
    - loop_count: 循环次数，0 表示无限
    """
    if not files:
        raise HTTPException(status_code=400, detail="请至少上传一帧")
    if len(files) > MAX_FRAMES:
        raise HTTPException(status_code=400, detail=f"帧数不能超过 {MAX_FRAMES}")

    try:
        delay_list = json.loads(delays)
    except json.JSONDecodeError:
        raise HTTPException(status_code=400, detail="delays 不是合法的 JSON")

    if not isinstance(delay_list, list) or len(delay_list) != len(files):
        raise HTTPException(status_code=400, detail="delays 长度必须与帧数一致")

    images: List[Image.Image] = []
    for f in files:
        content = await f.read()
        if len(content) > MAX_FILE_SIZE:
            raise HTTPException(status_code=400, detail=f"文件 {f.filename} 过大")
        try:
            img = Image.open(BytesIO(content))
            img.load()
        except UnidentifiedImageError:
            raise HTTPException(status_code=400, detail=f"无法识别图片：{f.filename}")
        images.append(img)

    try:
        apng_bytes = generate_apng(images, [tuple(d) for d in delay_list], loop_count)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))

    return Response(
        content=apng_bytes,
        media_type="image/png",
        headers={"Content-Disposition": 'attachment; filename="output.png"'},
    )


@app.get("/api/health")
async def health():
    return {"status": "ok"}


# 挂载前端静态文件（放在最后）
app.mount("/", StaticFiles(directory="static", html=True), name="static")