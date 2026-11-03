# TapHide Android 原型

独立技术验证工程，应用 ID `cn.reaidea.taphide`（Kotlin 包名仍为 `com.reaidea.lenshide.prototype`）。不是完整安卓产品，不代表已完成 iOS 功能迁移或发布验收。

## 底层实验管线

- Kotlin + Compose；最低 Android 12 / API 31，compile/target API 35。最低版本暂用于缩小系统兼容性范围，不代表低端设备已过滤。
- 系统文件选择器导入照片/视频，无 INTERNET、摄像头或全盘存储权限；禁止备份。
- 随包附带 MIT 许可的 YuNet `2023mar` 固定输入模型，OpenCV 4.12.0 CPU 后端，2 线程。首次准备模型与推理在工作线程执行。
- 人物轮廓：TensorFlow Lite CPU 运行 DeepLab-v3 `deeplab_v3.tflite`（输入 257×257，输出 21 类 logits，person = 15），在同一个 320×320 补黑边帧上取「person logit − 其他类最大 logit」的符号作为掩码，双线性放大回 320 网格后膨胀 2 texel。**该权重许可未确认，只放在 `src/debug/assets` 且由 `FLAG_DEBUGGABLE` 门控：debug 构建启用，release 构建不打包该模型、退回人脸椭圆**，见 `THIRD_PARTY.md`。
- 实验测试使用 320 输入、3 次预热、20 次检测，记录中位数和 P95。编辑器照片保持方向，最长边降采样到约 2048 像素以内，导出 JPEG 时不复制源 EXIF。
- 视频 Media3 Transformer / MediaCodec + 自定义 GL 效果：GPU 缩小并补黑边到 320×320，仅回读低分辨率 RGBA，逐帧 CPU 检测与人物分割，再在 GPU 按「人物轮廓 ∪ 人脸椭圆」混合整帧马赛克。同步背压，输出纹理池容量为 1，不缓存整段视频。
- 实验用轮廓遮盖与 iOS 默认行为对齐：人物掩码为逐像素轮廓（`smoothstep(0.35, 0.65)` 羽化）；人脸为按人脸框扩展 1.48×/1.62× 的椭圆，`0.86→1.0` 径向渐隐；马赛克单元取短边的 `24 × 短边/720`（下限 8），与 iOS `CIPixellate` 默认强度 24 同量级，不再是每张脸一个 4×4 矩形块。
- 播放预览和导出复用同一 `FacePixelEffect`，坐标使用显示方向左上原点的归一化矩形。超出 64 张脸或推理异常时停止，不退回无打码输出。
- 原实验导出入口仍在处理器内验证前 30 秒、720p 的限制。Android 编辑器的真实素材导出见下节。
- 原声/静音、取消、失败重试、进度、结果播放、保存相册。离开页面取消任务；失败/取消删部分成品，结果离开时删除，启动兜底清理临时输出。
- 新 MP4 的 muxer 丢弃源 metadata 和轨道 metadata，保留必要的媒体结构与显示旋转信息。

当前不是零拷贝推理：每帧低分辨率 GL readback 会产生同步成本；原始全尺寸帧不走 Bitmap。`inferenceMeanMs` 只统计颜色转换与模型检测等 CPU 工作；`effectMeanMs` 包含分析渲染、同步回读和提交合成命令，不等于最终 GPU 全部执行完成时间。端到端耗时单独记录。

## 构建与安装

需要 Android SDK 35、JDK 17 或 21。Gradle Wrapper 固定 8.9，AGP 8.7.3。依赖版本用于这次可复现基线，正式发布前再完成升级与兼容性审计。

```bash
cd android
export ANDROID_HOME="$HOME/Library/Android/sdk"
export JAVA_HOME="/Library/Java/JavaVirtualMachines/openjdk-21.jdk/Contents/Home"
./gradlew :app:assembleDebug :app:lintDebug
adb install -r app/build/outputs/apk/debug/app-arm64-v8a-debug.apk
```

按 ABI 分包，arm64 真机与 ARM 模拟器用 `arm64-v8a`，Intel 模拟器用 `x86_64`。OpenCV 完整运行库体积明显偏大，包体不代表正式版目标；下一轮需要比较 ncnn 或裁剪 OpenCV，不能据此宣称 ncnn 已验证。

临时旧机安装试验可用 `./gradlew -PlabMinSdk=28 :app:assembleDebug`，只降低该次构建的安装门槛，默认仍为 API 31。此参数不代表 Android 9 完整兼容：旧系统相册保存等尚未适配。2026-11-02 的 OnePlus 3 / Android 9 首次因空间不足安装失败；用户清理空间后，安装、启动、照片检测和 2 秒视频打码导出通过。修复了旧系统 `MediaMetadataRetriever` 不实现 `AutoCloseable` 的兼容问题；详情见验证报告。

## 复现实验

选择有正脸的 1280×720 SDR 横屏素材作为输入；本次使用仓库已有的婚礼合照演示素材，手工确认可见 8 张脸。生成的输入、检测结果与导出文件只留在本机，均不提交 Git。更换素材后不要沿用本次脸数结论。

```bash
research/prepare-fixtures.sh /absolute/path/to/source.mp4
./gradlew :app:assembleDebug :app:assembleDebugAndroidTest
adb install -r app/build/outputs/apk/debug/app-arm64-v8a-debug.apk
adb install -r app/build/outputs/apk/androidTest/debug/app-debug-androidTest.apk
adb shell am instrument -w \
  cn.reaidea.taphide.test/androidx.test.runner.AndroidJUnitRunner
adb shell run-as cn.reaidea.taphide cat files/lab-results.txt
adb shell run-as cn.reaidea.taphide cat files/matrix-results.txt
```

`clean` 会删除生成的测试素材，之后需重新执行准备脚本。也可运行 `connectedDebugAndroidTest`，但 Gradle 可能卸载测试 App 并删除其内部输出。

测试素材脚本需要支持 `-display_rotation` 的 FFmpeg（本次使用 FFmpeg 7）。测试覆盖照片检测/实际像素变化、短视频导出、90° 旋转源、取消清理、损坏素材后重试，以及 30 秒/1 分钟/3 分钟输入在原声/静音下的横竖屏导出、免费边界、GPS 清除。后两种时长仍只导出前 30 秒，不能证明完整 1 分钟或 3 分钟导出通过。这一组是原有实验管线的矩阵用例。编辑器另有三种音频模式及遮盖时间线复用测试。

仪器测试会在 debug App 私有目录写报告和检查用图/短片，供开发者拉取核对；生产 UI 不保存人脸框、身份特征或分析历史。清除 App 数据或卸载会删除这些实验输出。

## 当前不承诺的能力

- 未移植跨遮挡身份跟踪、人物与宠物自动分类、关键帧、ASCII 效果和正式购买。
- 人物轮廓来自 257×257 输出的语义分割，边缘精度约为 ±5–10 显示像素，人物之间的缝隙可能被并入同一块掩码；它不是 iOS 的实例分割（`VNGeneratePersonInstanceMaskRequest`），也没有逐人实例编号。高精度轮廓、发丝级边缘尚未实现。
- 未验证完整买断长时导出、后台处理、4K/HDR 保留、存储不足、复杂遮挡/小脸/侧脸的漏遮率。
- 未建立真实手机性能矩阵；模拟器速度不能外推为普通安卓手机速度。API 31 最低版本本身也需在 Android 12 真机上验证。
- 不用内存、CPU 核数或系统版本单独决定安全性。正式设备策略应结合硬件解码/编码能力、实测模型/导出耗时、热稳定性和漏遮率；降档不能简单跳过检测。

结果记录见 [验证报告](../docs/android-prototype-validation-2026-11-02.md)。

## TapHide 编辑器

首页分别打开系统照片多选和视频选择器。照片单批最多 20 张，依次分析并共用效果设置。每张照片独立预览和调整遮盖，可保存当前照片或整批保存。整批保存逐张报告成败，仅重试失败项。取消会清理该次操作已写入的相册副本。

视频使用 Media3 和本地 YuNet 对实际导入素材逐帧检测，支持自动遮脸、手动补遮、播放和寻帧、原声／静音／变声、处理进度、取消及完整时长的保存与分享。遮盖坐标和帧时间只保留在当前会话内存，预览与导出共用。当前支持最长五分钟、已知大小不超过 1 GiB 的 SDR 输入。导出结果在编辑会话内可播放，并可复用同一个处理文件保存或分享。

Android 测试版本直接开放真实批量保存和完整视频导出。iOS 的 StoreKit 权益规则照旧。Android 系统分享只授予目标 App 读取处理结果的权限，分享临时文件满 24 小时后会在后续启动时清理。
