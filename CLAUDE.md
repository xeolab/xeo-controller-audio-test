# XEO 手柄探针 · 工程入口

本仓库存放 iOS 台架验证 App。验证范围见 `docs/验证需求.md`，装机与读数方法见 `README.md`。

- 手柄输入使用 Apple Game Controller 的标准左右扳机。触觉输出按各设备报告的位置开放，DualSense 自适应效果使用对应的硬件接口。
- 回放使用 AVPlayer。片源、系统输出声道与空间化权限分别展示。外部链路的实际封包和物理出声依据实测。
- `App/Samples` 的离线定位样本可用 `Tools/make_audio_samples.py` 重新生成。Atmos 使用 Apple 官方 HLS 音轨。
- 开发签名团队通过 `xcodebuild` 参数或本机 Xcode 配置传入。
