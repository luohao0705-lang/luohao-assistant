# iOS 客户端

目标：SwiftUI 原生 App，单用户登录，支持 Face ID 解锁本地会话、语音输入和经营看板。

## Xcode 设置

1. 在 Mac 上新建 iOS App 项目，产品名使用 `LuohaoAssistant`。
2. 将 `LuohaoAssistant/` 下的 Swift 文件加入 target。
3. 在 target 的 Signing & Capabilities 中启用你的个人 Team。
4. 在 `Info.plist` 增加：
   - `NSMicrophoneUsageDescription`
   - `NSSpeechRecognitionUsageDescription`
   - `NSFaceIDUsageDescription`
5. 将 `APIClient.baseURL` 改为 `https://luohao.hsh6.com`。

Mac/Xcode 是生成签名、安装到 iPhone 和验证 Face ID 的必要环境。
