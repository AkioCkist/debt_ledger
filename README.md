# Sổ Nợ - Ứng dụng theo dõi công nợ nhiều người

Ứng dụng Flutter + Supabase để theo dõi công nợ với **nhiều người**. Mỗi người tự
tạo tài khoản, vào **sảnh** để kết bạn nợ với nhau (bằng mã ngắn hạn hoặc QR),
rồi mỗi cặp có một sổ nợ riêng. Khi một bên ghi nợ hoặc trả nợ cho bên kia, hệ
thống tạo một "invoice" ở trạng thái `waiting`; giao dịch chỉ thực sự được tính
vào số dư sau khi bên còn lại **xác nhận (accept)**. Bên kia cũng có thể
**từ chối (decline)**.

## Tính năng

- Tự đăng ký tài khoản (email + mật khẩu) ngay trong app, có xác nhận email.
- **Sảnh** là màn hình đầu tiên sau khi đăng nhập: danh bạ bạn nợ, lời mời đang chờ, thẻ đối soát.
- **Kết bạn nợ bằng mã/QR**: một bên tạo mã 8 ký tự (hiệu lực 10 phút, dùng một lần) kèm QR; bên kia nhập mã hoặc quét QR; bên tạo nhận lời mời và chọn Đồng ý / Từ chối.
- Mỗi bạn nợ có một ô riêng ở sảnh, hiện số dư ròng của riêng người đó; chạm vào mở sổ nợ của cặp đó.
- **Đổi tên riêng cho bạn nợ** (ví dụ "Anh Nam"): chỉ lưu phía mình, đối phương không thấy.
- Ghi nợ / trả nợ kèm số tiền (VND) và mô tả, chỉ với người đã kết bạn nợ.
- Giao dịch mới luôn ở trạng thái `waiting` cho tới khi người nhận xác nhận.
- Người nhận xác nhận (`accepted`) hoặc từ chối (`declined`) ngay trên app, cập nhật realtime qua Supabase Realtime.
- Màn hình lịch sử có bộ lọc theo trạng thái.
- **Đối soát dữ liệu**: mục ngay trên sảnh, tự so khớp dữ liệu đang thấy với mốc đã chốt để phát hiện ai đó sửa database ngoài app (xem mục "Đối soát dữ liệu" bên dưới).
- Bảo mật bằng Row Level Security (RLS): chỉ thấy giao dịch mình liên quan, chỉ đọc được hồ sơ của người mình đã kết bạn (hoặc đang có lời mời), chỉ ghi được giao dịch với người đã kết bạn.
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
│                            # DebtConnection/ContactBook, PairCode,
│                            # LedgerSnapshot, IntegrityReport, SyncCheckpoint
├── services/
│   ├── auth_service.dart          # Đăng nhập / đăng ký / đăng xuất / theo dõi phiên
│   ├── profile_service.dart       # Lấy hồ sơ của mình & của nhiều người
│   ├── connection_service.dart    # Quan hệ bạn nợ + RPC tạo/ nhập mã pairing
│   ├── contact_alias_service.dart # Tên riêng mình đặt cho bạn nợ (chỉ phía mình)
│   ├── transaction_service.dart   # Stream realtime + tạo/ phản hồi invoice
│   ├── ledger_math.dart           # Công thức số dư + lọc theo cặp + vân tay giao dịch
│   ├── integrity_service.dart     # Logic đối soát (phát hiện sửa ngoài luồng)
│   └── integrity_store.dart       # Lưu mốc đối soát trên máy (per-tài khoản)
├── screens/
│   ├── auth_gate.dart              # Điều hướng Login <-> Sảnh theo trạng thái đăng nhập
│   ├── login_screen.dart
│   ├── signup_screen.dart          # Tự đăng ký tài khoản
│   ├── lobby_screen.dart           # Sảnh: lời mời, danh bạ, đối soát, nút Thêm bạn nợ
│   ├── contact_ledger_screen.dart  # Sổ nợ của MỘT bạn nợ
│   ├── add_transaction_screen.dart # Tạo invoice mới (ghi nợ / trả nợ)
│   ├── invoice_detail_screen.dart  # Chi tiết + nút Xác nhận / Từ chối
│   ├── history_screen.dart         # Lịch sử của một bạn nợ, có bộ lọc
│   ├── scan_qr_screen.dart         # Quét QR kết bạn nợ (mobile_scanner)
│   └── data_integrity_screen.dart  # Chi tiết đối soát + đặt lại mốc
└── widgets/                 # BalanceCard, IntegrityCard, TransactionTile,
                             # StatusBadge, AddContactSheet (mã + QR + ô nhập mã)

supabase/schema.sql          # Toàn bộ schema + RLS, chạy 1 lần trong SQL Editor
supabase/migrations/         # Migration cho database đã cài từ trước
```

**Kết bạn nợ (pairing):**

1. A mở **Thêm bạn nợ** ở sảnh: app gọi RPC `create_pair_code()` để server sinh mã 8 ký tự
   (hiệu lực 10 phút, dùng một lần) rồi hiện mã kèm QR.
2. B nhập mã đó, hoặc quét QR (`sono://pair?code=XXXXXXXX`) — app gọi RPC `redeem_pair_code()`.
3. Server xoá mã, tạo một dòng `connections` ở trạng thái `pending` giữa B (người gửi) và A (người nhận).
4. A thấy lời mời ngay ở sảnh (Realtime), chọn **Đồng ý** hoặc **Từ chối**.
5. Đồng ý thì hai người thấy nhau trong danh bạ và gửi được giao dịch cho nhau; từ chối thì không,
   và A phải tạo mã mới nếu muốn B thử lại (mã cũ đã bị dùng).

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

Sảnh có mục **Đối soát dữ liệu** (và icon khiên trên thanh tiêu đề), tự động
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
   - Script sẽ tạo bảng `profiles`, `transactions`, `connections`, `pair_invites`,
     `contact_aliases`, các policy RLS, trigger tự động tạo `profiles` khi có user
     mới, cột `updated_at`/`version` cho đối soát, RPC `ledger_snapshot()`,
     `create_pair_code()`, `redeem_pair_code()`, và bật Realtime cho
     `transactions` + `connections`.
   - File đã idempotent: chạy lại nhiều lần không lỗi và không mất dữ liệu.
   - Lưu ý: SQL Editor chạy cả file trong **một transaction**, nên một lệnh lỗi sẽ
     rollback toàn bộ. Cứ sửa lỗi rồi chạy lại từ đầu.

> **Database đã cài từ trước:** chạy thêm hai file trong `supabase/migrations/`
> theo thứ tự (mỗi file chạy một lần trong SQL Editor):
>
> 1. `20260914120000_ledger_integrity.sql` — thêm cột `updated_at`/`version`, trigger
>    chặn sửa field quan trọng, siết quyền UPDATE theo cột, tạo RPC đối soát.
>    Bỏ qua thì app vẫn chạy, chỉ là mục Đối soát báo "Database chưa theo dõi phiên bản".
> 2. `20260916120000_pairing.sql` — thêm bảng pairing, hai RPC sinh/nhập mã, siết lại
>    quyền đọc `profiles` và quyền tạo giao dịch.
>
> **Chạy migration pairing TRƯỚC khi phát hành bản app mới.** Migration này siết
> policy đọc `profiles`; app cũ (bản đi tìm "người kia" bằng `neq('id', uid)`) sẽ
> không còn đọc được hồ sơ người kia nữa. Migration có sẵn bước seed: mọi cặp tài
> khoản đã từng có giao dịch với nhau được đánh dấu là bạn nợ sẵn, nên dữ liệu
> đang dùng không bị ảnh hưởng.

## Bước 1b - Bật xác nhận email

1. Vào **Authentication > Sign In / Providers > Email**, bật **Confirm email**.
   - Người dùng đăng ký trong app, Supabase gửi mail kèm link xác nhận.
   - **Đây là công tắc duy nhất quyết định việc chặn đăng nhập.** Khi tắt, GoTrue
     cấp phiên ngay lúc đăng ký và đóng dấu `email_confirmed_at` luôn, nên app
     không phân biệt được và người dùng vào sảnh mà chưa bấm link. App có sẵn chốt
     phòng ngừa ở `AuthGate`, nhưng chỉ cấu hình này mới chặn được.
   - Project mới chưa cấu hình SMTP riêng thì dùng mail mặc định của Supabase, có
     giới hạn số mail mỗi giờ — đủ cho vài tài khoản, nhưng nên cấu hình
     **Authentication > Emails > SMTP Settings** nếu dùng thật.
2. Không cần tạo user thủ công: mỗi người tự đăng ký trong app.

> Sau khi bấm link xác nhận trong mail, người dùng quay lại app và **đăng nhập**.
> Link xác nhận chưa mở thẳng app được vì project chưa cấu hình deep link.

## Bước 2 - Tạo tài khoản

Mở app, chọn **Chưa có tài khoản? Tạo tài khoản**, nhập tên hiển thị, email và
mật khẩu. Trigger `handle_new_user` sẽ tự tạo dòng trong bảng `profiles` với
`display_name` lấy từ tên đã nhập.

Muốn thêm tài khoản thứ hai để thử: đăng ký tiếp bằng email khác (hoặc
**Authentication > Users > Add user** với **Auto Confirm User**).

> Tên hiển thị hiện cho người khác thấy khi kết bạn nợ, và có thể đổi lại lúc
> nào cũng được trong **Table Editor > profiles**.

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

Chọn thiết bị / emulator / Chrome khi được hỏi. Đăng ký một tài khoản, vào sảnh,
rồi mở thêm một trình giả lập/thiết bị khác (hoặc Chrome + mobile emulator song
song) và đăng ký tài khoản thứ hai để test luồng kết bạn nợ và gửi - xác nhận
hai chiều.

Nút **Quét QR** chỉ hiện trên Android/iOS — camera không có trên web/desktop nên
ở đó chỉ nhập mã bằng tay. Trên Android/iOS lần đầu quét, hệ điều hành sẽ hỏi
quyền camera (đã khai báo trong `AndroidManifest.xml` / `Info.plist`).

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
| Đăng nhập lỗi "Invalid login credentials" | Sai email/mật khẩu. Nếu chắc chắn đúng, kiểm tra user có tồn tại trong **Authentication > Users** không. |
| Sảnh trống, không ai trong danh bạ | Chưa kết bạn nợ. Nhấn **Thêm bạn nợ** để lấy mã, người kia nhập mã (hoặc quét QR) rồi bên bạn Đồng ý lời mời. |
| Nhập mã báo "Mã không đúng hoặc đã hết hạn" | Mã quá 10 phút, hoặc đã bị dùng một lần rồi, hoặc người kia đã tạo mã mới. Xin mã mới. |
| Nhập mã báo "Đang có một lời mời chờ trả lời giữa hai bạn" | Đã có lời mời `pending` giữa hai người; vào sảnh trả lời lời mời đó thay vì tạo lời mời mới. |
| Quét QR không mở được camera | Chưa cấp quyền camera cho app (Cài đặt > Ứng dụng > Sổ Nợ > Quyền), hoặc đang chạy trên web/desktop — dùng cách nhập mã bằng tay. |
| Đăng nhập báo "Email chưa được xác nhận" | Bấm link xác nhận trong mail trước, rồi đăng nhập lại. Kiểm tra cả thư mục spam. |
| Đăng ký xong vào thẳng sảnh dù chưa bấm link trong mail | **Confirm email** đang tắt ở **Authentication > Sign In / Providers > Email**. Bật lên rồi xoá các user chưa xác nhận trong **Authentication > Users** và đăng ký lại. |
| Đọc được hồ sơ người lạ / không đọc được hồ sơ bạn nợ | Chưa chạy `20260916120000_pairing.sql`, hoặc chạy rồi nhưng thiếu bước seed: mọi cặp đã từng có giao dịch phải có một dòng `connections` trạng thái `accepted` trong bảng `connections`. |
| Danh sách giao dịch không tự cập nhật realtime | Kiểm tra bảng `transactions` đã được bật trong **Database > Replication** (script SQL đã có lệnh này, nhưng có thể cần bật lại thủ công tùy phiên bản Supabase). |
| Không gửi/xác nhận được giao dịch, lỗi quyền (RLS) | Kiểm tra đã chạy đầy đủ `schema.sql`, đặc biệt phần `create policy`. Người GỬI phải là `created_by`; chỉ người NHẬN mới được đổi trạng thái từ `waiting`. |
| Xác nhận/từ chối báo lỗi `permission denied for table transactions` | Chưa chạy migration (mục 3c trong `schema.sql` hoặc file trong `supabase/migrations/`): quyền UPDATE toàn bảng bị thu hồi nhưng chưa grant lại cho cột `status`. Chạy lại `schema.sql`. |
| Đối soát báo "Database chưa theo dõi phiên bản" | Chưa chạy migration `ledger_integrity`. Chạy file trong `supabase/migrations/` trong SQL Editor. |
| Đối soát báo "Số dư lệch so với server" | Client và server tính trên cùng dữ liệu nên lệch là bất thường thật: kiểm tra các dòng `accepted` trong Table Editor, hoặc có bản build app cũ đang chạy công thức khác. |

## Ghi chú bảo mật

- Toàn bộ phân quyền đọc/ghi nằm ở RLS trong Postgres (không tin tưởng logic phía client).
- `anon key` là key public, an toàn để nhúng vào app client; mọi ràng buộc quan trọng (ai được xem, ai được sửa trạng thái nào) đều nằm trong policy SQL.
- **Không có secret nào trong app.** Mốc đối soát chỉ là bản chụp dữ liệu lưu trên máy; mất mốc chỉ khiến app chốt lại mốc mới.
- **Mã kết bạn nợ do server sinh**, không bao giờ sinh ở client: RPC `create_pair_code()` dùng
  `gen_random_uuid()` (CSPRNG, ở `pg_catalog` nên gọi được khi `search_path` rỗng — không dùng
  `gen_random_bytes()` vì pgcrypto nằm ở schema `extensions`, tên không qualify sẽ không resolve),
  bảng chữ 32 ký tự bỏ `I/O/0/1`, mã 8 ký tự (~2^40 khả năng),
  hiệu lực 10 phút và **chỉ dùng được một lần** (xoá ngay khi nhập, trong cùng transaction với
  bước kiểm tra nên nếu bước sau lỗi thì mã vẫn còn).
- Bảng `pair_invites` bật RLS và **không có policy nào**: không ai đọc/ghi trực tiếp được, chỉ vào
  được qua RPC `security definer`. Cả hai RPC đều `revoke execute from public, anon` — phải có
  phiên đăng nhập (đã xác nhận email) mới gọi được, nên `anon key` một mình không brute-force được.
- **Ai đọc được hồ sơ:** policy `profiles_select_connected` chỉ cho đọc chính mình, người đã kết bạn nợ,
  hoặc người đang có lời mời (`pending`). Lời mời đã bị từ chối (`declined`) **không** còn quyền đọc —
  nếu tính cả `declined` thì người từng nhận lời mời giữ được quyền đọc `email` của người đã từ chối họ.
- **Chỉ tạo được giao dịch với người đã kết bạn nợ**: policy insert của `transactions` gọi
  `is_connected(created_by, recipient_id)`. Hàm này từ chối khi gọi với hai uuid không liên quan
  tới người đang đăng nhập, nên không dùng làm công cụ dò quan hệ giữa hai người khác.
- **Tên riêng chỉ lưu phía mình**: bảng `contact_aliases` bắt mọi lệnh phải có `owner_id = auth.uid()`.
- RPC `redeem_pair_code()` chỉ trả `connection_id` và `addressee_id`, không trả tên/email, và thông báo
  lỗi không kèm tên ai — tránh biến lỗi thành công cụ dò tài khoản.
- Chưa làm: huỷ kết bạn (unpair), giới hạn số lần nhập mã sai (chống dò mã), deep link cho link xác nhận email.
- Quyền ghi ở tầng database bị siết 2 lớp, độc lập với RLS:
  - `transactions_guard` chặn mọi thay đổi trên `created_by`, `recipient_id`, `type`, `amount`, `description`, `created_at`, chặn chuyển trạng thái sai hướng và chặn sửa `responded_at` sau khi đã chốt.
  - `revoke update` toàn bảng + `grant update (status)`: tài khoản đăng nhập chỉ PATCH được đúng cột `status`. Đây là lỗ hổng đã tồn tại trước đây — policy update chỉ kiểm tra `recipient_id` và `status` ở `WITH CHECK`, nên người nhận có thể gửi kèm `amount` trong cùng câu UPDATE.
  - Trigger vẫn ghi được `version`/`updated_at` dù client không có quyền trên hai cột đó (Postgres kiểm tra quyền theo cột trong mệnh đề `SET`).
- Nếu muốn đổi mật khẩu / thu hồi truy cập một tài khoản, thao tác trực tiếp trong Supabase Authentication dashboard.

## License

Dự án mẫu, tự do sử dụng và chỉnh sửa cho mục đích cá nhân.
