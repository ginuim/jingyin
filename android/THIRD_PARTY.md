# 第三方来源与交付边界

| 组件 | 固定版本/文件 | 来源 | 许可 |
| --- | --- | --- | --- |
| YuNet | `face_detection_yunet_2023mar.onnx` | OpenCV Zoo `models/face_detection_yunet` | 对应目录 MIT；完整文本随 APK assets 附带 |
| OpenCV Android | Maven `org.opencv:opencv:4.12.0` | OpenCV 官方 Maven Central 交付 | Apache-2.0；完整文本随 APK assets 附带；原生传递依赖需在发布前补齐逐项清单 |
| AndroidX / Media3 | 见 `app/build.gradle.kts` 固定版本 | Google Maven | Apache-2.0；与 OpenCV 附带文本相同 |
| Kotlin | 2.0.21 | JetBrains | Apache-2.0 |
| Gradle Wrapper | 8.9 | Gradle 官方仓库 tag `v8.9.0` | Apache-2.0 |

模型 SHA-256：`8f2383e4dd3cfbb4553ea8718107fc0423210dc964f9f4280604804ed2552fa4`。

模型原地址：<https://github.com/opencv/opencv_zoo/tree/main/models/face_detection_yunet>。许可核对为该子目录，不从整个模型集合的顶层许可推断。

此原型没有集成 Ultralytics、InsightFace、NanoDet 或 ncnn。后续加入模型时，代码许可、具体权重、训练数据来源、导出工具与运行库需要分别留档，不因转成其他推理格式而改变许可。

当前仅为本地开发测试交付，尚未完成上架所需的完整 SBOM、原生依赖 NOTICE 审计、发布签名和商店政策检查。
