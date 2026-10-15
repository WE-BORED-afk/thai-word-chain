# Thai Word Chain Helper & Auto-Answer (ต่อคำศัพท์ภาษาไทย)

สคริปต์ช่วยเล่นและแก้คำศัพท์อัตโนมัติสำหรับเกม Roblox **"ต่อคำศัพท์ภาษาไทย [Thai Word Chain]"** (PlaceId: `101001957765810`)

## 🚀 วิธีใช้งาน (Quick Start Loader)

คัดลอกคำสั่งด้านล่างนี้ไปวางใน Roblox Executor ของคุณ:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/WE-BORED-afk/thai-word-chain/main/thai_word_chain_helper.lua"))()
```

## ✨ ฟีเจอร์หลัก
- **Auto-Answer**: ตอบคำศัพท์อัตโนมัติเฉพาะตาเรา
- **Human Typing Simulation**: จำลองการพิมพ์ทีละตัวอักษร ปรับความเร็วและดีเลย์ได้
- **Mode Detection**: ตรวจจับโหมดง่าย (กี่ตัวก็ได้) และโหมดยาก (ขั้นต่ำ 5 ตัวอักษร)
- **Permanent Blacklist**: คำที่เซิร์ฟเวอร์ปฏิเสธจะไม่ถูกนำมาตอบซ้ำ
- **UI ภาษาไทย / English**: สลับภาษาได้ในหน้าต่างการตั้งค่า
