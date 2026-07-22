import type { DetectedObject } from "@tensorflow-models/coco-ssd";

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

export type YoloMask = {
  detection: DetectedObject;
  data: Uint8Array;
  width: number;
  height: number;
};

let ortPromise: Promise<OrtModule> | null = null;
let sessionPromise: Promise<OrtSession> | null = null;

export type YoloLoadProgress = { stage: "download" | "compile" | "warmup" | "ready"; percent: number };

function withTimeout<T>(promise: Promise<T>, milliseconds: number, code: string) {
  return new Promise<T>((resolve, reject) => {
    const timer = window.setTimeout(() => reject(new Error(code)), milliseconds);
    promise.then((value) => {
      window.clearTimeout(timer);
      resolve(value);
    }, (error) => {
      window.clearTimeout(timer);
      reject(error);
    });
  });
}

function iou(a: number[], b: number[]) {
  const left = Math.max(a[0], b[0]);
  const top = Math.max(a[1], b[1]);
  const right = Math.min(a[0] + a[2], b[0] + b[2]);
  const bottom = Math.min(a[1] + a[3], b[1] + b[3]);
  const overlap = Math.max(0, right - left) * Math.max(0, bottom - top);
  return overlap / Math.max(1, a[2] * a[3] + b[2] * b[3] - overlap);
}

export function supportsWebGpu() {
  return typeof navigator !== "undefined" && "gpu" in navigator;
}

export function isMobileLikeDevice() {
  if (typeof navigator === "undefined") return false;
  const userAgentData = (navigator as Navigator & { userAgentData?: { mobile?: boolean } }).userAgentData;
  return Boolean(
    userAgentData?.mobile
    || /Android|iPhone|iPad|iPod|Mobile|HarmonyOS/i.test(navigator.userAgent)
    || (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1)
  );
}

export function supportsPreciseWebMode() {
  return supportsWebGpu() && !isMobileLikeDevice();
}

export async function loadYoloSegModel(onProgress?: (progress: YoloLoadProgress) => void) {
  if (sessionPromise) return sessionPromise;
  if (!supportsWebGpu()) throw new Error("WEBGPU_REQUIRED");
  if (isMobileLikeDevice()) throw new Error("MOBILE_WEBGPU_DISABLED");
  ortPromise ||= import("onnxruntime-web/webgpu");
  sessionPromise = ortPromise.then(async (ort) => {
    const parts = Array.from({ length: MODEL_PARTS }, (_, index) => index);
    let downloaded = 0;
    const buffers = await Promise.all(parts.map(async (part) => {
      const response = await fetch(`${MODEL_PATH}${part}`, { cache: "force-cache" });
      if (!response.ok) throw new Error("MODEL_DOWNLOAD_FAILED");
      const buffer = await response.arrayBuffer();
      downloaded += 1;
      onProgress?.({ stage: "download", percent: Math.round((downloaded / parts.length) * 100) });
      return new Uint8Array(buffer);
    }));
    const byteLength = buffers.reduce((sum, buffer) => sum + buffer.byteLength, 0);
    const model = new Uint8Array(byteLength);
    let offset = 0;
    buffers.forEach((buffer) => { model.set(buffer, offset); offset += buffer.byteLength; });
    onProgress?.({ stage: "compile", percent: 100 });
    const session = await withTimeout(ort.InferenceSession.create(model, {
      executionProviders: ["webgpu"],
      graphOptimizationLevel: "basic",
    }), 45_000, "MODEL_COMPILE_TIMEOUT");
    onProgress?.({ stage: "warmup", percent: 100 });
    const empty = new Float32Array(3 * INPUT_SIZE * INPUT_SIZE);
    await withTimeout(session.run({ [session.inputNames[0]]: new ort.Tensor("float32", empty, [1, 3, INPUT_SIZE, INPUT_SIZE]) }), 30_000, "MODEL_WARMUP_TIMEOUT");
    onProgress?.({ stage: "ready", percent: 100 });
    return session;
  }).catch((error) => {
    sessionPromise = null;
    throw error;
  });
  return sessionPromise;
}

export async function segmentWithYolo(source: CanvasImageSource, sourceWidth: number, sourceHeight: number) {
  const [ort, session] = await Promise.all([ortPromise || import("onnxruntime-web/webgpu"), loadYoloSegModel()]);
  const scale = Math.min(INPUT_SIZE / sourceWidth, INPUT_SIZE / sourceHeight);
  const contentWidth = Math.max(1, Math.round(sourceWidth * scale));
  const contentHeight = Math.max(1, Math.round(sourceHeight * scale));
  const offsetX = Math.floor((INPUT_SIZE - contentWidth) / 2);
  const offsetY = Math.floor((INPUT_SIZE - contentHeight) / 2);
  const canvas = document.createElement("canvas");
  canvas.width = INPUT_SIZE;
  canvas.height = INPUT_SIZE;
  const ctx = canvas.getContext("2d", { willReadFrequently: true });
  if (!ctx) throw new Error("NO_YOLO_CANVAS");
  ctx.fillStyle = "rgb(114,114,114)";
  ctx.fillRect(0, 0, INPUT_SIZE, INPUT_SIZE);
  ctx.drawImage(source, 0, 0, sourceWidth, sourceHeight, offsetX, offsetY, contentWidth, contentHeight);
  const rgba = ctx.getImageData(0, 0, INPUT_SIZE, INPUT_SIZE).data;
  const input = new Float32Array(3 * INPUT_SIZE * INPUT_SIZE);
  const plane = INPUT_SIZE * INPUT_SIZE;
  for (let i = 0; i < plane; i += 1) {
    input[i] = rgba[i * 4] / 255;
    input[plane + i] = rgba[i * 4 + 1] / 255;
    input[plane * 2 + i] = rgba[i * 4 + 2] / 255;
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
      if (value > score) { score = value; classId = candidateClass; }
    });
    if (classId < 0 || score < 0.36) continue;
    const cx = prediction[index];
    const cy = prediction[CANDIDATES + index];
    const w = prediction[CANDIDATES * 2 + index];
    const h = prediction[CANDIDATES * 3 + index];
    const modelBox = [cx - w / 2, cy - h / 2, w, h];
    const bbox: [number, number, number, number] = [
      Math.max(0, (modelBox[0] - offsetX) / scale),
      Math.max(0, (modelBox[1] - offsetY) / scale),
      Math.min(sourceWidth, w / scale),
      Math.min(sourceHeight, h / scale),
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
