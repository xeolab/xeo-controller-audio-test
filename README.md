# XEO 手柄探针

原生 iOS 台架工具。测试 iOS 兼容手柄的左右扳机输入与触觉，并比较 iPhone、AirPods 和 USB / HDMI 设备上的多声道回放。iOS / iPadOS 17 起可用。

## 手柄测试

1. 连接 Xbox Elite Series 2、GameSir G8+ MFi、DualSense 或其他 iOS 兼容手柄。进入「手柄」，选中设备，在「扳机输入」分别扣动左右扳机，观察按下或松开的状态，模拟扳机还会显示行程百分比。验证有线时，在 iPhone「设置」中关闭蓝牙，再按手柄说明用支持数据的线连接，并做拔线对照。
2. 在「触觉输出」选择位置和波形。系统报告左右扳机或握把位置时，逐个选择并播放，记录对应位置的触感。
3. DualSense 可在「自适应扳机」选择固定振动、振幅递增或线性阻力。下发后扣动对应扳机，读取设备回报的状态。每次下发 20 秒，可随时按「全部停止」。

扳机输入读取 `GCExtendedGamepad` 或通用物理输入配置的左右按钮。Core Haptics 位置根据 `GCDeviceHaptics.supportedLocalities` 开放。自适应扳机使用 `GCDualSenseAdaptiveTrigger`。系统控制器配置和触觉支持取决于型号、连接方式及固件。[Apple 扩展手柄输入](https://developer.apple.com/documentation/gamecontroller/gcextendedgamepad/lefttrigger) · [控制器触觉位置](https://developer.apple.com/documentation/gamecontroller/gcdevicehaptics) · [Apple Xbox 手柄连接指南](https://support.apple.com/en-ca/111101) · [GameSir G8+ MFi 说明](https://gamesir.com/support/manuals/gamesir-g8-plus-mfi)

## 音频测试

1. 打开「音频」，选一个样本并播放。先用 iPhone 外放记录基线，再插入目标设备、播同一片段并比较读数。在定位样本播放中对照「当前测试声道」听哪一侧发声。
2. 在「片源格式」读取系统暴露的音轨编码、采样率和声道数。在「当前输出设备」看当前/最大声道、系统输出节点格式、采样率及空间音频状态。也可以在待播放时点「读取当前输出」。App 保持 iOS 默认输出设置。
3. 测 AirPods 时，可在控制中心切换空间音频，再用同一片段试听。「允许多声道空间化」是 App 提交给 AVPlayer 的许可；设备的系统状态在输出区显示。双声道耳机也可以进行空间化。测试 USB 或 HDMI 上的物理声道、传输封包或 Atmos 解码时，以接收设备读数、逐声道听感或外部信号采集为准。

| 样本 | 实测片源 | 发声顺序 |
|---|---|---|
| 立体声 | FLAC，16 bit / 48 kHz，2 声道 | 左、右 |
| 5.1 环绕 | FLAC，16 bit / 48 kHz，6 声道 | 左前、右前、中置、低频、左侧、右侧 |
| 7.1 环绕 | FLAC，16 bit / 48 kHz，8 声道 | 5.1 顺序之后接左后、右后 |
| Dolby Atmos | Apple 官方 HLS，EC-3 + JOC，48 kHz，5.1 兼容层 | 预告片音轨，需联网 |

Apple 样本直连指定的 Atmos 音频播放列表。已用 `ffprobe` 检验 Apple fMP4 初始化段与第一个媒体段，显示 `Dolby Digital Plus + Dolby Atmos`、`5.1(side)` 和 48 kHz。主清单的 `16/JOC` 对应编码复杂度字段。也可从「文件」导入自己的测试媒体，查看 AVFoundation 识别的音轨描述。[Apple 官方 HLS 样本](https://developer.apple.com/streaming/examples/advanced-stream-dv-atmos.html) · [HLS JOC 信令规范](https://developer.apple.com/streaming/hls-authoring-specification-for-apple-devices.html) · [Apple Spatial Audio 播放与路由说明](https://developer.apple.com/videos/play/wwdc2021/10265/) · [系统输出节点的硬件格式](https://developer.apple.com/documentation/avfaudio/avaudioengine/outputnode)

## 本机构建

在 Xcode 打开 `XEOProbe.xcodeproj`，选本机开发 Team 和连接的设备，运行 `XEOProbe`。在命令行可用以下命令替换 `TEAM_ID` 和 `DEVICE_ID` 后构建和安装。

```sh
xcodebuild -project XEOProbe.xcodeproj -scheme XEOProbe -configuration Debug \
  -destination 'id=DEVICE_ID' -derivedDataPath build \
  DEVELOPMENT_TEAM=TEAM_ID -allowProvisioningUpdates build
xcrun devicectl device install app --device DEVICE_ID build/Build/Products/Debug-iphoneos/XEOProbe.app
```

`project.yml` 修改后运行 `xcodegen generate` 更新工程。执行 `python3 Tools/make_audio_samples.py` 重新生成三个离线样本，需安装 FFmpeg。

[验证需求](docs/验证需求.md)
