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
- **Đối soát dữ liệu**: mục ngay trên màn hình chính, tự so khớp dữ liệu đang thấy với mốc đã chốt để phát hiện ai đó sửa database ngoài app (xem mục "Đối soát dữ liệu" bên dưới).
- Bảo mật bằng Row Level Security (RLS): mỗi người chỉ thấy và thao tác được trên giao dịch liên quan đến mình; chỉ người nhận mới đổi được trạng thái invoice.
- Số tiền và nội dung giao dịch bị **khoá cứng ở tầng database**: không sửa được sau khi tạo, kể cả khi sửa trực tiếp bằng SQL.
- Giao diện tối giản (minimalism), không hiệu ứng sao chép AI-slop: bảng màu trung tính, một màu nhấn duy nhất, không gradient/emoji thừa.

## Kiến trúc & luồng dữ liệu

```
lib/
├── main.dart               # Khởi tạo Supabase, intl locale
├── app.dart                 # MaterialApp + theme
├── config.dart              # Đọc SUPABASE_URL / SUPABASE_ANON_KEY từ --dart-define
├── theme/app_theme.dart     # Bảng màu, ThemeData tối giản
├── models/                  # AppProfile, DebtTransaction (+ TxType, TxStatus),
│                            # LedgerSnapshot, IntegrityReport, SyncCheckpoint
├── services/
│   ├── auth_service.dart          # Đăng nhập / đăng xuất / theo dõi phiên
│   ├── profile_service.dart       # Lấy hồ sơ của mình & của "người kia"
│   ├── transaction_service.dart   # Stream realtime + tạo/ phản hồi invoice
│   ├── ledger_math.dart           # Công thức số dư + vân tay giao dịch
│   ├── integrity_service.dart     # Logic đối soát (phát hiện sửa ngoài luồng)
│   └── integrity_store.dart       # Lưu mốc đối soát trên máy (per-tài khoản)
├── screens/
│   ├── auth_gate.dart              # Điều hướng Login <-> Home theo trạng thái đăng nhập
│   ├── login_screen.dart
│   ├── home_screen.dart            # Số dư + đối soát + chờ xác nhận + lịch sử gần đây
│   ├── add_transaction_screen.dart # Tạo invoice mới (ghi nợ / trả nợ)
│   ├── invoice_detail_screen.dart  # Chi tiết + nút Xác nhận / Từ chối
│   ├── history_screen.dart         # Toàn bộ lịch sử, có bộ lọc
│   └── data_integrity_screen.dart  # Chi tiết đối soát + đặt lại mốc
└── widgets/                 # BalanceCard, IntegrityCard, TransactionTile, StatusBadge

supabase/schema.sql          # Toàn bộ schema + RLS, chạy 1 lần trong SQL Editor
supabase/migrations/         # Migration cho database đã cài từ trước
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

## Đối soát dữ liệu (phát hiện database bị sửa ngoài app)

Màn hình chính có mục **Đối soát dữ liệu** (và icon khiên trên thanh tiêu đề), tự động
so khớp dữ liệu đang thấy với mốc đã chốt gần nhất. Mọi việc diễn ra tại client,
không gửi dữ liệu đi đâu, không cần secret.

### Cách hoạt động

1. **Mốc đối soát (checkpoint)** — lần đầu chạy, app ghi lại vân tay từng giao dịch
   (SHA-256 của `id`, người tạo/nhận, loại, số tiền, mô tả, `created_at`), trạng thái,
   `version`, số dư và `ledger_hash` của server vào bộ nhớ máy, tách riêng theo tài khoản.
2. **`updated_at` / `version`** do trigger trong database ghi mỗi lần một dòng bị sửa.
   Client biết dữ liệu đã đổi kể từ lần sync cuối và lấy phần thay đổi bằng
   `updated_at > mốc` (`TransactionService.fetchChangedSince`).
3. **So khớp mỗi lần có dữ liệu mới.** Thay đổi hợp lệ (`waiting -> accepted/declined`,
   giao dịch mới) được tự động đưa vào mốc. Thay đổi bất thường thì giữ nguyên mốc cũ
   để lần sau vẫn còn cảnh báo, cho tới khi người dùng xem và bấm "Đặt lại mốc đối soát".

### Các phép so khớp

| Phép so khớp | Phát hiện |
|---|---|
| Số dư tính lại khớp server | Client và server (RPC `ledger_snapshot()`) tính độc lập trên cùng dữ liệu |
| Số dòng khớp server | Có giao dịch bị thiếu khi đọc về |
| Số tiền / nội dung không bị sửa | Vân tay giao dịch lệch mốc: `amount`, `type`, `description`, `created_at` bị đổi |
| Trạng thái chuyển hợp lệ | `accepted -> declined`, quay lại `waiting`, hoặc đổi trạng thái mà `version` không tăng |
| Ràng buộc dữ liệu | Số tiền ≤ 0, tự ghi nợ chính mình, loại/trạng thái lạ, dòng trùng id |
| Theo dõi thay đổi | Database chưa chạy migration nên chưa có `version`/`updated_at` |
| Xoá ngoài luồng | Giao dịch có trong mốc nhưng đã biến mất khỏi database |

### Vì sao không dùng HMAC/signature trong client

Chữ ký HMAC chỉ có ý nghĩa nếu khoá ký nằm ngoài tầm với của client — mà client Flutter
thì không được giữ secret. Hơn nữa hash do chính database tính bằng trigger sẽ **tự tính
lại** khi có người sửa dòng, nên không phát hiện được gì. Vì vậy:

- **Chặn cứng** việc sửa `amount`/`type`/`created_by`/`recipient_id`/`description`/`created_at`
  bằng trigger + quyền theo cột ở database (kể cả người có SQL cũng bị chặn).
- **Phát hiện** thay đổi bằng vân tay lưu trên máy: cái này hoạt động kể cả khi trigger
  bị tắt hoặc dữ liệu bị sửa bằng đường vòng, vì mốc cũ vẫn còn nguyên để so.
- Nếu về sau cần bảo đảm bằng mật mã (chống cả người có toàn quyền database), hướng đúng
  là ký bằng khoá giữ trong Supabase Vault và xác minh qua Edge Function — khi đó client
  chỉ gọi hàm xác minh, không giữ khoá.

### Thử nghiệm nhanh

1. Mở app, vào **Đối soát dữ liệu** một lần để chốt mốc.
2. Vào Supabase SQL Editor, thử sửa số tiền:
   ```sql
   update public.transactions set amount = 1 where id = '<id>';
   ```
   Kết quả mong đợi: `ERROR: IMMUTABLE_TRANSACTION_FIELD: ...` — database chặn luôn.
3. Tắt kiểm tra đó để thử phần phát hiện:
   ```sql
   alter table public.transactions disable trigger trg_transactions_guard;
   update public.transactions set amount = 1 where id = '<id>';
   alter table public.transactions enable trigger trg_transactions_guard;
   ```
4. Mở lại **Đối soát dữ liệu** trong app: mục "Số tiền / nội dung không bị sửa" báo
   *Không khớp* kèm mã `row_payload_changed` và id giao dịch.
5. Bấm "Đặt lại mốc đối soát" để chấp nhận trạng thái mới (hoặc tự sửa lại dữ liệu).

App không crash ở bất kỳ bước nào: RPC lỗi, mất mạng, mốc hỏng trên máy đều được xử lý
thành thông báo thay vì lỗi.

## Yêu cầu

- Flutter SDK >= 3.19 (Dart >= 3.3). Kiểm tra: `flutter --version`
- Một project Supabase (miễn phí tại https://supabase.com)
- Android Studio / Xcode nếu muốn chạy trên thiết bị thật hoặc emulator (không bắt buộc nếu chỉ chạy web/desktop)

## Bước 1 - Tạo project Supabase

1. Vào https://supabase.com/dashboard, tạo project mới (nhớ lưu lại mật khẩu database).
2. Vào **SQL Editor**, dán toàn bộ nội dung file `supabase/schema.sql` và nhấn **Run**.
   - Script sẽ tạo bảng `profiles`, `transactions`, các policy RLS, trigger tự động tạo `profiles` khi có user mới, cột `updated_at`/`version` cho đối soát, RPC `ledger_snapshot()`, và bật Realtime cho bảng `transactions`.
   - File đã idempotent: chạy lại nhiều lần không lỗi và không mất dữ liệu.

> **Database đã cài từ trước:** chỉ cần chạy thêm `supabase/migrations/20260914120000_ledger_integrity.sql`
> trong SQL Editor. Migration này thêm cột `updated_at`/`version`, trigger chặn sửa field quan trọng,
> siết quyền UPDATE theo cột và tạo RPC đối soát — không đổi dữ liệu hiện có.
> Nếu bỏ qua bước này, app vẫn chạy bình thường, chỉ là mục Đối soát sẽ báo
> "Database chưa theo dõi phiên bản" và giảm bớt vài phép so khớp.

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
flutter run
```

Ứng dụng tự đọc `.env` khi khởi động. Có thể tiếp tục dùng
`--dart-define-from-file=.env` cho môi trường CI hoặc bản build release.

Chọn thiết bị / emulator / Chrome khi được hỏi. Đăng nhập bằng 1 trong 2 tài khoản đã tạo ở Bước 2 để kiểm tra; mở thêm một trình giả lập/thiết bị khác (hoặc Chrome + mobile emulator song song) rồi đăng nhập tài khoản còn lại để test luồng gửi - xác nhận hai chiều.

### Đổi icon ứng dụng

Ảnh nguồn của icon nằm tại `assets/icon/icon.png`. Sau khi thay ảnh, chạy:

```bash
flutter pub get
flutter pub run flutter_launcher_icons
flutter clean
flutter build apk --dart-define-from-file=.env
```

Lệnh `flutter_launcher_icons` sẽ tạo icon cho Android, iOS, web, Windows và macOS
theo cấu hình trong `pubspec.yaml`. Nếu thiết bị vẫn hiển thị icon cũ, hãy gỡ ứng
dụng khỏi thiết bị/emulator rồi cài lại bản APK mới để xoá cache icon của launcher.

### Build bản release

```bash
flutter build apk --dart-define-from-file=.env          # Android
flutter build ios --dart-define-from-file=.env           # iOS (cần Xcode + máy Mac)
flutter build web --dart-define-from-file=.env            # Web
```

## Xử lý sự cố thường gặp

| Triệu chứng | Nguyên nhân / cách xử lý |
|---|---|
| Màn hình báo "Thiếu cấu hình Supabase" | File `.env` chưa tồn tại/còn để trống, hoặc chưa truyền `--dart-define-from-file=.env`. |
| Đăng nhập lỗi "Invalid login credentials" | Sai email/mật khẩu, hoặc user chưa được **Auto Confirm** trong Supabase Auth. |
| Lỗi "Chưa tìm thấy tài khoản thứ hai" | Chưa tạo đủ 2 user trong Supabase Authentication (xem Bước 2). |
| Danh sách giao dịch không tự cập nhật realtime | Kiểm tra bảng `transactions` đã được bật trong **Database > Replication** (script SQL đã có lệnh này, nhưng có thể cần bật lại thủ công tùy phiên bản Supabase). |
| Không gửi/xác nhận được giao dịch, lỗi quyền (RLS) | Kiểm tra đã chạy đầy đủ `schema.sql`, đặc biệt phần `create policy`. Người GỬI phải là `created_by`; chỉ người NHẬN mới được đổi trạng thái từ `waiting`. |
| Xác nhận/từ chối báo lỗi `permission denied for table transactions` | Chưa chạy migration (mục 3c trong `schema.sql` hoặc file trong `supabase/migrations/`): quyền UPDATE toàn bảng bị thu hồi nhưng chưa grant lại cho cột `status`. Chạy lại `schema.sql`. |
| Đối soát báo "Database chưa theo dõi phiên bản" | Chưa chạy migration `ledger_integrity`. Chạy file trong `supabase/migrations/` trong SQL Editor. |
| Đối soát báo "Số dư lệch so với server" | Client và server tính trên cùng dữ liệu nên lệch là bất thường thật: kiểm tra các dòng `accepted` trong Table Editor, hoặc có bản build app cũ đang chạy công thức khác. |

## Ghi chú bảo mật

- Toàn bộ phân quyền đọc/ghi giao dịch nằm ở RLS trong Postgres (không tin tưởng logic phía client).
- `anon key` là key public, an toàn để nhúng vào app client; mọi ràng buộc quan trọng (ai được xem, ai được sửa trạng thái nào) đều nằm trong policy SQL.
- **Không có secret nào trong app.** Mốc đối soát chỉ là bản chụp dữ liệu lưu trên máy; mất mốc chỉ khiến app chốt lại mốc mới.
- Quyền ghi ở tầng database bị siết 2 lớp, độc lập với RLS:
  - `transactions_guard` chặn mọi thay đổi trên `created_by`, `recipient_id`, `type`, `amount`, `description`, `created_at`, chặn chuyển trạng thái sai hướng và chặn sửa `responded_at` sau khi đã chốt.
  - `revoke update` toàn bảng + `grant update (status)`: tài khoản đăng nhập chỉ PATCH được đúng cột `status`. Đây là lỗ hổng đã tồn tại trước đây — policy update chỉ kiểm tra `recipient_id` và `status` ở `WITH CHECK`, nên người nhận có thể gửi kèm `amount` trong cùng câu UPDATE.
  - Trigger vẫn ghi được `version`/`updated_at` dù client không có quyền trên hai cột đó (Postgres kiểm tra quyền theo cột trong mệnh đề `SET`).
- Nếu muốn đổi mật khẩu / thu hồi truy cập một tài khoản, thao tác trực tiếp trong Supabase Authentication dashboard.

## License

Dự án mẫu, tự do sử dụng và chỉnh sửa cho mục đích cá nhân.
