# TDMU Marketplace Flutter

Flutter frontend dùng lại backend Node hiện tại.

## Chạy backend

```powershell
cd C:\Users\nguye\Documents\Codex\2026-05-18\app_tdmu_market
npm.cmd start
```

IP máy hiện tại có thể đổi theo Wi-Fi. Trong app Flutter, màn đăng nhập có ô Server URL, ví dụ:

```text
http://10.72.9.4:3000
```

## Chạy Flutter

Máy này hiện chưa có lệnh `flutter` trong PATH. Khi cài Flutter SDK xong:

```powershell
cd C:\Users\nguye\Documents\Codex\2026-05-18\app_tdmu_market\tdmu_market
flutter create .
flutter pub get
flutter run
```

Build APK:

```powershell
flutter build apk --debug
```
