const dropZone = document.getElementById("drop-zone");
const fileInput = document.getElementById("file-input");
const frameList = document.getElementById("frame-list");
const preview = document.getElementById("preview");
const loopCount = document.getElementById("loop-count");
const playBtn = document.getElementById("play-btn");
const generateBtn = document.getElementById("generate-btn");
const clearBtn = document.getElementById("clear-btn");
const batchDelay = document.getElementById("batch-delay");
const applyDelayBtn = document.getElementById("apply-delay-btn");
const previewArea = document.querySelector(".preview-area");
const previewPlaceholder = document.getElementById("preview-placeholder");

const SUPPORTED_EXT = ["png", "jpg", "jpeg", "bmp", "gif", "tiff"];

const DEFAULT_DELAY_NUM = 10;
const DEFAULT_DELAY_DEN = 100;

/** 帧数据：{ file, url, delayNum } */
let frames = [];

let previewTimer = null;
let previewIndex = 0;

/* ---------- 拖拽上传 ---------- */
dropZone.addEventListener("dragover", (e) => {
  e.preventDefault();
  dropZone.classList.add("dragover");
});

dropZone.addEventListener("dragleave", () => {
  dropZone.classList.remove("dragover");
});

dropZone.addEventListener("drop", (e) => {
  e.preventDefault();
  dropZone.classList.remove("dragover");
  handleFiles(Array.from(e.dataTransfer.files));
});

fileInput.addEventListener("change", () => {
  handleFiles(Array.from(fileInput.files));
  fileInput.value = "";
});

function handleFiles(files) {
  const unsupported = [];
  const accepted = [];

  for (const file of files) {
    const ext = file.name.split(".").pop().toLowerCase();
    if (file.type.startsWith("image/") && SUPPORTED_EXT.includes(ext)) {
      accepted.push(file);
    } else {
      unsupported.push(file.name);
    }
  }

  if (unsupported.length > 0) {
    alert(
      "以下文件不是支持的图片格式，已忽略：\n\n" +
      unsupported.map((n) => "• " + n).join("\n") +
      "\n\n支持的格式：PNG、JPEG、BMP、GIF、TIFF"
    );
  }

  for (const file of accepted) {
    frames.push({
      file,
      url: URL.createObjectURL(file),
      delayNum: DEFAULT_DELAY_NUM,   // 默认 10/100 = 0.1s
      delayDen: DEFAULT_DELAY_DEN,
    });
  }

  renderFrames();
  if (accepted.length > 0) {
    showPreview(0);
  }
}

/* ---------- 帧列表渲染 ---------- */
function renderFrames() {
  frameList.innerHTML = "";

  frames.forEach((frame, index) => {
    const li = document.createElement("li");
    li.className = "frame-item";

    const img = document.createElement("img");
    img.src = frame.url;
    li.appendChild(img);

    const info = document.createElement("div");
    info.className = "info";
    info.innerHTML = `<strong>帧 ${index + 1}</strong>`;

    const delayLabel = document.createElement("label");
    delayLabel.textContent = "延迟（1/100s）：";
    const delayInput = document.createElement("input");
    delayInput.type = "number";
    delayInput.min = "1";
    delayInput.max = "10000";
    delayInput.value = frame.delayNum;
    delayInput.addEventListener("change", () => {
      frame.delayNum = Math.max(1, parseInt(delayInput.value, 10) || 1);
      delayInput.value = frame.delayNum;
    });
    delayLabel.appendChild(delayInput);
    info.appendChild(delayLabel);
    li.appendChild(info);

    const actions = document.createElement("div");
    actions.className = "actions";

    const upBtn = document.createElement("button");
    upBtn.textContent = "↑";
    upBtn.disabled = index === 0;
    upBtn.addEventListener("click", () => moveFrame(index, -1));
    actions.appendChild(upBtn);

    const downBtn = document.createElement("button");
    downBtn.textContent = "↓";
    downBtn.disabled = index === frames.length - 1;
    downBtn.addEventListener("click", () => moveFrame(index, 1));
    actions.appendChild(downBtn);

    const removeBtn = document.createElement("button");
    removeBtn.textContent = "删除";
    removeBtn.addEventListener("click", () => removeFrame(index));
    actions.appendChild(removeBtn);

    li.appendChild(actions);
    frameList.appendChild(li);
  });
}

function moveFrame(index, delta) {
  const target = index + delta;
  if (target < 0 || target >= frames.length) return;
  [frames[index], frames[target]] = [frames[target], frames[index]];
  renderFrames();
}

function removeFrame(index) {
  URL.revokeObjectURL(frames[index].url);
  frames.splice(index, 1);
  renderFrames();
  if (frames.length === 0) {
    clearPreview();
  } else {
    showPreview(0)
  }
}

/* ---------- 预览 ---------- */
playBtn.addEventListener("click", () => {
  if (frames.length === 0) {
    alert("请先添加帧");
    return;
  }
  if (previewTimer) {
    stopPreview();
  } else {
    startPreview();
  }
});

function startPreview() {
  playBtn.textContent = "停止预览";
  previewIndex = 0;
  showPreview(previewIndex);
  scheduleNext();
}

function scheduleNext() {
  const frame = frames[previewIndex];
  const delayMs = (frame.delayNum * 1000) / frame.delayDen;
  previewTimer = setTimeout(() => {
    previewIndex = (previewIndex + 1) % frames.length;
    showPreview(previewIndex);
    scheduleNext();
  }, delayMs);
}

function stopPreview() {
  clearTimeout(previewTimer);
  previewTimer = null;
  playBtn.textContent = "播放预览";
}

function showPreview(index) {
  if (index < 0 || index >= frames.length) return;
  preview.src = frames[index].url;
  preview.style.display = "block";
  previewArea.classList.add("has-image");
}

/* ---------- 清空 ---------- */
clearBtn.addEventListener("click", () => {
  if (frames.length === 0) return;
  if (!confirm("确定要清空所有帧吗？")) return;
  stopPreview();
  frames.forEach((f) => URL.revokeObjectURL(f.url));
  frames = [];
  renderFrames();
  clearPreview();
});

function clearPreview() {
  preview.removeAttribute("src");
  preview.style.display = "none";
  previewArea.classList.remove("has-image");
}

/* ---------- 批量应用延迟 ---------- */
applyDelayBtn.addEventListener("click", () => {
  if (frames.length === 0) {
    alert("请先添加帧");
    return;
  }

  const value = Math.max(1, parseInt(batchDelay.value, 10) || 1);
  batchDelay.value = value;

  for (const frame of frames) {
    frame.delayNum = value;
    // delayDen 固定为 100，无需修改
  }

  renderFrames();  // 重新渲染列表，使每帧输入框显示新值
});

/* ---------- 生成 APNG ---------- */
generateBtn.addEventListener("click", async () => {
  if (frames.length === 0) {
    alert("请先添加帧");
    return;
  }

  const formData = new FormData();
  frames.forEach((frame) => {
    formData.append("files", frame.file, frame.file.name);
  });
  formData.append(
    "delays",
    JSON.stringify(frames.map((f) => [f.delayNum, f.delayDen]))
  );
  formData.append("loop_count", loopCount.value || "0");

  generateBtn.disabled = true;
  generateBtn.textContent = "生成中…";

  try {
    const resp = await fetch("/api/generate", {
      method: "POST",
      body: formData,
    });

    if (!resp.ok) {
      const err = await resp.json().catch(() => ({ detail: "未知错误" }));
      throw new Error(err.detail || "生成失败");
    }

    const blob = await resp.blob();
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = "output.png";
    document.body.appendChild(a);
    a.click();
    a.remove();
    URL.revokeObjectURL(url);
  } catch (e) {
    alert("生成失败：" + e.message);
  } finally {
    generateBtn.disabled = false;
    generateBtn.textContent = "生成 APNG";
  }
});