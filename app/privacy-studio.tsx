"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import {
  ArrowDownToLine,
  Baby,
  Check,
  ChevronRight,
  EyeOff,
  FileVideo,
  LockKeyhole,
  Pause,
  Play,
  RotateCcw,
  ScanFace,
  ShieldCheck,
  Sparkles,
  Upload,
  MapPin,
  Users,
  X,
} from "lucide-react";
import type { ObjectDetection, DetectedObject } from "@tensorflow-models/coco-ssd";
import type { BodyPix, PersonSegmentation, SemanticPersonSegmentation } from "@tensorflow-models/body-pix";
import soundTouchProcessorUrl from "@soundtouchjs/audio-worklet/processor?url";
import { loadYoloSegModel, segmentWithYolo, supportsPreciseWebMode, supportsWebGpu, type YoloLoadProgress, type YoloMask } from "./yolo-seg";

type EntityKey = "person" | "vehicle" | "pet";
type QualityMode = "fast" | "balanced" | "precise";
type MaskScope = "subjects" | "background" | "full";
type FullFrameStyle = "blur" | "pixel" | "ascii";
type SettingsTab = "general" | "subjects";
type AudioMode = "original" | "voice" | "mute";
type TrackedDetection = DetectedObject & { trackId: string };
type SubjectItem = { id: string; key: EntityKey; label: string; thumbnail: string };
type TrackState = { id: string; className: string; bbox: [number, number, number, number]; lastSeen: number };
type VoiceAudioGraph = {
  output: GainNode;
  preview: GainNode;
  pitchShift: import("@soundtouchjs/audio-worklet").SoundTouchNode;
};
type BiquadCoefficients = { b0: number; b1: number; b2: number; a1: number; a2: number };
type BiquadState = { x1: number; x2: number; y1: number; y2: number };

const ENTITY_GROUPS: Array<{ key: EntityKey; label: string; sub: string; classes: string[] }> = [
  { key: "person", label: "人物", sub: "全身与半身", classes: ["person"] },
  { key: "vehicle", label: "车辆", sub: "汽车、摩托与公交", classes: ["car", "truck", "bus", "motorcycle", "bicycle"] },
  { key: "pet", label: "宠物", sub: "猫与狗", classes: ["cat", "dog"] },
];

function formatTime(seconds: number) {
  if (!Number.isFinite(seconds)) return "00:00";
  const m = Math.floor(seconds / 60).toString().padStart(2, "0");
  const s = Math.floor(seconds % 60).toString().padStart(2, "0");
  return `${m}:${s}`;
}

function pickMimeType() {
  const options = ["video/mp4;codecs=h264,aac", "video/webm;codecs=vp9,opus", "video/webm;codecs=vp8,opus", "video/webm"];
  return options.find((type) => MediaRecorder.isTypeSupported(type)) || "";
}

async function finalizeRecordedMedia(blob: Blob, mimeType: string, onProgress?: (value: number) => void) {
  const media = await import("mediabunny");
  const isMp4 = mimeType.startsWith("video/mp4");
  const convert = async (toMp4: boolean, forceCompatibleCodecs: boolean) => {
    const input = new media.Input({ formats: media.ALL_FORMATS, source: new media.BlobSource(blob) });
    const videoTrack = await input.getPrimaryVideoTrack();
    if (!videoTrack) throw new Error("NO_RECORDED_VIDEO_TRACK");
    const audioTrack = await input.getPrimaryAudioTrack();
    const width = await videoTrack.getDisplayWidth();
    const height = await videoTrack.getDisplayHeight();
    const evenWidth = Math.max(2, width - (width % 2));
    const evenHeight = Math.max(2, height - (height % 2));
    const format = toMp4
      ? new media.Mp4OutputFormat({ fastStart: "in-memory" })
      : new media.WebMOutputFormat();
    const videoCodec = forceCompatibleCodecs
      ? await media.getFirstEncodableVideoCodec(["avc"], { width: evenWidth, height: evenHeight, bitrate: media.QUALITY_HIGH })
      : null;
    const audioCodec = forceCompatibleCodecs && audioTrack
      ? await media.getFirstEncodableAudioCodec(["aac"], {
        numberOfChannels: await audioTrack.getNumberOfChannels(),
        sampleRate: await audioTrack.getSampleRate(),
        bitrate: media.QUALITY_HIGH,
      })
      : null;
    if (forceCompatibleCodecs && (!videoCodec || (audioTrack && !audioCodec))) throw new Error("MP4_CODEC_UNAVAILABLE");

    const target = new media.BufferTarget();
    const output = new media.Output({ format, target });
    const conversion = await media.Conversion.init({
      input,
      output,
      tracks: "primary",
      video: forceCompatibleCodecs ? {
        codec: videoCodec!,
        width: evenWidth,
        height: evenHeight,
        fit: "fill",
        bitrate: media.QUALITY_HIGH,
        hardwareAcceleration: "prefer-hardware",
        forceTranscode: true,
      } : undefined,
      audio: forceCompatibleCodecs && audioTrack ? {
        codec: audioCodec!,
        bitrate: media.QUALITY_HIGH,
        forceTranscode: true,
      } : undefined,
      showWarnings: false,
    });
    if (!conversion.isValid) throw new Error("INVALID_RECORDED_MEDIA");
    conversion.onProgress = (value) => onProgress?.(Math.max(0, Math.min(1, value)));
    await conversion.execute();
    if (!target.buffer) throw new Error("EMPTY_RECORDED_MEDIA");
    const normalized = new Blob([target.buffer], { type: toMp4 ? "video/mp4" : "video/webm" });
    const normalizedInput = new media.Input({ formats: media.ALL_FORMATS, source: new media.BlobSource(normalized) });
    const normalizedDuration = await normalizedInput.computeDuration();
    return { blob: normalized, duration: normalizedDuration, extension: toMp4 ? "mp4" as const : "webm" as const };
  };

  if (isMp4) return convert(true, false);
  try {
    return await convert(true, true);
  } catch (error) {
    console.warn("H.264/AAC MP4 conversion unavailable; keeping WebM", error);
    return convert(false, false);
  }
}

function entityKeyForClass(className: string) {
  return ENTITY_GROUPS.find((group) => group.classes.includes(className))?.key;
}

function intersectionOverUnion(a: number[], b: number[]) {
  const left = Math.max(a[0], b[0]);
  const top = Math.max(a[1], b[1]);
  const right = Math.min(a[0] + a[2], b[0] + b[2]);
  const bottom = Math.min(a[1] + a[3], b[1] + b[3]);
  const intersection = Math.max(0, right - left) * Math.max(0, bottom - top);
  return intersection / Math.max(1, a[2] * a[3] + b[2] * b[3] - intersection);
}

function isTaintedCanvasError(error: unknown) {
  return error instanceof DOMException
    ? error.name === "SecurityError"
    : error instanceof Error && /tainted|SecurityError|texSubImage2D/i.test(`${error.name} ${error.message}`);
}

function getPeakingCoefficients(frequency: number, sampleRate: number, q: number, gainDb: number): BiquadCoefficients {
  const omega = 2 * Math.PI * Math.min(frequency, sampleRate * 0.45) / sampleRate;
  const alpha = Math.sin(omega) / (2 * q);
  const amplitude = 10 ** (gainDb / 40);
  const a0 = 1 + alpha / amplitude;
  return {
    b0: (1 + alpha * amplitude) / a0,
    b1: (-2 * Math.cos(omega)) / a0,
    b2: (1 - alpha * amplitude) / a0,
    a1: (-2 * Math.cos(omega)) / a0,
    a2: (1 - alpha / amplitude) / a0,
  };
}

function applyBiquad(value: number, state: BiquadState, coefficients: BiquadCoefficients) {
  const output = coefficients.b0 * value + coefficients.b1 * state.x1 + coefficients.b2 * state.x2
    - coefficients.a1 * state.y1 - coefficients.a2 * state.y2;
  state.x2 = state.x1;
  state.x1 = value;
  state.y2 = state.y1;
  state.y1 = output;
  return output;
}

export default function PrivacyStudio() {
  const inputRef = useRef<HTMLInputElement>(null);
  const videoRef = useRef<HTMLVideoElement>(null);
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const modelRef = useRef<ObjectDetection | null>(null);
  const bodyPixRef = useRef<BodyPix | null>(null);
  const detectionsRef = useRef<TrackedDetection[]>([]);
  const segmentationRef = useRef<SemanticPersonSegmentation | null>(null);
  const maskCanvasRef = useRef<HTMLCanvasElement | null>(null);
  const expandedMaskCanvasRef = useRef<HTMLCanvasElement | null>(null);
  const effectCanvasRef = useRef<HTMLCanvasElement | null>(null);
  const inferenceCanvasRef = useRef<HTMLCanvasElement | null>(null);
  const lastInferenceErrorRef = useRef(0);
  const selectedRef = useRef<Set<EntityKey>>(new Set(["person"]));
  const selectedSubjectIdsRef = useRef<Set<string>>(new Set());
  const knownSubjectIdsRef = useRef<Set<string>>(new Set());
  const tracksRef = useRef<Map<string, TrackState>>(new Map());
  const trackCounterRef = useRef<Record<EntityKey, number>>({ person: 0, vehicle: 0, pet: 0 });
  const trackingFrameRef = useRef(0);
  const qualityRef = useRef<QualityMode>("balanced");
  const scopeRef = useRef<MaskScope>("full");
  const fullFrameStyleRef = useRef<FullFrameStyle>("blur");
  const effectStrengthRef = useRef(46);
  const animationRef = useRef<number>(0);
  const detectingRef = useRef(false);
  const segmentingRef = useRef(false);
  const lastDetectionRef = useRef(0);
  const lastSegmentationRef = useRef(0);
  const exportStopRef = useRef<(() => void) | null>(null);
  const drawFrameRef = useRef<(() => void) | null>(null);
  const offlineConversionRef = useRef<{ cancel: () => Promise<void> } | null>(null);
  const benchmarkingRef = useRef(false);
  const audioContextRef = useRef<AudioContext | null>(null);
  const audioSourceRef = useRef<MediaElementAudioSourceNode | null>(null);
  const audioMonitorRef = useRef<GainNode | null>(null);
  const voiceAudioGraphRef = useRef<VoiceAudioGraph | null>(null);

  const [file, setFile] = useState<File | null>(null);
  const [videoUrl, setVideoUrl] = useState("");
  const [selected, setSelected] = useState<Set<EntityKey>>(new Set(["person"]));
  const [subjects, setSubjects] = useState<SubjectItem[]>([]);
  const [selectedSubjectIds, setSelectedSubjectIds] = useState<Set<string>>(new Set());
  const [quality, setQuality] = useState<QualityMode>("balanced");
  const [maskScope, setMaskScope] = useState<MaskScope>("full");
  const [fullFrameStyle, setFullFrameStyle] = useState<FullFrameStyle>("blur");
  const [settingsTab, setSettingsTab] = useState<SettingsTab>("general");
  const [effectStrength, setEffectStrength] = useState(46);
  const [highLoadRequested, setHighLoadRequested] = useState(false);
  const [modelState, setModelState] = useState<"idle" | "loading" | "ready" | "error">("idle");
  const [preciseModelState, setPreciseModelState] = useState<"idle" | "loading" | "ready" | "error">("idle");
  const [preciseLoadProgress, setPreciseLoadProgress] = useState<YoloLoadProgress | null>(null);
  const [isPlaying, setIsPlaying] = useState(false);
  const [duration, setDuration] = useState(0);
  const [currentTime, setCurrentTime] = useState(0);
  const [detectedCount, setDetectedCount] = useState(0);
  const [exporting, setExporting] = useState(false);
  const [progress, setProgress] = useState(0);
  const [etaSeconds, setEtaSeconds] = useState<number | null>(null);
  const [estimatedHighSeconds, setEstimatedHighSeconds] = useState<number | null>(null);
  const [downloadUrl, setDownloadUrl] = useState("");
  const [outputExtension, setOutputExtension] = useState<"mp4" | "webm">("webm");
  const [message, setMessage] = useState("");
  const [audioMode, setAudioMode] = useState<AudioMode>("original");
  const [voicePitch, setVoicePitch] = useState(-4);

  useEffect(() => {
    selectedRef.current = selected;
    drawFrameRef.current?.();
  }, [selected]);

  useEffect(() => {
    selectedSubjectIdsRef.current = selectedSubjectIds;
    drawFrameRef.current?.();
  }, [selectedSubjectIds]);

  useEffect(() => {
    qualityRef.current = quality;
    scopeRef.current = maskScope;
    fullFrameStyleRef.current = fullFrameStyle;
    effectStrengthRef.current = effectStrength;
    drawFrameRef.current?.();
  }, [effectStrength, fullFrameStyle, quality, maskScope]);

  useEffect(() => () => {
    if (videoUrl) URL.revokeObjectURL(videoUrl);
  }, [videoUrl]);

  useEffect(() => () => {
    if (downloadUrl) URL.revokeObjectURL(downloadUrl);
  }, [downloadUrl]);

  useEffect(() => () => cancelAnimationFrame(animationRef.current), []);

  useEffect(() => () => {
    void audioContextRef.current?.close();
    audioContextRef.current = null;
    audioSourceRef.current = null;
    audioMonitorRef.current = null;
    voiceAudioGraphRef.current = null;
  }, []);

  const isSelectedClass = useCallback((className: string) => {
    return ENTITY_GROUPS.some((group) => selectedRef.current.has(group.key) && group.classes.includes(className));
  }, []);

  const getSegmentationModel = useCallback(() => {
    return bodyPixRef.current;
  }, []);

  const prepareInferenceSource = useCallback((video: HTMLVideoElement) => {
    if (!inferenceCanvasRef.current) inferenceCanvasRef.current = document.createElement("canvas");
    const canvas = inferenceCanvasRef.current;
    if (canvas.width !== video.videoWidth || canvas.height !== video.videoHeight) {
      canvas.width = video.videoWidth;
      canvas.height = video.videoHeight;
    }
    const context = canvas.getContext("2d", { alpha: false, willReadFrequently: false });
    if (!context) throw new Error("INFERENCE_CANVAS_UNAVAILABLE");
    context.drawImage(video, 0, 0, canvas.width, canvas.height);
    return canvas;
  }, []);

  const runWithPixelFallback = useCallback(async <T,>(
    canvas: HTMLCanvasElement,
    operation: (source: HTMLCanvasElement | ImageData) => Promise<T>,
  ) => {
    try {
      return await operation(canvas);
    } catch (error) {
      if (!isTaintedCanvasError(error)) throw error;
      const context = canvas.getContext("2d", { alpha: false, willReadFrequently: true });
      if (!context) throw error;
      return operation(context.getImageData(0, 0, canvas.width, canvas.height));
    }
  }, []);

  const handleInferenceError = useCallback((error: unknown) => {
    console.error("Local frame inference failed", error);
    const now = Date.now();
    if (now - lastInferenceErrorRef.current < 4000) return;
    lastInferenceErrorRef.current = now;
    const securityError = isTaintedCanvasError(error);
    setMessage(securityError
      ? "浏览器拒绝读取当前视频帧，已安全跳过；请重新选择原始本地视频，避免从网页播放器直接分享的临时文件"
      : "当前帧识别失败，已自动跳过并继续处理");
  }, []);

  const assignTracks = useCallback((detections: DetectedObject[]) => {
    trackingFrameRef.current += 1;
    const frame = trackingFrameRef.current;
    const used = new Set<string>();
    const tracked = detections.filter((detection) => entityKeyForClass(detection.class)).map((detection) => {
      const key = entityKeyForClass(detection.class)!;
      let best: TrackState | undefined;
      let bestScore = 0.08;
      tracksRef.current.forEach((track) => {
        if (used.has(track.id) || track.className !== detection.class || frame - track.lastSeen > 45) return;
        const score = intersectionOverUnion(track.bbox, detection.bbox);
        if (score > bestScore) { best = track; bestScore = score; }
      });
      if (!best) {
        trackCounterRef.current[key] += 1;
        best = { id: `${key}-${trackCounterRef.current[key]}`, className: detection.class, bbox: detection.bbox, lastSeen: frame };
      }
      best.bbox = detection.bbox;
      best.lastSeen = frame;
      tracksRef.current.set(best.id, best);
      used.add(best.id);
      return { ...detection, trackId: best.id };
    });
    tracksRef.current.forEach((track, id) => {
      if (frame - track.lastSeen > 90) tracksRef.current.delete(id);
    });
    return tracked;
  }, []);

  const updateSubjectList = useCallback((tracked: TrackedDetection[], source: CanvasImageSource) => {
    const additions: SubjectItem[] = [];
    tracked.filter((item) => item.score > 0.42).forEach((item) => {
      const key = entityKeyForClass(item.class);
      if (!key || knownSubjectIdsRef.current.has(item.trackId)) return;
      const [x, y, w, h] = item.bbox;
      const crop = document.createElement("canvas");
      crop.width = 72;
      crop.height = 72;
      const cropCtx = crop.getContext("2d");
      if (cropCtx) {
        cropCtx.fillStyle = "#e9eeea";
        cropCtx.fillRect(0, 0, 72, 72);
        cropCtx.drawImage(source, Math.max(0, x), Math.max(0, y), Math.max(1, w), Math.max(1, h), 0, 0, 72, 72);
      }
      const number = Number(item.trackId.split("-").pop()) || 1;
      const label = `${ENTITY_GROUPS.find((group) => group.key === key)?.label || "主体"} ${number}`;
      additions.push({ id: item.trackId, key, label, thumbnail: crop.toDataURL("image/jpeg", 0.72) });
      knownSubjectIdsRef.current.add(item.trackId);
    });
    if (additions.length) {
      setSubjects((previous) => [...previous, ...additions].slice(-30));
      setSelectedSubjectIds((previous) => {
        const next = new Set([...previous, ...additions.map((item) => item.id)]);
        selectedSubjectIdsRef.current = next;
        return next;
      });
    }
  }, []);

  const isSelectedDetection = useCallback((item: TrackedDetection) => {
    return isSelectedClass(item.class) && (!knownSubjectIdsRef.current.has(item.trackId) || selectedSubjectIdsRef.current.has(item.trackId));
  }, [isSelectedClass]);

  const combineSelectedPeople = useCallback((instances: PersonSegmentation[], detections: TrackedDetection[]) => {
    if (!instances.length) return null;
    const people = detections.filter((item) => item.class === "person" && item.score > 0.34);
    const included = instances.filter((instance) => {
      const points = instance.pose.keypoints.filter((point) => point.score > 0.15);
      if (!points.length) return selectedRef.current.has("person");
      const cx = points.reduce((sum, point) => sum + point.position.x, 0) / points.length;
      const cy = points.reduce((sum, point) => sum + point.position.y, 0) / points.length;
      const match = people
        .map((person) => ({ person, distance: Math.hypot(cx - (person.bbox[0] + person.bbox[2] / 2), cy - (person.bbox[1] + person.bbox[3] / 2)) }))
        .sort((a, b) => a.distance - b.distance)[0]?.person;
      return Boolean(match && isSelectedDetection(match));
    });
    const first = instances[0];
    const data = new Uint8Array(first.width * first.height);
    included.forEach((instance) => instance.data.forEach((value, index) => { if (value) data[index] = 1; }));
    return { data, width: first.width, height: first.height, allPoses: included.map((instance) => instance.pose) } satisfies SemanticPersonSegmentation;
  }, [isSelectedDetection]);

  const prepareSegmentationMask = useCallback((segmentation: SemanticPersonSegmentation) => {
    if (!maskCanvasRef.current) maskCanvasRef.current = document.createElement("canvas");
    if (!expandedMaskCanvasRef.current) expandedMaskCanvasRef.current = document.createElement("canvas");
    const maskCanvas = maskCanvasRef.current;
    const expandedMask = expandedMaskCanvasRef.current;
    const maskWidth = Math.min(segmentation.width, qualityRef.current === "precise" ? 1080 : 640);
    const maskScale = maskWidth / segmentation.width;
    const maskHeight = Math.max(1, Math.round(segmentation.height * maskScale));
    maskCanvas.width = maskWidth;
    maskCanvas.height = maskHeight;
    expandedMask.width = maskWidth;
    expandedMask.height = maskHeight;
    const maskCtx = maskCanvas.getContext("2d");
    const expandedCtx = expandedMask.getContext("2d");
    if (!maskCtx || !expandedCtx) return;

    const imageData = maskCtx.createImageData(maskWidth, maskHeight);
    for (let y = 0; y < maskHeight; y += 1) {
      const sourceY = Math.min(segmentation.height - 1, Math.floor(y / maskScale));
      for (let x = 0; x < maskWidth; x += 1) {
        const sourceX = Math.min(segmentation.width - 1, Math.floor(x / maskScale));
        const sourceOffset = sourceY * segmentation.width + sourceX;
        const offset = (y * maskWidth + x) * 4;
        imageData.data[offset] = 255;
        imageData.data[offset + 1] = 255;
        imageData.data[offset + 2] = 255;
        imageData.data[offset + 3] = segmentation.data[sourceOffset] ? 255 : 0;
      }
    }
    maskCtx.putImageData(imageData, 0, 0);

    const limbPairs = [
      ["leftShoulder", "leftElbow"], ["leftElbow", "leftWrist"],
      ["rightShoulder", "rightElbow"], ["rightElbow", "rightWrist"],
      ["leftShoulder", "rightShoulder"], ["leftShoulder", "leftHip"],
      ["rightShoulder", "rightHip"], ["leftHip", "rightHip"],
      ["leftHip", "leftKnee"], ["leftKnee", "leftAnkle"],
      ["rightHip", "rightKnee"], ["rightKnee", "rightAnkle"],
    ];
    if (qualityRef.current !== "precise") {
      maskCtx.save();
      maskCtx.strokeStyle = "#fff";
      maskCtx.fillStyle = "#fff";
      maskCtx.lineCap = "round";
      maskCtx.lineJoin = "round";
      maskCtx.lineWidth = Math.max(14, maskWidth * 0.034);
      segmentation.allPoses.forEach((pose) => {
        const points = new Map(pose.keypoints.map((point) => [point.part, point]));
        limbPairs.forEach(([fromName, toName]) => {
          const from = points.get(fromName);
          const to = points.get(toName);
          if (!from || !to || from.score < 0.16 || to.score < 0.16) return;
          maskCtx.beginPath();
          maskCtx.moveTo(from.position.x * maskScale, from.position.y * maskScale);
          maskCtx.lineTo(to.position.x * maskScale, to.position.y * maskScale);
          maskCtx.stroke();
        });
        const nose = points.get("nose");
        if (nose && nose.score > 0.16) {
          maskCtx.beginPath();
          maskCtx.arc(nose.position.x * maskScale, nose.position.y * maskScale, Math.max(18, maskWidth * 0.045), 0, Math.PI * 2);
          maskCtx.fill();
        }
      });
      maskCtx.restore();
    }

    expandedCtx.clearRect(0, 0, maskWidth, maskHeight);
    const safetyRadius = qualityRef.current === "precise"
      ? Math.max(8, Math.min(22, maskWidth * 0.015))
      : Math.max(12, Math.min(34, maskWidth * 0.028));
    expandedCtx.globalAlpha = 1;
    expandedCtx.drawImage(maskCanvas, 0, 0);
    for (let step = 0; step < 12; step += 1) {
      const angle = (step / 12) * Math.PI * 2;
      expandedCtx.drawImage(maskCanvas, Math.cos(angle) * safetyRadius, Math.sin(angle) * safetyRadius);
    }
  }, []);

  const applyYoloResults = useCallback((results: YoloMask[], source: CanvasImageSource, updateList = false, updateCount = true) => {
    const tracked = assignTracks(results.map((result) => result.detection));
    detectionsRef.current = tracked;
    if (updateList) updateSubjectList(tracked, source);
    if (!results.length) {
      segmentationRef.current = null;
      if (updateCount) setDetectedCount(0);
      return;
    }
    const data = new Uint8Array(results[0].width * results[0].height);
    results.forEach((result, index) => {
      const detection = tracked[index];
      if (!detection || !isSelectedDetection(detection)) return;
      result.data.forEach((value, offset) => { if (value) data[offset] = 1; });
    });
    const segmentation: SemanticPersonSegmentation = { data, width: results[0].width, height: results[0].height, allPoses: [] };
    segmentationRef.current = segmentation;
    prepareSegmentationMask(segmentation);
    if (updateCount) setDetectedCount(tracked.filter((item) => item.score > 0.36 && isSelectedDetection(item)).length);
  }, [assignTracks, isSelectedDetection, prepareSegmentationMask, updateSubjectList]);

  const renderProcessedFrame = useCallback((source: CanvasImageSource, targetCanvas: HTMLCanvasElement, width: number, height: number) => {
    if (targetCanvas.width !== width || targetCanvas.height !== height) {
      targetCanvas.width = width;
      targetCanvas.height = height;
    }
    const ctx = targetCanvas.getContext("2d");
    if (!ctx) return;
    const blurAmount = Math.max(2, effectStrengthRef.current);
    const precisePerson = qualityRef.current === "precise"
      ? segmentationRef.current
      : qualityRef.current === "balanced" && selectedRef.current.has("person") && segmentationRef.current;
    const selectedObjects = detectionsRef.current.filter((item) => item.score > 0.42 && isSelectedDetection(item));
    const boxObjects = qualityRef.current === "precise" ? [] : precisePerson ? selectedObjects.filter((item) => item.class !== "person") : selectedObjects;
    const personSafetyObjects = precisePerson && qualityRef.current === "balanced" && scopeRef.current === "subjects" ? selectedObjects.filter((item) => item.class === "person") : [];

    const drawFullFrame = (blurred: boolean) => {
      ctx.save();
      ctx.filter = blurred ? `blur(${blurAmount}px)` : "none";
      ctx.drawImage(source, 0, 0, width, height);
      ctx.restore();
    };

    const drawPixelatedFullFrame = () => {
      if (!effectCanvasRef.current) effectCanvasRef.current = document.createElement("canvas");
      const pixelCanvas = effectCanvasRef.current;
      const blockSize = Math.max(4, effectStrengthRef.current);
      pixelCanvas.width = Math.max(1, Math.ceil(width / blockSize));
      pixelCanvas.height = Math.max(1, Math.ceil(height / blockSize));
      const pixelCtx = pixelCanvas.getContext("2d");
      if (!pixelCtx) return;
      pixelCtx.imageSmoothingEnabled = true;
      pixelCtx.drawImage(source, 0, 0, pixelCanvas.width, pixelCanvas.height);
      ctx.save();
      ctx.imageSmoothingEnabled = false;
      ctx.drawImage(pixelCanvas, 0, 0, width, height);
      ctx.restore();
    };

    const drawAsciiFullFrame = () => {
      if (!effectCanvasRef.current) effectCanvasRef.current = document.createElement("canvas");
      const sampleCanvas = effectCanvasRef.current;
      const fontSize = Math.max(8, effectStrengthRef.current);
      ctx.save();
      ctx.font = `700 ${fontSize}px ui-monospace, SFMono-Regular, Menlo, Consolas, monospace`;
      ctx.textBaseline = "top";
      const characterWidth = Math.max(4, ctx.measureText("M").width);
      const columns = Math.max(1, Math.ceil(width / characterWidth));
      const rows = Math.max(1, Math.ceil(height / fontSize));
      sampleCanvas.width = columns;
      sampleCanvas.height = rows;
      const sampleCtx = sampleCanvas.getContext("2d", { willReadFrequently: true });
      if (!sampleCtx) {
        ctx.restore();
        return;
      }
      sampleCtx.drawImage(source, 0, 0, columns, rows);
      const pixels = sampleCtx.getImageData(0, 0, columns, rows).data;
      const glyphs = " .,:;irsXA253hMHGS#9B&@";
      ctx.fillStyle = "#050706";
      ctx.fillRect(0, 0, width, height);
      ctx.fillStyle = "#f4f7f5";
      for (let row = 0; row < rows; row += 1) {
        let line = "";
        for (let column = 0; column < columns; column += 1) {
          const offset = (row * columns + column) * 4;
          const red = pixels[offset];
          const green = pixels[offset + 1];
          const blue = pixels[offset + 2];
          const luminance = red * 0.2126 + green * 0.7152 + blue * 0.0722;
          const glyph = glyphs[Math.min(glyphs.length - 1, Math.floor((luminance / 256) * glyphs.length))];
          line += glyph;
        }
        ctx.fillText(line, 0, row * fontSize);
      }
      ctx.restore();
    };

    const drawSegmentedPerson = (blurred: boolean) => {
      const segmentation = segmentationRef.current;
      if (!segmentation) return;
      if (!effectCanvasRef.current) effectCanvasRef.current = document.createElement("canvas");
      const maskCanvas = expandedMaskCanvasRef.current;
      const effectCanvas = effectCanvasRef.current;
      if (!maskCanvas) return;
      effectCanvas.width = width;
      effectCanvas.height = height;
      const effectCtx = effectCanvas.getContext("2d");
      if (!effectCtx) return;
      effectCtx.clearRect(0, 0, width, height);
      effectCtx.globalCompositeOperation = "source-over";
      effectCtx.filter = blurred ? `blur(${blurAmount}px)` : "none";
      effectCtx.drawImage(source, 0, 0, width, height);
      effectCtx.globalCompositeOperation = "destination-in";
      effectCtx.filter = "blur(4px)";
      effectCtx.drawImage(maskCanvas, 0, 0, width, height);
      effectCtx.globalCompositeOperation = "source-over";
      effectCtx.filter = "none";
      ctx.drawImage(effectCanvas, 0, 0);
    };

    if (scopeRef.current === "full") {
      if (fullFrameStyleRef.current === "pixel") drawPixelatedFullFrame();
      else if (fullFrameStyleRef.current === "ascii") drawAsciiFullFrame();
      else drawFullFrame(true);
    } else if (scopeRef.current === "background") {
      drawFullFrame(true);
      if (precisePerson) drawSegmentedPerson(false);
    } else {
      drawFullFrame(false);
      if (precisePerson) drawSegmentedPerson(true);
    }

    if (scopeRef.current !== "full") personSafetyObjects.forEach((item) => {
      const [x, y, w, h] = item.bbox;
      const pad = Math.max(18, Math.min(w, h) * 0.18);
      ctx.save();
      ctx.beginPath();
      ctx.roundRect(x - pad, y + h * 0.1, w + pad * 2, h * 0.58, Math.min(w * 0.34, h * 0.2));
      ctx.roundRect(x + w * 0.16, y - pad, w * 0.68, h + pad * 2, Math.min(w * 0.34, h * 0.18));
      ctx.clip();
      ctx.filter = `blur(${blurAmount}px)`;
      ctx.drawImage(source, 0, 0, width, height);
      ctx.restore();
    });

    if (scopeRef.current !== "full") boxObjects.forEach((item) => {
      const [x, y, w, h] = item.bbox;
      const pad = Math.max(12, Math.min(w, h) * (qualityRef.current === "precise" ? 0.14 : 0.1));
      ctx.save();
      ctx.beginPath();
      if (item.class === "person") {
        ctx.ellipse(x + w / 2, y + h / 2, w / 2 + pad, h / 2 + pad, 0, 0, Math.PI * 2);
      } else {
        ctx.roundRect(Math.max(0, x - pad), Math.max(0, y - pad), Math.min(width - x + pad, w + pad * 2), Math.min(height - y + pad, h + pad * 2), Math.min(w, h) * 0.42);
      }
      ctx.clip();
      ctx.filter = scopeRef.current === "background" ? "none" : `blur(${blurAmount}px)`;
      ctx.drawImage(source, 0, 0, width, height);
      ctx.restore();
    });

    const watermarkSize = Math.max(14, Math.min(30, width * 0.022));
    const watermarkPaddingX = watermarkSize * 0.72;
    const watermarkPaddingY = watermarkSize * 0.48;
    const watermarkText = "镜隐 · PRIVACY";
    ctx.save();
    ctx.font = `650 ${watermarkSize}px system-ui, sans-serif`;
    const watermarkWidth = ctx.measureText(watermarkText).width + watermarkPaddingX * 2;
    const watermarkHeight = watermarkSize + watermarkPaddingY * 2;
    const watermarkX = width - watermarkWidth - Math.max(14, width * 0.025);
    const watermarkY = height - watermarkHeight - Math.max(14, height * 0.025);
    ctx.globalAlpha = 0.72;
    ctx.fillStyle = "rgba(12, 30, 25, 0.72)";
    ctx.beginPath();
    ctx.roundRect(watermarkX, watermarkY, watermarkWidth, watermarkHeight, watermarkHeight / 2);
    ctx.fill();
    ctx.globalAlpha = 0.92;
    ctx.fillStyle = "#ffffff";
    ctx.textBaseline = "middle";
    ctx.fillText(watermarkText, watermarkX + watermarkPaddingX, watermarkY + watermarkHeight / 2);
    ctx.restore();
  }, [isSelectedDetection]);

  const drawFrame = useCallback(() => {
    const video = videoRef.current;
    const canvas = canvasRef.current;
    if (!video || !canvas || video.readyState < 2 || !video.videoWidth || !video.videoHeight) return;
    renderProcessedFrame(video, canvas, video.videoWidth, video.videoHeight);
  }, [renderProcessedFrame]);

  drawFrameRef.current = drawFrame;

  const loadPreciseModel = useCallback(async () => {
    setPreciseModelState("loading");
    try {
      const model = await loadYoloSegModel((nextProgress) => {
        setPreciseLoadProgress(nextProgress);
        if (nextProgress.stage === "download") setMessage(`正在下载网页高档模型 ${nextProgress.percent}%`);
        if (nextProgress.stage === "compile") setMessage("模型下载完成，正在编译 WebGPU 运算图（最长 45 秒）");
        if (nextProgress.stage === "warmup") setMessage("WebGPU 编译完成，正在进行首次预热（最长 30 秒）");
      });
      setPreciseModelState("ready");
      return model;
    } catch (error) {
      console.error("YOLO WebGPU initialization failed", error);
      setPreciseModelState("error");
      throw error;
    }
  }, []);

  const renderLoop = useCallback((time: number) => {
    const video = videoRef.current;
    if (!video) return;
    drawFrame();
    setCurrentTime(video.currentTime);
    if (scopeRef.current === "full") {
      if (!video.paused && !video.ended) animationRef.current = requestAnimationFrame(renderLoop);
      return;
    }
    const detectionInterval = qualityRef.current === "balanced" ? 150 : 300;
    if (qualityRef.current !== "precise" && modelRef.current && !detectingRef.current && time - lastDetectionRef.current > detectionInterval && !video.paused) {
      detectingRef.current = true;
      lastDetectionRef.current = time;
      let inferenceSource: HTMLCanvasElement | null = null;
      try {
        inferenceSource = prepareInferenceSource(video);
      } catch (error) {
        detectingRef.current = false;
        handleInferenceError(error);
      }
      if (inferenceSource) void runWithPixelFallback(inferenceSource, (source) => modelRef.current!.detect(source, 14, 0.34)).then((detections) => {
        const tracked = assignTracks(detections);
        detectionsRef.current = tracked;
        updateSubjectList(tracked, video);
        const objectCount = tracked.filter((item) => item.score > 0.42 && isSelectedDetection(item) && (qualityRef.current === "fast" || item.class !== "person")).length;
        const peopleCount = qualityRef.current === "balanced" && selectedRef.current.has("person") ? (segmentationRef.current?.allPoses.length || 0) : 0;
        setDetectedCount(objectCount + peopleCount);
      }).catch(handleInferenceError).finally(() => { detectingRef.current = false; });
    }
    const segmentationModel = getSegmentationModel();
    if (qualityRef.current === "precise" && preciseModelState === "ready" && !segmentingRef.current && time - lastSegmentationRef.current > 160 && !video.paused) {
      segmentingRef.current = true;
      lastSegmentationRef.current = time;
      void segmentWithYolo(video, video.videoWidth, video.videoHeight)
        .then((results) => applyYoloResults(results, video, true))
        .catch(handleInferenceError)
        .finally(() => { segmentingRef.current = false; });
    } else if (qualityRef.current === "balanced" && selectedRef.current.has("person") && segmentationModel && !segmentingRef.current && time - lastSegmentationRef.current > 100 && !video.paused) {
      segmentingRef.current = true;
      lastSegmentationRef.current = time;
      let inferenceSource: HTMLCanvasElement | null = null;
      try {
        inferenceSource = prepareInferenceSource(video);
      } catch (error) {
        segmentingRef.current = false;
        handleInferenceError(error);
      }
      if (inferenceSource) void runWithPixelFallback(inferenceSource, (source) => segmentationModel.segmentMultiPerson(source, {
        internalResolution: "medium",
        segmentationThreshold: 0.34,
        maxDetections: 10,
        scoreThreshold: 0.2,
        nmsRadius: 20,
        minKeypointScore: 0.2,
        refineSteps: 7,
      })).then((instances) => {
        const segmentation = combineSelectedPeople(instances, detectionsRef.current);
        if (!segmentation) {
          segmentationRef.current = null;
          return;
        }
        segmentationRef.current = segmentation;
        prepareSegmentationMask(segmentation);
      }).catch(handleInferenceError).finally(() => { segmentingRef.current = false; });
    }
    if (!video.paused && !video.ended) animationRef.current = requestAnimationFrame(renderLoop);
  }, [applyYoloResults, assignTracks, combineSelectedPeople, drawFrame, getSegmentationModel, handleInferenceError, isSelectedDetection, preciseModelState, prepareInferenceSource, prepareSegmentationMask, runWithPixelFallback, updateSubjectList]);

  const analyzeCurrentFrame = useCallback(async (video: HTMLVideoElement) => {
    if (scopeRef.current === "full") {
      drawFrame();
      return;
    }
    const segmentationModel = getSegmentationModel();
    if (!modelRef.current || !segmentationModel || video.readyState < 2) return;
    if (qualityRef.current === "precise") {
      if (preciseModelState === "ready") {
        const results = await segmentWithYolo(video, video.videoWidth, video.videoHeight);
        applyYoloResults(results, video, true);
        drawFrame();
      } else {
        const inferenceSource = prepareInferenceSource(video);
        const detections = await runWithPixelFallback(inferenceSource, (source) => modelRef.current!.detect(source, 14, 0.34));
        const tracked = assignTracks(detections);
        detectionsRef.current = tracked;
        updateSubjectList(tracked, video);
      }
      return;
    }
    const inferenceSource = prepareInferenceSource(video);
    const [detections, instances] = await Promise.all([
      runWithPixelFallback(inferenceSource, (source) => modelRef.current!.detect(source, 14, 0.34)),
      runWithPixelFallback(inferenceSource, (source) => segmentationModel.segmentMultiPerson(source, {
        internalResolution: "medium",
        segmentationThreshold: 0.34,
        minKeypointScore: 0.2,
        refineSteps: 7,
      })),
    ]);
    const tracked = assignTracks(detections);
    detectionsRef.current = tracked;
    updateSubjectList(tracked, video);
    const segmentation = combineSelectedPeople(instances, tracked);
    segmentationRef.current = segmentation;
    if (segmentation) prepareSegmentationMask(segmentation);
    setDetectedCount(tracked.filter((item) => item.score > 0.42 && isSelectedDetection(item) && item.class !== "person").length + (segmentation?.allPoses.length || 0));
    drawFrame();
  }, [applyYoloResults, assignTracks, combineSelectedPeople, drawFrame, getSegmentationModel, isSelectedDetection, preciseModelState, prepareInferenceSource, prepareSegmentationMask, runWithPixelFallback, updateSubjectList]);

  useEffect(() => {
    const video = videoRef.current;
    if (video && video.paused && modelState === "ready") void analyzeCurrentFrame(video).catch(handleInferenceError);
  }, [analyzeCurrentFrame, handleInferenceError, modelState, quality, selectedSubjectIds]);

  useEffect(() => {
    if (!highLoadRequested || quality !== "precise" || modelState !== "ready" || (preciseModelState !== "idle" && preciseModelState !== "error")) return;
    setMessage("正在后台加载 YOLO 实例分割模型；中、低档已经可以使用");
    void loadPreciseModel()
      .then(() => {
        setHighLoadRequested(false);
        setMessage(supportsWebGpu() ? "YOLO WebGPU 实例分割已就绪" : "当前设备无 WebGPU，将使用兼容模式；建议切换中档或使用 App");
      })
      .catch((error) => {
        setHighLoadRequested(false);
        const code = error instanceof Error ? error.message : "";
        if (code === "MOBILE_WEBGPU_DISABLED") setMessage("为避免手机卡死和发热，网页高档已在移动端停用；请选择中档或使用 App");
        else if (code === "WEBGPU_REQUIRED") setMessage("当前浏览器没有可用的 WebGPU，高档已停用；请选择中档或使用 App");
        else if (code.includes("TIMEOUT")) setMessage("本机 WebGPU 初始化超过 75 秒，高档已自动停止；请选择中档或使用 App");
        else setMessage("YOLO 模型初始化失败；请选择中档或使用 App");
      });
  }, [highLoadRequested, loadPreciseModel, modelState, preciseModelState, quality]);

  useEffect(() => {
    const video = videoRef.current;
    if (maskScope === "full" || preciseModelState !== "ready" || !duration || estimatedHighSeconds !== null || benchmarkingRef.current || !video?.paused || !video.videoWidth) return;
    benchmarkingRef.current = true;
    void segmentWithYolo(video, video.videoWidth, video.videoHeight)
      .then(() => {
        const started = performance.now();
        return segmentWithYolo(video, video.videoWidth, video.videoHeight).then((results) => ({ results, started }));
      })
      .then(({ results, started }) => {
        const millisecondsPerFrame = performance.now() - started;
        applyYoloResults(results, video, true);
        setEstimatedHighSeconds(Math.max(duration, (millisecondsPerFrame / 1000) * duration * 60 * 1.15));
        drawFrame();
      })
      .catch(handleInferenceError)
      .finally(() => { benchmarkingRef.current = false; });
  }, [applyYoloResults, drawFrame, duration, estimatedHighSeconds, handleInferenceError, maskScope, preciseModelState]);

  const loadModel = useCallback(async () => {
    if (modelRef.current) return;
    setModelState("loading");
    setMessage("正在加载本地 AI；首次使用需要下载模型，之后浏览器通常会缓存");
    try {
      const tf = await import("@tensorflow/tfjs");
      if (tf.findBackend("webgl")) await tf.setBackend("webgl");
      await tf.ready();
      const [cocoSsd, bodyPix] = await Promise.all([
        import("@tensorflow-models/coco-ssd"),
        import("@tensorflow-models/body-pix"),
      ]);
      [modelRef.current, bodyPixRef.current] = await Promise.all([
        cocoSsd.load({ base: "lite_mobilenet_v2" }),
        bodyPix.load({
          architecture: "MobileNetV1",
          outputStride: 16,
          multiplier: 0.75,
          quantBytes: 2,
        }),
      ]);
      if (videoRef.current?.readyState && videoRef.current.readyState >= 2) await analyzeCurrentFrame(videoRef.current);
      setModelState("ready");
      setMessage("已识别当前画面主体，可在下方逐个选择");
    } catch {
      setModelState("error");
      setMessage("AI 模型加载失败，请检查网络后重试");
    }
  }, [analyzeCurrentFrame]);

  const handleFile = async (nextFile?: File) => {
    if (!nextFile) return;
    if (!nextFile.type.startsWith("video/")) {
      setMessage("请选择 MP4、MOV 或 WebM 视频");
      return;
    }
    if (nextFile.size > 500 * 1024 * 1024) {
      setMessage("首期建议使用 500MB 以内的视频");
      return;
    }
    if (videoUrl) URL.revokeObjectURL(videoUrl);
    if (downloadUrl) URL.revokeObjectURL(downloadUrl);
    detectionsRef.current = [];
    segmentationRef.current = null;
    tracksRef.current.clear();
    knownSubjectIdsRef.current.clear();
    trackCounterRef.current = { person: 0, vehicle: 0, pet: 0 };
    trackingFrameRef.current = 0;
    lastInferenceErrorRef.current = 0;
    setSubjects([]);
    setSelectedSubjectIds(new Set());
    setDetectedCount(0);
    setDownloadUrl("");
    setEtaSeconds(null);
    setEstimatedHighSeconds(null);
    setHighLoadRequested(false);
    if (preciseModelState === "error") {
      setPreciseModelState("idle");
      setPreciseLoadProgress(null);
    }
    setFile(nextFile);
    setVideoUrl(URL.createObjectURL(nextFile));
    setMessage("视频已在本地打开；请选择遮盖范围");
  };

  const togglePlayback = async () => {
    const video = videoRef.current;
    if (!video) return;
    if (video.paused) {
      await video.play();
      setIsPlaying(true);
      cancelAnimationFrame(animationRef.current);
      animationRef.current = requestAnimationFrame(renderLoop);
    } else {
      video.pause();
      setIsPlaying(false);
      drawFrame();
    }
  };

  const seek = (value: number) => {
    const video = videoRef.current;
    if (!video) return;
    video.currentTime = value;
    setCurrentTime(value);
    window.setTimeout(async () => {
      try {
        if (qualityRef.current === "precise" && preciseModelState === "ready") {
          const results = await segmentWithYolo(video, video.videoWidth, video.videoHeight);
          applyYoloResults(results, video, true);
          drawFrame();
          return;
        }
        const inferenceSource = prepareInferenceSource(video);
        const tasks: Promise<unknown>[] = [];
        if (modelRef.current) tasks.push(runWithPixelFallback(inferenceSource, (source) => modelRef.current!.detect(source, 14, 0.34)).then((result) => {
          const tracked = assignTracks(result);
          detectionsRef.current = tracked;
          updateSubjectList(tracked, video);
        }));
        await Promise.all(tasks);
        const segmentationModel = getSegmentationModel();
        if (segmentationModel && qualityRef.current === "balanced") {
          const instances = await runWithPixelFallback(inferenceSource, (source) => segmentationModel.segmentMultiPerson(source, {
            internalResolution: "medium",
            segmentationThreshold: 0.34,
            minKeypointScore: 0.2,
            refineSteps: 7,
          }));
          const segmentation = combineSelectedPeople(instances, detectionsRef.current);
          segmentationRef.current = segmentation;
          if (segmentation) prepareSegmentationMask(segmentation);
        }
        drawFrame();
      } catch (error) {
        handleInferenceError(error);
      }
    }, 40);
  };

  const ensureVoiceAudioGraph = async (video: HTMLVideoElement) => {
    const AudioContextConstructor = window.AudioContext
      || (window as typeof window & { webkitAudioContext?: typeof AudioContext }).webkitAudioContext;
    if (!AudioContextConstructor) throw new Error("WEB_AUDIO_UNAVAILABLE");

    let audioContext = audioContextRef.current;
    if (!audioContext || audioContext.state === "closed") {
      audioContext = new AudioContextConstructor();
      audioContextRef.current = audioContext;
      audioSourceRef.current = null;
      audioMonitorRef.current = null;
      voiceAudioGraphRef.current = null;
    }
    if (!audioSourceRef.current) {
      const source = audioContext.createMediaElementSource(video);
      const monitor = audioContext.createGain();
      monitor.gain.value = 1;
      source.connect(monitor);
      monitor.connect(audioContext.destination);
      audioSourceRef.current = source;
      audioMonitorRef.current = monitor;
    }
    await audioContext.resume();
    if (voiceAudioGraphRef.current) return { audioContext, graph: voiceAudioGraphRef.current };

    const source = audioSourceRef.current;
    const { SoundTouchNode } = await import("@soundtouchjs/audio-worklet");
    await SoundTouchNode.register(audioContext, soundTouchProcessorUrl);
    const pitchShift = new SoundTouchNode({ context: audioContext });
    pitchShift.pitchSemitones.value = voicePitch;
    pitchShift.playbackRate.value = 1;
    const highpass = audioContext.createBiquadFilter();
    highpass.type = "highpass";
    highpass.frequency.value = 95;
    const lowpass = audioContext.createBiquadFilter();
    lowpass.type = "lowpass";
    lowpass.frequency.value = 5600;
    const lowerFormant = audioContext.createBiquadFilter();
    lowerFormant.type = "peaking";
    lowerFormant.frequency.value = 760;
    lowerFormant.Q.value = 1.1;
    lowerFormant.gain.value = 4;
    const upperFormant = audioContext.createBiquadFilter();
    upperFormant.type = "peaking";
    upperFormant.frequency.value = 2450;
    upperFormant.Q.value = 1.3;
    upperFormant.gain.value = -3;
    const shaper = audioContext.createWaveShaper();
    const curve = new Float32Array(1024);
    const normalizer = Math.tanh(1.35);
    for (let index = 0; index < curve.length; index += 1) {
      const value = (index / (curve.length - 1)) * 2 - 1;
      curve[index] = Math.tanh(value * 1.35) / normalizer;
    }
    shaper.curve = curve;
    shaper.oversample = "2x";
    const compressor = audioContext.createDynamicsCompressor();
    compressor.threshold.value = -22;
    compressor.knee.value = 18;
    compressor.ratio.value = 3.5;
    compressor.attack.value = 0.005;
    compressor.release.value = 0.18;
    const outputGain = audioContext.createGain();
    outputGain.gain.value = 1.06;
    const preview = audioContext.createGain();
    preview.gain.value = 0;

    source.connect(pitchShift);
    pitchShift.connect(highpass);
    highpass.connect(lowerFormant);
    lowerFormant.connect(upperFormant);
    upperFormant.connect(lowpass);
    lowpass.connect(shaper);
    shaper.connect(compressor);
    compressor.connect(outputGain);
    outputGain.connect(preview);
    preview.connect(audioContext.destination);

    const graph = { output: outputGain, preview, pitchShift };
    voiceAudioGraphRef.current = graph;
    return { audioContext, graph };
  };

  const routeAudioPreview = (mode: AudioMode, audioContext = audioContextRef.current) => {
    if (!audioContext) return;
    const now = audioContext.currentTime;
    const monitor = audioMonitorRef.current;
    const voicePreview = voiceAudioGraphRef.current?.preview;
    monitor?.gain.setTargetAtTime(mode === "original" ? 1 : 0, now, 0.01);
    voicePreview?.gain.setTargetAtTime(mode === "voice" ? 1 : 0, now, 0.01);
  };

  const updateVoicePitch = (value: number) => {
    setVoicePitch(value);
    const audioContext = audioContextRef.current;
    const graph = voiceAudioGraphRef.current;
    if (!audioContext || !graph) return;
    const now = audioContext.currentTime;
    graph.pitchShift.pitchSemitones.setTargetAtTime(value, now, 0.025);
  };

  const selectAudioMode = async (mode: AudioMode) => {
    setAudioMode(mode);
    const video = videoRef.current;
    if (video) video.muted = mode === "mute";
    try {
      if (mode === "voice" && video) {
        const { audioContext } = await ensureVoiceAudioGraph(video);
        routeAudioPreview(mode, audioContext);
      } else {
        routeAudioPreview(mode);
      }
    } catch (error) {
      console.error("Failed to initialize voice preview", error);
      setAudioMode("original");
      if (video) video.muted = false;
      routeAudioPreview("original");
      setMessage("当前浏览器无法实时预览变音，请选择保留原声或静音");
    }
  };

  const createVoiceExportTrack = async (video: HTMLVideoElement) => {
    const { audioContext, graph } = await ensureVoiceAudioGraph(video);
    routeAudioPreview("voice", audioContext);
    const destination = audioContext.createMediaStreamDestination();
    graph.output.connect(destination);

    const track = destination.stream.getAudioTracks()[0];
    if (!track) throw new Error("VOICE_TRACK_UNAVAILABLE");
    return {
      track,
      cleanup: () => {
        try { graph.output.disconnect(destination); } catch { /* already disconnected */ }
        track.stop();
      },
    };
  };

  const reset = () => {
    videoRef.current?.pause();
    cancelAnimationFrame(animationRef.current);
    if (videoUrl) URL.revokeObjectURL(videoUrl);
    if (downloadUrl) URL.revokeObjectURL(downloadUrl);
    setFile(null);
    setVideoUrl("");
    setDownloadUrl("");
    setIsPlaying(false);
    setProgress(0);
    setEtaSeconds(null);
    setEstimatedHighSeconds(null);
    setHighLoadRequested(false);
    setMessage("");
    detectionsRef.current = [];
    segmentationRef.current = null;
    tracksRef.current.clear();
    knownSubjectIdsRef.current.clear();
    trackCounterRef.current = { person: 0, vehicle: 0, pet: 0 };
    trackingFrameRef.current = 0;
    lastInferenceErrorRef.current = 0;
    setSubjects([]);
    setSelectedSubjectIds(new Set());
    void audioContextRef.current?.close();
    audioContextRef.current = null;
    audioSourceRef.current = null;
    audioMonitorRef.current = null;
    voiceAudioGraphRef.current = null;
  };

  const exportOffline = async () => {
    const previewVideo = videoRef.current;
    if (!file || !bodyPixRef.current || !modelRef.current || !previewVideo) return;
    if (!("VideoEncoder" in window) || !("VideoDecoder" in window)) {
      setMessage("当前浏览器不支持硬件逐帧编码，请使用最新版 Chrome、Edge 或切换快速模式");
      return;
    }

    setMessage("正在确认 YOLO WebGPU 实例分割模型…");
    try {
      await loadPreciseModel();
    } catch {
      setMessage("高精度模型加载失败，请检查网络或切换中档");
      return;
    }

    setExporting(true);
    setDownloadUrl("");
    setProgress(0);
    setEtaSeconds(null);
    setMessage("正在逐帧识别和编码；请勿锁屏、切换应用或关闭页面");
    previewVideo.pause();
    cancelAnimationFrame(animationRef.current);
    setIsPlaying(false);
    tracksRef.current.clear();
    trackCounterRef.current = { person: 0, vehicle: 0, pet: 0 };
    trackingFrameRef.current = 0;

    const startedAt = performance.now();
    try {
      const media = await import("mediabunny");
      const input = new media.Input({ formats: media.ALL_FORMATS, source: new media.BlobSource(file) });
      const videoTrack = await input.getPrimaryVideoTrack();
      if (!videoTrack) throw new Error("NO_VIDEO_TRACK");
      const audioTrack = await input.getPrimaryAudioTrack();
      const audioDuration = audioTrack ? await input.computeDuration([audioTrack]) : 0;
      const SoundTouchConstructor = audioMode === "voice" && audioTrack
        ? (await import("@soundtouchjs/core")).SoundTouch
        : null;
      const width = await videoTrack.getDisplayWidth();
      const height = await videoTrack.getDisplayHeight();
      const outputFormat = new media.Mp4OutputFormat();
      const codec = await media.getFirstEncodableVideoCodec(outputFormat.getSupportedVideoCodecs(), {
        width,
        height,
        bitrate: media.QUALITY_HIGH,
      });
      if (!codec) throw new Error("NO_VIDEO_ENCODER");

      const target = new media.BufferTarget();
      const output = new media.Output({ format: outputFormat, target });
      const sourceCanvas = document.createElement("canvas");
      const outputCanvas = document.createElement("canvas");
      sourceCanvas.width = width;
      sourceCanvas.height = height;
      outputCanvas.width = width;
      outputCanvas.height = height;
      const sourceCtx = sourceCanvas.getContext("2d", { alpha: false });
      if (!sourceCtx) throw new Error("NO_CANVAS_CONTEXT");

      let voicePreviousInput: number[] = [];
      let voicePreviousHighpass: number[] = [];
      let voicePreviousLowpass: number[] = [];
      let voiceLowerFormantState: BiquadState[] = [];
      let voiceUpperFormantState: BiquadState[] = [];
      let voicePitchProcessor: import("@soundtouchjs/core").SoundTouch | null = null;
      let voiceOutputFrames = 0;
      let voiceTimestampBase: number | null = null;
      let voiceSampleRate = 0;
      let voiceChannelCount = 0;

      let frameNumber = 0;
      let processingLock: Promise<void> = Promise.resolve();
      const runInOrder = <T,>(task: () => Promise<T>) => {
        const result = processingLock.then(task, task);
        processingLock = result.then(() => undefined, () => undefined);
        return result;
      };

      const conversion = await media.Conversion.init({
        input,
        output,
        tracks: "primary",
        video: {
          codec,
          bitrate: media.QUALITY_HIGH,
          hardwareAcceleration: "prefer-hardware",
          forceTranscode: true,
          keyFrameInterval: 2,
          process: (sample) => runInOrder(async () => {
            sourceCtx.clearRect(0, 0, width, height);
            sample.draw(sourceCtx, 0, 0, width, height);
            const results = await segmentWithYolo(sourceCanvas, width, height);
            applyYoloResults(results, sourceCanvas, false, false);
            renderProcessedFrame(sourceCanvas, outputCanvas, width, height);
            frameNumber += 1;
            if (frameNumber % 12 === 0) {
              setDetectedCount(detectionsRef.current.filter((item) => item.score > 0.36 && isSelectedDetection(item)).length);
            }
            return new media.VideoSample(outputCanvas, {
              timestamp: sample.timestamp,
              duration: sample.duration,
            });
          }),
        },
        audio: audioMode === "mute" ? { discard: true } : audioMode === "voice" ? {
          sampleFormat: "f32",
          forceTranscode: true,
          process: (sample) => {
            const channels = sample.numberOfChannels;
            const inputData = new Float32Array(sample.numberOfFrames * channels);
            sample.copyTo(inputData, { planeIndex: 0, format: "f32" });
            if (!SoundTouchConstructor) return sample;
            if (!voicePitchProcessor || voiceSampleRate !== sample.sampleRate || voiceChannelCount !== channels) {
              voicePitchProcessor = new SoundTouchConstructor({ sampleRate: sample.sampleRate });
              voicePitchProcessor.pitchSemitones = voicePitch;
              voiceOutputFrames = 0;
              voiceTimestampBase = sample.timestamp;
              voiceSampleRate = sample.sampleRate;
              voiceChannelCount = channels;
              voicePreviousInput = Array(channels).fill(0);
              voicePreviousHighpass = Array(channels).fill(0);
              voicePreviousLowpass = Array(channels).fill(0);
              voiceLowerFormantState = Array.from({ length: channels }, () => ({ x1: 0, x2: 0, y1: 0, y2: 0 }));
              voiceUpperFormantState = Array.from({ length: channels }, () => ({ x1: 0, x2: 0, y1: 0, y2: 0 }));
            }

            const stereoInput = new Float32Array(sample.numberOfFrames * 2);
            for (let frame = 0; frame < sample.numberOfFrames; frame += 1) {
              stereoInput[frame * 2] = inputData[frame * channels];
              stereoInput[frame * 2 + 1] = channels > 1 ? inputData[frame * channels + 1] : inputData[frame * channels];
            }
            voicePitchProcessor.inputBuffer.putSamples(stereoInput, 0, sample.numberOfFrames);
            voicePitchProcessor.process();

            const isLastSample = sample.timestamp + sample.duration >= audioDuration - 0.01;
            const expectedFrames = Math.max(0, Math.round((audioDuration - (voiceTimestampBase ?? 0)) * sample.sampleRate));
            if (isLastSample) {
              for (let attempt = 0; attempt < 8 && voiceOutputFrames + voicePitchProcessor.outputBuffer.frameCount < expectedFrames; attempt += 1) {
                const silenceFrames = 8192;
                voicePitchProcessor.inputBuffer.putSamples(new Float32Array(silenceFrames * 2), 0, silenceFrames);
                voicePitchProcessor.process();
              }
            }

            const remainingFrames = isLastSample
              ? Math.max(0, expectedFrames - voiceOutputFrames)
              : voicePitchProcessor.outputBuffer.frameCount;
            const outputFrames = Math.min(voicePitchProcessor.outputBuffer.frameCount, remainingFrames);
            if (outputFrames === 0) return null;
            const stereoOutput = new Float32Array(outputFrames * 2);
            voicePitchProcessor.outputBuffer.extract(stereoOutput, 0, outputFrames);
            voicePitchProcessor.outputBuffer.receive(outputFrames);
            const data = new Float32Array(outputFrames * channels);
            for (let frame = 0; frame < outputFrames; frame += 1) {
              for (let channel = 0; channel < channels; channel += 1) {
                data[frame * channels + channel] = stereoOutput[frame * 2 + Math.min(channel, 1)];
              }
            }

            const highpassAlpha = Math.exp((-2 * Math.PI * 95) / sample.sampleRate);
            const lowpassAlpha = 1 - Math.exp((-2 * Math.PI * 5600) / sample.sampleRate);
            const saturationNormalizer = Math.tanh(1.35);
            const lowerFormantCoefficients = getPeakingCoefficients(760, sample.sampleRate, 1.1, 4);
            const upperFormantCoefficients = getPeakingCoefficients(2450, sample.sampleRate, 1.3, -3);
            for (let frame = 0; frame < outputFrames; frame += 1) {
              for (let channel = 0; channel < channels; channel += 1) {
                const index = frame * channels + channel;
                const inputValue = data[index];
                const highpassed = highpassAlpha * (voicePreviousHighpass[channel] + inputValue - voicePreviousInput[channel]);
                const lowerFormant = applyBiquad(highpassed, voiceLowerFormantState[channel], lowerFormantCoefficients);
                const upperFormant = applyBiquad(lowerFormant, voiceUpperFormantState[channel], upperFormantCoefficients);
                const lowpassed = voicePreviousLowpass[channel] + lowpassAlpha * (upperFormant - voicePreviousLowpass[channel]);
                voicePreviousInput[channel] = inputValue;
                voicePreviousHighpass[channel] = highpassed;
                voicePreviousLowpass[channel] = lowpassed;
                const shaped = Math.tanh(lowpassed * 1.35) / saturationNormalizer;
                data[index] = Math.tanh(shaped * 1.08) * 0.94;
              }
            }
            const outputTimestamp = (voiceTimestampBase ?? sample.timestamp) + voiceOutputFrames / sample.sampleRate;
            voiceOutputFrames += outputFrames;
            return new media.AudioSample({
              data,
              format: "f32",
              numberOfChannels: channels,
              sampleRate: sample.sampleRate,
              timestamp: outputTimestamp,
            });
          },
        } : undefined,
        showWarnings: false,
      });

      if (!conversion.isValid) throw new Error("UNSUPPORTED_CONVERSION");
      offlineConversionRef.current = conversion;
      exportStopRef.current = () => { void conversion.cancel(); };
      conversion.onProgress = (value, processedTime) => {
        const normalized = Math.max(0, Math.min(1, value));
        setProgress(normalized * 100);
        setCurrentTime(processedTime);
        if (normalized > 0.025) {
          const elapsed = (performance.now() - startedAt) / 1000;
          setEtaSeconds(Math.max(0, (elapsed / normalized) - elapsed));
        }
      };
      await conversion.execute();
      if (!target.buffer) throw new Error("EMPTY_OUTPUT");
      const blob = new Blob([target.buffer], { type: "video/mp4" });
      setOutputExtension("mp4");
      setDownloadUrl(URL.createObjectURL(blob));
      setProgress(100);
      setMessage("逐帧处理完成：每一帧都已等待遮罩生成后再编码");
      previewVideo.currentTime = 0;
      drawFrame();
    } catch (error) {
      const wasCanceled = error instanceof Error && error.name === "ConversionCanceledError";
      setProgress(0);
      setMessage(wasCanceled ? "已停止逐帧处理" : "逐帧处理失败；可尝试最新版 Chrome 或切换快速模式");
    } finally {
      offlineConversionRef.current = null;
      exportStopRef.current = null;
      setEtaSeconds(null);
      setExporting(false);
    }
  };

  const exportVideo = async () => {
    const video = videoRef.current;
    const canvas = canvasRef.current;
    if (!video || !canvas) return;
    if (maskScope !== "full" && (!modelRef.current || selected.size === 0)) return;
    if (quality === "precise" && maskScope !== "full") {
      await exportOffline();
      return;
    }
    if (!("MediaRecorder" in window) || !canvas.captureStream) {
      setMessage("当前浏览器暂不支持导出，请使用最新版 Chrome 或 Edge");
      return;
    }
    let voiceTrack: MediaStreamTrack | null = null;
    let cleanupVoiceTrack: (() => void) | null = null;
    if (audioMode === "voice") {
      try {
        const voiceOutput = await createVoiceExportTrack(video);
        voiceTrack = voiceOutput.track;
        cleanupVoiceTrack = voiceOutput.cleanup;
      } catch (error) {
        console.error("Failed to initialize local voice filter", error);
        setMessage("当前浏览器无法初始化隐私变音；请选择保留原声或静音");
        return;
      }
    }
    setExporting(true);
    setDownloadUrl("");
    setProgress(0);
    setMessage("正在本地逐帧处理，请保持页面开启");
    video.loop = false;
    video.pause();
    if (video.currentTime > 0.01) {
      video.currentTime = 0;
      await new Promise((resolve) => video.addEventListener("seeked", resolve, { once: true }));
    }

    const canvasStream = canvas.captureStream(30);
    const sourceStream = (video as HTMLVideoElement & { captureStream?: () => MediaStream }).captureStream?.();
    if (audioMode === "original") sourceStream?.getAudioTracks().forEach((track) => canvasStream.addTrack(track));
    if (voiceTrack) canvasStream.addTrack(voiceTrack);
    const mimeType = pickMimeType();
    const recorder = new MediaRecorder(canvasStream, mimeType ? { mimeType, videoBitsPerSecond: 6_000_000 } : undefined);
    const chunks: BlobPart[] = [];
    recorder.ondataavailable = (event) => event.data.size && chunks.push(event.data);
    recorder.onstop = () => {
      cleanupVoiceTrack?.();
      cleanupVoiceTrack = null;
      void (async () => {
        const recordedMime = mimeType || "video/webm";
        const recordedBlob = new Blob(chunks, { type: recordedMime });
        setMessage(recordedMime.startsWith("video/mp4") ? "正在写入 MP4 时长与播放索引…" : "正在本地生成 H.264/AAC MP4…");
        try {
          const finalized = await finalizeRecordedMedia(recordedBlob, recordedMime, (value) => setProgress(99 + value));
          setOutputExtension(finalized.extension);
          setDownloadUrl(URL.createObjectURL(finalized.blob));
          setMessage(finalized.extension === "mp4"
            ? `MP4 处理完成 · 时长 ${formatTime(finalized.duration)}`
            : `处理完成 · 当前设备无 H.264/AAC 编码器，已保留 WebM · ${formatTime(finalized.duration)}`);
        } catch (error) {
          console.error("Failed to finalize recorded video metadata", error);
          setOutputExtension(recordedMime.startsWith("video/mp4") ? "mp4" : "webm");
          setDownloadUrl(URL.createObjectURL(recordedBlob));
          setMessage("处理完成，但当前浏览器未能重写时长索引");
        } finally {
          setExporting(false);
          setProgress(100);
          video.currentTime = 0;
          video.loop = true;
          drawFrame();
        }
      })();
    };
    exportStopRef.current = () => {
      video.pause();
      if (recorder.state !== "inactive") recorder.stop();
    };
    video.onended = () => exportStopRef.current?.();
    video.ontimeupdate = () => setProgress(duration ? Math.min(99, (video.currentTime / duration) * 100) : 0);
    try {
      recorder.start(1000);
      await video.play();
    } catch (error) {
      console.error("Failed to start video export playback", error);
      cleanupVoiceTrack?.();
      cleanupVoiceTrack = null;
      recorder.onstop = null;
      if (recorder.state !== "inactive") recorder.stop();
      setExporting(false);
      video.loop = true;
      setMessage("无法开始视频播放，请重新打开视频后再试");
      return;
    }
    setIsPlaying(true);
    cancelAnimationFrame(animationRef.current);
    animationRef.current = requestAnimationFrame(renderLoop);
  };

  const fileBase = file?.name.replace(/\.[^.]+$/, "") || "privacy-video";
  const modelLoadingVisible = modelState === "loading" || (quality === "precise" && preciseModelState === "loading");
  const activeEffectStyle = maskScope === "full" ? fullFrameStyle : "blur";
  const strengthRange = activeEffectStyle === "blur"
    ? { min: 4, max: 64, unit: "px", label: "模糊半径" }
    : activeEffectStyle === "pixel"
      ? { min: 6, max: 48, unit: "px", label: "像素块大小" }
      : { min: 8, max: 30, unit: "px", label: "字符尺寸" };

  return (
    <main>
      <header className="site-header">
        <a className="brand" href="#top" aria-label="镜隐首页">
          <span className="brand-mark"><EyeOff size={20} strokeWidth={2.4} /></span>
          <span>镜隐</span>
        </a>
        <div className="local-badge"><LockKeyhole size={14} /> 本地处理 · 不上传</div>
      </header>

      <section className="hero" id="top">
        <div className="eyebrow"><Sparkles size={15} /> LOCAL-FIRST VIDEO PRIVACY</div>
        <h1>想分享生活，<br /><span>先把隐私藏好。</span></h1>
        <p>孩子的视频、家人的身影和清晰语音，都可能成为可被复制的身份素材。<br className="desktop-only" />镜隐在本机完成画面遮盖与声音处理，减少内容被截取、冒用或用于 AI 换脸与声音克隆的风险。</p>
        <div className="trust-row">
          <span><Check size={15} /> 无需注册</span>
          <span><Check size={15} /> 免费使用</span>
          <span><Check size={15} /> 视频不出设备</span>
        </div>
      </section>

      <section className={`studio ${file ? "has-video" : ""}`} aria-label="视频打码工作台">
        {!file ? (
          <button
            className="upload-zone"
            type="button"
            onClick={() => inputRef.current?.click()}
            onDragOver={(event) => event.preventDefault()}
            onDrop={(event) => { event.preventDefault(); void handleFile(event.dataTransfer.files[0]); }}
          >
            <span className="upload-icon"><Upload size={30} /></span>
            <strong>上传你的视频</strong>
            <span>点击选择，或将文件拖到这里</span>
            <span className="upload-button">选择视频 <ChevronRight size={17} /></span>
            <small>支持 MP4、MOV、WebM · 建议 500MB 以内</small>
          </button>
        ) : (
          <div className="workspace">
            <div className="preview-column">
              <div className="video-shell">
                <video
                  ref={videoRef}
                  crossOrigin="anonymous"
                  src={videoUrl}
                  muted={audioMode === "mute"}
                  loop={!exporting}
                  playsInline
                  preload="metadata"
                  onLoadedMetadata={(event) => {
                    setDuration(event.currentTarget.duration);
                    event.currentTarget.currentTime = Math.min(0.01, event.currentTarget.duration);
                  }}
                  onLoadedData={(event) => {
                    const video = event.currentTarget;
                    if (scopeRef.current === "full") drawFrame();
                    else void loadModel().then(() => analyzeCurrentFrame(video)).catch(handleInferenceError);
                  }}
                  onSeeked={() => drawFrame()}
                  onPause={() => setIsPlaying(false)}
                  aria-label="原始视频（隐藏显示）"
                />
                <canvas ref={canvasRef} aria-label="隐私打码预览" />
                <button className="video-close-mobile" type="button" onClick={reset} disabled={exporting} aria-label="移除视频"><X size={18} /></button>
                {modelLoadingVisible && maskScope !== "full" && (
                  <div className="model-loading">
                    <span />
                    {modelState === "loading"
                      ? "首次加载基础模型…"
                      : preciseLoadProgress?.stage === "download"
                        ? `下载轻量模型 ${preciseLoadProgress.percent}%`
                        : preciseLoadProgress?.stage === "compile"
                          ? "下载完成 · 编译 WebGPU…"
                          : preciseLoadProgress?.stage === "warmup"
                            ? "编译完成 · 首次预热…"
                            : "准备 YOLO WebGPU…"}
                  </div>
                )}
                {detectedCount > 0 && !modelLoadingVisible && maskScope !== "full" && <div className="detect-pill"><span /> {maskScope === "background" ? `已保留 ${detectedCount} 个主体` : `已遮挡 ${detectedCount} 个实体`}</div>}
              </div>
              <div className="player-controls">
                <button type="button" className="play-button" onClick={togglePlayback} aria-label={isPlaying ? "暂停" : "播放"}>
                  {isPlaying ? <Pause size={18} fill="currentColor" /> : <Play size={18} fill="currentColor" />}
                </button>
                <span>{formatTime(currentTime)}</span>
                <input aria-label="视频进度" type="range" min="0" max={duration || 0} step="0.01" value={Math.min(currentTime, duration || 0)} onChange={(event) => seek(Number(event.target.value))} />
                <span>{formatTime(duration)}</span>
              </div>
            </div>

            <aside className="settings-panel">
              <div className="settings-toolbar">
                <button className="desktop-close" type="button" onClick={reset} disabled={exporting} aria-label="移除视频"><X size={19} /></button>
              </div>
              <div className="control-block">
                <div className="control-title"><span>遮盖范围</span><small>{maskScope === "background" ? "反选已开启" : maskScope === "full" ? "无需 AI 识别" : "常规"}</small></div>
                <div className="segmented-control scope-control" aria-label="遮盖范围">
                  <button type="button" disabled={exporting} className={maskScope === "full" ? "active" : ""} aria-pressed={maskScope === "full"} onClick={() => { if (maskScope !== "full") setEffectStrength(fullFrameStyle === "blur" ? 46 : fullFrameStyle === "pixel" ? 18 : 14); setMaskScope("full"); }}>全画面</button>
                  <button type="button" disabled={exporting} className={maskScope === "subjects" ? "active" : ""} aria-pressed={maskScope === "subjects"} onClick={() => { if (maskScope === "full" && fullFrameStyle !== "blur") setEffectStrength(46); setMaskScope("subjects"); void loadModel().then(() => videoRef.current ? analyzeCurrentFrame(videoRef.current) : undefined).catch(handleInferenceError); }}>遮盖主体</button>
                  <button type="button" disabled={exporting} className={maskScope === "background" ? "active" : ""} aria-pressed={maskScope === "background"} onClick={() => { if (maskScope === "full" && fullFrameStyle !== "blur") setEffectStrength(46); setMaskScope("background"); void loadModel().then(() => videoRef.current ? analyzeCurrentFrame(videoRef.current) : undefined).catch(handleInferenceError); }}>遮盖主体之外</button>
                </div>
              </div>

              {maskScope !== "full" && (
                <div className="settings-tabs" role="tablist" aria-label="设置分类">
                  <button type="button" role="tab" aria-selected={settingsTab === "general"} className={settingsTab === "general" ? "active" : ""} onClick={() => setSettingsTab("general")}>通用设置</button>
                  <button type="button" role="tab" aria-selected={settingsTab === "subjects"} className={settingsTab === "subjects" ? "active" : ""} onClick={() => setSettingsTab("subjects")}>选择主体</button>
                </div>
              )}

              {maskScope === "full" ? (
                <div className="control-block effect-control">
                  <div className="control-title"><span>全画面风格</span><small>{fullFrameStyle === "ascii" ? `黑白字符画 · ${effectStrength}px` : `${strengthRange.label} ${effectStrength}${strengthRange.unit}`}</small></div>
                  <div className="segmented-control effect-style-control" aria-label="全画面风格">
                    <button type="button" disabled={exporting} className={fullFrameStyle === "blur" ? "active" : ""} aria-pressed={fullFrameStyle === "blur"} onClick={() => { setFullFrameStyle("blur"); setEffectStrength(46); }}>模糊</button>
                    <button type="button" disabled={exporting} className={fullFrameStyle === "pixel" ? "active" : ""} aria-pressed={fullFrameStyle === "pixel"} onClick={() => { setFullFrameStyle("pixel"); setEffectStrength(18); }}>低像素</button>
                    <button type="button" disabled={exporting} className={fullFrameStyle === "ascii" ? "active" : ""} aria-pressed={fullFrameStyle === "ascii"} onClick={() => { setFullFrameStyle("ascii"); setEffectStrength(14); }}>ASCII</button>
                  </div>
                  <div className="strength-slider">
                    <span>{strengthRange.min}</span>
                    <input aria-label={strengthRange.label} type="range" min={strengthRange.min} max={strengthRange.max} step="1" value={Math.max(strengthRange.min, Math.min(strengthRange.max, effectStrength))} disabled={exporting} onChange={(event) => setEffectStrength(Number(event.target.value))} />
                    <span>{strengthRange.max}</span>
                  </div>
                </div>
              ) : <>
                {settingsTab === "general" && <>
                <div className="control-block">
                  <div className="control-title"><span>处理精度</span><small>{quality === "precise" ? "逐帧最稳" : quality === "balanced" ? "轮廓实时" : "轻量人形"}</small></div>
                  <div className="segmented-control quality-control" aria-label="处理精度">
                    <button type="button" disabled={exporting} className={quality === "fast" ? "active" : ""} aria-pressed={quality === "fast"} onClick={() => setQuality("fast")}>低 <small>省性能</small></button>
                    <button type="button" disabled={exporting} className={quality === "balanced" ? "active" : ""} aria-pressed={quality === "balanced"} onClick={() => setQuality("balanced")}>中 <small>轮廓</small></button>
                    <button type="button" disabled={exporting} className={quality === "precise" ? "active" : ""} aria-pressed={quality === "precise"} onClick={() => {
                      if (!supportsPreciseWebMode()) {
                        setMessage("为避免手机页面卡死和严重发热，网页高档仅支持桌面 WebGPU；手机请选择中档或使用 App");
                        return;
                      }
                      setQuality("precise");
                      if (preciseModelState !== "ready") setMessage("高档模型约 11MB；桌面浏览器首次编译可能短暂停顿，请确认后再加载");
                    }}>高 <small>桌面</small></button>
                  </div>
                </div>
                {quality === "precise" && (
                  <div className="offline-notice">
                    <strong>网页高档 · YOLO 实例轮廓</strong>
                    <span>统一识别人、宠物与车辆，使用 WebGPU 逐帧生成独立轮廓。{preciseModelState === "ready" ? (estimatedHighSeconds === null ? "模型已就绪，正在测速。" : `本机预计约 ${formatTime(estimatedHighSeconds)} 完成。`) : "为避免手机刚切换档位就卡住，模型不会自动加载。"}</span>
                    {(preciseModelState === "idle" || preciseModelState === "error") && (
                      <button className="high-model-trigger" type="button" disabled={modelState !== "ready" || highLoadRequested} onClick={() => {
                        setMessage("即将初始化高档 WebGPU 模型；手机页面可能短暂停顿，请勿切换应用");
                        setHighLoadRequested(true);
                      }}>{preciseModelState === "error" ? "重新加载高档模型" : "确认加载高档模型"}</button>
                    )}
                    {estimatedHighSeconds !== null && estimatedHighSeconds > 360 && <span className="estimate-warning">本机预计超过 6 分钟，已停用高档；请选择中档或等待 App 超精细版。</span>}
                  </div>
                )}
                <div className="control-block effect-control">
                  <div className="control-title"><span>模糊强度</span><small>模糊半径 {effectStrength}px</small></div>
                  <div className="strength-slider">
                    <span>4</span>
                    <input aria-label="模糊半径" type="range" min="4" max="64" step="1" value={Math.max(4, Math.min(64, effectStrength))} disabled={exporting} onChange={(event) => setEffectStrength(Number(event.target.value))} />
                    <span>64</span>
                  </div>
                </div>
                <div className="watermark-note"><LockKeyhole size={14} /><span><strong>网页版默认添加右下角水印</strong><small>后续可通过广告权益或一次买断移除；当前版本暂不提供付费入口。</small></span></div>
                </>}
              </>}
              {(maskScope === "full" || settingsTab === "general") && (
                <div className="control-block audio-privacy-control">
                  <div className="control-title"><span>声音处理</span><small>{audioMode === "voice" ? `音调 ${voicePitch > 0 ? "+" : ""}${voicePitch} 半音` : audioMode === "mute" ? "导出无音轨" : "保留视频原声"}</small></div>
                  <div className="segmented-control audio-mode-control" aria-label="声音隐私">
                    <button type="button" disabled={exporting} className={audioMode === "original" ? "active" : ""} aria-pressed={audioMode === "original"} onClick={() => { void selectAudioMode("original"); }}>原声 <small>保留</small></button>
                    <button type="button" disabled={exporting} className={audioMode === "voice" ? "active" : ""} aria-pressed={audioMode === "voice"} onClick={() => { void selectAudioMode("voice"); }}>变音 <small>音调偏移</small></button>
                    <button type="button" disabled={exporting} className={audioMode === "mute" ? "active" : ""} aria-pressed={audioMode === "mute"} onClick={() => { void selectAudioMode("mute"); }}>静音 <small>无音轨</small></button>
                  </div>
                  {audioMode === "voice" && (
                    <div className="strength-slider voice-pitch-slider">
                      <span>低</span>
                      <input aria-label="变声音调" type="range" min="-8" max="8" step="1" value={voicePitch} disabled={exporting} onChange={(event) => updateVoicePitch(Number(event.target.value))} />
                      <span>高</span>
                    </div>
                  )}
                  <p className="audio-mode-note">真正改变音调，不改变语速；播放时拖动可实时试听。</p>
                </div>
              )}
              {settingsTab === "subjects" && maskScope !== "full" && <>
                <div className="entity-heading"><span>{maskScope === "background" ? "选择要保留清晰的主体" : "选择要遮盖的主体"}</span><small>可多选</small></div>
                <div className="entity-list">
                {ENTITY_GROUPS.map((group) => {
                  const active = selected.has(group.key);
                  return (
                    <button
                      type="button"
                      disabled={exporting}
                      className={`entity-option ${active ? "active" : ""}`}
                      key={group.key}
                      aria-pressed={active}
                      onClick={() => setSelected((previous) => {
                        const next = new Set(previous);
                        if (next.has(group.key)) next.delete(group.key); else next.add(group.key);
                        return next;
                      })}
                    >
                      <span className="entity-icon">{group.key === "person" ? "人" : group.key === "vehicle" ? "车" : "宠"}</span>
                      <span><strong>{group.label}</strong><small>{group.sub}</small></span>
                      <span className="check-box">{active && <Check size={15} />}</span>
                    </button>
                  );
                })}
                </div>
                <div className="subject-heading">
                <span>当前画面识别到的主体</span><small>{subjects.length ? `${subjects.length} 个` : "等待识别"}</small>
                </div>
              {subjects.length > 0 ? (
                <div className="subject-grid">
                  {subjects.map((subject) => {
                    const active = selectedSubjectIds.has(subject.id) && selected.has(subject.key);
                    return (
                      <button
                        type="button"
                        key={subject.id}
                        disabled={exporting || !selected.has(subject.key)}
                        className={`subject-chip ${active ? "active" : ""}`}
                        aria-pressed={active}
                        onClick={() => setSelectedSubjectIds((previous) => {
                          const next = new Set(previous);
                          if (next.has(subject.id)) next.delete(subject.id); else next.add(subject.id);
                          return next;
                        })}
                      >
                        <img src={subject.thumbnail} alt="" />
                        <span>{subject.label}</span>
                        <span className="check-box">{active && <Check size={13} />}</span>
                      </button>
                    );
                  })}
                </div>
              ) : <p className="subject-empty">加载后会在这里列出人物、车辆和宠物，可逐个勾选。</p>}
                <p className="tracking-note">主体编号由本地跟踪生成；多人交叉遮挡或离开后重新出现时，可能生成新编号。</p>
              </>}
              {settingsTab === "subjects" && maskScope !== "full" && <>
              <div className="coming-soon"><span>人脸与车牌</span><small>精细识别模型 · 即将支持</small></div>
              <div className="app-upsell" id="app-preview">
                <span className="app-kicker">NATIVE APP · ULTRA</span>
                <strong>超精细视频遮罩，交给原生 App</strong>
                <small>原生 GPU/NPU 推理、硬件编解码和时序跟踪，更适合长视频、4K 与低耗电处理。</small>
                <button type="button" onClick={() => setMessage("App 超精细版正在规划中，网页端会继续保持免费的性能平衡模式")}>查看 App 版计划</button>
              </div>
              </>}
              <div className="privacy-note"><ShieldCheck size={18} /><span><strong>只在你的浏览器中运行</strong><small>原视频和处理结果都不会上传。</small></span></div>
              {exporting ? (
                <div className="export-progress">
                  <div><span>{quality === "precise" ? "正在逐帧分析与编码" : "正在处理视频"}</span><strong>{Math.round(progress)}%</strong></div>
                  <div className="progress-track"><span style={{ width: `${progress}%` }} /></div>
                  {quality === "precise" && <p>{etaSeconds === null ? "正在估算剩余时间…" : `预计还需约 ${formatTime(etaSeconds)}`}</p>}
                  <button type="button" onClick={() => exportStopRef.current?.()}>停止处理</button>
                </div>
              ) : downloadUrl ? (
                <a className="primary-action success" href={downloadUrl} download={`${fileBase}-已打码.${outputExtension}`}>
                  <ArrowDownToLine size={19} /> 下载处理后的视频
                </a>
              ) : (
                <button className="primary-action" type="button" disabled={maskScope !== "full" && (modelState !== "ready" || selected.size === 0 || (quality === "precise" && (preciseModelState !== "ready" || (estimatedHighSeconds !== null && estimatedHighSeconds > 360))))} onClick={exportVideo}>
                  {maskScope === "full" ? "开始全画面处理" : modelState === "loading" ? "AI 准备中…" : quality === "precise" && preciseModelState !== "ready" ? "请先确认加载高档模型" : quality === "precise" && estimatedHighSeconds !== null && estimatedHighSeconds > 360 ? "本机较慢 · 建议 App" : quality === "precise" ? "开始逐帧处理" : "开始快速处理"} <ChevronRight size={18} />
                </button>
              )}
              {message && !(maskScope === "full" && /(AI|模型|识别)/.test(message)) && <p className={`status-message ${modelState === "error" ? "error" : ""}`}>{message}</p>}
            </aside>
          </div>
        )}
        <input ref={inputRef} className="visually-hidden" type="file" accept="video/mp4,video/quicktime,video/webm" onChange={(event) => void handleFile(event.target.files?.[0])} />
      </section>

      <section className="privacy-scenarios" aria-labelledby="privacy-scenarios-title">
        <div className="privacy-scenarios-intro">
          <div className="section-label">BEFORE YOU SHARE</div>
          <h2 id="privacy-scenarios-title">不是不分享，<br />是分享前先保护好。</h2>
          <p>照片和视频一旦公开，就可能被保存、裁剪和再次传播。先遮住不需要出现的主体或环境，让分享保留快乐，不留下多余的身份线索。</p>
          <div className="local-proof"><ShieldCheck size={17} /><span><strong>视频不上传</strong><small>识别、遮盖和导出都在当前设备完成</small></span></div>
        </div>
        <div className="scenario-grid">
          <article>
            <span className="scenario-icon"><Baby /></span>
            <div><h3>分享孩子的成长</h3><p>公开发布前隐藏孩子、同伴或旁观者，减少清晰人像在未知渠道中继续流传。</p><small>适合：遮盖主体</small></div>
          </article>
          <article>
            <span className="scenario-icon"><ScanFace /></span>
            <div><h3>降低 AI 换脸与声音克隆风险</h3><p>高质量正脸、连续动作和清晰语音都可能成为可复用素材，可同时模糊人物并变音或静音。</p><small>适合：遮盖主体 + 声音处理</small></div>
          </article>
          <article>
            <span className="scenario-icon"><MapPin /></span>
            <div><h3>不暴露生活环境</h3><p>家庭陈设、学校周边、常走路线都可能透露位置和生活规律，可反选主体，只遮盖环境。</p><small>适合：遮盖主体之外</small></div>
          </article>
          <article>
            <span className="scenario-icon"><Users /></span>
            <div><h3>避免路人和家人被公开</h3><p>聚会、旅行和街拍里常有无关人员入镜。发布前处理，让没有同意出镜的人保持匿名。</p><small>适合：选择主体</small></div>
          </article>
        </div>
      </section>

      <section className="how-it-works" aria-labelledby="how-title">
        <div className="section-label">HOW IT WORKS</div>
        <h2 id="how-title">三步，保护每一帧。</h2>
        <div className="steps">
          <article><span>01</span><div className="step-icon"><FileVideo /></div><h3>上传视频</h3><p>从手机或电脑选择视频，文件只在本机打开。</p></article>
          <article><span>02</span><div className="step-icon"><EyeOff /></div><h3>设置隐私处理</h3><p>选择画面遮盖范围，并决定保留原声、变音或静音。</p></article>
          <article><span>03</span><div className="step-icon"><ArrowDownToLine /></div><h3>下载结果</h3><p>浏览器逐帧完成处理，然后直接保存到设备。</p></article>
        </div>
      </section>

      <section className="privacy-banner">
        <div className="shield-large"><ShieldCheck /></div>
        <div><span>PRIVACY BY DESIGN</span><h2>你的视频，始终是你的。</h2><p>没有上传、没有云端副本、没有账号。关闭页面后，本次数据随即消失。</p></div>
      </section>

      <footer>
        <a className="brand" href="#top"><span className="brand-mark"><EyeOff size={18} /></span><span>镜隐</span></a>
        <p>浏览器里的视频隐私保护工具</p>
        <button type="button" onClick={() => { reset(); inputRef.current?.click(); }}><RotateCcw size={15} /> 处理一个新视频</button>
      </footer>
    </main>
  );
}
