# BiliMusic for iOS

基于 [HanversionOvO/BiliMusic v1.0.2](https://github.com/HanversionOvO/BiliMusic/tree/v1.0.2) 的非官方 iPhone 适配工程，使用 React、Capacitor 和原生 Swift 音频播放器。Windows 安装包及个人账号数据不包含在此工程中。

- 保留搜索、发现、歌单、收藏和最近播放。
- iPhone 触控布局、底部导航和安全区域适配。
- 原生 AVPlayer 音频播放、原生播放队列、后台切歌和锁屏播放控制。
- 原生网络接口与 Bilibili 登录页面；登录由使用者在手机上完成。
- 音频保存到应用 Documents/BiliMusic，可从“文件”App 访问和分享。

## 云编译 IPA

在 GitHub 的 Actions 页面运行 **Build iOS sideload IPA**。构建成功后，在该次运行的 Artifacts 下载 **BiliMusic-iOS-sideload**。

得到的 `BiliMusic-iOS-unsigned.ipa` 需要通过 AltStore Classic / Sideloadly 使用自己的 Apple 账号签名并安装，不需要提交 App Store，也不需要将 Apple 密码或签名证书放入仓库。

## 开发

```sh
npm ci
npm test
npm run ios:sync
npm run verify:project
```

macOS / Xcode 26 或以上版本可以继续运行：

```sh
npm run ios:ipa
```

普通浏览器预览使用 `npm run dev`；原生音频、登录和文件分享需要 iPhone 或 iOS 模拟器。后台播放、锁屏控制和 Bilibili 登录最终需要在实际 iPhone 上验证。

原项目说明保留在 `UPSTREAM-README.md`。
