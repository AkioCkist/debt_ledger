# Sổ Nợ - Ứng dụng theo dõi công nợ giữa 2 người

Ứng dụng Flutter + Supabase để theo dõi công nợ giữa **đúng 2 tài khoản cố định**.
Khi một bên ghi nợ hoặc trả nợ cho bên kia, hệ thống tạo một "invoice" ở trạng
thái `waiting`; giao dịch chỉ thực sự được tính vào số dư sau khi bên còn lại
**xác nhận (accept)**. Bên kia cũng có thể **từ chối (decline)**.

## Tính năng

- Đăng nhập bằng 2 tài khoản đã tạo sẵn trong Supabase Auth (không có màn hình đăng ký).
- Ghi nợ / trả nợ kèm số tiền (VND) và mô tả.
- Giao dịch mới luôn ở trạng thái `waiting` cho tới khi người nhận xác nhận.
- Người nhận xác nhận (`accepted`) hoặc từ chối (`declined`) ngay trên app, cập nhật realtime qua Supabase Realtime.
- Màn hình chính hiển thị số dư ròng hiện tại (ai đang nợ ai bao nhiêu), danh sách chờ xác nhận, và lịch sử gần đây.
- Màn hình lịch sử có bộ lọc theo trạng thái.
- Bảo mật bằng Row Level Security (RLS): mỗi người chỉ thấy và thao tác được trên giao dịch liên quan đến mình; chỉ người nhận mới đổi được trạng thái invoice.
- Giao diện tối giản (minimalism), không hiệu ứng sao chép AI-slop: bảng màu trung tính, một màu nhấn duy nhất, không gradient/emoji thừa.

## Kiến trúc & luồng dữ liệu

```
lib/
├── main.dart               # Khởi tạo Supabase, intl locale
├── app.dart                 # MaterialApp + theme
├── config.dart              # Đọc SUPABASE_URL / SUPABASE_ANON_KEY từ --dart-define
├── theme/app_theme.dart     # Bảng màu, ThemeData tối giản
├── models/                  # AppProfile, DebtTransaction (+ TxType, TxStatus)
├── services/
│   ├── auth_service.dart          # Đăng nhập / đăng xuất / theo dõi phiên
│   ├── profile_service.dart       # Lấy hồ sơ của mình & của "người kia"
│   └── transaction_service.dart   # Stream realtime + tạo/ phản hồi invoice
├── screens/
│   ├── auth_gate.dart              # Điều hướng Login <-> Home theo trạng thái đăng nhập
│   ├── login_screen.dart
│   ├── home_screen.dart            # Số dư + chờ xác nhận + lịch sử gần đây
│   ├── add_transaction_screen.dart # Tạo invoice mới (ghi nợ / trả nợ)
│   ├── invoice_detail_screen.dart  # Chi tiết + nút Xác nhận / Từ chối
│   └── history_screen.dart         # Toàn bộ lịch sử, có bộ lọc
└── widgets/                 # BalanceCard, TransactionTile, StatusBadge

supabase/schema.sql          # Toàn bộ schema + RLS, chạy 1 lần trong SQL Editor
```

**Vòng đời một giao dịch:**

1. Tài khoản A mở "Thêm giao dịch", chọn **Ghi nợ** hoặc **Trả nợ**, nhập số tiền + mô tả, nhấn "Gửi yêu cầu".
2. Bản ghi được INSERT vào bảng `transactions` với `status = 'waiting'`.
3. Tài khoản B thấy ngay ở mục "Cần bạn xác nhận" (nhờ Supabase Realtime), mở chi tiết, chọn **Xác nhận** hoặc **Từ chối**.
4. Nếu **Xác nhận**: `status -> 'accepted'`, giao dịch được cộng/trừ vào số dư chung của cả hai tài khoản.
5. Nếu **Từ chối**: `status -> 'declined'`, giao dịch không ảnh hưởng số dư nhưng vẫn lưu lại trong lịch sử.

Công thức số dư (tính ở client, chỉ trên các giao dịch `accepted`):
`số_dư += số_tiền` nếu tài khoản của mình là người TẠO giao dịch, ngược lại `số_dư -= số_tiền`.
Số dư dương nghĩa là người kia đang nợ mình; số dư âm nghĩa là mình đang nợ người kia.
(Cả hai loại "ghi nợ" và "trả nợ" đều dịch chuyển số dư theo hướng có lợi cho người tạo invoice -
"trả nợ" đơn giản là một bản ghi chuyển tiền theo chiều ngược lại với một khoản nợ trước đó.)

## Yêu cầu

- Flutter SDK >= 3.19 (Dart >= 3.3). Kiểm tra: `flutter --version`
- Một project Supabase (miễn phí tại https://supabase.com)
- Android Studio / Xcode nếu muốn chạy trên thiết bị thật hoặc emulator (không bắt buộc nếu chỉ chạy web/desktop)

## Bước 1 - Tạo project Supabase

1. Vào https://supabase.com/dashboard, tạo project mới (nhớ lưu lại mật khẩu database).
2. Vào **SQL Editor**, dán toàn bộ nội dung file `supabase/schema.sql` và nhấn **Run**.
   - Script sẽ tạo bảng `profiles`, `transactions`, các policy RLS, trigger tự động tạo `profiles` khi có user mới, và bật Realtime cho bảng `transactions`.
   - Nếu dòng lệnh `alter publication supabase_realtime add table public.transactions;` báo lỗi "already member of publication", bỏ qua - nghĩa là Realtime đã được bật sẵn.

## Bước 2 - Tạo 2 tài khoản cố định

1. Vào **Authentication > Users > Add user > Create new user**.
2. Tạo 2 user, ví dụ:
   - `an@sono.app` / mật khẩu tùy chọn
   - `binh@sono.app` / mật khẩu tùy chọn
   - Tick **Auto Confirm User** để không cần xác nhận email.
3. Trigger `handle_new_user` sẽ tự động tạo dòng tương ứng trong bảng `profiles` với `display_name` mặc định là phần trước `@` của email.
4. (Tùy chọn) Vào **Table Editor > profiles**, sửa cột `display_name` thành tên hiển thị dễ dùng, ví dụ "An", "Bình".

> Lưu ý: ứng dụng giả định hệ thống **luôn có đúng 2 profile**. Nếu tạo thêm tài khoản thứ 3, màn hình sẽ chỉ lấy 1 "người kia" bất kỳ (người đầu tiên khác mình) - không phù hợp cho >2 người dùng.

## Bước 3 - Lấy API keys

Vào **Project Settings > API**, lấy:
- `Project URL` (dạng `https://xxxx.supabase.co`)
- `anon public` key

## Bước 4 - Cấu hình app

```bash
cp .env.example .env
```

Mở `.env` và điền:

```dotenv
SUPABASE_URL=https://xxxx.supabase.co
SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

File `.env` đã được thêm vào `.gitignore`, không commit lên git. File `.env.example`
(không chứa key thật) thì được commit để người khác biết cần những biến nào.

## Bước 5 - Chạy ứng dụng

```bash
flutter pub get
flutter run --dart-define-from-file=.env
```

Chọn thiết bị / emulator / Chrome khi được hỏi. Đăng nhập bằng 1 trong 2 tài khoản đã tạo ở Bước 2 để kiểm tra; mở thêm một trình giả lập/thiết bị khác (hoặc Chrome + mobile emulator song song) rồi đăng nhập tài khoản còn lại để test luồng gửi - xác nhận hai chiều.

### Build bản release

```bash
flutter build apk --dart-define-from-file=.env          # Android
flutter build ios --dart-define-from-file=.env           # iOS (cần Xcode + máy Mac)
flutter build web --dart-define-from-file=.env            # Web
```

## Xử lý sự cố thường gặp

| Triệu chứng | Nguyên nhân / cách xử lý |
|---|---|
| Màn hình báo "Thiếu cấu hình Supabase" | Chưa truyền `--dart-define-from-file=.env` khi chạy/build, hoặc file `.env` còn để trống. |
| Đăng nhập lỗi "Invalid login credentials" | Sai email/mật khẩu, hoặc user chưa được **Auto Confirm** trong Supabase Auth. |
| Lỗi "Chưa tìm thấy tài khoản thứ hai" | Chưa tạo đủ 2 user trong Supabase Authentication (xem Bước 2). |
| Danh sách giao dịch không tự cập nhật realtime | Kiểm tra bảng `transactions` đã được bật trong **Database > Replication** (script SQL đã có lệnh này, nhưng có thể cần bật lại thủ công tùy phiên bản Supabase). |
| Không gửi/xác nhận được giao dịch, lỗi quyền (RLS) | Kiểm tra đã chạy đầy đủ `schema.sql`, đặc biệt phần `create policy`. Người GỬI phải là `created_by`; chỉ người NHẬN mới được đổi trạng thái từ `waiting`. |

## Ghi chú bảo mật

- Toàn bộ phân quyền đọc/ghi giao dịch nằm ở RLS trong Postgres (không tin tưởng logic phía client).
- `anon key` là key public, an toàn để nhúng vào app client; mọi ràng buộc quan trọng (ai được xem, ai được sửa trạng thái nào) đều nằm trong policy SQL.
- Nếu muốn đổi mật khẩu / thu hồi truy cập một tài khoản, thao tác trực tiếp trong Supabase Authentication dashboard.

## License

Dự án mẫu, tự do sử dụng và chỉnh sửa cho mục đích cá nhân.
