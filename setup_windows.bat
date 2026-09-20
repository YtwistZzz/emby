@echo off
chcp 65001 >nul
cd /d "%~dp0"

where flutter >nul 2>nul
if errorlevel 1 (
  echo [错误] 没有找到 flutter 命令。请先安装 Flutter SDK 并把 flutter\bin 加入 PATH。
  pause
  exit /b 1
)

REM 国内网络如果 pub get 很慢或失败,去掉下面两行开头的 REM
REM set PUB_HOSTED_URL=https://pub.flutter-io.cn
REM set FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn

if not exist windows (
  echo [1/3] 生成 Windows 平台工程...
  xcopy /E /I /Y lib .lib_backup >nul
  copy /Y pubspec.yaml .pubspec.bak >nul
  call flutter create --platforms=windows --project-name emby_player --org com.embyplayer .
  xcopy /E /I /Y .lib_backup lib >nul
  copy /Y .pubspec.bak pubspec.yaml >nul
  rmdir /S /Q .lib_backup
  del .pubspec.bak
  if exist test\widget_test.dart del test\widget_test.dart
) else (
  echo [1/3] windows 目录已存在,跳过生成。
)

echo [2/3] 安装依赖...
call flutter pub get
if errorlevel 1 (
  echo [错误] flutter pub get 失败,请检查网络。
  pause
  exit /b 1
)

echo [3/3] 完成。
echo   调试运行:  run.bat
echo   打包发布:  build_release.bat
pause
