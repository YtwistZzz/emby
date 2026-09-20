# Emby Player(Windows 版)

Flutter + media_kit(libmpv / FFmpeg / libass)写的 Emby 桌面播放器。

- **解码**:HEVC / AV1 / VP9 / DTS / TrueHD / PGS / ASS 等全部由 mpv 本地解码,直连播放,不占服务器转码;直连失败时自动退到服务器 HLS 转码
- **特效字幕**:libass 渲染 ASS/SSA(样式、定位、卡拉 OK、内嵌字体);内封 PGS 位图字幕、外挂 SRT/ASS 都支持
- **评分**:MDBList 一次拿 IMDb / 烂番茄 / Metacritic / TMDb / Trakt / Letterboxd,本机缓存 7 天;没填 Key 时显示 Emby 自带评分
- **Trakt**:Device Code 授权;仅在开始 / 暂停·恢复 / 拖动进度 / 结束时各发一次 scrobble,没有定时心跳;设置页可看到每条实际发出的请求

## 1. 环境准备(一次性)

1. 安装 [Flutter SDK](https://docs.flutter.dev/get-started/install/windows/desktop),把 `flutter\bin` 加入 PATH
2. 安装 **Visual Studio 2022**(Community 即可),勾选工作负载 **「使用 C++ 的桌面开发」**
3. Windows 设置 → 隐私和安全性 → 开发者选项 → 打开 **开发人员模式**(Flutter 插件需要创建符号链接)
4. 终端里运行 `flutter doctor`,确认 Flutter 和 Visual Studio 两项都是绿色对勾

## 2. 运行

```
setup_windows.bat     生成 Windows 工程并安装依赖(只需第一次)
run.bat               调试运行
build_release.bat     打包,产物在 dist\EmbyPlayer-win64.zip,解压即用
```

第一次构建时,`media_kit_libs_windows_video` 会从 GitHub 下载 libmpv,需要能访问 github.com。
国内网络如果 `pub get` 很慢,把 `setup_windows.bat` 里两行镜像设置前面的 `REM` 去掉。

## 2b. 不想装 Flutter:用 GitHub 云端编译

1. 在 GitHub 新建一个仓库(私有也行),把本项目所有文件传上去,**注意包含隐藏的 `.github` 文件夹**。
   如果网页拖拽漏掉了它,就在仓库里点 Add file → Create new file,文件名输入 `.github/workflows/build-windows.yml`,把文件内容粘进去。
2. 打开仓库的 Actions 页面 → 选 Build Windows → Run workflow
3. 等 5~10 分钟,完成后在该次运行页面底部 Artifacts 下载 `EmbyPlayer-win64`,解压后运行 `emby_player.exe`
4. 如果失败,打开日志,把红色报错贴给我

运行 exe 的电脑需要有 VC++ 运行库(绝大多数 Windows 已自带,缺的话装 Microsoft Visual C++ Redistributable 2015-2022 x64)。

## 3. 首次使用

1. 登录页填服务器地址(如 `192.168.1.10:8096`)、用户名、密码
2. 设置 → **MDBList API Key**(可选,免费注册 mdblist.com 获取)
3. 设置 → **Trakt**:
   - 到 <https://trakt.tv/oauth/applications/new> 新建应用,Redirect URI 填 `urn:ietf:wg:oauth:2.0:oob`
   - 把 Client ID / Client Secret 填进设置页,点「连接 Trakt」,浏览器里输入弹窗里的授权码
   - 服务器上如果已装 Emby 官方 Trakt 插件,不要在这里重复连接

## 4. 播放快捷键

空格 播放/暂停 · ←/→ 快退/快进 10 秒 · ↑/↓ 音量 · F / F11 全屏 · M 静音 · N / P 下一集 / 上一集 · Esc 退出全屏或返回 · 双击画面 全屏

## 5. 如何验证 Trakt「没有多发请求」

设置页底部「最近的 Trakt 请求」会逐条列出发送记录。预期表现:

| 操作 | 应出现的请求 |
| --- | --- |
| 开始播放 | 1 条 `start` |
| 暂停 / 恢复 | 各 1 条 `pause` / `start` |
| 拖动进度(连续拖) | 停手 1.5 秒后 1 条 |
| 看完或退出 | 1 条 `stop` |
| 播放中什么都不做 | **0 条** |

## 6. 项目结构

```
lib/
  core/       主题、全局状态、工具函数
  models/     Emby 数据模型
  services/
    emby_client.dart       Emby REST 封装(浏览 / 图片 / 播放信息 / 进度上报)
    ratings_service.dart   MDBList 评分聚合 + 缓存
    trakt_service.dart     Trakt 授权、令牌刷新、请求日志、离线补录
    trakt_scrobbler.dart   Scrobble 状态机(串行队列、合并、防抖、限流)
  ui/         登录 / 首页 / 媒体库 / 搜索 / 详情 / 播放 / 设置
  widgets/    海报卡片、评分徽章、横向列表
```

## 7. 已知限制

- **杜比视界**:mpv 对 DV 只能做 HDR10 层映射,Profile 5(无 HDR 兼容层)片源可能偏紫绿。完整 DV 需要系统级解码通道,Windows 上暂无好方案
- **HDR**:Windows 上 HDR 输出取决于系统是否开启 HDR,SDR 屏会自动做色调映射
- 关闭窗口时会尝试补发 `stop`,但如果进程被任务管理器强杀则不会;此时 Emby 服务端仍有 10 秒粒度的进度
- 暂无:多版本片源选择、字幕延迟调整、片头跳过、海报 blurhash 占位
- iOS 版尚未开始(需要 Mac / 云编译),`services/` 与 `models/` 是纯 Dart,后续可直接复用
