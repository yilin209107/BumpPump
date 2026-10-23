# 发布 BumpPump · 泵碰

公开仓库：https://github.com/yilin209107/BumpPump 。本项目目录即独立源码仓库，使用 GitHub Desktop 管理提交与推送。

## 源码

上传本项目根目录的 Package.swift、Sources、Resources、Tests、script、docs、README、LICENSE、.gitignore 和 .github。不要上传 .build、dist、outputs、work、数据库、聊天、API Key 或证书。也可以解压 BumpPump-Source-v1.0.0.zip，将其 BumpPump 文件夹作为 GitHub Desktop 的本地仓库。

仓库首页使用 Resources/Cover.png。应用名称为 BumpPump，中文名为泵碰，Bundle ID 为 app.bumppump.mac，初始版本为 1.0.0。

## 安装包

运行 `./script/build.sh` 和 `python3 script/package.py`。outputs 中包含 Mac 安装 ZIP、源码 ZIP、SHA256SUMS 和 release-manifest.json。

在 GitHub Releases → Draft a new release，标签为 v1.0.0，目标 main。上传 Mac ZIP、SHA256SUMS 和 manifest；源码 ZIP 可选。先保存草稿，核对后发布。初期试用可标为 pre-release；App 内版本检查只查询正式 Release。

## 签名

默认只有 ad-hoc 签名，未公证。免费 Apple ID 不能创建用于公开分发的 Developer ID Application 证书。具备付费 Apple Developer Program 身份后，可用 script/sign_and_notarize.sh 正式签名并公证，再重新打包；证书、私钥与公证凭据不提交到 GitHub。

## 自动化

CI 验证构建及隔离测试；推送 v* 标签会尝试构建并创建 Release 草稿。流程只创建草稿，仍需检查后发布。尚未在具体远程仓库验证权限及云端执行。自动化不会提供 Apple 正式证书或自动获得公证。

参考：https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository
