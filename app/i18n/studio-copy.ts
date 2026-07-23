import type { Locale } from "./locale";

export type EntityKey = "person" | "vehicle" | "pet";

export type StudioCopy = {
  brand: string;
  documentTitle: string;
  header: {
    homeAria: string;
    localBadge: string;
    langZh: string;
    langEn: string;
    langSwitchAria: string;
    themeToggleAria: string;
  };
  hero: {
    eyebrow: string;
    titleLine1: string;
    titleHighlight: string;
    body: string;
    trustNoSignup: string;
    trustFree: string;
    trustLocal: string;
  };
  studio: {
    ariaLabel: string;
    uploadTitle: string;
    uploadHint: string;
    uploadButton: string;
    uploadFormats: string;
    videoAria: string;
    previewAria: string;
    removeVideo: string;
    play: string;
    pause: string;
    progressAria: string;
    modelLoadingBase: string;
    modelDownload: (percent: number) => string;
    modelCompile: string;
    modelWarmup: string;
    modelYoloPrep: string;
    detectKept: (count: number) => string;
    detectMasked: (count: number) => string;
  };
  scope: {
    title: string;
    invertOn: string;
    noAi: string;
    normal: string;
    aria: string;
    full: string;
    subjects: string;
    background: string;
  };
  settings: {
    tabsAria: string;
    general: string;
    subjects: string;
  };
  fullFrame: {
    title: string;
    asciiMeta: (strength: number) => string;
    strengthMeta: (label: string, strength: number, unit: string) => string;
    aria: string;
    blur: string;
    pixel: string;
    ascii: string;
    blurRadius: string;
    pixelSize: string;
    charSize: string;
  };
  quality: {
    title: string;
    precise: string;
    balanced: string;
    fast: string;
    low: string;
    lowSub: string;
    mid: string;
    midSub: string;
    high: string;
    highSub: string;
    aria: string;
    preciseNoticeTitle: string;
    preciseNoticeBodyReady: string;
    preciseNoticeBodyBenchmarking: string;
    preciseEstimateDone: (time: string) => string;
    preciseNoticeBodyIdle: string;
    preciseReload: string;
    preciseConfirmLoad: string;
    preciseEstimateWarning: string;
    blurStrength: string;
    blurRadius: (px: number) => string;
    watermarkTitle: string;
    watermarkSub: string;
  };
  audio: {
    title: string;
    pitchMeta: (semitones: number) => string;
    muteMeta: string;
    originalMeta: string;
    aria: string;
    original: string;
    originalSub: string;
    voice: string;
    voiceSub: string;
    mute: string;
    muteSub: string;
    pitchLow: string;
    pitchHigh: string;
    pitchAria: string;
    note: string;
  };
  entities: Record<EntityKey, { label: string; sub: string; icon: string }>;
  entityFallback: string;
  subjects: {
    headingKeep: string;
    headingMask: string;
    multiSelect: string;
    detectedTitle: string;
    detectedCount: (n: number) => string;
    waiting: string;
    empty: string;
    trackingNote: string;
  };
  comingSoon: { title: string; sub: string };
  appUpsell: {
    kicker: string;
    title: string;
    body: string;
    button: string;
  };
  privacyNote: { title: string; sub: string };
  export: {
    preciseProgress: string;
    fastProgress: string;
    etaUnknown: string;
    eta: (time: string) => string;
    stop: string;
    download: string;
    downloadSuffix: string;
    startFull: string;
    aiPreparing: string;
    confirmHighModel: string;
    slowMachine: string;
    startPrecise: string;
    startFast: string;
  };
  scenarios: {
    label: string;
    titleLine1: string;
    titleLine2: string;
    intro: string;
    localProofTitle: string;
    localProofSub: string;
    cards: Array<{ title: string; body: string; fit: string }>;
  };
  how: {
    label: string;
    title: string;
    steps: Array<{ title: string; body: string }>;
  };
  banner: {
    label: string;
    title: string;
    body: string;
  };
  footer: {
    tagline: string;
    reaidea: string;
    reaideaAria: string;
  };
  msg: {
    inferenceSecurity: string;
    inferenceFailed: string;
    yoloDownload: (percent: number) => string;
    yoloCompile: string;
    yoloWarmup: string;
    yoloBackgroundLoad: string;
    yoloReadyWebGpu: string;
    yoloReadyCompat: string;
    mobileWebGpuDisabled: string;
    webGpuRequired: string;
    webGpuTimeout: string;
    yoloInitFailed: string;
    aiLoading: string;
    subjectsIdentified: string;
    aiLoadFailed: string;
    invalidFormat: string;
    fileTooLarge: string;
    videoOpened: string;
    voicePreviewUnsupported: string;
    hardwareEncodeUnsupported: string;
    confirmingYolo: string;
    preciseModelFailed: string;
    preciseProcessing: string;
    preciseComplete: string;
    preciseStopped: string;
    preciseFailed: string;
    exportUnsupported: string;
    voiceInitFailed: string;
    fastProcessing: string;
    writingMp4Index: string;
    generatingMp4: string;
    completeMp4: (duration: string) => string;
    completeWebm: (duration: string) => string;
    completeNoIndex: string;
    playbackFailed: string;
    mobileHighDisabled: string;
    highModelSizeHint: string;
    highModelInitSoon: string;
    appPlanMessage: string;
    highOnlyDesktop: string;
  };
};

const zh: StudioCopy = {
  brand: "镜隐",
  documentTitle: "镜隐｜在线视频隐私打码工具",
  header: {
    homeAria: "镜隐首页",
    localBadge: "本地处理 · 不上传",
    langZh: "中文",
    langEn: "EN",
    langSwitchAria: "切换语言",
    themeToggleAria: "切换浅色/深色显示",
  },
  hero: {
    eyebrow: "LOCAL-FIRST VIDEO PRIVACY",
    titleLine1: "想分享生活，",
    titleHighlight: "先把隐私藏好。",
    body: "孩子的视频、家人的身影和清晰语音，都可能成为可被复制的身份素材。镜隐在本机完成画面遮盖与声音处理，减少内容被截取、冒用或用于 AI 换脸与声音克隆的风险。",
    trustNoSignup: "无需注册",
    trustFree: "免费使用",
    trustLocal: "视频不出设备",
  },
  studio: {
    ariaLabel: "视频打码工作台",
    uploadTitle: "上传你的视频",
    uploadHint: "点击选择，或将文件拖到这里",
    uploadButton: "选择视频",
    uploadFormats: "支持 MP4、MOV、WebM · 建议 500MB 以内",
    videoAria: "原始视频（隐藏显示）",
    previewAria: "隐私打码预览",
    removeVideo: "移除视频",
    play: "播放",
    pause: "暂停",
    progressAria: "视频进度",
    modelLoadingBase: "首次加载基础模型…",
    modelDownload: (percent) => `下载轻量模型 ${percent}%`,
    modelCompile: "下载完成 · 编译 WebGPU…",
    modelWarmup: "编译完成 · 首次预热…",
    modelYoloPrep: "准备 YOLO WebGPU…",
    detectKept: (count) => `已保留 ${count} 个主体`,
    detectMasked: (count) => `已遮挡 ${count} 个实体`,
  },
  scope: {
    title: "遮盖范围",
    invertOn: "反选已开启",
    noAi: "无需 AI 识别",
    normal: "常规",
    aria: "遮盖范围",
    full: "全画面",
    subjects: "遮盖主体",
    background: "遮盖主体之外",
  },
  settings: {
    tabsAria: "设置分类",
    general: "通用设置",
    subjects: "选择主体",
  },
  fullFrame: {
    title: "全画面风格",
    asciiMeta: (strength) => `黑白字符画 · ${strength}px`,
    strengthMeta: (label, strength, unit) => `${label} ${strength}${unit}`,
    aria: "全画面风格",
    blur: "模糊",
    pixel: "低像素",
    ascii: "ASCII",
    blurRadius: "模糊半径",
    pixelSize: "像素块大小",
    charSize: "字符尺寸",
  },
  quality: {
    title: "处理精度",
    precise: "逐帧最稳",
    balanced: "轮廓实时",
    fast: "轻量人形",
    low: "低",
    lowSub: "省性能",
    mid: "中",
    midSub: "轮廓",
    high: "高",
    highSub: "桌面",
    aria: "处理精度",
    preciseNoticeTitle: "网页高档 · YOLO 实例轮廓",
    preciseNoticeBodyReady: "统一识别人、宠物与车辆，使用 WebGPU 逐帧生成独立轮廓。",
    preciseNoticeBodyBenchmarking: "模型已就绪，正在测速。",
    preciseEstimateDone: (time) => `本机预计约 ${time} 完成。`,
    preciseNoticeBodyIdle: "为避免手机刚切换档位就卡住，模型不会自动加载。",
    preciseReload: "重新加载高档模型",
    preciseConfirmLoad: "确认加载高档模型",
    preciseEstimateWarning: "本机预计超过 6 分钟，已停用高档；请选择中档或等待 App 超精细版。",
    blurStrength: "模糊强度",
    blurRadius: (px) => `模糊半径 ${px}px`,
    watermarkTitle: "网页版默认添加右下角水印",
    watermarkSub: "后续可通过广告权益或一次买断移除；当前版本暂不提供付费入口。",
  },
  audio: {
    title: "声音处理",
    pitchMeta: (semitones) => `音调 ${semitones > 0 ? "+" : ""}${semitones} 半音`,
    muteMeta: "导出无音轨",
    originalMeta: "保留视频原声",
    aria: "声音隐私",
    original: "原声",
    originalSub: "保留",
    voice: "变音",
    voiceSub: "音调偏移",
    mute: "静音",
    muteSub: "无音轨",
    pitchLow: "低",
    pitchHigh: "高",
    pitchAria: "变声音调",
    note: "真正改变音调，不改变语速；播放时拖动可实时试听。",
  },
  entities: {
    person: { label: "人物", sub: "全身与半身", icon: "人" },
    vehicle: { label: "车辆", sub: "汽车、摩托与公交", icon: "车" },
    pet: { label: "宠物", sub: "猫与狗", icon: "宠" },
  },
  entityFallback: "主体",
  subjects: {
    headingKeep: "选择要保留清晰的主体",
    headingMask: "选择要遮盖的主体",
    multiSelect: "可多选",
    detectedTitle: "当前画面识别到的主体",
    detectedCount: (n) => `${n} 个`,
    waiting: "等待识别",
    empty: "加载后会在这里列出人物、车辆和宠物，可逐个勾选。",
    trackingNote: "主体编号由本地跟踪生成；多人交叉遮挡或离开后重新出现时，可能生成新编号。",
  },
  comingSoon: { title: "人脸与车牌", sub: "精细识别模型 · 即将支持" },
  appUpsell: {
    kicker: "NATIVE APP · ULTRA",
    title: "超精细视频遮罩，交给原生 App",
    body: "原生 GPU/NPU 推理、硬件编解码和时序跟踪，更适合长视频、4K 与低耗电处理。",
    button: "查看 App 版计划",
  },
  privacyNote: {
    title: "只在你的浏览器中运行",
    sub: "原视频和处理结果都不会上传。",
  },
  export: {
    preciseProgress: "正在逐帧分析与编码",
    fastProgress: "正在处理视频",
    etaUnknown: "正在估算剩余时间…",
    eta: (time) => `预计还需约 ${time}`,
    stop: "停止处理",
    download: "下载处理后的视频",
    downloadSuffix: "已打码",
    startFull: "开始全画面处理",
    aiPreparing: "AI 准备中…",
    confirmHighModel: "请先确认加载高档模型",
    slowMachine: "本机较慢 · 建议 App",
    startPrecise: "开始逐帧处理",
    startFast: "开始快速处理",
  },
  scenarios: {
    label: "BEFORE YOU SHARE",
    titleLine1: "不是不分享，",
    titleLine2: "是分享前先保护好。",
    intro: "照片和视频一旦公开，就可能被保存、裁剪和再次传播。先遮住不需要出现的主体或环境，让分享保留快乐，不留下多余的身份线索。",
    localProofTitle: "视频不上传",
    localProofSub: "识别、遮盖和导出都在当前设备完成",
    cards: [
      {
        title: "分享孩子的成长",
        body: "公开发布前隐藏孩子、同伴或旁观者，减少清晰人像在未知渠道中继续流传。",
        fit: "适合：遮盖主体",
      },
      {
        title: "降低 AI 换脸与声音克隆风险",
        body: "高质量正脸、连续动作和清晰语音都可能成为可复用素材，可同时模糊人物并变音或静音。",
        fit: "适合：遮盖主体 + 声音处理",
      },
      {
        title: "不暴露生活环境",
        body: "家庭陈设、学校周边、常走路线都可能透露位置和生活规律，可反选主体，只遮盖环境。",
        fit: "适合：遮盖主体之外",
      },
      {
        title: "避免路人和家人被公开",
        body: "聚会、旅行和街拍里常有无关人员入镜。发布前处理，让没有同意出镜的人保持匿名。",
        fit: "适合：选择主体",
      },
    ],
  },
  how: {
    label: "HOW IT WORKS",
    title: "三步，保护每一帧。",
    steps: [
      { title: "上传视频", body: "从手机或电脑选择视频，文件只在本机打开。" },
      { title: "设置隐私处理", body: "选择画面遮盖范围，并决定保留原声、变音或静音。" },
      { title: "下载结果", body: "浏览器逐帧完成处理，然后直接保存到设备。" },
    ],
  },
  banner: {
    label: "PRIVACY BY DESIGN",
    title: "你的视频，始终是你的。",
    body: "没有上传、没有云端副本、没有账号。关闭页面后，本次数据随即消失。",
  },
  footer: {
    tagline: "浏览器里的视频隐私保护工具",
    reaidea: "reaidea.com",
    reaideaAria: "访问 reaidea 主站",
  },
  msg: {
    inferenceSecurity: "浏览器拒绝读取当前视频帧，已安全跳过；请重新选择原始本地视频，避免从网页播放器直接分享的临时文件",
    inferenceFailed: "当前帧识别失败，已自动跳过并继续处理",
    yoloDownload: (percent) => `正在下载网页高档模型 ${percent}%`,
    yoloCompile: "模型下载完成，正在编译 WebGPU 运算图（最长 45 秒）",
    yoloWarmup: "WebGPU 编译完成，正在进行首次预热（最长 30 秒）",
    yoloBackgroundLoad: "正在后台加载 YOLO 实例分割模型；中、低档已经可以使用",
    yoloReadyWebGpu: "YOLO WebGPU 实例分割已就绪",
    yoloReadyCompat: "当前设备无 WebGPU，将使用兼容模式；建议切换中档或使用 App",
    mobileWebGpuDisabled: "为避免手机卡死和发热，网页高档已在移动端停用；请选择中档或使用 App",
    webGpuRequired: "当前浏览器没有可用的 WebGPU，高档已停用；请选择中档或使用 App",
    webGpuTimeout: "本机 WebGPU 初始化超过 75 秒，高档已自动停止；请选择中档或使用 App",
    yoloInitFailed: "YOLO 模型初始化失败；请选择中档或使用 App",
    aiLoading: "正在加载本地 AI；首次使用需要下载模型，之后浏览器通常会缓存",
    subjectsIdentified: "已识别当前画面主体，可在下方逐个选择",
    aiLoadFailed: "AI 模型加载失败，请检查网络后重试",
    invalidFormat: "请选择 MP4、MOV 或 WebM 视频",
    fileTooLarge: "首期建议使用 500MB 以内的视频",
    videoOpened: "视频已在本地打开；请选择遮盖范围",
    voicePreviewUnsupported: "当前浏览器无法实时预览变音，请选择保留原声或静音",
    hardwareEncodeUnsupported: "当前浏览器不支持硬件逐帧编码，请使用最新版 Chrome、Edge 或切换快速模式",
    confirmingYolo: "正在确认 YOLO WebGPU 实例分割模型…",
    preciseModelFailed: "高精度模型加载失败，请检查网络或切换中档",
    preciseProcessing: "正在逐帧识别和编码；请勿锁屏、切换应用或关闭页面",
    preciseComplete: "逐帧处理完成：每一帧都已等待遮罩生成后再编码",
    preciseStopped: "已停止逐帧处理",
    preciseFailed: "逐帧处理失败；可尝试最新版 Chrome 或切换快速模式",
    exportUnsupported: "当前浏览器暂不支持导出，请使用最新版 Chrome 或 Edge",
    voiceInitFailed: "当前浏览器无法初始化隐私变音；请选择保留原声或静音",
    fastProcessing: "正在本地逐帧处理，请保持页面开启",
    writingMp4Index: "正在写入 MP4 时长与播放索引…",
    generatingMp4: "正在本地生成 H.264/AAC MP4…",
    completeMp4: (duration) => `MP4 处理完成 · 时长 ${duration}`,
    completeWebm: (duration) => `处理完成 · 当前设备无 H.264/AAC 编码器，已保留 WebM · ${duration}`,
    completeNoIndex: "处理完成，但当前浏览器未能重写时长索引",
    playbackFailed: "无法开始视频播放，请重新打开视频后再试",
    mobileHighDisabled: "为避免手机页面卡死和严重发热，网页高档仅支持桌面 WebGPU；手机请选择中档或使用 App",
    highModelSizeHint: "高档模型约 11MB；桌面浏览器首次编译可能短暂停顿，请确认后再加载",
    highModelInitSoon: "即将初始化高档 WebGPU 模型；手机页面可能短暂停顿，请勿切换应用",
    appPlanMessage: "App 超精细版正在规划中，网页端会继续保持免费的性能平衡模式",
    highOnlyDesktop: "为避免手机页面卡死和严重发热，网页高档仅支持桌面 WebGPU；手机请选择中档或使用 App",
  },
};

const en: StudioCopy = {
  brand: "LensHide",
  documentTitle: "LensHide | Local video privacy blur",
  header: {
    homeAria: "LensHide home",
    localBadge: "On-device · No upload",
    langZh: "中文",
    langEn: "EN",
    langSwitchAria: "Switch language",
    themeToggleAria: "Toggle light/dark appearance",
  },
  hero: {
    eyebrow: "LOCAL-FIRST VIDEO PRIVACY",
    titleLine1: "Share your life,",
    titleHighlight: "hide what should stay private.",
    body: "Kids on camera, family faces, and clear voices can all become copyable identity material. LensHide blurs video and adjusts audio entirely on your device—before you post—so clips are harder to misuse for deepfakes or voice cloning.",
    trustNoSignup: "No sign-up",
    trustFree: "Free to use",
    trustLocal: "Video never leaves your device",
  },
  studio: {
    ariaLabel: "Video privacy workspace",
    uploadTitle: "Upload your video",
    uploadHint: "Click to choose, or drop a file here",
    uploadButton: "Choose video",
    uploadFormats: "MP4, MOV, WebM · up to ~500MB recommended",
    videoAria: "Source video (hidden from view)",
    previewAria: "Privacy mask preview",
    removeVideo: "Remove video",
    play: "Play",
    pause: "Pause",
    progressAria: "Playback position",
    modelLoadingBase: "Loading base models (first visit)…",
    modelDownload: (percent) => `Downloading model ${percent}%`,
    modelCompile: "Download done · compiling WebGPU…",
    modelWarmup: "Compile done · warming up…",
    modelYoloPrep: "Preparing YOLO WebGPU…",
    detectKept: (count) => `${count} subject${count === 1 ? "" : "s"} kept clear`,
    detectMasked: (count) => `${count} subject${count === 1 ? "" : "s"} masked`,
  },
  scope: {
    title: "Mask area",
    invertOn: "Invert on",
    noAi: "No AI needed",
    normal: "Standard",
    aria: "Mask area",
    full: "Full frame",
    subjects: "Mask subjects",
    background: "Mask everything else",
  },
  settings: {
    tabsAria: "Settings sections",
    general: "General",
    subjects: "Pick subjects",
  },
  fullFrame: {
    title: "Full-frame style",
    asciiMeta: (strength) => `ASCII art · ${strength}px`,
    strengthMeta: (label, strength, unit) => `${label} ${strength}${unit}`,
    aria: "Full-frame style",
    blur: "Blur",
    pixel: "Pixelate",
    ascii: "ASCII",
    blurRadius: "Blur radius",
    pixelSize: "Block size",
    charSize: "Character size",
  },
  quality: {
    title: "Quality",
    precise: "Frame-perfect",
    balanced: "Live outlines",
    fast: "Lightweight",
    low: "Low",
    lowSub: "Fastest",
    mid: "Medium",
    midSub: "Outlines",
    high: "High",
    highSub: "Desktop",
    aria: "Processing quality",
    preciseNoticeTitle: "High · YOLO instance masks",
    preciseNoticeBodyReady: "Detects people, pets, and vehicles, then builds per-instance outlines with WebGPU, frame by frame.",
    preciseNoticeBodyBenchmarking: "Model ready; benchmarking this device.",
    preciseEstimateDone: (time) => `About ${time} on this device.`,
    preciseNoticeBodyIdle: "The high model does not auto-load on mobile to avoid freezing the page.",
    preciseReload: "Reload high model",
    preciseConfirmLoad: "Load high model",
    preciseEstimateWarning: "Estimated over 6 minutes on this device; high mode disabled. Use medium or wait for the native app.",
    blurStrength: "Blur strength",
    blurRadius: (px) => `Blur radius ${px}px`,
    watermarkTitle: "Web export includes a small watermark",
    watermarkSub: "Remove via ads or a one-time purchase later; no paid option in this version yet.",
  },
  audio: {
    title: "Audio",
    pitchMeta: (semitones) => `Pitch ${semitones > 0 ? "+" : ""}${semitones} semitones`,
    muteMeta: "Silent export",
    originalMeta: "Keep original audio",
    aria: "Audio privacy",
    original: "Original",
    originalSub: "Keep",
    voice: "Shift pitch",
    voiceSub: "Pitch offset",
    mute: "Mute",
    muteSub: "No track",
    pitchLow: "Lower",
    pitchHigh: "Higher",
    pitchAria: "Pitch shift",
    note: "Changes pitch, not speed. Drag while playing to preview.",
  },
  entities: {
    person: { label: "People", sub: "Full or partial body", icon: "P" },
    vehicle: { label: "Vehicles", sub: "Cars, bikes, buses", icon: "V" },
    pet: { label: "Pets", sub: "Cats and dogs", icon: "A" },
  },
  entityFallback: "Subject",
  subjects: {
    headingKeep: "Choose subjects to keep clear",
    headingMask: "Choose subjects to mask",
    multiSelect: "Multi-select",
    detectedTitle: "Detected in this frame",
    detectedCount: (n) => `${n}`,
    waiting: "Waiting for detection",
    empty: "People, vehicles, and pets will show up here after detection. Tap to include or exclude.",
    trackingNote: "IDs come from on-device tracking. New IDs may appear after overlap or when someone leaves and returns.",
  },
  comingSoon: { title: "Faces & plates", sub: "Dedicated models · coming soon" },
  appUpsell: {
    kicker: "NATIVE APP · ULTRA",
    title: "Ultra-fine masking belongs in the native app",
    body: "GPU/NPU inference, hardware codecs, and temporal tracking—better for long clips, 4K, and battery life.",
    button: "See app roadmap",
  },
  privacyNote: {
    title: "Runs only in your browser",
    sub: "Source video and exports are never uploaded.",
  },
  export: {
    preciseProgress: "Analyzing and encoding frame by frame",
    fastProgress: "Processing video",
    etaUnknown: "Estimating time left…",
    eta: (time) => `About ${time} left`,
    stop: "Stop",
    download: "Download processed video",
    downloadSuffix: "masked",
    startFull: "Process full frame",
    aiPreparing: "Preparing AI…",
    confirmHighModel: "Load high model first",
    slowMachine: "Slow device · try the app",
    startPrecise: "Start frame-perfect export",
    startFast: "Start fast export",
  },
  scenarios: {
    label: "BEFORE YOU SHARE",
    titleLine1: "Still want to share—",
    titleLine2: "just protect it first.",
    intro: "Once a clip is public, it can be saved, cropped, and reshared. Mask people or places you do not want in the open, and keep the joy without extra identity breadcrumbs.",
    localProofTitle: "No upload",
    localProofSub: "Detection, masking, and export stay on this device",
    cards: [
      {
        title: "Kids growing up online",
        body: "Hide children, friends, or bystanders before posting so clear faces do not keep spreading through unknown channels.",
        fit: "Best for: mask subjects",
      },
      {
        title: "Lower deepfake & voice-clone risk",
        body: "Sharp faces, motion, and clean audio are reusable training material. Blur visuals and shift or mute audio together.",
        fit: "Best for: mask subjects + audio",
      },
      {
        title: "Hide where you live",
        body: "Home layout, school routes, and daily paths leak location and routine. Invert the mask to blur the background only.",
        fit: "Best for: mask background",
      },
      {
        title: "Protect people who did not consent",
        body: "Parties, trips, and street shots catch strangers and relatives. Anonymize anyone who did not agree to be public.",
        fit: "Best for: pick subjects",
      },
    ],
  },
  how: {
    label: "HOW IT WORKS",
    title: "Three steps. Every frame covered.",
    steps: [
      { title: "Upload", body: "Pick a file from phone or computer—it opens locally only." },
      { title: "Set privacy", body: "Choose what to mask on screen and whether to keep, shift, or mute audio." },
      { title: "Download", body: "The browser processes frame by frame, then you save to your device." },
    ],
  },
  banner: {
    label: "PRIVACY BY DESIGN",
    title: "Your video stays yours.",
    body: "No upload, no cloud copy, no account. Close the tab and this session is gone.",
  },
  footer: {
    tagline: "Video privacy tools in the browser",
    reaidea: "reaidea.com",
    reaideaAria: "Visit reaidea.com",
  },
  msg: {
    inferenceSecurity: "The browser blocked reading this frame (safe skip). Re-select the original local file—not a temporary share from another web player.",
    inferenceFailed: "Detection failed on this frame; skipped and continuing.",
    yoloDownload: (percent) => `Downloading high model ${percent}%`,
    yoloCompile: "Download complete; compiling WebGPU graph (up to 45s)",
    yoloWarmup: "WebGPU ready; first warmup (up to 30s)",
    yoloBackgroundLoad: "Loading YOLO segmentation in the background; medium and low modes are ready",
    yoloReadyWebGpu: "YOLO WebGPU segmentation ready",
    yoloReadyCompat: "No WebGPU; using compatibility path. Try medium quality or the native app.",
    mobileWebGpuDisabled: "High mode is off on mobile to prevent overheating. Use medium or the app.",
    webGpuRequired: "WebGPU unavailable; high mode disabled. Use medium or the app.",
    webGpuTimeout: "WebGPU init exceeded 75s; high mode stopped. Use medium or the app.",
    yoloInitFailed: "YOLO failed to start; use medium or the app.",
    aiLoading: "Loading on-device AI; first run downloads models, then the browser caches them.",
    subjectsIdentified: "Subjects detected—pick them below",
    aiLoadFailed: "AI models failed to load. Check your network and retry.",
    invalidFormat: "Choose an MP4, MOV, or WebM video",
    fileTooLarge: "For now, keep files under about 500MB",
    videoOpened: "Video opened locally—choose a mask mode",
    voicePreviewUnsupported: "Live pitch preview is not supported here. Use original audio or mute.",
    hardwareEncodeUnsupported: "Frame-by-frame hardware encoding is unavailable. Use latest Chrome/Edge or fast mode.",
    confirmingYolo: "Confirming YOLO WebGPU segmentation…",
    preciseModelFailed: "High model failed to load. Check network or switch to medium.",
    preciseProcessing: "Processing frame by frame—keep this tab open",
    preciseComplete: "Frame-perfect export done; every frame waited for its mask",
    preciseStopped: "Frame-perfect export stopped",
    preciseFailed: "Frame-perfect export failed. Try latest Chrome or fast mode.",
    exportUnsupported: "Export is not supported in this browser. Use latest Chrome or Edge.",
    voiceInitFailed: "Could not init pitch shift. Use original audio or mute.",
    fastProcessing: "Processing locally—keep this page open",
    writingMp4Index: "Writing MP4 duration and index…",
    generatingMp4: "Building H.264/AAC MP4 locally…",
    completeMp4: (duration) => `MP4 ready · ${duration}`,
    completeWebm: (duration) => `Done · no H.264/AAC encoder; kept WebM · ${duration}`,
    completeNoIndex: "Done, but duration index could not be rewritten",
    playbackFailed: "Playback could not start. Re-open the video and try again.",
    mobileHighDisabled: "High mode is desktop WebGPU only. On phone, use medium or the app.",
    highModelSizeHint: "High model is ~11MB; first WebGPU compile may pause briefly—confirm to load.",
    highModelInitSoon: "About to init high WebGPU model; the page may pause briefly.",
    appPlanMessage: "Ultra native app is in planning; the web stays free with balanced performance.",
    highOnlyDesktop: "High mode needs desktop WebGPU. On phone, use medium or the app.",
  },
};

export function getStudioCopy(locale: Locale): StudioCopy {
  return locale === "en" ? en : zh;
}

export const ENTITY_CLASS_GROUPS: Array<{ key: EntityKey; classes: string[] }> = [
  { key: "person", classes: ["person"] },
  { key: "vehicle", classes: ["car", "truck", "bus", "motorcycle", "bicycle"] },
  { key: "pet", classes: ["cat", "dog"] },
];

export function entityKeyForClass(className: string, groups = ENTITY_CLASS_GROUPS) {
  return groups.find((group) => group.classes.includes(className))?.key;
}
