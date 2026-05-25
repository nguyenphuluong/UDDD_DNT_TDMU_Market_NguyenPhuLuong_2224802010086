# TDMU Marketplace

Ứng dụng marketplace cho sinh viên TDMU, gồm app Flutter và backend Node.js riêng.

## Chức năng chính

- Đăng ký, đăng nhập, quên mật khẩu bằng email sinh viên
- Xem, tìm kiếm, lọc sản phẩm theo danh mục
- Đăng bán sản phẩm, duyệt bài bởi admin
- Chat giữa người mua và người bán
- Gửi ảnh trong chat, thông báo tin nhắn mới
- Giỏ hàng và thanh toán demo
- Trang cá nhân, đổi avatar, quản lý bài đăng của tôi
- Admin duyệt bài, xóa bài, xem thống kê, quản lý tài khoản user

## Tài khoản mẫu

- Admin: `admin@tdmu.edu.vn` / `admin123`
- Sinh viên: `an@tdmu.edu.vn` / `123456`
- Sinh viên: `binh@tdmu.edu.vn` / `123456`

## Chạy backend

```bash
npm install
npm start
```


## Database

Backend dùng SQL Server Express qua TCP port `1433`.

Trước tiên bật TCP/IP cho `SQLEXPRESS`:

```text
SQL Server Configuration Manager
SQL Server Network Configuration
Protocols for SQLEXPRESS
TCP/IP = Enabled
IPAll: TCP Dynamic Ports = rỗng
IPAll: TCP Port = 1433
Restart service SQL Server (SQLEXPRESS)
```

Sau đó chạy script này trong Azure Data Studio/SSMS:

```text
data/sqlserver-schema.sql
```

Cấu hình `.env`:

```env
DB_CLIENT=sqlserver
SQLSERVER_SERVER=127.0.0.1
SQLSERVER_PORT=1433
SQLSERVER_DATABASE=tdmu_market
SQLSERVER_TRUSTED_CONNECTION=true
SQLSERVER_SCHEMA=dbo
SQLSERVER_ENCRYPT=false
SQLSERVER_TRUST_SERVER_CERTIFICATE=true
```

Dữ liệu được lưu trong nhiều bảng SQL Server:

```text
Users
Products
Favorites
Chats
Messages
Reviews
Notifications
CartItems
Orders
OrderItems
AuthCodes
```

## Cấu trúc

```text
server.js                  Backend Node.js, REST API, SSE chat realtime
storage.js                 Tầng lưu trữ SQL Server
data/sqlserver-schema.sql  Script tạo database nhiều bảng SQL Server
public/uploads/            Ảnh upload từ app
tdmu_market/               App Flutter
```
