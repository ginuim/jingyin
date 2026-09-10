# 镜隐 App Store 商店文案与审核备注草稿

更新日期：2026-09-10

本文件是可直接复制到 App Store Connect 的文案草稿。实际填写、截图上传和随构建提交
仍需在 App Store Connect 中完成。

2026-09-09 优化简体中文文案并补充中文审核备注；贴纸与 Emoji 纳入当前商店表达，不再沿用旧方案的“人脸贴纸后置”表述。当天只在 App Store Connect 保存了四种语言的推广文本，其中繁中、英文、日文推广文本仍是旧稿。

2026-09-10 仓库草稿已按简中结构同步繁中、英文、日文的名称、副标题、宣传文本、描述、关键词，以及英文审核备注。商店后台尚未按本稿回填。描述不再单列 ASCII（应用内仍保留该效果）；手动遮盖只写拖动、缩放和不同时间的位置，不写指定人脸跟踪。

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

鏡隱 - 影片照片打碼與遮臉

### 副標題

馬賽克與人臉模糊，照片批量，本機處理

### 宣傳文字

分享畫面，也留住隱私。為影片遮住人臉，為多張照片統一打碼，再逐張檢查調整。支援馬賽克、模糊和 Emoji 貼紙遮臉，辨識與處理都在 iPhone 本機完成，原始素材不上傳。免費編輯預覽，一次買斷解鎖完整影片與照片批量匯出。

### 描述

鏡隱是一款在 iPhone 本機處理的影片與照片打碼工具。遮住不想公開的人臉和畫面，照片還能批量處理，原始素材無需上傳。

影片與照片均支援：

• 像素化、模糊和 Emoji 貼紙遮臉
• 自動偵測畫面中的人臉、人物和貓狗，並加入遮蓋
• 手動加入橢圓或矩形遮蓋
• 儲存到照片圖庫或透過系統分享

Emoji 貼紙用於人臉遮蓋；其他主體或手動區域可使用像素化、模糊等效果。

照片可以一次選擇多張，統一處理，再逐張覆核和調整。

影片中的手動遮蓋可拖曳、縮放，並設定它在不同時間的位置；聲音可以保留原聲、靜音或改變音高。

所有偵測和處理均在裝置本機完成。匯出時移除原始素材中的位置、裝置和拍攝時間等中繼資料，減少附帶資訊外洩。

免費版可完整編輯和預覽：影片可匯出前 30 秒、最高 720p、無浮水印；照片每次可匯出 1 張。一次買斷永久版，即可解鎖完整影片匯出和照片批量匯出。無訂閱，無廣告。

目前可匯入最長 5 分鐘、最大 1 GB 的影片；永久版可匯出所匯入影片的完整時長。

### 關鍵字（85 UTF-8 字節）

圖片,像素化,隱私,遮擋,貼紙,emoji,表情,路人,兒童,寵物,變音,離線

## English

### Name

lenshide - Face Blur & Mosaic

### Subtitle

Mosaic, face blur, photo batch

### Promotional Text

Cover faces in video; batch photos, then check each. Mosaic, blur, emoji stickers on iPhone; no upload. Free edit/preview; buy once for full video and photo batch export.

### Description

lenshide is an on-device video and photo redaction tool for iPhone. Cover faces and other areas you do not want public. Photos can be processed in a batch. Originals are not uploaded.

Video and photos both support:

• Pixelation, blur, and emoji stickers for covering faces
• Automatic detection of faces, people, and cats or dogs, then adding covers
• Manually added ellipse or rectangle covers
• Save to Photos or share with the system share sheet

Emoji stickers are for covering faces. Other subjects or manual areas can use pixelation, blur, and similar effects.

Select multiple photos at once, apply the same treatment, then review and adjust each image.

Manual covers in a video can be moved, resized, and placed at different times. Audio can stay original, be muted, or have its pitch shifted.

All detection and processing run on the device. Export removes location, device, and capture-time metadata from the source, so less extra information leaves with the file.

The free version includes full editing and preview: video export is limited to the first 30 seconds at up to 720p with no watermark; photos are limited to 1 image per export. A one-time Lifetime purchase unlocks full video export and batch photo export. No subscription. No ads.

Imported videos can be up to 5 minutes and 1 GB. Lifetime can export the full duration of the imported video.

### Keywords (80 characters)

photo,pixelate,privacy,cover,sticker,emoji,face,bystander,kids,pet,pitch,offline

## 日本語

### 名前

lenshide - 顔隠しとモザイク

### サブタイトル

モザイクと顔ぼかし、写真一括、端末内

### プロモーションテキスト

画面は共有しても、プライバシーは残す。動画の顔を隠し、複数の写真をまとめて処理し、1枚ずつ確認・調整。モザイク、ぼかし、Emojiステッカーで顔を覆い、認識と処理はiPhone上で完結。元データはアップロードしません。無料で編集・プレビュー。買い切りでフル動画と写真一括書き出し。

### 説明

lenshide は、iPhone 上で動作する動画・写真のモザイク／顔隠しツールです。公開したくない顔や画面を隠し、写真はまとめて処理できます。元データはアップロードしません。

動画と写真の両方で利用できます：

• モザイク、ぼかし、Emojiステッカーで顔を隠す
• 画面内の顔、人物、猫と犬を自動検出して覆う
• 楕円または長方形の手動マスクを追加
• 写真アプリに保存、またはシステムの共有シートから共有

Emojiステッカーは顔を隠す用途です。他の対象や手動範囲にはモザイク、ぼかしなどを使えます。

写真は一度に複数枚を選び、同じ設定で処理し、1枚ずつ確認・調整できます。

動画の手動マスクは移動・サイズ変更でき、時間ごとの位置も設定できます。音声は元のまま、消音、または音高の変更が可能です。

検出と処理はすべて端末内で行います。書き出し時に、元データに含まれる位置情報、端末、撮影日時などのメタデータを削除し、付随情報の持ち出しを減らします。

無料版ではすべての編集とプレビューが利用できます。動画の書き出しは先頭 30 秒・最大 720p・透かしなし、写真は1回につき1枚までです。買い切りの永久版で、フル動画書き出しと写真の一括書き出しを解除します。サブスクリプションなし、広告なし。

読み込める動画は最長 5 分、最大 1 GB です。永久版は、読み込んだ動画の全長を書き出せます。

### キーワード（42 文字 / 98 UTF-8 バイト）

写真,モザイク,ステッカー,emoji,顔,通行人,子ども,ペット,変声,オフライン

## App Review Notes（英文，可直接粘贴）

lenshide does not require an account or sign-in. No demo account is needed.

All video frames, photo pixels, face detection, audio processing, and exports run locally on the device. Original media, recognition data, and exports are not uploaded to the developer’s servers.

Face data use, retention, and deletion:

• Photo processing enables face covering by default. After Face is selected as the video cover subject, Apple Vision detects face locations on-device and temporarily creates bounding boxes, normalized coordinates, masks, or keyframes to place pixelation, blur, or emoji sticker effects.
• The app does not identify or confirm a person’s identity and does not create face embeddings, biometric templates, or identity labels. Face data is not used for authentication, advertising, marketing, analytics, or profiling. It is not uploaded or shared with third parties. The developer cannot access it.
• Face coordinates, masks, and keyframes stay in volatile memory for the current edit and export session and are discarded when the session ends or the app terminates. They are not written to a persistent database or user defaults. Video timeline thumbnails and region-edit undo state are also session-only, are not written to disk or preferences, and are released when the editor is closed or the app terminates.
• Input copies, intermediate files, and export temp files are kept only while editing, previewing, exporting, or showing results. Leaving a project, canceling, failing, or leaving the result screen cleans up the matching temp files. Later launches clean recognized leftover files. Deleting the app removes remaining sandbox data. Copies the user saves to Photos or Files are managed by the user.

Free users can fully edit and preview. The processor enforces video export of the first 30 seconds at up to 720p with no watermark, and at most 1 photo per export.

The only in-app purchase is Non-Consumable Lifetime Access, Product ID: com.reaidea.jingyin.lifetime. One purchase unlocks full video export and batch photo export. Not a subscription. Video import remains limited to 5 minutes and 1 GB.

Purchase path: open Settings, go to the Lifetime Access section, tap Unlock, then tap the purchase button that shows the localized App Store price. In App Review, complete or cancel the purchase.

Restore path: open Settings, go to the Lifetime Access section, tap Restore Purchases. Production entitlement comes from current StoreKit 2 transactions. Do not treat development unlock arguments as purchase verification.

Privacy policy: https://lenshide.reaidea.com/privacy

## 提交前人工核对

- [x] 2026-09-09：已在 App Store Connect 保存四种语言的推广文本，并核对剩余字符数：简中 60、繁中 126、英文 32、日文 114；此次不触发新的 App 审核。后台这四条推广文本仍是旧稿，与 2026-09-10 仓库草稿不一致。
- [x] 2026-09-10：仓库内繁中 / 英文 / 日文名称、副标题、宣传文本、描述、关键词，以及英文审核备注，已按简中事实同步（Emoji 贴纸、去掉商店描述中的 ASCII、手动位置而非指定人脸跟踪、设置页购买与恢复、人脸数据用途与保留删除）。
- [x] 2026-09-10：已在 App Store Connect 的 iOS `1.0.2`（准备提交）按本稿保存简中 / 繁中 / 英文 / 日文的名称、副标题、宣传文本、描述、关键词、此版本新增内容，以及英文审核备注。四种语言 iPhone 6.9 英寸截屏顺序已改为原 3、4、1、2。未点「添加以供审核」；`1.0.2` 尚无新构建。`1.0.1` 仍为可分发，检查前不要手动发布旧版。
- [x] 2026-09-10 19:50：已提交 iOS `1.0.2 (7)` 审核（状态：正在等待审核）。本次提交内容为 1 个项目（App 版本）；未把 IAP 一并加入该草稿。构建由本机归档上传。`1.0.1` 仍为可分发。
- [ ] 确认营销 URL、隐私政策 URL 和支持 URL 在公网可访问
- [ ] 确认支持 URL 直达镜隐帮助与联系页面，并提供实际联系信息（例如支持邮箱）
- [ ] 确认审核备注包含无需登录、人脸数据用途与保留删除方式、免费限制、永久版 Product ID、购买与恢复入口
- [ ] Review Notes 中的界面路径与送审构建完全一致
- [ ] IAP 显示名称与 App Store Connect 当前本地化一致（含「视频 + 照片批量」描述）
- [ ] 确认照片批量及人脸 Emoji 贴纸在送审构建的预览与导出中均可用
- [ ] 将 `com.reaidea.jingyin.lifetime` 和该 App 版本一起提交审核
