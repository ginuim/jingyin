import type { DetectedObject } from "@tensorflow-models/coco-ssd";

export type YoloMask = {
  detection: DetectedObject;
  data: Uint8Array;
  width: number;
  height: number;
};

export type YoloLoadProgress = { stage: "download" | "compile" | "warmup" | "ready"; percent: number };

type WorkerRequest =
  | { id: number; type: "load" }
  | { id: number; type: "segment"; bitmap: ImageBitmap; sourceWidth: number; sourceHeight: number };
type WorkerRequestWithoutId =
  | { type: "load" }
  | { type: "segment"; bitmap: ImageBitmap; sourceWidth: number; sourceHeight: number };

type WorkerResponse =
  | { type: "progress"; id: number; progress: YoloLoadProgress }
  | { type: "result"; id: number; result?: YoloMask[] }
  | { type: "error"; id: number; code: string };

type PendingRequest = {
  kind: WorkerRequest["type"];
  resolve: (value: YoloMask[] | undefined) => void;
  reject: (error: Error) => void;
  timer: number;
};

const LOAD_STAGE_TIMEOUTS: Record<YoloLoadProgress["stage"], number> = {
  download: 60_000,
  compile: 45_000,
  warmup: 30_000,
  ready: 10_000,
};
const SEGMENT_TIMEOUT = 45_000;

let yoloWorker: Worker | null = null;
let requestCounter = 0;
let loadPromise: Promise<void> | null = null;
const pendingRequests = new Map<number, PendingRequest>();
const progressSubscribers = new Set<(progress: YoloLoadProgress) => void>();

function errorCode(error: unknown) {
  if (error instanceof Error && error.message) return error.message;
  return "YOLO_WORKER_FAILED";
}

function rejectAndResetWorker(error: Error) {
  const worker = yoloWorker;
  yoloWorker = null;
  loadPromise = null;
  worker?.terminate();
  pendingRequests.forEach((pending) => {
    window.clearTimeout(pending.timer);
    pending.reject(error);
  });
  pendingRequests.clear();
}

function armTimeout(id: number, milliseconds: number, code: string) {
  const pending = pendingRequests.get(id);
  if (!pending) return;
  window.clearTimeout(pending.timer);
  pending.timer = window.setTimeout(() => {
    rejectAndResetWorker(new Error(code));
  }, milliseconds);
}

function ensureWorker() {
  if (yoloWorker) return yoloWorker;
  const worker = new Worker(new URL("./yolo-seg-worker.ts", import.meta.url), { type: "module" });
  worker.onmessage = (event: MessageEvent<WorkerResponse>) => {
    const message = event.data;
    const pending = pendingRequests.get(message.id);
    if (!pending) return;
    if (message.type === "progress") {
      armTimeout(message.id, LOAD_STAGE_TIMEOUTS[message.progress.stage], `MODEL_${message.progress.stage.toUpperCase()}_TIMEOUT`);
      progressSubscribers.forEach((subscriber) => subscriber(message.progress));
      return;
    }

    window.clearTimeout(pending.timer);
    pendingRequests.delete(message.id);
    if (message.type === "error") {
      const error = new Error(message.code);
      pending.reject(error);
      if (pending.kind === "load") rejectAndResetWorker(error);
      return;
    }
    pending.resolve(message.result);
  };
  worker.onerror = (event) => {
    event.preventDefault();
    rejectAndResetWorker(new Error(event.message || "YOLO_WORKER_CRASHED"));
  };
  yoloWorker = worker;
  return worker;
}

function requestWorker(
  request: WorkerRequestWithoutId,
  timeout: number,
  timeoutCode: string,
  transfer: Transferable[] = [],
) {
  const id = ++requestCounter;
  const message = { ...request, id } as WorkerRequest;
  return new Promise<YoloMask[] | undefined>((resolve, reject) => {
    const timer = window.setTimeout(() => {
      rejectAndResetWorker(new Error(timeoutCode));
    }, timeout);
    pendingRequests.set(id, { kind: message.type, resolve, reject, timer });
    ensureWorker().postMessage(message, transfer);
  });
}

export function supportsWebGpu() {
  return typeof navigator !== "undefined" && "gpu" in navigator && typeof Worker !== "undefined";
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
  if (!supportsWebGpu()) throw new Error("WEBGPU_REQUIRED");
  if (isMobileLikeDevice()) throw new Error("MOBILE_WEBGPU_DISABLED");
  if (onProgress) progressSubscribers.add(onProgress);
  try {
    loadPromise ||= requestWorker({ type: "load" }, LOAD_STAGE_TIMEOUTS.download, "MODEL_DOWNLOAD_TIMEOUT")
      .then(() => undefined)
      .catch((error) => {
        loadPromise = null;
        throw error;
      });
    await loadPromise;
  } finally {
    if (onProgress) progressSubscribers.delete(onProgress);
  }
}

export async function segmentWithYolo(source: CanvasImageSource, sourceWidth: number, sourceHeight: number) {
  await loadYoloSegModel();
  let bitmap: ImageBitmap;
  try {
    bitmap = await createImageBitmap(
      source as ImageBitmapSource,
      0,
      0,
      Math.max(1, Math.round(sourceWidth)),
      Math.max(1, Math.round(sourceHeight)),
    );
  } catch (error) {
    throw new Error(`YOLO_FRAME_COPY_FAILED: ${errorCode(error)}`);
  }
  try {
    const result = await requestWorker(
      { type: "segment", bitmap, sourceWidth, sourceHeight },
      SEGMENT_TIMEOUT,
      "MODEL_INFERENCE_TIMEOUT",
      [bitmap],
    );
    return result || [];
  } catch (error) {
    bitmap.close();
    throw error;
  }
}
