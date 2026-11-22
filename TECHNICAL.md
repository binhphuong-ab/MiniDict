# MiniDict — Tài liệu kỹ thuật

> Viết ngày 2026-11-21. Nguồn: `~/Code/MiniDict`. Bản cài: `/Applications/MiniDict.app`.

## 1. Nguồn dữ liệu

Oxford Learner's Dictionaries **không có API công khai**. App dùng đúng các URL mà website tự gọi (khảo sát ngày 2026-11-21):

| Mục đích | URL | Trả về |
|---|---|---|
| Gợi ý khi gõ | `/autocomplete/english/?q=…&contentType=application/json; charset=utf-8` | JSON `{"results":[{"searchtext":…}]}` |
| Tra từ | `/search/english/direct/?q=…` | 302 → `/definition/english/{id}` hoặc `/spellcheck/english/?q=…` |
| Mục từ | `/definition/english/{id}` | HTML (~50–70 KB), phần cần lấy nằm trong `#entryContent` |
| Phát âm | `/media/english/{uk,us}_pron/…/*.mp3` | MP3, link lấy từ `data-src-mp3` |

Nội dung miễn phí **không cần đăng nhập**, nên app không lưu tài khoản hay cookie nào.
Đây là dùng cá nhân, mỗi lần tra một trang như trình duyệt; không crawl hàng loạt.
`robots.txt` của Oxford chặn bot đối với `/autocomplete/`, nên đừng biến app thành công cụ tải hàng loạt.

## 2. Kiến trúc

```
main.swift ─ NSApplication .accessory (không icon Dock)
AppDelegate ─ NSStatusItem + menu · HotKey ⌥Space · URL scheme minidict:// · ScreenPref (chọn màn hình)
   │
   ├─ Selection   AX kAXSelectedTextAttribute → fallback ⌘C giả lập + khôi phục clipboard
   │
   └─ LookupPanelController
        FloatingPanel (NSPanel .nonactivatingPanel, level .floating, mọi Space)
        └─ NSVisualEffectView ─ WKWebView ← Resources/ui.html
                 ▲  window.webkit.messageHandlers.native (WKScriptMessageHandlerWithReply)
                 │  cmd: ready · suggest · page · open · pin · hide · loadData · saveData · copy
                 └─ Oxford.swift (WKWebView ẩn, UA WebKit gốc, chỉ cho phép host Oxford)
```

**Vì sao HTML render trong WKWebView, còn fetch ở Swift:**
- Mục từ Oxford rất phong phú (nghĩa, CEFR, ví dụ, collocations, idioms, bảng chia động từ). Parse sang native view sẽ mất dữ liệu và dễ vỡ.
  `DOMParser` trong JS tách `#entryContent`, bỏ script/ảnh/quảng cáo, rồi áp CSS riêng.
  `DOMParser` tạo document "trơ" nên script của Oxford không bao giờ chạy.
- Tải trang bằng một WKWebView ẩn (engine và User-Agent WebKit gốc, kho cookie mặc định của app) thay vì URLSession: Oxford đứng sau bước kiểm tra trình duyệt của Cloudflare, client HTTP thường bị trả 403, còn WebKit chạy bước kiểm tra như Safari. Nếu bước kiểm tra cần người dùng, trang hiện trong một cửa sổ nhỏ để họ tự hoàn tất. Gợi ý tìm kiếm gọi `fetch()` ngay trong trang Oxford đó. Host vẫn giới hạn ở `oxfordlearnersdictionaries.com`.
- Quyền Trợ năng: `AccessSetup.swift` hiện hướng dẫn lần đầu mở app, theo dõi `AXIsProcessTrusted()` mỗi 1,5 giây khi chưa có quyền, rồi bật ⌘⌘ và báo người dùng ngay khi quyền được cấp.

**Vì sao panel non-activating:** khung tra nhận bàn phím nhưng app đang đọc tài liệu vẫn là app *active*. Ẩn panel là focus tự trả về chỗ cũ, không nháy cửa sổ, không đổi Space (giống Spotlight).

**Hotkey** dùng Carbon `RegisterEventHotKey`: không cần quyền Trợ năng và nuốt luôn phím (không gõ ra ký tự).
**⌘⌘ (mặc định từ 1.4)** dùng `NSEvent` global + local monitor cho `.flagsChanged` (`DoubleTap.swift`): hai lần nhấn ⌘ đơn (mỗi lần < 0.35 s, cách nhau < 0.4 s), mọi phím/click/modifier khác xen vào đều huỷ. Cần quyền Trợ năng; nếu chưa có, app chờ và tự cài monitor khi quyền được cấp. Không dùng nhấn đúp Space vì Space luôn tới app đích trước: xoá chữ đang bôi đen trong ô soạn thảo, cuộn trang trong trình đọc PDF.
**Tự phát âm**: `Prefs.autoplay` (`off`/`uk`/`us`) gửi sang JS qua reply của `ready` và `MiniDict.setPrefs`. Chỉ phát khi tra mới, không phát khi ⌘[ / ⌘].
**Chỉ phần đọc chữ bôi đen** mới cần quyền Trợ năng.

## 3. Biến đổi HTML (ui.html → `clean()`)

| Oxford | MiniDict |
|---|---|
| `.symbols` (icon Oxford 3000/5000) | badge chữ `Oxford 5000 · B2` (chỉ ở đầu mục từ) |
| `li.sense[cefr]` | badge `B2` trước định nghĩa |
| `.collapse > .unbox` (Extra Examples, Collocations, Word Origin…) | `<details>` thu gọn |
| `.sound[data-src-mp3]` | nút `UK` / `US`, phát bằng `new Audio()` |
| `#ring-links-box`, jumplinks, topics, ảnh, app banner | xoá |
| `#relatedentries` | chip các từ loại khác của cùng headword |
| link `/definition/…`, `/search/…` | tra ngay trong app; link khác mở trình duyệt |

Lịch sử "Gần đây" lưu `localStorage` (16 từ). Cache trong phiên là `Map` ở JS.

## 3b. Gamification & sổ từ (từ 1.8)

Toàn bộ logic nằm trong JS (`ui.html`, khối *progress*). Swift (`Store.swift`) chỉ đọc/ghi một file JSON:
`~/Library/Application Support/MiniDict/data.json`. Ghi kiểu atomic, và từ chối ghi nếu chuỗi không phải JSON object.
Không dùng `localStorage` cho dữ liệu này, vì xoá dữ liệu website của WebKit sẽ mất theo.

```json
{ "v": 1,
  "days":  { "2026-11-21": ["extraction", "break"] },
  "words": { "break": { "w": "break", "n": 3, "d": 2, "first": 0, "last": 0 } },
  "saved": { "<url mục từ>": { "w": "break", "pos": "verb", "def": "…", "at": 0 } } }
```

- **Mốc trong ngày** = số headword *không trùng* tra trong ngày (giờ địa phương): 5 · 25 · 50 · 100. Tra lại một từ không được tính thêm, nên không "cày" được.
- `n` = số lần tra mới (⌘[ / ⌘] không tính), `d` = số ngày khác nhau đã tra từ đó. Bảng xếp hạng sắp theo `n`: đây là những từ hay phải tra lại, đáng ôn nhất.
- **Chuỗi ngày** = số ngày liên tiếp đạt ≥ 5 từ. Hôm nay chưa đủ 5 thì chuỗi vẫn tính tới hôm qua, không bị mất.
- Sổ từ được khoá theo URL mục từ (`break_1` động từ và `break_2` danh từ là hai mục riêng).
- Ăn mừng: confetti canvas + toast; tắt được trong menu (`Prefs.celebrate`). Tự bỏ confetti nếu bật *Giảm chuyển động*.

## 4. Chữ ký & quyền Trợ năng

macOS (TCC) gắn quyền Trợ năng với *designated requirement* (DR) của app:

| Cách ký | DR | Sau khi build lại |
|---|---|---|
| Ad-hoc (`--sign -`) | `cdhash H"…"`: mã băm của chính bản build | Thành app mới → mất quyền |
| Chứng chỉ "MiniDict Local Signing" | `identifier "com.user.minidict" and certificate leaf = H"7ac3f368…"` | Giữ nguyên → **giữ quyền** |

- `tools/make-signing-cert.sh` tạo chứng chỉ tự ký (RSA 2048, EKU codeSigning, 10 năm) trong login Keychain, với `-T /usr/bin/codesign` để codesign dùng khoá mà không hỏi.
- `build.sh` ký bằng `$SIGN_ID` (mặc định "MiniDict Local Signing"). Thiếu chứng chỉ thì quay về ad-hoc.
- Ngày 2026-11-21 chứng chỉ được user đánh dấu tin cậy cho Code Signing trong login Keychain (`security add-trusted-cert -r trustRoot -p codeSign`). Bước này không bắt buộc cho TCC, chỉ để `codesign --verify` và `find-identity -v` báo hợp lệ.
- **Bẫy đã gặp:** TCC lưu cách nhận dạng app *tại lúc tạo mục quyền*. Mục cũ được tạo từ thời ký ad-hoc nên vẫn là `cdhash H"…"`, và gạt công tắc tắt/bật không đổi được nó, nên bản 1.1 mất quyền. Cách sửa: `tccutil reset Accessibility com.user.minidict` (user tự chạy), rồi cấp lại. Sau đó TCC lưu `identifier "com.user.minidict" and certificate leaf = H"7ac3f368…"`.
- Kiểm tra mục TCC hiện tại (cần Full Disk Access để đọc):
  `sqlite3 "/Library/Application Support/com.apple.TCC/TCC.db" "select hex(csreq) from access where service='kTCCServiceAccessibility' and client='com.user.minidict'" | xxd -r -p > /tmp/r.csreq && csreq -r /tmp/r.csreq -t`
- Kiểm tra một bản build có khớp quy tắc đó không (không cần user thử): `codesign --verify -R /tmp/r.csreq /Applications/MiniDict.app`
- Đã kiểm chứng ngày 2026-11-21: bản 1.2 (CDHash `252fc90e…`) → 1.3 (`38236a74…`) vẫn khớp quy tắc, và tra chữ bôi đen chạy mà không phải cấp lại quyền.
- Khi thiếu quyền, ⌥Space hiện thông báo kèm nút "Bật quyền" (`MiniDict.notice('noAccess')`) thay vì mở khung trống.

## 5. Kiểm thử

- Dữ liệu thật đã thử: `differ`, `better` (4 từ loại), `ran` → `run` (xref), `diffferr` (gợi ý chính tả), ⌘[ quay lại, audio UK/US.
- App thật: `open "minidict://lookup?q=serendipity"` → log `200 /search/english/direct -> /definition/english/serendipity`.
- Muốn xem log: chạy thẳng `/Applications/MiniDict.app/Contents/MacOS/MiniDict` trong Terminal.
- Debug giao diện: Safari ▸ Develop ▸ (tên máy) ▸ MiniDict (`isInspectable = true`).

## 6. Khi Oxford đổi giao diện

**App tự báo (từ 1.9):** một trang `/definition/english/…` mà không có `#entryContent` chứa `h1.headword` thì bị coi là Oxford đã đổi HTML.
Khi đó JS gửi `health {ok:false}`, Swift đặt `oxford.broken = true`, và đầu menu hiện dòng *⚠︎ Oxford đã đổi giao diện*; khung tra báo lỗi thay vì "Không có từ".
Trang tra lần sau đọc được bình thường sẽ tự xoá cảnh báo. Gõ sai chính tả (trang `/spellcheck/`) không bị tính là lỗi.

Lịch sử (đo qua Wayback Machine, 11/2026): lần thiết kế lại lớn gần nhất là khoảng 2019–2020 (phiên bản 1.6 → 2.1). Từ đó đến 2.3.82 chỉ có thay đổi nhỏ ở phần bao ngoài; các class phần nghĩa giữ nguyên.

Mọi selector nằm trong `ui.html`: `#entryContent`, `h1.headword`, `li.sense`, `.def`, `.collapse`, `.box_title`, `.sound`, `#relatedentries`, `.result-list`. Sửa xong chỉ cần `./build.sh`.
