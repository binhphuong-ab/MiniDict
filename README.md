# MiniDict

App menu bar macOS để tra **Oxford Advanced Learner's Dictionary** mà không phải mở web: không quảng cáo, không tracker, không tab mới. Bôi đen một chữ rồi **nhấn đúp ⌘ Command** ở bất kỳ app nào, khung tra hiện ra kèm nghĩa và tự đọc phát âm; **Esc** là quay lại đúng chỗ đang đọc.

## Dùng

| Thao tác | Kết quả |
|---|---|
| **⌘ ⌘** (nhấn đúp Command) | Mở / đóng khung tra |
| Bôi đen một chữ → **⌘ ⌘** | Tra ngay chữ đó (cần bật quyền, xem dưới) |
| Menu ▸ *Phím tắt* | Bật/tắt ⌘⌘ và ⌥Space (mặc định chỉ ⌘⌘) |
| Menu ▸ *Tự phát âm khi tra* | Tắt / UK / US (mặc định UK) |
| Menu ▸ *Giao diện* | Theo hệ thống / Sáng / Tối / Vàng (dịu mắt) |
| Ô 🔥 **5/25** trên thanh tìm | Số từ (không trùng) đã tra hôm nay / mốc kế tiếp; bấm để mở Thống kê |
| Nút ☆ trên mục từ, hoặc **⌘D** | Lưu / bỏ lưu vào sổ từ |
| Menu ▸ *Thống kê & thành tích…* | Chuỗi ngày, mốc hôm nay, biểu đồ 14 ngày, bảng xếp hạng từ tra nhiều nhất, ngày kỷ lục |
| Menu ▸ *Sổ từ đã lưu…* | Danh sách đã lưu; *Sao chép danh sách* ra dạng bảng (từ ⇥ loại từ ⇥ nghĩa) để dán vào Anki, Excel, Sheets |
| Menu ▸ *Ăn mừng khi đạt mốc* | Pháo giấy + thông báo ở mốc 5 / 25 / 50 / 100 từ mỗi ngày (bật mặc định) |
| Gõ từ → **Enter** | Tra; **↑ ↓** chọn gợi ý |
| Gõ phím bất kỳ khi đang xem kết quả | Bắt đầu tra từ mới |
| **⌘[ / ⌘]** | Lùi / tiến lịch sử tra |
| Nút **UK / US** | Nghe phát âm |
| Nút ghim (📌) | Giữ khung tra khi bấm ra ngoài (mặc định: bấm ra ngoài là ẩn) |
| Nút ↗ | Mở trang hiện tại trên web Oxford |
| `minidict://lookup?q=word` | Mở khung tra từ Shortcuts, Raycast, PopClip… |
| `minidict://setup-selection` | Xin lại quyền Trợ năng + mở trang Cài đặt |

**Tra chữ đang bôi đen:** menu bar ▸ *Bật tra chữ đang bôi đen…* ▸ bật MiniDict trong *Quyền riêng tư & Bảo mật ▸ Trợ năng*.
Chỉ cần bật một lần: app được ký bằng chứng chỉ cố định nên quyền vẫn còn sau khi build lại.

## Build

```bash
./build.sh               # build + cài vào /Applications
./build.sh --no-install  # chỉ build
```

Cần Xcode Command Line Tools (`xcode-select --install`), không cần Xcode.app. Không có thư viện ngoài.

**Máy mới:** chạy `tools/make-signing-cert.sh` một lần trước khi build. Script tạo chứng chỉ "MiniDict Local Signing" trong login Keychain. Không có chứng chỉ thì `build.sh` vẫn ký tạm (ad-hoc), nhưng khi đó mỗi lần build lại phải bật lại quyền Trợ năng.

**Dữ liệu tra từ** (lịch sử, sổ từ, thống kê) nằm trong `~/Library/Application Support/MiniDict/data.json`, chỉ ở trên máy này. Sao lưu file đó là giữ được hết.

Chi tiết kỹ thuật: [TECHNICAL.md](TECHNICAL.md).
