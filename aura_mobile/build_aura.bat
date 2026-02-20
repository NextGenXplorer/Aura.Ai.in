@echo off
cd android
echo Starting build...
call gradlew.bat assembleRelease > build_log.txt 2>&1
echo Build finished with exit code %errorlevel% >> build_log.txt
cd ..
