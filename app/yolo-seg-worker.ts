import type { DetectedObject } from "@tensorflow-models/coco-ssd";
import type { YoloLoadProgress, YoloMask } from "./yolo-seg";

const INPUT_SIZE = 384;
const PROTO_SIZE = 96;
const CANDIDATES = 3024;
const CLASS_COUNT = 80;
const MASK_CHANNELS = 32;
const MODEL_PARTS = 4;
const MODEL_PATH = "/models/yolo11n-seg-384-fp32.part";
const CLASS_NAMES = [
  "person", "bicycle", "car", "motorcycle", "airplane", "bus", "train", "truck", "boat", "traffic light",
  "fire hydrant", "stop sign", "parking meter", "bench", "bird", "cat", "dog", "horse", "sheep", "cow",
  "elephant", "bear", "zebra", "giraffe", "backpack", "umbrella", "handbag", "tie", "suitcase", "frisbee",
  "skis", "snowboard", "sports ball", "kite", "baseball bat", "baseball glove", "skateboard", "surfboard",
  "tennis racket", "bottle", "wine glass", "cup", "fork", "knife", "spoon", "bowl", "banana", "apple",
  "sandwich", "orange", "broccoli", "carrot", "hot dog", "pizza", "donut", "cake", "chair", "couch",
  "potted plant", "bed", "dining table", "toilet", "tv", "laptop", "mouse", "remote", "keyboard",
  "cell phone", "microwave", "oven", "toaster", "sink", "refrigerator", "book", "clock", "vase", "scissors",
  "teddy bear", "hair drier", "toothbrush",
];
const WANTED_CLASSES = new Set([0, 1, 2, 3, 5, 7, 15, 16]);

type OrtModule = typeof import("onnxruntime-web/webgpu");
type OrtSession = import("onnxruntime-web").InferenceSession;
type WorkerRequest =
  | { id: number; type: "load" }
  | { id: number; type: "segment"; bitmap: ImageBitmap; sourceWidth: number; sourceHeight: number };
type WorkerResponse =
  | { type: "progress"; id: number; progress: YoloLoadProgress }
  | { type: "result"; id: number; result?: YoloMask[] }
  | { type: "error"; id: number; code: string };
type WorkerScope = {
  onmessage: ((event: MessageEvent<WorkerRequest>) => void) | null;
  postMessage: (message: WorkerResponse, transfer?: Transferable[]) => void;
};

const workerScope = self as unknown as WorkerScope;
let ortPromise: Promise<OrtModule> | null = null;
let sessionPromise: Promise<OrtSession> | null = null;
let operationQueue = Promise.resolve();

function postProgress(id: number, stage: YoloLoadProgress["stage"], percent = 100) {
  workerScope.postMessage({ type: "progress", id, progress: { stage, percent } });
}

function iou(a: number[], b: number[]) {
  const left = Math.max(a[0], b[0]);
  const top = Math.max(a[1], b[1]);
  const right = Math.min(a[0] + a[2], b[0] + b[2]);
  const bottom = Math.min(a[1] + a[3], b[1] + b[3]);
  const overlap = Math.max(0, right - left) * Math.max(0, bottom - top);
  return overlap / Math.max(1, a[2] * a[3] + b[2] * b[3] - overlap);
}

async function loadModel(id: number) {
  if (sessionPromise) return sessionPromise;
  ortPromise ||= import("onnxruntime-web/webgpu");
  sessionPromise = ortPromise.then(async (ort) => {
    const parts = Array.from({ length: MODEL_PARTS }, (_, index) => index);
    let downloaded = 0;
    const buffers = await Promise.all(parts.map(async (part) => {
      const response = await fetch(`${MODEL_PATH}${part}`, { cache: "force-cache" });
      if (!response.ok) throw new Error("MODEL_DOWNLOAD_FAILED");
      const buffer = await response.arrayBuffer();
      downloaded += 1;
      postProgress(id, "download", Math.round((downloaded / parts.length) * 100));
      return new Uint8Array(buffer);
    }));
    const byteLength = buffers.reduce((sum, buffer) => sum + buffer.byteLength, 0);
    const model = new Uint8Array(byteLength);
    let offset = 0;
    buffers.forEach((buffer) => {
      model.set(buffer, offset);
      offset += buffer.byteLength;
    });
    postProgress(id, "compile");
    const session = await ort.InferenceSession.create(model, {
      executionProviders: ["webgpu"],
      graphOptimizationLevel: "basic",
    });
    postProgress(id, "warmup");
    const empty = new Float32Array(3 * INPUT_SIZE * INPUT_SIZE);
    await session.run({
      [session.inputNames[0]]: new ort.Tensor("float32", empty, [1, 3, INPUT_SIZE, INPUT_SIZE]),
    });
    postProgress(id, "ready");
    return session;
  }).catch((error) => {
    sessionPromise = null;
    throw error;
  });
  return sessionPromise;
}

async function segment(bitmap: ImageBitmap, sourceWidth: number, sourceHeight: number, id: number) {
  const [ort, session] = await Promise.all([ortPromise || import("onnxruntime-web/webgpu"), loadModel(id)]);
  const scale = Math.min(INPUT_SIZE / sourceWidth, INPUT_SIZE / sourceHeight);
  const contentWidth = Math.max(1, Math.round(sourceWidth * scale));
  const contentHeight = Math.max(1, Math.round(sourceHeight * scale));
  const offsetX = Math.floor((INPUT_SIZE - contentWidth) / 2);
  const offsetY = Math.floor((INPUT_SIZE - contentHeight) / 2);
  const canvas = new OffscreenCanvas(INPUT_SIZE, INPUT_SIZE);
  const ctx = canvas.getContext("2d", { willReadFrequently: true });
  if (!ctx) throw new Error("NO_YOLO_CANVAS");
  ctx.fillStyle = "rgb(114,114,114)";
  ctx.fillRect(0, 0, INPUT_SIZE, INPUT_SIZE);
  ctx.drawImage(bitmap, 0, 0, sourceWidth, sourceHeight, offsetX, offsetY, contentWidth, contentHeight);
  bitmap.close();
  const rgba = ctx.getImageData(0, 0, INPUT_SIZE, INPUT_SIZE).data;
  const input = new Float32Array(3 * INPUT_SIZE * INPUT_SIZE);
  const plane = INPUT_SIZE * INPUT_SIZE;
  for (let index = 0; index < plane; index += 1) {
    input[index] = rgba[index * 4] / 255;
    input[plane + index] = rgba[index * 4 + 1] / 255;
    input[plane * 2 + index] = rgba[index * 4 + 2] / 255;
  }

  const feeds = { [session.inputNames[0]]: new ort.Tensor("float32", input, [1, 3, INPUT_SIZE, INPUT_SIZE]) };
  const output = await session.run(feeds);
  const prediction = output[session.outputNames[0]].data as Float32Array;
  const prototypes = output[session.outputNames[1]].data as Float32Array;
  const proposals: Array<{ detection: DetectedObject; coeffs: Float32Array; modelBox: number[] }> = [];

  for (let index = 0; index < CANDIDATES; index += 1) {
    let classId = -1;
    let score = 0;
    WANTED_CLASSES.forEach((candidateClass) => {
      const value = prediction[(4 + candidateClass) * CANDIDATES + index];
      if (value > score) {
        score = value;
        classId = candidateClass;
      }
    });
    if (classId < 0 || score < 0.36) continue;
    const cx = prediction[index];
    const cy = prediction[CANDIDATES + index];
    const width = prediction[CANDIDATES * 2 + index];
    const height = prediction[CANDIDATES * 3 + index];
    const modelBox = [cx - width / 2, cy - height / 2, width, height];
    const bbox: [number, number, number, number] = [
      Math.max(0, (modelBox[0] - offsetX) / scale),
      Math.max(0, (modelBox[1] - offsetY) / scale),
      Math.min(sourceWidth, width / scale),
      Math.min(sourceHeight, height / scale),
    ];
    const coeffs = new Float32Array(MASK_CHANNELS);
    for (let channel = 0; channel < MASK_CHANNELS; channel += 1) {
      coeffs[channel] = prediction[(4 + CLASS_COUNT + channel) * CANDIDATES + index];
    }
    proposals.push({ detection: { class: CLASS_NAMES[classId], score, bbox }, coeffs, modelBox });
  }

  proposals.sort((a, b) => b.detection.score - a.detection.score);
  const kept: typeof proposals = [];
  for (const proposal of proposals) {
    if (kept.length >= 20) break;
    if (kept.some((item) => item.detection.class === proposal.detection.class && iou(item.detection.bbox, proposal.detection.bbox) > 0.48)) continue;
    kept.push(proposal);
  }

  return kept.map((proposal): YoloMask => {
    const data = new Uint8Array(contentWidth * contentHeight);
    const protoLogits = new Float32Array(PROTO_SIZE * PROTO_SIZE);
    for (let channel = 0; channel < MASK_CHANNELS; channel += 1) {
      const coefficient = proposal.coeffs[channel];
      if (Math.abs(coefficient) < 0.0001) continue;
      const channelOffset = channel * PROTO_SIZE * PROTO_SIZE;
      for (let pixel = 0; pixel < protoLogits.length; pixel += 1) {
        protoLogits[pixel] += coefficient * prototypes[channelOffset + pixel];
      }
    }
    const left = Math.max(0, Math.floor(proposal.modelBox[0] - offsetX));
    const top = Math.max(0, Math.floor(proposal.modelBox[1] - offsetY));
    const right = Math.min(contentWidth, Math.ceil(proposal.modelBox[0] + proposal.modelBox[2] - offsetX));
    const bottom = Math.min(contentHeight, Math.ceil(proposal.modelBox[1] + proposal.modelBox[3] - offsetY));
    for (let y = top; y < bottom; y += 1) {
      const protoY = Math.max(0, Math.min(PROTO_SIZE - 1, Math.floor((y + offsetY) / 4)));
      for (let x = left; x < right; x += 1) {
        const protoX = Math.max(0, Math.min(PROTO_SIZE - 1, Math.floor((x + offsetX) / 4)));
        const protoOffset = protoY * PROTO_SIZE + protoX;
        if (protoLogits[protoOffset] > -0.08) data[y * contentWidth + x] = 1;
      }
    }
    return { detection: proposal.detection, data, width: contentWidth, height: contentHeight };
  });
}

async function handleRequest(message: WorkerRequest) {
  try {
    if (message.type === "load") {
      await loadModel(message.id);
      workerScope.postMessage({ type: "result", id: message.id });
      return;
    }
    const results = await segment(message.bitmap, message.sourceWidth, message.sourceHeight, message.id);
    workerScope.postMessage(
      { type: "result", id: message.id, result: results },
      results.map((result) => result.data.buffer),
    );
  } catch (error) {
    if (message.type === "segment") message.bitmap.close();
    workerScope.postMessage({
      type: "error",
      id: message.id,
      code: error instanceof Error ? error.message : "YOLO_WORKER_FAILED",
    });
  }
}

workerScope.onmessage = (event) => {
  operationQueue = operationQueue.then(() => handleRequest(event.data));
};
