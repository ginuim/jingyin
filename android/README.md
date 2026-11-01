# LensHide Android Lab

独立技术验证工程，包名 `com.reaidea.lenshide.prototype`。不是完整安卓产品，不代表已完成 iOS 功能迁移或发布验收。

## 已接入的链路

- Kotlin + Compose；最低 Android 12 / API 31，compile/target API 35。最低版本暂用于缩小系统兼容性范围，不代表低端设备已过滤。
- 系统文件选择器导入照片/视频，无 INTERNET、摄像头或全盘存储权限；禁止备份。
- 随包附带 MIT 许可的 YuNet `2023mar` 固定输入模型，OpenCV 4.12.0 CPU 后端，2 线程。首次准备模型与推理在工作线程执行。
- 照片保持方向，最长边降采样到约 2048 像素以内。320 输入、3 次预热、20 次检测，显示中位数/P95；单张像素化后保存 JPEG，不复制源 EXIF。
- 视频 Media3 Transformer / MediaCodec + 自定义 GL 效果：GPU 缩小并补黑边到 320×320，仅回读低分辨率 RGBA，逐帧 CPU 检测，再在 GPU 覆盖扩大的人脸矩形。同步背压，输出纹理池容量为 1，不缓存整段视频。
- 播放预览和导出复用同一 `FacePixelEffect`，坐标使用显示方向左上原点的归一化矩形。超出 64 张脸或推理异常时停止，不退回无打码输出。
- `VideoExporter` 内部强制前 30 秒、720p 范围，不依赖 UI；没有伪造的买断权益。原素材最长 5 分钟，HDR 拒绝导出。
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
  com.reaidea.lenshide.prototype.test/androidx.test.runner.AndroidJUnitRunner
adb shell run-as com.reaidea.lenshide.prototype cat files/lab-results.txt
adb shell run-as com.reaidea.lenshide.prototype cat files/matrix-results.txt
```

`clean` 会删除生成的测试素材，之后需重新执行准备脚本。也可运行 `connectedDebugAndroidTest`，但 Gradle 可能卸载测试 App 并删除其内部输出。

测试素材脚本需要支持 `-display_rotation` 的 FFmpeg（本次使用 FFmpeg 7）。测试覆盖照片检测/实际像素变化、短视频导出、90° 旋转源、取消清理、损坏素材后重试，以及 30 秒/1 分钟/3 分钟输入在原声/静音下的横竖屏导出、免费边界、GPS 清除。后两种时长仍只导出前 30 秒，不能证明完整 1 分钟或 3 分钟导出通过。语音变调没有实现。

仪器测试会在 debug App 私有目录写报告和检查用图/短片，供开发者拉取核对；生产 UI 不保存人脸框、身份特征或分析历史。清除 App 数据或卸载会删除这些实验输出。

## 当前不承诺的能力

- 指定身份跟踪、人物/猫狗检测、精细分割、手动蒙版、关键帧、照片批量、ASCII、贴纸、变音和购买尚未移植。
- 未验证完整买断长时导出、后台处理、4K/HDR 保留、存储不足、复杂遮挡/小脸/侧脸的漏遮率。
- 未建立真实手机性能矩阵；模拟器速度不能外推为普通安卓手机速度。API 31 最低版本本身也需在 Android 12 真机上验证。
- 不用内存、CPU 核数或系统版本单独决定安全性。正式设备策略应结合硬件解码/编码能力、实测模型/导出耗时、热稳定性和漏遮率；降档不能简单跳过检测。

结果记录见 [验证报告](../docs/android-prototype-validation-2026-11-02.md)。
