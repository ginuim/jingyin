# 第三方来源与交付边界

| 组件 | 固定版本/文件 | 来源 | 许可 |
| --- | --- | --- | --- |
| YuNet | `face_detection_yunet_2023mar.onnx` | OpenCV Zoo `models/face_detection_yunet` | 对应目录 MIT；完整文本随 APK assets 附带 |
| DeepLab-v3 人物分割 | `deeplab_v3.tflite` | MediaPipe 模型库 `image_segmenter/deeplab_v3/float32/1` | **许可未确认，禁止用于发布**：权重为 PASCAL VOC 21 类（person = 15）训练，模型卡未附随包许可文本；VOC 数据集条款通常仅限研究/教育用途。正式版必须替换为许可明确的权重或取得商用授权，并在替换前不提交商店 |
| TensorFlow Lite | Maven `org.tensorflow:tensorflow-lite:2.16.1` | Google Maven | Apache-2.0 |
| OpenCV Android | Maven `org.opencv:opencv:4.12.0` | OpenCV 官方 Maven Central 交付 | Apache-2.0；完整文本随 APK assets 附带；原生传递依赖需在发布前补齐逐项清单 |
| AndroidX / Media3 | 见 `app/build.gradle.kts` 固定版本 | Google Maven | Apache-2.0；与 OpenCV 附带文本相同 |
| Kotlin | 2.0.21 | JetBrains | Apache-2.0 |
| Gradle Wrapper | 8.9 | Gradle 官方仓库 tag `v8.9.0` | Apache-2.0 |

模型 SHA-256：`8f2383e4dd3cfbb4553ea8718107fc0423210dc964f9f4280604804ed2552fa4`。

分割模型 SHA-256：`ff36e24d40547fe9e645e2f4e8745d1876d6e38b332d39a82f0bf0f5d1d561b3`（`deeplab_v3.tflite`，2,780,176 字节），原地址 <https://storage.googleapis.com/mediapipe-models/image_segmenter/deeplab_v3/float32/1/deeplab_v3.tflite>。该模型位于 debug 专用资源目录，只打入 Debug APK，Release 不包含该权重。正式启用轮廓分割前必须换用许可明确的权重或取得授权。

未引入 MediaPipe Tasks：其 `ImageSegmenter` 图在创建阶段即初始化 GL 后处理，需要 GLES 3.1 compute；实验机与模拟器上分别暴露 3.0，故改用 TFLite CPU 解释器自行实现输入缩放与掩码后处理。

模型原地址：<https://github.com/opencv/opencv_zoo/tree/main/models/face_detection_yunet>。许可核对为该子目录，不从整个模型集合的顶层许可推断。

此原型没有集成 Ultralytics、InsightFace、NanoDet、ncnn 或 MediaPipe Tasks。后续加入模型时，代码许可、具体权重、训练数据来源、导出工具与运行库需要分别留档，不因转成其他推理格式而改变许可。

当前仅为本地开发测试交付，尚未完成上架所需的完整 SBOM、原生依赖 NOTICE 审计、发布签名和商店政策检查。
