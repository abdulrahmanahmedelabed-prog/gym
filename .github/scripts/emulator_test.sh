#!/usr/bin/env bash
# يُشغَّل داخل المحاكي: تثبيت نسخة الإصدار الفعلية وفتحها، ثم اختبار آلي يمر على الشاشات ويلتقط صورها.
set -x
mkdir -p emulator-shots
# صلاحية root في المحاكي فقط: لفحص أن الحذف لا يترك ملفات في مجلد التطبيق الخاص
adb root >/dev/null 2>&1; sleep 3; adb wait-for-device
# محاكاة شاشة جوال قديم: 720×1280 بكثافة 320 (مثل Galaxy J5/J7 وأغلب جوالات 2016-2019)
if [ -n "$SMALL_SCREEN" ]; then
  set -- $SMALL_SCREEN
  adb shell wm size "$1"
  adb shell wm density "$2"
  sleep 3
fi
adb shell getprop ro.build.version.release | tee emulator-shots/android_version.txt
adb shell cat /proc/meminfo | head -1 | tee -a emulator-shots/android_version.txt
adb install -r nadi-gym-x86_64.apk
adb shell pm grant com.nadi.gym android.permission.CAMERA || true
adb shell am start -W -n com.nadi.gym/com.nadi.nadi_gym.MainActivity
sleep 20
adb exec-out screencap -p > emulator-shots/00_release_apk_launch.png
# تشخيص: حجم الصورة (الشاشة السوداء أو الفارغة تكون صغيرة جداً) والنصوص الظاهرة فعلاً على الشاشة
ls -la emulator-shots/00_release_apk_launch.png
adb shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1; adb shell cat /sdcard/ui.xml 2>/dev/null | tr '>' '\n' | grep -o 'content-desc="[^"]*"\|text="[^"]*"' | grep -v '=""' | head -30 | tee emulator-shots/release_screen_texts.txt || true
# ذاكرة التطبيق الفعلية بعد الفتح
adb shell dumpsys meminfo com.nadi.gym | grep -E "TOTAL|Native Heap" | head -3 | tee emulator-shots/memory.txt || true
adb logcat -d -t 400 > emulator-shots/logcat_release.txt || true
# هل ما زال التطبيق يعمل (لم ينهَر)؟
adb shell pidof com.nadi.gym && echo "APP RUNNING" | tee emulator-shots/release_status.txt || { echo "APP CRASHED" | tee emulator-shots/release_status.txt; exit 1; }
# الحذف النظيف: بعد إلغاء التثبيت لا يبقى للتطبيق أي ملف على الجوال
adb shell ls -R /data/data/com.nadi.gym 2>/dev/null | head -20 > emulator-shots/files_before_uninstall.txt || true
adb uninstall com.nadi.gym || true
sleep 2
left=""
adb shell pm list packages | grep -q com.nadi.gym && left="$left package"
adb shell ls /sdcard/Android/data 2>/dev/null | grep -q com.nadi.gym && left="$left sdcard-data"
adb shell ls /sdcard/Android/media 2>/dev/null | grep -q com.nadi.gym && left="$left sdcard-media"
adb shell ls /data/data 2>/dev/null | grep -q com.nadi.gym && left="$left data"
if [ -n "$left" ]; then echo "LEFTOVERS:$left" | tee emulator-shots/uninstall_check.txt; exit 1; fi
echo "CLEAN UNINSTALL: no files left" | tee emulator-shots/uninstall_check.txt
if [ -f integration_test/app_test.dart ]; then
  flutter drive --driver=test_driver/integration_test.dart --target=integration_test/app_test.dart -d emulator-5554 2>&1 | tee emulator-shots/integration_test.log
  status=${PIPESTATUS[0]}
  mv -f screenshots/*.png emulator-shots/ 2>/dev/null || true
  exit $status
fi
