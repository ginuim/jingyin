# 镜隐 App Store 商店文案与审核备注草稿

更新日期：2026-09-09

本文件是可直接复制到 App Store Connect 的文案草稿。实际填写、截图上传和随构建提交
仍需在 App Store Connect 中完成。

2026-09-09 本轮优化简体中文文案并补充中文审核备注与提交核对事项；贴纸与 Emoji 纳入当前商店表达，不再沿用旧方案的“人脸贴纸后置”表述。当天已在 App Store Connect 保存简中、繁中、英文、日文四种语言的推广文本；其余繁中、英文、日文字段及英文审核备注仍保留现有草稿，尚未按本轮简中调整同步。

## 字段约束与公共信息

以下长度按 Apple 当前字段要求准备：

- App 名称：最多 30 个字符
- 副标题：最多 30 个字符
- 宣传文本：最多 170 个字符
- 描述：最多 4,000 个字符，使用纯文本
- 关键词：使用半角逗号分隔，不加逗号两侧空格。Apple 产品页指南写 100 个字符，Connect 字段参考写 100 字节；本轮简中稿保守控制在 100 个 UTF-8 字节以内，提交时仍检查实际保存校验
- App Review Notes：最多 4,000 字节

Apple 参考：

- [Creating your product page](https://developer.apple.com/app-store/product-page/)
- [App information](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information/)
- [Platform version information](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information)

公共链接：

- 营销 URL：`https://lenshide.reaidea.com`
- 隐私政策 URL：`https://lenshide.reaidea.com/privacy`
- 支持 URL：当前草稿为 `https://reaidea.com`；建议改为直达镜隐帮助与联系页面的实际 URL。目标页面尚待确认，不预填不存在的路径；页面须提供实际联系信息（例如支持邮箱），便于反馈问题与功能建议，不能只有产品介绍。

## 简体中文

### 名称

镜隐 - 视频照片打码与遮脸

### 副标题

马赛克与人脸模糊，照片批量，本地处理

### 宣传文本

分享画面，也留住隐私。为视频遮住人脸，为多张照片统一打码，再逐张检查调整。支持马赛克、模糊和 Emoji 贴纸遮脸，识别与处理都在 iPhone 本地完成，原素材不上传。免费编辑预览，一次买断解锁完整视频与照片批量导出。

### 描述

镜隐是一款在 iPhone 本地处理的视频与照片打码工具。遮住不想公开的人脸和画面，照片还能批量处理，原素材无需上传。

视频与照片均支持：

• 像素化、模糊和 Emoji 贴纸遮脸
• 自动检测画面中的人脸、人物和猫狗，并添加遮盖
• 手动添加椭圆或矩形遮盖
• 保存到相册或通过系统分享

Emoji 贴纸用于人脸遮盖；其他主体或手动区域可使用像素化、模糊等效果。

照片可以一次选择多张，统一处理，再逐张复核和调整。

视频中的手动遮盖可拖动、缩放，并设置它在不同时间的位置；声音可以保留原声、静音或改变音高。

所有检测和处理均在设备本地完成。导出时移除原素材中的位置、设备和拍摄时间等元数据，减少附带信息泄露。

免费版可完整编辑和预览：视频可导出前 30 秒、最高 720p、无水印；照片每次可导出 1 张。一次买断永久版，即可解锁完整视频导出和照片批量导出。无订阅，无广告。

当前可导入最长 5 分钟、最大 1 GB 的视频；永久版可导出所导入视频的完整时长。

### 关键词

图片,像素化,隐私,遮挡,贴纸,emoji,表情,路人,儿童,宠物,变音,离线

### 简中文案优化记录（不复制到商店字段）

- 保留名称中的视频、照片、打码与遮脸；副标题补充本地处理和照片批量价值。
- 关键词明确保留“贴纸”和“emoji”；当前候选未经过搜索量或转化验证，后续依据实际表现调整。
- 宣传文本用于解释使用价值，不为搜索排名堆词；描述明确手动位置调整，避免暗示指定人脸自动跟踪已开放。
- 保留免费 30 秒 / 720p / 无水印、照片每次 1 张，以及买断后的导出权益；“完整视频”仍受导入最长 5 分钟、最大 1 GB 限制。

### App Review Notes（简体中文草稿）

镜隐无需注册或登录，无需提供演示账号。

视频帧、照片像素、人脸检测、音频处理和导出均在设备本地完成。原素材、识别数据和导出结果不会上传到开发者服务器。

人脸数据用途与保留删除方式：

• 照片处理默认开启人脸遮盖；视频选择“人脸”作为遮盖主体后，使用 Apple Vision 在本地检测人脸位置，临时生成边界框、归一化坐标、蒙版或关键帧，用于放置像素化、模糊或 Emoji 贴纸效果。
• 不识别或确认人物身份，不创建人脸特征向量、生物识别模板或身份标签；人脸数据不用于身份验证、广告、营销、分析或用户画像，不上传或共享给第三方，开发者无法访问。
• 人脸坐标、蒙版和关键帧仅保存在当前编辑与导出会话的易失性内存中，会话结束或 App 终止后丢弃，不写入持久化数据库或用户偏好。视频时间轴缩略图与区域修改撤销状态也仅用于当前会话，不写入磁盘或偏好设置，关闭编辑器或 App 终止时释放。
• 输入副本、中间文件和导出临时文件仅在编辑、预览、导出或展示结果所需期间保留。离开项目、取消、失败或离开结果页时清理相应临时文件；后续启动清理已识别的遗留文件。删除 App 会移除剩余沙盒数据。用户主动保存到照片图库或“文件”的副本由用户自行管理。

免费版可完整编辑和预览；处理器内部强制视频仅导出前 30 秒、最高 720p、无水印，照片每次最多导出 1 张。

唯一内购为非消耗型永久版，Product ID：com.reaidea.jingyin.lifetime。一次购买解锁完整视频与照片批量导出，无订阅。视频导入仍限制最长 5 分钟、最大 1 GB。

购买入口：打开设置中的永久版区域，点击永久解锁，再点击显示 App Store 本地化价格的购买按钮。可在审核环境验证完成或取消购买。

恢复入口：打开设置中的永久版区域，点击恢复购买。生产权益由 StoreKit 2 当前交易权益判断，不使用开发调试解锁参数作为购买验证。

隐私政策：https://lenshide.reaidea.com/privacy

### 中文审核备注使用说明（不复制到 Notes）

- 上述人脸说明依据当前简中隐私政策，记录现有行为，不引入新的数据收集或存储方式；提交前与送审构建和线上政策再次核对。
- 购买与恢复入口的按钮名称、位置须在送审构建实测，真实购买与恢复仍需 Sandbox / TestFlight 或真实 iPhone 验证。
- 支持页面最终 URL、联系信息及公网可访问性待核对；确认后填写到 Support URL 字段。

## 繁體中文

### 名稱

鏡隱

### 副標題

本機影片與照片隱私遮蓋

### 宣傳文字

影片與照片全程在裝置本機處理：像素化、模糊、手動遮蓋、照片批次與變聲，無需上傳原始素材。

### 描述

鏡隱是一款端側影片與照片隱私處理工具。原始素材、辨識資料和匯出結果都在你的裝置上處理，
無需上傳伺服器。

主要功能：

• 從照片圖庫或「檔案」匯入影片；從圖庫多選照片批次處理  
• 對人物、人臉、貓狗或手動橢圓／矩形區域加入遮蓋  
• 支援隱私級像素化、視覺模糊和 ASCII 效果  
• 影片可手動拖曳、縮放遮蓋並調整關鍵影格；照片可逐張覆核遮罩  
• 保留原聲、靜音匯出或改變音高  
• 匯出時清除位置、裝置和拍攝時間等來源中繼資料  
• 儲存到照片圖庫或透過系統分享面板傳送

免費版可以完整編輯和預覽：影片匯出前 30 秒、最高 720p、無浮水印；照片每次匯出 1 張。
一次買斷永久版後可解除影片時長與解析度限制，並解鎖照片批次匯出。

首個版本專注於可靠處理短影片與照片批次，影片支援最長 5 分鐘、最大 1 GB。

### 關鍵字（87 字節）

影片隱私,照片遮蓋,批次打碼,像素化,人臉遮蓋,聲音變調,本機處理

## English

### Name

lenshide

### Subtitle

On-device media privacy

### Promotional Text

Process videos and photos on your device with pixelation, blur, manual masks, batch photos, mute, and pitch shift. Originals stay offline.

### Description

lenshide is an on-device video and photo privacy tool. Original media, recognition data, and
exports are processed on your device and are never uploaded to a server.

Key features:

• Import videos from Photos or Files; multi-select photos for batch processing  
• Cover people, faces, cats and dogs, or manually placed ellipse and rectangle areas  
• Choose privacy-focused pixelation, visual blur, or an ASCII effect  
• Move and resize video masks with keyframes; review and adjust photo masks one by one  
• Keep original audio, export silently, or shift voice pitch  
• Remove source location, device, and capture-time metadata during export  
• Save to Photos or share through the system share sheet

The free version includes full editing and preview. Video exports are limited to the first 30
seconds at up to 720p with no watermark; photo exports are limited to 1 image per run. A
one-time Lifetime Access purchase unlocks full video exports and batch photo exports.

The first version focuses on reliable short-video processing and photo batching, and supports
videos up to 5 minutes and files up to 1 GB.

### Keywords (66 bytes)

video privacy,photo blur,batch,pixelate,face mask,offline,metadata

## 日本語

### 名前

lenshide

### サブタイトル

端末内で動画と写真を保護

### プロモーションテキスト

モザイク、ぼかし、手動マスク、写真一括、消音、声の高さ変更をすべて端末内で処理。元データはアップロードしません。

### 説明

lenshide は、端末内で動作する動画・写真プライバシー保護ツールです。元のメディア、認識データ、
書き出し結果は端末内で処理され、サーバーへアップロードされません。

主な機能：

• 写真または「ファイル」から動画を読み込み；写真の複数選択で一括処理  
• 人物、顔、猫と犬、または手動で置いた楕円／長方形の範囲を隠す  
• プライバシー向けモザイク、視覚的なぼかし、ASCII エフェクト  
• 動画マスクの移動・サイズ変更とキーフレーム調整；写真は1枚ずつ確認  
• 元の音声、消音書き出し、声の高さ変更  
• 書き出し時に位置情報、端末、撮影日時などの元メタデータを削除  
• 写真への保存、またはシステム共有シートから共有

無料版では、すべての編集とプレビューを利用できます。動画の書き出しは先頭 30 秒・最大 720p・
透かしなし；写真は1回につき1枚までです。買い切りの永久版で動画制限を解除し、写真の一括
書き出しも利用できます。

初版は短い動画と写真一括の確実な処理を重視し、最長 5 分、最大 1 GB の動画ファイルに対応します。

### キーワード（80 バイト）

動画保護,写真モザイク,一括処理,ぼかし,顔隠し,オフライン

## App Review Notes（英文，可直接粘贴）

lenshide does not require an account or sign-in.

All video frames, photo pixels, recognition data, audio processing, and exports are processed
locally on the device. The app does not upload the user's original media or export to a server.

Free users can use the complete editor and preview. Export limits are enforced inside the
processing pipeline: videos are limited to the first 30 seconds at up to 720p with no watermark;
photos are limited to 1 image per export run.

The app offers one Non-Consumable in-app purchase:

- Product ID: `com.reaidea.jingyin.lifetime`
- Display name: Lifetime Access
- One-time unlock for full video exports and batch photo exports (not a subscription).

To test the purchase:

1. Import a video from Photos or Files, or select photos for batch processing.
2. Complete editing and proceed to Export.
3. Tap Unlock on the export screen.
4. On the Lifetime Access screen, tap the purchase button showing the localized App Store price.
5. Use an App Review Sandbox account to complete or cancel the purchase.

To test Restore Purchases:

1. Open Settings.
2. Under Lifetime Access, tap Restore Purchases.

The editor supports original audio, silent export, and offline pitch shifting. The first release
accepts video files up to 5 minutes and 1 GB, plus on-device photo batch processing. No demo
account is required.

The development-only `-storekitUnlocked` launch argument is not part of the Release/App Review
workflow and does not grant production entitlement. Release entitlement is determined from
current StoreKit 2 transactions.

## 提交前人工核对

- [x] 2026-09-09：已在 App Store Connect 保存四种语言的推广文本，并核对剩余字符数：简中 60、繁中 126、英文 32、日文 114；此次不触发新的 App 审核。
- [ ] 本轮简中描述、关键词和中文审核备注，以及其他语言的名称、副标题、描述、关键词和英文审核备注，仍须在可编辑的下一版本中按本稿核对并同步
- [ ] 确认营销 URL、隐私政策 URL 和支持 URL 在公网可访问
- [ ] 确认支持 URL 直达镜隐帮助与联系页面，并提供实际联系信息（例如支持邮箱）
- [ ] 确认审核备注包含无需登录、人脸数据用途与保留删除方式、免费限制、永久版 Product ID、购买与恢复入口
- [ ] Review Notes 中的界面路径与送审构建完全一致
- [ ] IAP 显示名称与 App Store Connect 当前本地化一致（含「视频 + 照片批量」描述）
- [ ] 确认照片批量及人脸 Emoji 贴纸在送审构建的预览与导出中均可用
- [ ] 将 `com.reaidea.jingyin.lifetime` 和该 App 版本一起提交审核
