# 🇹🇭 Thai Word Chain Helper & Auto-Answer (ต่อคำศัพท์ภาษาไทย)

สคริปต์ช่วยเล่นและแก้คำศัพท์ภาษาไทยอัตโนมัติสำหรับเกม Roblox **"ต่อคำศัพท์ภาษาไทย [Thai Word Chain]"** (PlaceId: `101001957765810`)

---

## ⚡ วิธีรันสคริปต์ (Quick Loader)

นำโค้ดด้านล่างนี้ไปวางใน Roblox Executor (เช่น Real, Delta, Fluxus, Wave, Codex, Hydrogen, Krnl, ฯลฯ) แล้วกด Execute:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/WE-BORED-afk/thai-word-chain/main/thai_word_chain_helper.lua"))()
```

---

## 🌟 ฟีเจอร์เด่นในเวอร์ชัน 7.0

| ฟังก์ชัน | รายละเอียด |
|---|---|
| **📖 คลังคำศัพท์แท้จากเกม (60,933 คำ)** | สกัดคลังคำศัพท์ทางการจาก Memory ของเกมโดยตรง (`game_dictionary.txt`) แทนที่คำศัพท์ทั่วไปของ PyThaiNLP หมดปัญหาคำศัพท์เซิร์ฟเวอร์ไม่รับ 100% |
| **🛡️ กรองตัวอักษรเดี่ยว/หัวหมวด (Anti-Single Char)** | กรองตัวอักษรเดี่ยว (ก, ข, ค, ... ฮ) และสระที่เป็นหัวแท็บออกอย่างหมดจด บังคับว่าคำตอบต้องยาวกว่าโจทย์ (`#word > #prefix` และ `>= 2 ตัวอักษร`) ป้องกันการเลือกตัวอักษรโดดๆ |
| **⚡ ระบบโหลดแบบ Multi-Tier (4 ลำดับ)** | **Tier 1:** อ่านไฟล์ `game_dictionary.txt` ใน Workspace ในเครื่อง (รวดเร็ว 0.05 วิ) ➔ **Tier 2:** ดึงจาก GitHub Raw ➔ **Tier 3:** สแกน Memory ผ่าน `getgc(true)` ➔ **Tier 4:** FallbackWords |
| **🎯 นับพยัญชนะ/สระบรรทัดแท้ในโหมดยาก** | ใช้ `getThaiBaseCharCount` ไม่นับสระบน/ล่าง (ั, ิ, ี, ึ, ื, ุ, ู, ฺ, ็) และวรรณยุกต์/การันต์ การันตี 5 ตัวอักษรแท้จริง |
| **🔒 Sticky / Latched Hard Mode** | โหมดโต๊ะจะไม่เด้งสลับกลับไปเป็น Easy เมื่อหน้าต่างเลือกโต๊ะปิดตัวลง ล็อกโหมดยากต่อเนื่องตลอดการนั่งเล่นที่โต๊ะ |
| **🔘 3-Way Mode Pill Selector** | ปุ่มลัดเลือกโหมดแบบเดียวกับสถานะเทิร์น `[🤖 Auto] [🟢 ง่าย] [🔴 ยาก]` สลับและล็อกโหมดได้ทันที |
| **⚡ Event-Driven Detection** | ดักจับ Event ภายในเกมผ่าน `getgc()` (`updateRound`, `strike`, `correct`) ตอบสนองฉับไวไม่ต้องรอ UI Polling |
| **🛡️ Token Desync Protection** | ใช้ระบบ `roundToken` ตรวจสอบสถานะก่อนพิมพ์ทุกตัวอักษร ตัดการทำงานทันทีหากหมดเทิร์น ป้องกันการพิมพ์ข้ามรอบ |
| **⌫ Auto-Backspace on Rejection** | เมื่อเซิร์ฟเวอร์แจ้งว่าคำไม่ผ่าน สคริปต์จะลบตัวอักษรที่พิมพ์ค้างไว้อัตโนมัติ แล้วสุ่มลองคำใหม่ทันที |
| **🚫 0% Repeating Rejected Words** | ระบบ `PermanentBlacklist` + `triedThisRound` + ลบคำออกจากหน่วยความจำทันที ไม่พิมพ์คำผิดซ้ำแน่นอน |
| **🌐 รองรับ 2 ภาษา** | สลับหน้าต่าง UI ภาษาไทย 🇹🇭 / English 🇺🇸 ได้ทันทีในหน้า Setting |

---

## 📜 วิธี Revert กลับไปยังเวอร์ชันก่อนหน้า (Version Tags)

หากต้องการรันเวอร์ชันเฉพาะเจาะจง สามารถเปลี่ยน URL ดึงตาม Tag ได้เลย:

### โหลด v7.0 (ล่าสุด):
```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/WE-BORED-afk/thai-word-chain/v7.0/thai_word_chain_helper.lua"))()
```

### โหลด v6.1:
```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/WE-BORED-afk/thai-word-chain/v6.1/thai_word_chain_helper.lua"))()
```

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
- สลับไปดู v7.0: `git checkout v7.0`
- สลับไปดู v6.1: `git checkout v6.1`
- สลับไปดู v6.0: `git checkout v6.0`
- กลับมา v7.0 (main): `git checkout main`
