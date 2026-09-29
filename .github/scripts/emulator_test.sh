#!/usr/bin/env bash
# يُشغَّل داخل المحاكي: تثبيت نسخة الإصدار الفعلية وفتحها، ثم اختبار آلي يمر على الشاشات ويلتقط صورها.
set -x
mkdir -p emulator-shots
adb install -r nadi-gym.apk
adb shell pm grant com.nadi.gym android.permission.CAMERA || true
adb shell am start -W -n com.nadi.gym/com.nadi.nadi_gym.MainActivity
sleep 20
adb exec-out screencap -p > emulator-shots/00_release_apk_launch.png
adb logcat -d -t 400 > emulator-shots/logcat_release.txt || true
# هل ما زال التطبيق يعمل (لم ينهَر)؟
adb shell pidof com.nadi.gym && echo "APP RUNNING" | tee emulator-shots/release_status.txt || { echo "APP CRASHED" | tee emulator-shots/release_status.txt; exit 1; }
adb uninstall com.nadi.gym || true
if [ -f integration_test/app_test.dart ]; then
  flutter drive --driver=test_driver/integration_test.dart --target=integration_test/app_test.dart -d emulator-5554 2>&1 | tee emulator-shots/integration_test.log
  status=${PIPESTATUS[0]}
  mv -f screenshots/*.png emulator-shots/ 2>/dev/null || true
  exit $status
fi
