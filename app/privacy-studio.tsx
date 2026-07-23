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
import { useLocale } from "./i18n/locale";
import { ENTITY_CLASS_GROUPS, entityKeyForClass, getStudioCopy, type EntityKey } from "./i18n/studio-copy";

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
  const { locale, setLocale } = useLocale();
  const copy = getStudioCopy(locale);
  const msg = copy.msg;

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

  const watermarkTextRef = useRef("LensHide · PRIVACY");

  useEffect(() => {
    watermarkTextRef.current = `${copy.brand} · PRIVACY`;
  }, [copy.brand]);

  const isSelectedClass = useCallback((className: string) => {
    return ENTITY_CLASS_GROUPS.some((group) => selectedRef.current.has(group.key) && group.classes.includes(className));
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
    setMessage(securityError ? msg.inferenceSecurity : msg.inferenceFailed);
  }, [msg.inferenceFailed, msg.inferenceSecurity]);

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
      const entityLabel = copy.entities[key]?.label || copy.entityFallback;
      const label = `${entityLabel} ${number}`;
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
  }, [copy.entities, copy.entityFallback]);

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
    const watermarkText = watermarkTextRef.current;
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
        if (nextProgress.stage === "download") setMessage(msg.yoloDownload(nextProgress.percent));
        if (nextProgress.stage === "compile") setMessage(msg.yoloCompile);
        if (nextProgress.stage === "warmup") setMessage(msg.yoloWarmup);
      });
      setPreciseModelState("ready");
      return model;
    } catch (error) {
      console.error("YOLO WebGPU initialization failed", error);
      setPreciseModelState("error");
      throw error;
    }
  }, [msg.yoloCompile, msg.yoloDownload, msg.yoloWarmup]);

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
    setMessage(msg.yoloBackgroundLoad);
    void loadPreciseModel()
      .then(() => {
        setHighLoadRequested(false);
        setMessage(supportsWebGpu() ? msg.yoloReadyWebGpu : msg.yoloReadyCompat);
      })
      .catch((error) => {
        setHighLoadRequested(false);
        const code = error instanceof Error ? error.message : "";
        if (code === "MOBILE_WEBGPU_DISABLED") setMessage(msg.mobileWebGpuDisabled);
        else if (code === "WEBGPU_REQUIRED") setMessage(msg.webGpuRequired);
        else if (code.includes("TIMEOUT")) setMessage(msg.webGpuTimeout);
        else setMessage(msg.yoloInitFailed);
      });
  }, [highLoadRequested, loadPreciseModel, modelState, msg, preciseModelState, quality]);

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
    setMessage(msg.aiLoading);
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
      setMessage(msg.subjectsIdentified);
    } catch {
      setModelState("error");
      setMessage(msg.aiLoadFailed);
    }
  }, [analyzeCurrentFrame, msg.aiLoadFailed, msg.aiLoading, msg.subjectsIdentified]);

  const handleFile = async (nextFile?: File) => {
    if (!nextFile) return;
    if (!nextFile.type.startsWith("video/")) {
      setMessage(msg.invalidFormat);
      return;
    }
    if (nextFile.size > 500 * 1024 * 1024) {
      setMessage(msg.fileTooLarge);
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
    setMessage(msg.videoOpened);
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
      setMessage(msg.voicePreviewUnsupported);
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
      setMessage(msg.hardwareEncodeUnsupported);
      return;
    }

    setMessage(msg.confirmingYolo);
    try {
      await loadPreciseModel();
    } catch {
      setMessage(msg.preciseModelFailed);
      return;
    }

    setExporting(true);
    setDownloadUrl("");
    setProgress(0);
    setEtaSeconds(null);
    setMessage(msg.preciseProcessing);
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
      setMessage(msg.preciseComplete);
      previewVideo.currentTime = 0;
      drawFrame();
    } catch (error) {
      const wasCanceled = error instanceof Error && error.name === "ConversionCanceledError";
      setProgress(0);
      setMessage(wasCanceled ? msg.preciseStopped : msg.preciseFailed);
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
      setMessage(msg.exportUnsupported);
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
        setMessage(msg.voiceInitFailed);
        return;
      }
    }
    setExporting(true);
    setDownloadUrl("");
    setProgress(0);
    setMessage(msg.fastProcessing);
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
        setMessage(recordedMime.startsWith("video/mp4") ? msg.writingMp4Index : msg.generatingMp4);
        try {
          const finalized = await finalizeRecordedMedia(recordedBlob, recordedMime, (value) => setProgress(99 + value));
          setOutputExtension(finalized.extension);
          setDownloadUrl(URL.createObjectURL(finalized.blob));
          setMessage(finalized.extension === "mp4"
            ? msg.completeMp4(formatTime(finalized.duration))
            : msg.completeWebm(formatTime(finalized.duration)));
        } catch (error) {
          console.error("Failed to finalize recorded video metadata", error);
          setOutputExtension(recordedMime.startsWith("video/mp4") ? "mp4" : "webm");
          setDownloadUrl(URL.createObjectURL(recordedBlob));
          setMessage(msg.completeNoIndex);
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
      setMessage(msg.playbackFailed);
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
    ? { min: 4, max: 64, unit: "px", label: copy.fullFrame.blurRadius }
    : activeEffectStyle === "pixel"
      ? { min: 6, max: 48, unit: "px", label: copy.fullFrame.pixelSize }
      : { min: 8, max: 30, unit: "px", label: copy.fullFrame.charSize };

  useEffect(() => {
    document.title = copy.documentTitle;
  }, [copy.documentTitle]);

  const entityGroups = (["person", "vehicle", "pet"] as const).map((key) => ({
    key,
    ...copy.entities[key],
  }));

  const hideModelStatus = message && maskScope === "full" && /(?:AI|模型|识别|model|detect|YOLO|WebGPU)/i.test(message);

  return (
    <main>
      <header className="site-header">
        <a className="brand" href="#top" aria-label={copy.header.homeAria}>
          <span className="brand-mark"><EyeOff size={20} strokeWidth={2.4} /></span>
          <span>{copy.brand}</span>
        </a>
        <div className="header-actions">
          <div className="lang-switch" role="group" aria-label={copy.header.langSwitchAria}>
            <button type="button" className={locale === "zh" ? "active" : ""} aria-pressed={locale === "zh"} onClick={() => setLocale("zh")}>{copy.header.langZh}</button>
            <button type="button" className={locale === "en" ? "active" : ""} aria-pressed={locale === "en"} onClick={() => setLocale("en")}>{copy.header.langEn}</button>
          </div>
          <div className="local-badge"><LockKeyhole size={14} /> {copy.header.localBadge}</div>
        </div>
      </header>

      <section className="hero" id="top">
        <div className="eyebrow"><Sparkles size={15} /> {copy.hero.eyebrow}</div>
        <h1>{copy.hero.titleLine1}<br /><span>{copy.hero.titleHighlight}</span></h1>
        <p>{copy.hero.body}</p>
        <div className="trust-row">
          <span><Check size={15} /> {copy.hero.trustNoSignup}</span>
          <span><Check size={15} /> {copy.hero.trustFree}</span>
          <span><Check size={15} /> {copy.hero.trustLocal}</span>
        </div>
      </section>

      <section className={`studio ${file ? "has-video" : ""}`} aria-label={copy.studio.ariaLabel}>
        {!file ? (
          <button
            className="upload-zone"
            type="button"
            onClick={() => inputRef.current?.click()}
            onDragOver={(event) => event.preventDefault()}
            onDrop={(event) => { event.preventDefault(); void handleFile(event.dataTransfer.files[0]); }}
          >
            <span className="upload-icon"><Upload size={30} /></span>
            <strong>{copy.studio.uploadTitle}</strong>
            <span>{copy.studio.uploadHint}</span>
            <span className="upload-button">{copy.studio.uploadButton} <ChevronRight size={17} /></span>
            <small>{copy.studio.uploadFormats}</small>
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
                  aria-label={copy.studio.videoAria}
                />
                <canvas ref={canvasRef} aria-label={copy.studio.previewAria} />
                <button className="video-close-mobile" type="button" onClick={reset} disabled={exporting} aria-label={copy.studio.removeVideo}><X size={18} /></button>
                {modelLoadingVisible && maskScope !== "full" && (
                  <div className="model-loading">
                    <span />
                    {modelState === "loading"
                      ? copy.studio.modelLoadingBase
                      : preciseLoadProgress?.stage === "download"
                        ? copy.studio.modelDownload(preciseLoadProgress.percent)
                        : preciseLoadProgress?.stage === "compile"
                          ? copy.studio.modelCompile
                          : preciseLoadProgress?.stage === "warmup"
                            ? copy.studio.modelWarmup
                            : copy.studio.modelYoloPrep}
                  </div>
                )}
                {detectedCount > 0 && !modelLoadingVisible && maskScope !== "full" && <div className="detect-pill"><span /> {maskScope === "background" ? copy.studio.detectKept(detectedCount) : copy.studio.detectMasked(detectedCount)}</div>}
              </div>
              <div className="player-controls">
                <button type="button" className="play-button" onClick={togglePlayback} aria-label={isPlaying ? copy.studio.pause : copy.studio.play}>
                  {isPlaying ? <Pause size={18} fill="currentColor" /> : <Play size={18} fill="currentColor" />}
                </button>
                <span>{formatTime(currentTime)}</span>
                <input aria-label={copy.studio.progressAria} type="range" min="0" max={duration || 0} step="0.01" value={Math.min(currentTime, duration || 0)} onChange={(event) => seek(Number(event.target.value))} />
                <span>{formatTime(duration)}</span>
              </div>
            </div>

            <aside className="settings-panel">
              <div className="settings-toolbar">
                <button className="desktop-close" type="button" onClick={reset} disabled={exporting} aria-label={copy.studio.removeVideo}><X size={19} /></button>
              </div>
              <div className="control-block">
                <div className="control-title"><span>{copy.scope.title}</span><small>{maskScope === "background" ? copy.scope.invertOn : maskScope === "full" ? copy.scope.noAi : copy.scope.normal}</small></div>
                <div className="segmented-control scope-control" aria-label={copy.scope.aria}>
                  <button type="button" disabled={exporting} className={maskScope === "full" ? "active" : ""} aria-pressed={maskScope === "full"} onClick={() => { if (maskScope !== "full") setEffectStrength(fullFrameStyle === "blur" ? 46 : fullFrameStyle === "pixel" ? 18 : 14); setMaskScope("full"); }}>{copy.scope.full}</button>
                  <button type="button" disabled={exporting} className={maskScope === "subjects" ? "active" : ""} aria-pressed={maskScope === "subjects"} onClick={() => { if (maskScope === "full" && fullFrameStyle !== "blur") setEffectStrength(46); setMaskScope("subjects"); void loadModel().then(() => videoRef.current ? analyzeCurrentFrame(videoRef.current) : undefined).catch(handleInferenceError); }}>{copy.scope.subjects}</button>
                  <button type="button" disabled={exporting} className={maskScope === "background" ? "active" : ""} aria-pressed={maskScope === "background"} onClick={() => { if (maskScope === "full" && fullFrameStyle !== "blur") setEffectStrength(46); setMaskScope("background"); void loadModel().then(() => videoRef.current ? analyzeCurrentFrame(videoRef.current) : undefined).catch(handleInferenceError); }}>{copy.scope.background}</button>
                </div>
              </div>

              {maskScope !== "full" && (
                <div className="settings-tabs" role="tablist" aria-label={copy.settings.tabsAria}>
                  <button type="button" role="tab" aria-selected={settingsTab === "general"} className={settingsTab === "general" ? "active" : ""} onClick={() => setSettingsTab("general")}>{copy.settings.general}</button>
                  <button type="button" role="tab" aria-selected={settingsTab === "subjects"} className={settingsTab === "subjects" ? "active" : ""} onClick={() => setSettingsTab("subjects")}>{copy.settings.subjects}</button>
                </div>
              )}

              {maskScope === "full" ? (
                <div className="control-block effect-control">
                  <div className="control-title"><span>{copy.fullFrame.title}</span><small>{fullFrameStyle === "ascii" ? copy.fullFrame.asciiMeta(effectStrength) : copy.fullFrame.strengthMeta(strengthRange.label, effectStrength, strengthRange.unit)}</small></div>
                  <div className="segmented-control effect-style-control" aria-label={copy.fullFrame.aria}>
                    <button type="button" disabled={exporting} className={fullFrameStyle === "blur" ? "active" : ""} aria-pressed={fullFrameStyle === "blur"} onClick={() => { setFullFrameStyle("blur"); setEffectStrength(46); }}>{copy.fullFrame.blur}</button>
                    <button type="button" disabled={exporting} className={fullFrameStyle === "pixel" ? "active" : ""} aria-pressed={fullFrameStyle === "pixel"} onClick={() => { setFullFrameStyle("pixel"); setEffectStrength(18); }}>{copy.fullFrame.pixel}</button>
                    <button type="button" disabled={exporting} className={fullFrameStyle === "ascii" ? "active" : ""} aria-pressed={fullFrameStyle === "ascii"} onClick={() => { setFullFrameStyle("ascii"); setEffectStrength(14); }}>{copy.fullFrame.ascii}</button>
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
                  <div className="control-title"><span>{copy.quality.title}</span><small>{quality === "precise" ? copy.quality.precise : quality === "balanced" ? copy.quality.balanced : copy.quality.fast}</small></div>
                  <div className="segmented-control quality-control" aria-label={copy.quality.aria}>
                    <button type="button" disabled={exporting} className={quality === "fast" ? "active" : ""} aria-pressed={quality === "fast"} onClick={() => setQuality("fast")}>{copy.quality.low} <small>{copy.quality.lowSub}</small></button>
                    <button type="button" disabled={exporting} className={quality === "balanced" ? "active" : ""} aria-pressed={quality === "balanced"} onClick={() => setQuality("balanced")}>{copy.quality.mid} <small>{copy.quality.midSub}</small></button>
                    <button type="button" disabled={exporting} className={quality === "precise" ? "active" : ""} aria-pressed={quality === "precise"} onClick={() => {
                      if (!supportsPreciseWebMode()) {
                        setMessage(msg.mobileHighDisabled);
                        return;
                      }
                      setQuality("precise");
                      if (preciseModelState !== "ready") setMessage(msg.highModelSizeHint);
                    }}>{copy.quality.high} <small>{copy.quality.highSub}</small></button>
                  </div>
                </div>
                {quality === "precise" && (
                  <div className="offline-notice">
                    <strong>{copy.quality.preciseNoticeTitle}</strong>
                    <span>{copy.quality.preciseNoticeBodyReady}{preciseModelState === "ready" ? (estimatedHighSeconds === null ? copy.quality.preciseNoticeBodyBenchmarking : copy.quality.preciseEstimateDone(formatTime(estimatedHighSeconds))) : copy.quality.preciseNoticeBodyIdle}</span>
                    {(preciseModelState === "idle" || preciseModelState === "error") && (
                      <button className="high-model-trigger" type="button" disabled={modelState !== "ready" || highLoadRequested} onClick={() => {
                        setMessage(msg.highModelInitSoon);
                        setHighLoadRequested(true);
                      }}>{preciseModelState === "error" ? copy.quality.preciseReload : copy.quality.preciseConfirmLoad}</button>
                    )}
                    {estimatedHighSeconds !== null && estimatedHighSeconds > 360 && <span className="estimate-warning">{copy.quality.preciseEstimateWarning}</span>}
                  </div>
                )}
                <div className="control-block effect-control">
                  <div className="control-title"><span>{copy.quality.blurStrength}</span><small>{copy.quality.blurRadius(effectStrength)}</small></div>
                  <div className="strength-slider">
                    <span>4</span>
                    <input aria-label={copy.fullFrame.blurRadius} type="range" min="4" max="64" step="1" value={Math.max(4, Math.min(64, effectStrength))} disabled={exporting} onChange={(event) => setEffectStrength(Number(event.target.value))} />
                    <span>64</span>
                  </div>
                </div>
                <div className="watermark-note"><LockKeyhole size={14} /><span><strong>{copy.quality.watermarkTitle}</strong><small>{copy.quality.watermarkSub}</small></span></div>
                </>}
              </>}
              {(maskScope === "full" || settingsTab === "general") && (
                <div className="control-block audio-privacy-control">
                  <div className="control-title"><span>{copy.audio.title}</span><small>{audioMode === "voice" ? copy.audio.pitchMeta(voicePitch) : audioMode === "mute" ? copy.audio.muteMeta : copy.audio.originalMeta}</small></div>
                  <div className="segmented-control audio-mode-control" aria-label={copy.audio.aria}>
                    <button type="button" disabled={exporting} className={audioMode === "original" ? "active" : ""} aria-pressed={audioMode === "original"} onClick={() => { void selectAudioMode("original"); }}>{copy.audio.original} <small>{copy.audio.originalSub}</small></button>
                    <button type="button" disabled={exporting} className={audioMode === "voice" ? "active" : ""} aria-pressed={audioMode === "voice"} onClick={() => { void selectAudioMode("voice"); }}>{copy.audio.voice} <small>{copy.audio.voiceSub}</small></button>
                    <button type="button" disabled={exporting} className={audioMode === "mute" ? "active" : ""} aria-pressed={audioMode === "mute"} onClick={() => { void selectAudioMode("mute"); }}>{copy.audio.mute} <small>{copy.audio.muteSub}</small></button>
                  </div>
                  {audioMode === "voice" && (
                    <div className="strength-slider voice-pitch-slider">
                      <span>{copy.audio.pitchLow}</span>
                      <input aria-label={copy.audio.pitchAria} type="range" min="-8" max="8" step="1" value={voicePitch} disabled={exporting} onChange={(event) => updateVoicePitch(Number(event.target.value))} />
                      <span>{copy.audio.pitchHigh}</span>
                    </div>
                  )}
                  <p className="audio-mode-note">{copy.audio.note}</p>
                </div>
              )}
              {settingsTab === "subjects" && maskScope !== "full" && <>
                <div className="entity-heading"><span>{maskScope === "background" ? copy.subjects.headingKeep : copy.subjects.headingMask}</span><small>{copy.subjects.multiSelect}</small></div>
                <div className="entity-list">
                {entityGroups.map((group) => {
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
                      <span className="entity-icon">{group.icon}</span>
                      <span><strong>{group.label}</strong><small>{group.sub}</small></span>
                      <span className="check-box">{active && <Check size={15} />}</span>
                    </button>
                  );
                })}
                </div>
                <div className="subject-heading">
                <span>{copy.subjects.detectedTitle}</span><small>{subjects.length ? copy.subjects.detectedCount(subjects.length) : copy.subjects.waiting}</small>
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
              ) : <p className="subject-empty">{copy.subjects.empty}</p>}
                <p className="tracking-note">{copy.subjects.trackingNote}</p>
              </>}
              {settingsTab === "subjects" && maskScope !== "full" && <>
              <div className="coming-soon"><span>{copy.comingSoon.title}</span><small>{copy.comingSoon.sub}</small></div>
              <div className="app-upsell" id="app-preview">
                <span className="app-kicker">{copy.appUpsell.kicker}</span>
                <strong>{copy.appUpsell.title}</strong>
                <small>{copy.appUpsell.body}</small>
                <button type="button" onClick={() => setMessage(msg.appPlanMessage)}>{copy.appUpsell.button}</button>
              </div>
              </>}
              <div className="privacy-note"><ShieldCheck size={18} /><span><strong>{copy.privacyNote.title}</strong><small>{copy.privacyNote.sub}</small></span></div>
              {exporting ? (
                <div className="export-progress">
                  <div><span>{quality === "precise" ? copy.export.preciseProgress : copy.export.fastProgress}</span><strong>{Math.round(progress)}%</strong></div>
                  <div className="progress-track"><span style={{ width: `${progress}%` }} /></div>
                  {quality === "precise" && <p>{etaSeconds === null ? copy.export.etaUnknown : copy.export.eta(formatTime(etaSeconds))}</p>}
                  <button type="button" onClick={() => exportStopRef.current?.()}>{copy.export.stop}</button>
                </div>
              ) : downloadUrl ? (
                <a className="primary-action success" href={downloadUrl} download={`${fileBase}-${copy.export.downloadSuffix}.${outputExtension}`}>
                  <ArrowDownToLine size={19} /> {copy.export.download}
                </a>
              ) : (
                <button className="primary-action" type="button" disabled={maskScope !== "full" && (modelState !== "ready" || selected.size === 0 || (quality === "precise" && (preciseModelState !== "ready" || (estimatedHighSeconds !== null && estimatedHighSeconds > 360))))} onClick={exportVideo}>
                  {maskScope === "full" ? copy.export.startFull : modelState === "loading" ? copy.export.aiPreparing : quality === "precise" && preciseModelState !== "ready" ? copy.export.confirmHighModel : quality === "precise" && estimatedHighSeconds !== null && estimatedHighSeconds > 360 ? copy.export.slowMachine : quality === "precise" ? copy.export.startPrecise : copy.export.startFast} <ChevronRight size={18} />
                </button>
              )}
              {message && !hideModelStatus && <p className={`status-message ${modelState === "error" ? "error" : ""}`}>{message}</p>}
            </aside>
          </div>
        )}
        <input ref={inputRef} className="visually-hidden" type="file" accept="video/mp4,video/quicktime,video/webm" onChange={(event) => void handleFile(event.target.files?.[0])} />
      </section>

      <section className="privacy-scenarios" aria-labelledby="privacy-scenarios-title">
        <div className="privacy-scenarios-intro">
          <div className="section-label">{copy.scenarios.label}</div>
          <h2 id="privacy-scenarios-title">{copy.scenarios.titleLine1}<br />{copy.scenarios.titleLine2}</h2>
          <p>{copy.scenarios.intro}</p>
          <div className="local-proof"><ShieldCheck size={17} /><span><strong>{copy.scenarios.localProofTitle}</strong><small>{copy.scenarios.localProofSub}</small></span></div>
        </div>
        <div className="scenario-grid">
          {[Baby, ScanFace, MapPin, Users].map((Icon, index) => {
            const card = copy.scenarios.cards[index];
            if (!card) return null;
            return (
              <article key={card.title}>
                <span className="scenario-icon"><Icon /></span>
                <div><h3>{card.title}</h3><p>{card.body}</p><small>{card.fit}</small></div>
              </article>
            );
          })}
        </div>
      </section>

      <section className="how-it-works" aria-labelledby="how-title">
        <div className="section-label">{copy.how.label}</div>
        <h2 id="how-title">{copy.how.title}</h2>
        <div className="steps">
          {[FileVideo, EyeOff, ArrowDownToLine].map((Icon, index) => {
            const step = copy.how.steps[index];
            if (!step) return null;
            return (
              <article key={step.title}><span>{String(index + 1).padStart(2, "0")}</span><div className="step-icon"><Icon /></div><h3>{step.title}</h3><p>{step.body}</p></article>
            );
          })}
        </div>
      </section>

      <section className="privacy-banner">
        <div className="shield-large"><ShieldCheck /></div>
        <div><span>{copy.banner.label}</span><h2>{copy.banner.title}</h2><p>{copy.banner.body}</p></div>
      </section>

      <footer>
        <a className="brand" href="#top"><span className="brand-mark"><EyeOff size={18} /></span><span>{copy.brand}</span></a>
        <p>{copy.footer.tagline}</p>
        <a className="reaidea-link" href="https://reaidea.com" rel="noopener noreferrer" aria-label={copy.footer.reaideaAria}>{copy.footer.reaidea}</a>
        <button type="button" onClick={() => { reset(); inputRef.current?.click(); }}><RotateCcw size={15} /> {copy.footer.newVideo}</button>
      </footer>
    </main>
  );
}
