# macOS 兼容性

BumpPump 1.0.3 的最低系统版本为 macOS 13.0，安装包适用于 Apple Silicon（arm64）。Intel Mac 不在当前安装包支持范围内。

| 系统 | 界面实现 |
|---|---|
| macOS 13 | 普通系统按钮与材质、路径绘制环图、兼容设置入口及动画；滚动使用该系统的标准裁切行为 |
| macOS 14–25 | 原有 Swift Charts 环图、数字滚动、滚动透层等系统能力 |
| macOS 26 及以上 | 在上述功能基础上启用原生 Liquid Glass |

运行要求和构建要求不同：编译源码仍需要支持 Liquid Glass 的 macOS 26+ SDK，生成的应用可部署到 macOS 13。新 API 使用版本判断和替代实现，不能仅通过修改版本号完成兼容。

验证方式：完整应用按 macOS 13 编译，检查 Info.plist 的最低版本及可执行文件的 LC_BUILD_VERSION，并执行 script 中的数据、助手、输入法、连接、版本检查和 macOS 兼容测试。兼容测试直接检查 Ventura 路径环图的透明中心、扇区方向、间隙及零值。

目前这些编译和测试在较新 macOS 主机执行，尚未在 macOS 13 真机或虚拟机完整运行验证。发布说明应保留这一限制，不能将编译通过描述为 Ventura 实机测试通过。
