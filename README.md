# 🇹🇭 Thai Word Chain Helper & Auto-Answer (ต่อคำศัพท์ภาษาไทย)

สคริปต์ช่วยเล่นและแก้คำศัพท์ภาษาไทยอัตโนมัติสำหรับเกม Roblox **"ต่อคำศัพท์ภาษาไทย [Thai Word Chain]"** (PlaceId: `101001957765810`)

---

## ⚡ วิธีรันสคริปต์ (Quick Loader)

นำโค้ดด้านล่างนี้ไปวางใน Roblox Executor (เช่น Delta, Fluxus, Wave, Codex, Hydrogen, Krnl, ฯลฯ) แล้วกด Execute:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/WE-BORED-afk/thai-word-chain/main/thai_word_chain_helper.lua"))()
```

---

## 🌟 ฟีเจอร์เด่นในเวอร์ชัน 6.0 (Base Version)

| ฟังก์ชัน | รายละเอียด |
|---|---|
| **⚡ Event-Driven Detection** | ดักจับ Event ภายในเกมผ่าน `getgc()` (`updateRound`, `strike`, `correct`) ทำให้ตอบสนองฉับไวทันทีโดยไม่ต้องรอ UI Polling |
| **🛡️ Token Desync Protection** | ใช้ระบบ `roundToken` ตรวจสอบสถานะก่อนพิมพ์ทุกตัวอักษร ตัดการทำงานทันทีหากหมดเทิร์นหรือขึ้นรอบใหม่ ป้องกันการพิมพ์ข้ามรอบ |
| **⌫ Auto-Backspace on Rejection** | เมื่อเซิร์ฟเวอร์แจ้งว่าคำไม่ผ่าน สคริปต์จะลบตัวอักษรที่พิมพ์ค้างไว้อัตโนมัติ แล้วสุ่มลองคำใหม่ทันที |
| **🚫 0% Repeating Rejected Words** | ระบบ `PermanentBlacklist` + `triedThisRound` + ลบคำออกจากหน่วยความจำทันที ไม่พิมพ์คำผิดซ้ำแน่นอน |
| **🎮 Mode Auto-Detection** | แยกแยะโหมดง่าย (กี่ตัวอักษรก็ได้) และโหมดยาก (ขั้นต่ำ 5 ตัวอักษร) พร้อมปุ่มล็อกโหมดด้วยตนเอง |
| **⌨️ Realistic Keystroke Typing** | จำลองการกดแป้นพิมพ์ทีละตัวอักษร ตั้งค่าดีเลย์ก่อนพิมพ์และดีเลย์ต่อตัวอักษรได้อิสระ |
| **🌐 รองรับ 2 ภาษา** | สลับหน้าต่าง UI ภาษาไทย 🇹🇭 / English 🇺🇸 ได้ทันทีในหน้า Setting |

---

## 📜 วิธี Revert กลับไปยังเวอร์ชันก่อนหน้า (Version Tags)

หากต้องการรันเวอร์ชันเฉพาะเจาะจง สามารถเปลี่ยน URL ดึงตาม Tag ได้เลย:

### โหลด v6.0:
```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/WE-BORED-afk/thai-word-chain/v6.0/thai_word_chain_helper.lua"))()
```

### Revert กลับไปโหลด v5.6:
```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/WE-BORED-afk/thai-word-chain/v5.6/thai_word_chain_helper.lua"))()
```

---

## 🛠️ การจัดการโค้ดผ่าน Git

- ดูประวัติเวอร์ชัน: `git log --oneline --decorate`
- สลับไปดู v5.6: `git checkout v5.6`
- กลับมา v6.0 (main): `git checkout main`
