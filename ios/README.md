# iOS 客户端

目标：SwiftUI 原生 App，单用户登录，支持 Face ID 解锁本地会话、中文语音输入和经营看板。

## Xcode 设置

```sh
git pull origin main
brew install xcodegen   # 已安装可跳过
cd ios
xcodegen generate
open LuohaoAssistant.xcodeproj
```

工程文件已经包含 Bundle ID、Team、签名 profile、权限说明和 `https://luo.hsh6.com`，不需要手动新建项目或复制 Swift 文件。

## 验收顺序

1. 选择 iPhone 17 Pro Max 或 iPhone 14 Simulator，执行 `Command + B`，再运行登录和下拉刷新。
2. 在助理页点击麦克风，允许麦克风和语音识别权限，确认中文转写。
3. 在财务页新增一笔记录，确认出现二次确认后才写入。
4. 在事项页创建事项，在项目页创建项目，在本周计划中编辑并保存。
5. 在真机上验证 Face ID、语音输入和财务确认；Simulator 不能证明真实麦克风体验。
6. 最后在 Codemagic 运行 `ios-adhoc` workflow，下载 `build/ios/ipa/*.ipa`。

Mac/Xcode 是生成签名、安装到 iPhone 和验证 Face ID 的必要环境。
