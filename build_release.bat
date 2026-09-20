@echo off
chcp 65001 >nul
cd /d "%~dp0"

call flutter build windows --release
if errorlevel 1 (
  echo [错误] 构建失败,请查看上面的报错。
  pause
  exit /b 1
)

set OUT=build\windows\x64\runner\Release
if not exist dist mkdir dist
powershell -NoProfile -Command "Compress-Archive -Path '%OUT%\*' -DestinationPath 'dist\EmbyPlayer-win64.zip' -Force"

echo.
echo 构建完成:
echo   可执行文件目录: %OUT%   (emby_player.exe 必须和同目录的 dll、data 文件夹一起使用)
echo   打包好的压缩包: dist\EmbyPlayer-win64.zip
pause
