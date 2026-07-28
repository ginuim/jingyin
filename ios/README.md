# 镜隐 iOS

原生 SwiftUI MVP，最低支持 iOS 17。视频读取、Vision 人像分割、Core Image
遮盖、AVFoundation 编码、相册保存均在设备本地完成。

## 命令行启动

```bash
cd ios
chmod +x run-ios.sh
./run-ios.sh
```

默认启动 `iPhone 17 Pro` 模拟器。指定其他已安装设备：

```bash
IOS_SIMULATOR="iPhone 17 Pro" ./run-ios.sh
```

只构建：

```bash
xcodebuild -project Jingyin.xcodeproj \
  -scheme Jingyin \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO build
```

模拟器相册需先放入测试视频，也可在应用中从“文件”导入。真机运行需要在
Xcode 的 Signing & Capabilities 中选择开发团队。

## 运行到真实 iPhone

首次运行需要一台 macOS、Xcode、Apple ID，以及一根已连接 Mac 的 iPhone：

1. 用 Xcode 打开 `ios/Jingyin.xcodeproj`。
2. 在工程设置的 **Signing & Capabilities** 中选择你的 Team。
3. 如果出现 Bundle Identifier 冲突，把 `com.reaidea.jingyin` 改成你自己的唯一标识。
4. 在 iPhone 上点“信任此电脑”，并在“设置 → 隐私与安全性 → 开发者模式”开启开发者模式。
5. 在 Xcode 的设备选择器中选中 iPhone，点击 Run。第一次启动时，若提示开发者不受信任，按系统提示完成信任后重新打开应用。

也可以完全通过命令行运行。先获取设备 UDID：

```bash
xcrun devicectl list devices
```

然后将 `TEAM_ID`、`DEVICE_UDID` 替换为你的值：

```bash
cd /Users/tao/Workspace/jingyin/ios

xcodebuild \
  -project Jingyin.xcodeproj \
  -scheme Jingyin \
  -configuration Debug \
  -destination "platform=iOS,id=DEVICE_UDID" \
  -derivedDataPath .device-derived-data \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM=TEAM_ID \
  CODE_SIGN_STYLE=Automatic \
  build

xcrun devicectl device install app \
  --device DEVICE_UDID \
  .device-derived-data/Build/Products/Debug-iphoneos/Jingyin.app

xcrun devicectl device process launch \
  --device DEVICE_UDID \
  com.reaidea.jingyin
```

如果团队配置已经保存在工程中，可以省略 `DEVELOPMENT_TEAM=TEAM_ID`；如果
Xcode 无法自动创建签名配置，先在 Xcode 中用同一 Apple ID 成功运行一次，再重新执行命令行构建。

真机命令行构建产生的 `.device-derived-data` 只用于本地签名产物，已被 Git 忽略。

## 当前能力

- 相册或文件导入
- 编辑页实时显示遮盖效果
- 精细人物轮廓分割、独立人脸遮盖、宠物区域识别、背景或全画面遮盖
- 模糊、像素化和黑白 ASCII 字符画效果、三档推理频率
- 原声、变音（可调半音、实时试听）或静音
- 导出分辨率与帧率选择、进度、稳定的剩余时间估算、取消和失败重试
- StoreKit 2 永久解锁、恢复购买；免费版导出前 30 秒且最高 720p
- 5 分钟/1 GB 限制、存储空间检查和精细档自动降级
- 导出预览、保存相册、系统分享

宠物当前使用 Vision 区域识别。人物使用 Vision 语义分割；精细档会再用前景
实例蒙版细化头发、衣物和四肢边缘。只有像素级分割不可用时才会启用人形框
兜底，避免矩形区域破坏人物轮廓。人脸可单独选择，并使用带羽化的椭圆安全区
覆盖额头、下巴和耳部。变音使用系统 `AVAudioUnitTimePitch`，预览与导出共用
同一半音设置，并会记住上次音调。

## StoreKit 2

永久解锁产品 ID 固定为：

```text
com.reaidea.jingyin.lifetime
```

需要在 App Store Connect 中创建同名的 Non-Consumable 产品并配置价格。产品尚未
创建或当前网络不可用时，App 会继续提供免费预览和免费短片导出，但购买按钮不可用。

Debug 构建可使用 `-storekitUnlocked` 启动参数模拟已买断状态，用于验证完整导出
路径；该参数不会编译进 Release 构建。

## 已验证样例

仓库中的 `work/trump-test-h264.mp4` 已在 iPhone 17 Pro（iOS 26）模拟器
完成端到端测试：导入、人物与宠物识别、H.264/AAC 导出和结果预览均成功，
输出时长约 4.99 秒、分辨率 588×1280。
