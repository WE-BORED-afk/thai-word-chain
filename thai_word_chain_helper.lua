--[[
    ╔══════════════════════════════════════════════════════════════════════╗
    ║       THAI WORD CHAIN HELPER & AUTO-ANSWER SCRIPT (V6.1)             ║
    ║           เกม: ต่อคำศัพท์ภาษาไทย [Thai Word Chain]                    ║
    ║                                                                      ║
    ║   Changelog v6.1 (Fix Hard Mode < 5 Chars Bug):                      ║
    ║   1. Fixed Hard Mode Linguistic Character Counting:                  ║
    ║      - Upper/Lower vowels (สระบน/ล่าง: ั, ิ, ี, ึ, ื, ุ, ู, ฺ, ็)    ║
    ║        and tone/cancellation marks (วรรณยุกต์/การันต์: ่, ้, ๊, ๋, ์)  ║
    ║        are combining marks and DO NOT count as standalone characters.║
    ║      - Implemented getThaiBaseCharCount() to ensure only base letters║
    ║        (พยัญชนะ + สระระดับบรรทัด) are counted towards the 5-char     ║
    ║        minimum in Hard Mode (preventing words like บอกซ์, ปกปิด).     ║
    ║   2. Sticky / Latched Hard Mode Detection:                           ║
    ║      - Hard mode no longer flickers or randomly resets to Easy mode  ║
    ║        when the table popup disappears.                              ║
    ║      - Latches to Hard Mode as long as player remains seated.        ║
    ║   3. 3-Way Mode Pill Selector GUI:                                   ║
    ║      - Added [🤖 Auto] [🟢 ง่าย] [🔴 ยาก] pill buttons in UI for     ║
    ║        instant one-click manual locking with clear visual badges.    ║
    ║   4. Hard Mode Safety Net in typeAndSubmitWord:                      ║
    ║      - Refuses to type or submit any word with < 5 base letters      ║
    ║        whenever Hard Mode is active.                                 ║
    ║   5. Retained all v6.0 & v5.6 features:                              ║
    ║      - roundToken async cancellation, getgc event-driven hooks,      ║
    ║        PermanentBlacklist, triedThisRound, auto-backspace on strike. ║
    ╚══════════════════════════════════════════════════════════════════════╝
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer
local Remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
local SubmitRemote = Remotes and Remotes:WaitForChild("Submit", 5)
local TypingRemote = Remotes and Remotes:WaitForChild("Typing", 5)
local MatchRemote = Remotes and Remotes:FindFirstChild("Match")
local NotifyRemote = Remotes and Remotes:FindFirstChild("Notify")

-- ==================== CONFIGURATION & STATE ====================
local Config = {
    Language = "TH",               -- "TH" or "ENG"
    DetectedMode = "Easy",         -- "Easy" (any length) or "Hard" (min 5 chars)
    AutoAnswer = true,             -- Auto submit when it is OUR turn
    SimulateTyping = true,         -- Simulate human typing keystrokes
    DelayBeforeTyping = 0.6,       -- Delay before starting to type (seconds)
    DelayPerChar = 0.08,           -- Delay between each character typed (seconds)
    MaxRetriesPerTurn = 8,         -- Max words to try per turn before giving up
}

local ManualTurnOverride = "Auto"   -- "Auto", "OurTurn", "OpponentTurn"
local ManualModeOverride = "Auto"   -- "Auto", "Easy", "Hard"
local LatchedTableMode = nil        -- Sticky table mode while seated ("Hard" or "Easy")
local ServerTurnState = nil         -- Updated by Remotes.Match listener

local WordDatabase = {}
local UsedWords = {}
local RejectedWords = {}
local PermanentBlacklist = {}
local ActivityLogs = {}
local WordCount = 0

local CurrentPrompt = ""
local TurnStatusText = "TurnWaitingSeat"
local isTypingOrSubmitting = false
local lastSubmittedWord = ""

-- ==================== V6.0: ROUND TOKEN & EVENT-DRIVEN STATE ====================
local roundToken = 0               -- Incremented on every new round; async loops abort if stale
local retriesThisTurn = 0          -- How many words we've tried this turn
local triedThisRound = {}          -- Words tried in current round (reset each round)
local pendingSuffix = 0            -- Number of suffix chars typed (for backspace on rejection)
local pendingWord = nil            -- Currently pending word awaiting accept/reject
local gameEventModule = nil        -- Internal game event module found via getgc()
local eventConnections = {}        -- Stored connections for cleanup
local useEventDriven = false       -- Whether we successfully hooked game events

-- Blacklist UI words to avoid picking up random buttons
local IgnoredUIWords = {
    ["เริ่ม"] = true, ["ออก"] = true, ["ร้านค้า"] = true, ["เวลา"] = true,
    ["ตาคุณ"] = true, ["ถึงตาคุณ"] = true, ["รอบที่"] = true, ["ชนะ"] = true, ["แพ้"] = true,
    ["เหรียญ"] = true, ["หัวใจ"] = true, ["อันดับ"] = true, ["แชท"] = true,
    ["ตั้งค่า"] = true, ["บริจาค"] = true, ["โปรไฟล์"] = true, ["โต๊ะ"] = true,
    ["ผู้เล่น"] = true, ["กำลังเล่น"] = true, ["รอผู้เล่น"] = true, ["หมดเวลา"] = true,
    ["กติกา"] = true, ["รางวัล"] = true, ["สุ่ม"] = true, ["ภารกิจ"] = true,
    ["ส่ง"] = true, ["ยืนยัน"] = true, ["ตอบ"] = true, ["พิมพ์ที่นี่"] = true,
    ["ตาคู่แข่ง"] = true, ["รอคู่แข่ง"] = true, ["รอบคุณ"] = true
}

-- ==================== TRANSLATIONS (TH & ENG) ====================
local I18N = {
    TH = {
        Title = "🇹🇭 ต่อคำศัพท์ภาษาไทย | ตัวช่วยอัจฉริยะ v6.1",
        TabMain = "⚡ หน้าหลัก",
        TabLogs = "📜 บันทึก (Logs)",
        TabSettings = "⚙️ ตั้งค่า",
        
        ModeLabel = "🎮 โหมดที่โต๊ะ:",
        ModeAutoBtn = "🤖 Auto",
        ModeEasyBtn = "🟢 ง่าย",
        ModeHardBtn = "🔴 ยาก",
        ModeEasy = "🟢 โหมดง่าย (กี่ตัวก็ได้)",
        ModeHard = "🔴 โหมดยาก (ขั้นต่ำ 5 ตัว)",
        ModeEasyLocked = "🔒 โหมดง่าย (ล็อก)",
        ModeHardLocked = "🔒 โหมดยาก (ล็อก 5+ ตัว)",
        
        TurnStatusLabel = "👤 สถานะเทิร์น:",
        TurnWaitingSeat = "🪑 รอเริ่มเกม / นั่งที่โต๊ะ",
        TurnOpponent = "⏳ รอตาคู่แข่ง",
        TurnOurs = "🟢 ถึงตาเราแล้ว!",
        TurnRetrying = "⚠️ คำไม่ผ่าน! ลองคำใหม่...",
        
        TurnAutoBtn = "🤖 Auto",
        TurnMeBtn = "🟢 ตาเรา",
        TurnOpponentBtn = "⏳ คู่แข่ง",
        
        AutoAnswerTitle = "ตอบคำศัพท์อัตโนมัติ (Auto-Answer)",
        SimulateTypingTitle = "จำลองการพิมพ์ (Human Typing)",
        
        DelayBeforeTitle = "ดีเลย์ก่อนเริ่มพิมพ์ (วินาที):",
        DelayPerCharTitle = "ดีเลย์ระหว่างพิมพ์แต่ละตัว (วินาที):",
        MaxRetriesTitle = "จำนวนครั้งลองสูงสุดต่อเทิร์น:",
        
        PromptSection = "🎯 โจทย์ปัจจุบัน (ตัวอักษรที่ต้องต่อ):",
        PromptPlaceholder = "ตรวจจับอัตโนมัติ หรือพิมพ์โจทย์เอง เช่น 'ก', 'กร', 'กรั'...",
        ClearBtn = "ล้าง",
        
        WordListTitle = "📋 คำศัพท์ที่ใช้ได้ (เรียงจากสั้น ➔ ยาว):",
        NoWordsFound = "ไม่พบคำศัพท์ที่ตรงเงื่อนไขโหมด",
        WordBadge = "[%d ตัว]",
        
        CopyLogBtn = "📋 คัดลอก Log",
        SaveLogBtn = "💾 บันทึกไฟล์ Log",
        ClearLogBtn = "🗑️ ล้าง",
        DebugScanBtn = "🔍 ตรวจ UI",
        ResetBlacklistBtn = "🔄 ล้าง Blacklist คำผิด (%d คำ)",
        LogCopied = "คัดลอก Log แล้ว!",
        LogSaved = "บันทึก log.txt แล้ว!",
        
        LangTitle = "ภาษาหน้าต่าง (Language)",
        UnloadBtn = "ปิดสคริปต์ (Close UI)",
        DictStatus = "📖 ฐานข้อมูลคำศัพท์: %d คำ",
        EventDrivenStatus = "🔗 Event Hook: %s",
    },
    ENG = {
        Title = "🇹🇭 Thai Word Chain | Helper & Solver v6.1",
        TabMain = "⚡ Main",
        TabLogs = "📜 Logs",
        TabSettings = "⚙️ Settings",
        
        ModeLabel = "🎮 Table Mode:",
        ModeAutoBtn = "🤖 Auto",
        ModeEasyBtn = "🟢 Easy",
        ModeHardBtn = "🔴 Hard",
        ModeEasy = "🟢 Easy (Any length)",
        ModeHard = "🔴 Hard (Min 5 chars)",
        ModeEasyLocked = "🔒 Easy (Locked)",
        ModeHardLocked = "🔒 Hard (Locked 5+ chars)",
        
        TurnStatusLabel = "👤 Turn Status:",
        TurnWaitingSeat = "🪑 Waiting for Game / Table",
        TurnOpponent = "⏳ Opponent's Turn",
        TurnOurs = "🟢 Our Turn!",
        TurnRetrying = "⚠️ Retrying next word...",
        
        TurnAutoBtn = "🤖 Auto",
        TurnMeBtn = "🟢 Me",
        TurnOpponentBtn = "⏳ Opponent",
        
        AutoAnswerTitle = "Auto-Answer",
        SimulateTypingTitle = "Simulate Typing",
        
        DelayBeforeTitle = "Delay Before Typing (Seconds):",
        DelayPerCharTitle = "Delay Per Character (Seconds):",
        MaxRetriesTitle = "Max Retries Per Turn:",
        
        PromptSection = "🎯 Current Prompt / Prefix:",
        PromptPlaceholder = "Auto-detected or enter prefix e.g. 'ก', 'กร', 'กรั'...",
        ClearBtn = "Clear",
        
        WordListTitle = "📋 Valid Words (Shortest ➔ Longest):",
        NoWordsFound = "No matching words found for current mode",
        WordBadge = "[%d chars]",
        
        CopyLogBtn = "📋 Copy Logs",
        SaveLogBtn = "💾 Save Log",
        ClearLogBtn = "🗑️ Clear",
        DebugScanBtn = "🔍 Debug UI",
        ResetBlacklistBtn = "🔄 Reset Blacklist (%d words)",
        LogCopied = "Logs copied!",
        LogSaved = "Saved to log.txt!",
        
        LangTitle = "Language (ภาษา)",
        UnloadBtn = "Unload / Close Script",
        DictStatus = "📖 Word Database: %d words",
        EventDrivenStatus = "🔗 Event Hook: %s",
    }
}

local function getText(key, ...)
    local lang = Config.Language or "TH"
    local str = (I18N[lang] and I18N[lang][key]) or I18N["TH"][key] or key
    if select("#", ...) > 0 then
        return string.format(str, ...)
    end
    return str
end

-- ==================== ACCURATE THAI CHARACTER COUNTING UTILITIES ====================

-- Determines if a Unicode codepoint is a Thai combining mark (non-spacing upper/lower vowel, tone mark, or thanthakhat)
-- In Thai Word Chain and Thai language rules, these sit on/under a consonant and DO NOT count as a standalone character.
local function isThaiCombiningMark(code)
    -- 3633: MAI HAN-AKAT (ั)
    -- 3636 to 3642: SARA I (ิ), SARA II (ี), SARA UE (ึ), SARA UEE (ื), SARA U (ุ), SARA UU (ู), PHINTHU (ฺ)
    -- 3655 to 3662: MAITAIKHU (็), MAI EK (่), MAI THO (้), MAI TRI (๊), MAI CHATTAWA (๋), THANTHAKHAT (์), NIKHAHIT (ํ), YAMAKKAN (๎)
    return code == 3633 or (code >= 3636 and code <= 3642) or (code >= 3655 and code <= 3662)
end

-- Counts only standalone/base characters (Consonants + in-line vowels like เ, แ, โ, ใ, ไ, ะ, า, ำ, อ)
-- Words like 'บอกซ์', 'ปกปิด', 'ปกรณ์' have only 4 base characters, so they are properly recognized as < 5.
local function getThaiBaseCharCount(str)
    if not str or str == "" then return 0 end
    local count = 0
    pcall(function()
        for _, code in utf8.codes(str) do
            if code >= 3585 and code <= 3675 then
                if not isThaiCombiningMark(code) then
                    count = count + 1
                end
            elseif (code >= 65 and code <= 90) or (code >= 97 and code <= 122) or (code >= 48 and code <= 57) then
                count = count + 1
            end
        end
    end)
    return count
end

-- Total UTF-8 codepoints count
local function getThaiCharCount(str)
    if not str or str == "" then return 0 end
    local ok, len = pcall(utf8.len, str)
    if ok and len then return len end
    local count = 0
    for _ in string.gmatch(str, "[%z\1-\127\194-\244][\128-\191]*") do
        count = count + 1
    end
    return count
end

local function extractThaiOnly(str)
    if not str or str == "" then return "" end
    local res = {}
    pcall(function()
        for _, code in utf8.codes(str) do
            if code >= 3585 and code <= 3675 then
                table.insert(res, utf8.char(code))
            end
        end
    end)
    return table.concat(res)
end

local function startsWithLeadingVowel(str)
    if not str or str == "" then return false end
    local ok, code = pcall(utf8.codepoint, str, 1, 1)
    if ok and code then
        if code >= 3648 and code <= 3652 then
            return true
        end
    end
    return false
end

-- Split a UTF-8 string into individual codepoint characters
local function utf8Chars(str)
    local chars = {}
    for ch in string.gmatch(str, "[%z\1-\127\194-\244][\128-\191]*") do
        table.insert(chars, ch)
    end
    return chars
end

-- Helper to check if Hard Mode is currently active (Manual or Detected)
local function isHardModeActive()
    if ManualModeOverride == "Hard" then return true end
    if ManualModeOverride == "Easy" then return false end
    return Config.DetectedMode == "Hard"
end

-- ==================== EXPANDED WORD DATABASE ====================

local FallbackWords = {
    -- ก
    "กา","กาก","กาง","กางเกง","กาแฟ","การ","การบ้าน","กาน้ำ","การค้า","กาละแม","กาลเวลา",
    "กรรมาธิการ","กรรณิการ์","กรรมการ","กรมการ","กรุณา","กรุงเทพ","กระดาษ","กระดาน","กระเป๋า",
    "กระรอก","กระถาง","กระจก","กระท่อม","กระเพาะ","กราบ","กรง","กรัก","กรัง","กักขัง","กัลปาวสาน",
    -- ข
    "ขา","ขาว","ข้า","ข้าม","ข้าว","ขวด","ของ","ขอทาน","ขนม","ขนส่ง","ขอบใจ","ขยัน",
    "ข้าราชการ","ขยายตัว","ขวนขวาย","ขัดสน","ขวานผ่าซาก","ขีดจำกัด","ขนมปัง","ขี้ผึ้ง","ขุนนาง",
    -- ค
    "คน","ความ","ครอบครัว","ควาย","คอมพิวเตอร์","คำ","คำตอบ","คำถาม","คณิตศาสตร์","คะแนน",
    "ความรัก","ความหวัง","ความฝัน","ความรู้","ความจริง","ความสุข","คริสตจักร","คฤหาสน์","ครูบาอาจารย์",
    -- ง
    "งู","งาน","เงิน","เงียบ","ง่าย","งดงาม","งอก","แง่","ง่วง","งบประมาณ","เงียบสงบ","งูเหลือม",
    -- จ
    "จาน","จริง","จดหมาย","จันทร์","ใจ","จักรยาน","จระเข้","จัด","จบ","จงกรม","จงรักภักดี",
    "จินตนาการ","จิตแพทย์","จิตรกร","จักรวาล","จารึก","จอมปลวก","จุฬาลงกรณ์","เจตนา","โจรกรรม",
    -- ฉ
    "ฉลาม","ฉัน","เฉลย","ฉาย","ฉลาด","โฉมงาม","ฉลอง","ฉัตรมงคล","ฉุกเฉิน","ฉลากกินแบ่ง",
    -- ช
    "ช้าง","ชอบ","ช่วย","ชาม","ชาย","ชีวิต","ชั่วโมง","ช้า","โชคดี","ชัยชนะ","ชมพู่","ชลประทาน",
    "ชาวประมง","ชาติพัฒนา","ชาวสวรรค์","ชุมทาง","เชี่ยวชาญ","โชคชะตา",
    -- ซ
    "ซ่อม","ซื้อ","ซอย","ซุป","ซื่อสัตย์","ซึ่งกันและกัน","ซากศพ","ซ่อนหา","ซอฟต์แวร์",
    -- ด
    "ดาว","ดิน","เดิน","เด็ก","ดู","ดี","ดับ","ดอกไม้","ดวงอาทิตย์","ดนตรี","ดาราศาสตร์",
    "ดวงจันทร์","ดำเนินคดี","ดำรงตำแหน่ง","ดูดกลืน","ดักแด้","ดาวฤกษ์",
    -- ต
    "ตา","ตาย","ตาม","ตาราง","ตื่น","โต๊ะ","ต้นไม้","ตลาด","ตะวัน","ตัวเลข","ตาสว่าง",
    "ตำรวจ","ตั้งใจ","ตระกูล","ตรากตรำ","ตัดเชือก","ตั้งครรภ์","ไต่สวน",
    -- ถ
    "ถนน","ถาม","ถ้วย","ถุง","ถูก","ถั่ว","แถว","ถาวร","ถ่ายรูป","ถิ่นกำเนิด","ถอดรหัส","ถ้อยคำ",
    -- ท
    "ทหาร","ทาง","ทำ","ที่","ทอง","ทะเล","โทรทัศน์","โทรศัพท์","ทุกข์","ธรรมชาติ","ทัศนศิลป์",
    "ทรัพยากร","ทวีปยุโรป","ทบทวน","ทองคำเปลว","เทศบาล",
    -- ธ
    "ธง","เธอ","ธรรม","ธรรมดา","ธรรมชาติ","ธนาคาร","ธรรมาภิบาล","ธาตุแท้","ธรณีวิทยา",
    -- น
    "นา","น้ำ","นก","นอน","นั่ง","น้อง","หนังสือ","นิทาน","นาฬิกา","นกยูง","นกฮูก","นักเรียน",
    "นักศึกษา","นักร้อง","นางฟ้า","นโยบาย","น้ำตาล","นารายณ์","น้ำประปา","นวนิยาย",
    -- บ
    "บ้าน","บิน","บอก","บาท","ใบ","บาง","บัว","บ่าย","บทเรียน","บงการ","บอกกล่าว",
    "บรรยากาศ","บรรยาย","บวชเรียน","บริจาค","บริษัท","บันทึก","บัณฑิต","บำรุงรักษา",
    -- ป
    "ปลา","ปาก","ไป","ป่า","เปิด","ปิด","ปี","แป้ง","แปร","ปกปิด","ปกรณ์","ปกครอง",
    "ประโยชน์","ปรากฏการณ์","ประเทศไทย","ประชากร","ประเพณี","ประตู","ประสบการณ์","ประดิษฐ์",
    -- ผ
    "ผม","ผ้า","ผู้","ผึ้ง","ผลไม้","ผัก","แผ่นดิน","แผนที่","ผู้ใหญ่","ผลัดใบ","ผลการเรียน",
    -- ฝ
    "ฝน","ฝาก","ฝา","ฝรั่ง","ฝึกฝน","ฝัน","ฝ่าฟัน","ฝากครรภ์","ฝึกอาชีพ",
    -- พ
    "พริก","พ่อ","พี่","เพื่อน","เพลง","พาย","พี่น้อง","พลัง","พูด","พัฒนา","พิจารณา",
    "พจนานุกรม","พระมหากษัตริย์","พฤติกรรม","พยากรณ์","พระอาทิตย์","พลเมือง",
    -- ฟ
    "ฟัน","ไฟ","ฟ้า","ฟาง","ฟุตบอล","ฟิล์ม","ฟองสบู่","ฟอสซิล","ฟ้าผ่า",
    -- ม
    "มด","มา","แม่","ไม้","มือ","แมว","เมือง","มะนาว","มะพร้าว","มนุษย์","มิตรภาพ",
    "มหาวิทยาลัย","มหาเศรษฐี","มรดกโลก","มาตุภูมิ","มาตรการ",
    -- ย
    "ยาย","ยาก","ยา","ยาว","ยิ้ม","เย็น","หยุด","ยอม","ยุค","ยุทธศาสตร์","ยุติธรรม",
    "ยานอวกาศ","ยอมรับ","ยามวิกาล","ยอดเยี่ยม",
    -- ร
    "รถ","รัก","เรา","ร้อน","รวย","โรงเรียน","เรือ","ร่ม","ร่างกาย","รกชัฏ","รกบิน",
    "รัฐบาล","รัฐธรรมนูญ","ราษฎร","ราชาธิปไตย","ระมัดระวัง","รางวัล",
    -- ล
    "ลม","ลิง","ลูก","เล่น","โลก","ลอย","ลำธาร","ลึก","ลูกหมา","ลวดลาย","ล่องหน",
    "ลูกเสือ","ลำดับขั้น","เลขาธิการ",
    -- ว
    "วัน","วัว","วิ่ง","วัด","วา","วิชา","วิถี","เวลา","วิทยาลัย","วิทยาศาสตร์",
    "วิศวกร","วัฒนธรรม","วิจารณญาณ","วิเคราะห์","วิวาห์",
    -- ศ
    "ศาลา","ศิลปะ","ศึกษา","ศีรษะ","ศัตรู","ศตวรรษ","ศานติ","ศิลาจารึก",
    -- ส
    "สวน","สวย","ส้ม","เสือ","เสื้อ","สาย","สี","สมอง","สงคราม","สะอาด","สกปรก",
    "สถานีรถไฟ","สังคมศาสตร์","สุนัขจิ้งจอก","สมุนไพร","สวัสดี","สุขภาพ","สหภาพแรงงาน",
    -- ห
    "หมู","หมา","หน้า","หนู","ห้อง","หัว","หาง","หัวใจ","หญ้า","หลวง","หินปูน",
    "หนังสือพิมพ์","ห้วงอวกาศ","หัตถกรรม","เห็ดหอม","หลอดเลือด",
    -- อ
    "อ่าง","อ่าน","อากาศ","อาหาร","อาจารย์","โอกาส","อิสระ","อนุสาวรีย์","อุทยานแห่งชาติ",
    "อุตสาหกรรม","อภิมหาเศรษฐี","อุปสรรค","อดีตชาติ","อารยธรรม",
    -- ฮ
    "ฮก","ฮา","ฮอลล์","ฮัม","ฮิต","เฮฮา","ฮิปโปโปเตมัส","ฮอร์โมน"
}

local function populateInitialWords()
    for _, w in ipairs(FallbackWords) do
        if not PermanentBlacklist[w] and not UsedWords[w] then
            if not WordDatabase[w] then
                WordDatabase[w] = true
                WordCount = WordCount + 1
            end
        end
    end
end
populateInitialWords()

-- Asynchronous full PyThaiNLP corpus loader (62,000+ words)
task.spawn(function()
    local success, content = pcall(function()
        return game:HttpGet("https://raw.githubusercontent.com/PyThaiNLP/pythainlp/dev/pythainlp/corpus/words_th.txt")
    end)
    
    if success and content and #content > 1000 then
        local count = 0
        for word in string.gmatch(content, "[^\r\n]+") do
            word = string.gsub(word, "^%s*(.-)%s*$", "%1")
            if #word >= 2 and not string.find(word, "[%a%d%p%s]") then
                if not PermanentBlacklist[word] and not UsedWords[word] and not WordDatabase[word] then
                    WordDatabase[word] = true
                    count = count + 1
                end
            end
        end
        WordCount = WordCount + count
        print("[ThaiWordChain] Total dictionary words loaded:", WordCount)
    end
end)

-- ==================== PERMANENT BLACKLIST & WORD REMOVAL ====================

local function getTableCount(tbl)
    local n = 0
    for _ in pairs(tbl) do n = n + 1 end
    return n
end

-- Permanently blacklists a rejected word so it can NEVER be repeated
local function blacklistRejectedWord(word)
    if not word or word == "" then return end
    RejectedWords[word] = true
    PermanentBlacklist[word] = true
    triedThisRound[word] = true
    if WordDatabase[word] then
        WordDatabase[word] = nil
        WordCount = math.max(0, WordCount - 1)
    end
end

-- Marks a successfully accepted word as used
local function markWordUsed(word)
    if not word or word == "" then return end
    UsedWords[word] = true
    if WordDatabase[word] then
        WordDatabase[word] = nil
        WordCount = math.max(0, WordCount - 1)
    end
end

-- Finds matching words for the given prefix, strictly adhering to mode constraints
local function findMatchingWords(prefix)
    prefix = string.gsub(prefix or "", "^%s*(.-)%s*$", "%1")
    if prefix == "" then return {} end
    
    local results = {}
    local pLen = #prefix
    local hardMode = isHardModeActive()
    local prefixHasLeadingVowel = startsWithLeadingVowel(prefix)
    
    for word, _ in pairs(WordDatabase) do
        -- Strict 4-Way Filter: Never return used, rejected, blacklisted, or tried-this-round words!
        if not UsedWords[word] and not RejectedWords[word] and not PermanentBlacklist[word] and not triedThisRound[word] then
            if prefixHasLeadingVowel or not startsWithLeadingVowel(word) then
                if string.sub(word, 1, pLen) == prefix then
                    local baseCount = getThaiBaseCharCount(word)
                    local totalCount = getThaiCharCount(word)
                    
                    if hardMode then
                        -- Hard Mode: Word MUST have AT LEAST 5 standalone base letters
                        -- AND total UTF-8 character length >= 5.
                        -- Words like 'บอกซ์' (4 base), 'ปกปิด' (4 base), 'ปกรณ์' (4 base) are STRICTLY excluded!
                        if baseCount >= 5 and totalCount >= 5 then
                            table.insert(results, {Word = word, Length = baseCount})
                        end
                    else
                        -- Easy Mode: Any word length >= 1 allowed
                        if totalCount >= 1 then
                            table.insert(results, {Word = word, Length = totalCount})
                        end
                    end
                end
            end
        end
    end
    
    table.sort(results, function(a, b)
        if a.Length == b.Length then
            return a.Word < b.Word
        end
        return a.Length < b.Length
    end)
    
    return results
end

-- ==================== V6.0: EVENT MODULE DISCOVERY VIA getgc() ====================

local function discoverGameEventModule()
    if not getgc then
        return nil
    end
    
    local success, result = pcall(function()
        local gc = getgc(true)
        for _, v in gc do
            if type(v) == "table" then
                if rawget(v, "remoteFire") and rawget(v, "remoteConnect") then
                    return v
                end
                if rawget(v, "fire") and rawget(v, "connect") and rawget(v, "remoteFire") then
                    return v
                end
            end
        end
        return nil
    end)
    
    if success and result then
        return result
    end
    return nil
end

-- ==================== GUI CREATION ====================
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "ThaiWordChainHelper_v6_1"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local parentTarget = CoreGui:FindFirstChild("RobloxGui") or CoreGui or LocalPlayer:WaitForChild("PlayerGui")
pcall(function()
    for _, old in ipairs(parentTarget:GetChildren()) do
        if string.find(old.Name, "ThaiWordChainHelper") then
            old:Destroy()
        end
    end
end)
ScreenGui.Parent = parentTarget

-- Main Window Frame
local MainFrame = Instance.new("Frame")
MainFrame.Name = "MainFrame"
MainFrame.Size = UDim2.new(0, 510, 0, 460)
MainFrame.Position = UDim2.new(0.5, -255, 0.5, -230)
MainFrame.BackgroundColor3 = Color3.fromRGB(24, 26, 33)
MainFrame.BorderSizePixel = 0
MainFrame.ClipsDescendants = true
MainFrame.Parent = ScreenGui

local UICorner = Instance.new("UICorner")
UICorner.CornerRadius = UDim.new(0, 12)
UICorner.Parent = MainFrame

local UIStroke = Instance.new("UIStroke")
UIStroke.Color = Color3.fromRGB(48, 52, 66)
UIStroke.Thickness = 1.5
UIStroke.Parent = MainFrame

-- Draggable Window
local dragging, dragInput, dragStart, startPos
MainFrame.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = MainFrame.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                dragging = false
            end
        end)
    end
end)

MainFrame.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
        dragInput = input
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if input == dragInput and dragging then
        local delta = input.Position - dragStart
        MainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end
end)

-- Topbar
local TopBar = Instance.new("Frame")
TopBar.Name = "TopBar"
TopBar.Size = UDim2.new(1, 0, 0, 42)
TopBar.BackgroundColor3 = Color3.fromRGB(30, 33, 44)
TopBar.BorderSizePixel = 0
TopBar.Parent = MainFrame

local TitleLabel = Instance.new("TextLabel")
TitleLabel.Name = "TitleLabel"
TitleLabel.Size = UDim2.new(1, -90, 1, 0)
TitleLabel.Position = UDim2.new(0, 14, 0, 0)
TitleLabel.BackgroundTransparency = 1
TitleLabel.Font = Enum.Font.GothamBold
TitleLabel.Text = getText("Title")
TitleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
TitleLabel.TextSize = 13
TitleLabel.TextXAlignment = Enum.TextXAlignment.Left
TitleLabel.Parent = TopBar

local CloseBtn = Instance.new("TextButton")
CloseBtn.Name = "CloseBtn"
CloseBtn.Size = UDim2.new(0, 28, 0, 28)
CloseBtn.Position = UDim2.new(1, -36, 0.5, -14)
CloseBtn.BackgroundColor3 = Color3.fromRGB(235, 75, 75)
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.Text = "✕"
CloseBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
CloseBtn.TextSize = 13
CloseBtn.Parent = TopBar

local CloseCorner = Instance.new("UICorner")
CloseCorner.CornerRadius = UDim.new(0, 6)
CloseCorner.Parent = CloseBtn

CloseBtn.MouseButton1Click:Connect(function()
    ScreenGui:Destroy()
end)

-- Tab Bar
local TabBar = Instance.new("Frame")
TabBar.Name = "TabBar"
TabBar.Size = UDim2.new(1, 0, 0, 34)
TabBar.Position = UDim2.new(0, 0, 0, 42)
TabBar.BackgroundColor3 = Color3.fromRGB(20, 22, 28)
TabBar.BorderSizePixel = 0
TabBar.Parent = MainFrame

local TabButtons = {}
local TabFrames = {}

local function createTab(name, key, posX, width)
    local btn = Instance.new("TextButton")
    btn.Name = name .. "TabBtn"
    btn.Size = UDim2.new(0, width, 1, 0)
    btn.Position = UDim2.new(0, posX, 0, 0)
    btn.BackgroundTransparency = 1
    btn.Font = Enum.Font.GothamSemibold
    btn.Text = getText(key)
    btn.TextColor3 = Color3.fromRGB(160, 165, 180)
    btn.TextSize = 12
    btn.Parent = TabBar
    
    local page = Instance.new("Frame")
    page.Name = name .. "Page"
    page.Size = UDim2.new(1, -20, 1, -86)
    page.Position = UDim2.new(0, 10, 0, 80)
    page.BackgroundTransparency = 1
    page.Visible = false
    page.Parent = MainFrame
    
    TabButtons[name] = {Btn = btn, Key = key}
    TabFrames[name] = page
    
    btn.MouseButton1Click:Connect(function()
        for tName, tData in pairs(TabFrames) do
            tData.Visible = (tName == name)
            TabButtons[tName].Btn.TextColor3 = (tName == name) and Color3.fromRGB(255, 215, 0) or Color3.fromRGB(160, 165, 180)
        end
    end)
    return page
end

local MainPage = createTab("Main", "TabMain", 10, 110)
local LogsPage = createTab("Logs", "TabLogs", 125, 120)
local SettingsPage = createTab("Settings", "TabSettings", 250, 110)

TabFrames["Main"].Visible = true
TabButtons["Main"].Btn.TextColor3 = Color3.fromRGB(255, 215, 0)

local ElementsToTranslate = {}

local function createCard(parent, height, yPos)
    local card = Instance.new("Frame")
    card.Size = UDim2.new(1, 0, 0, height or 54)
    if yPos then
        card.Position = UDim2.new(0, 0, 0, yPos)
    end
    card.BackgroundColor3 = Color3.fromRGB(32, 35, 46)
    card.BorderSizePixel = 0
    card.Parent = parent
    
    local crn = Instance.new("UICorner")
    crn.CornerRadius = UDim.new(0, 8)
    crn.Parent = card
    
    local strk = Instance.new("UIStroke")
    strk.Color = Color3.fromRGB(44, 48, 62)
    strk.Thickness = 1
    strk.Parent = card
    
    return card
end

-- Forward declaration of refreshWordList
local refreshWordList
local addLogEntry

-- ==================== TAB 1: MAIN PAGE ====================

local StatusCard = createCard(MainPage, 74, 0)

-- Mode Row & 3-Way Quick Pill Selectors
local ModeLabel = Instance.new("TextLabel")
ModeLabel.Size = UDim2.new(0, 70, 0, 24)
ModeLabel.Position = UDim2.new(0, 12, 0, 7)
ModeLabel.BackgroundTransparency = 1
ModeLabel.Font = Enum.Font.GothamBold
ModeLabel.Text = getText("ModeLabel")
ModeLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
ModeLabel.TextSize = 11
ModeLabel.TextXAlignment = Enum.TextXAlignment.Left
ModeLabel.Parent = StatusCard
table.insert(ElementsToTranslate, {Title = ModeLabel, TitleKey = "ModeLabel"})

local ModeAutoBtn = Instance.new("TextButton")
ModeAutoBtn.Size = UDim2.new(0, 56, 0, 22)
ModeAutoBtn.Position = UDim2.new(0, 85, 0, 8)
ModeAutoBtn.BackgroundColor3 = Color3.fromRGB(52, 152, 219)
ModeAutoBtn.Font = Enum.Font.GothamBold
ModeAutoBtn.Text = getText("ModeAutoBtn")
ModeAutoBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
ModeAutoBtn.TextSize = 10
ModeAutoBtn.Parent = StatusCard
local mabCrn = Instance.new("UICorner")
mabCrn.CornerRadius = UDim.new(0, 6)
mabCrn.Parent = ModeAutoBtn

local ModeEasyBtn = Instance.new("TextButton")
ModeEasyBtn.Size = UDim2.new(0, 60, 0, 22)
ModeEasyBtn.Position = UDim2.new(0, 146, 0, 8)
ModeEasyBtn.BackgroundColor3 = Color3.fromRGB(44, 48, 62)
ModeEasyBtn.Font = Enum.Font.GothamBold
ModeEasyBtn.Text = getText("ModeEasyBtn")
ModeEasyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
ModeEasyBtn.TextSize = 10
ModeEasyBtn.Parent = StatusCard
local mebCrn = Instance.new("UICorner")
mebCrn.CornerRadius = UDim.new(0, 6)
mebCrn.Parent = ModeEasyBtn

local ModeHardBtn = Instance.new("TextButton")
ModeHardBtn.Size = UDim2.new(0, 66, 0, 22)
ModeHardBtn.Position = UDim2.new(0, 211, 0, 8)
ModeHardBtn.BackgroundColor3 = Color3.fromRGB(44, 48, 62)
ModeHardBtn.Font = Enum.Font.GothamBold
ModeHardBtn.Text = getText("ModeHardBtn")
ModeHardBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
ModeHardBtn.TextSize = 10
ModeHardBtn.Parent = StatusCard
local mhbCrn = Instance.new("UICorner")
mhbCrn.CornerRadius = UDim.new(0, 6)
mhbCrn.Parent = ModeHardBtn

local ModeBadge = Instance.new("TextLabel")
ModeBadge.Size = UDim2.new(1, -290, 0, 22)
ModeBadge.Position = UDim2.new(0, 285, 0, 8)
ModeBadge.BackgroundTransparency = 1
ModeBadge.Font = Enum.Font.GothamBold
ModeBadge.Text = getText("ModeEasy")
ModeBadge.TextColor3 = Color3.fromRGB(46, 204, 113)
ModeBadge.TextSize = 11
ModeBadge.TextXAlignment = Enum.TextXAlignment.Left
ModeBadge.Parent = StatusCard

local function updateModePillButtons()
    if ManualModeOverride == "Auto" then
        ModeAutoBtn.BackgroundColor3 = Color3.fromRGB(52, 152, 219)
        ModeEasyBtn.BackgroundColor3 = Color3.fromRGB(44, 48, 62)
        ModeHardBtn.BackgroundColor3 = Color3.fromRGB(44, 48, 62)
        if Config.DetectedMode == "Hard" then
            ModeBadge.Text = getText("ModeHard")
            ModeBadge.TextColor3 = Color3.fromRGB(231, 76, 60)
        else
            ModeBadge.Text = getText("ModeEasy")
            ModeBadge.TextColor3 = Color3.fromRGB(46, 204, 113)
        end
    elseif ManualModeOverride == "Hard" then
        ModeAutoBtn.BackgroundColor3 = Color3.fromRGB(44, 48, 62)
        ModeEasyBtn.BackgroundColor3 = Color3.fromRGB(44, 48, 62)
        ModeHardBtn.BackgroundColor3 = Color3.fromRGB(231, 76, 60)
        ModeBadge.Text = getText("ModeHardLocked")
        ModeBadge.TextColor3 = Color3.fromRGB(231, 76, 60)
    elseif ManualModeOverride == "Easy" then
        ModeAutoBtn.BackgroundColor3 = Color3.fromRGB(44, 48, 62)
        ModeEasyBtn.BackgroundColor3 = Color3.fromRGB(46, 204, 113)
        ModeHardBtn.BackgroundColor3 = Color3.fromRGB(44, 48, 62)
        ModeBadge.Text = getText("ModeEasyLocked")
        ModeBadge.TextColor3 = Color3.fromRGB(46, 204, 113)
    end
end

ModeAutoBtn.MouseButton1Click:Connect(function()
    ManualModeOverride = "Auto"
    updateModePillButtons()
    if addLogEntry then addLogEntry("Mode set to [Auto Detection].", Color3.fromRGB(52, 152, 219)) end
    if refreshWordList then refreshWordList(CurrentPrompt) end
end)

ModeEasyBtn.MouseButton1Click:Connect(function()
    ManualModeOverride = "Easy"
    Config.DetectedMode = "Easy"
    updateModePillButtons()
    if addLogEntry then addLogEntry("Mode manually locked to [Easy Mode].", Color3.fromRGB(46, 204, 113)) end
    if refreshWordList then refreshWordList(CurrentPrompt) end
end)

ModeHardBtn.MouseButton1Click:Connect(function()
    ManualModeOverride = "Hard"
    Config.DetectedMode = "Hard"
    updateModePillButtons()
    if addLogEntry then addLogEntry("Mode manually locked to [Hard Mode - Min 5 Base Chars].", Color3.fromRGB(231, 76, 60)) end
    if refreshWordList then refreshWordList(CurrentPrompt) end
end)

-- Turn Row & 3-Way Quick Pill Selectors
local TurnLabel = Instance.new("TextLabel")
TurnLabel.Size = UDim2.new(0, 70, 0, 24)
TurnLabel.Position = UDim2.new(0, 12, 0, 40)
TurnLabel.BackgroundTransparency = 1
TurnLabel.Font = Enum.Font.GothamBold
TurnLabel.Text = getText("TurnStatusLabel")
TurnLabel.TextColor3 = Color3.fromRGB(180, 185, 200)
TurnLabel.TextSize = 11
TurnLabel.TextXAlignment = Enum.TextXAlignment.Left
TurnLabel.Parent = StatusCard
table.insert(ElementsToTranslate, {Title = TurnLabel, TitleKey = "TurnStatusLabel"})

local TurnAutoBtn = Instance.new("TextButton")
TurnAutoBtn.Size = UDim2.new(0, 56, 0, 22)
TurnAutoBtn.Position = UDim2.new(0, 85, 0, 41)
TurnAutoBtn.BackgroundColor3 = Color3.fromRGB(52, 152, 219)
TurnAutoBtn.Font = Enum.Font.GothamBold
TurnAutoBtn.Text = getText("TurnAutoBtn")
TurnAutoBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
TurnAutoBtn.TextSize = 10
TurnAutoBtn.Parent = StatusCard
local tabCrn = Instance.new("UICorner")
tabCrn.CornerRadius = UDim.new(0, 6)
tabCrn.Parent = TurnAutoBtn

local TurnMeBtn = Instance.new("TextButton")
TurnMeBtn.Size = UDim2.new(0, 60, 0, 22)
TurnMeBtn.Position = UDim2.new(0, 146, 0, 41)
TurnMeBtn.BackgroundColor3 = Color3.fromRGB(44, 48, 62)
TurnMeBtn.Font = Enum.Font.GothamBold
TurnMeBtn.Text = getText("TurnMeBtn")
TurnMeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
TurnMeBtn.TextSize = 10
TurnMeBtn.Parent = StatusCard
local tmbCrn = Instance.new("UICorner")
tmbCrn.CornerRadius = UDim.new(0, 6)
tmbCrn.Parent = TurnMeBtn

local TurnOpponentBtn = Instance.new("TextButton")
TurnOpponentBtn.Size = UDim2.new(0, 66, 0, 22)
TurnOpponentBtn.Position = UDim2.new(0, 211, 0, 41)
TurnOpponentBtn.BackgroundColor3 = Color3.fromRGB(44, 48, 62)
TurnOpponentBtn.Font = Enum.Font.GothamBold
TurnOpponentBtn.Text = getText("TurnOpponentBtn")
TurnOpponentBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
TurnOpponentBtn.TextSize = 10
TurnOpponentBtn.Parent = StatusCard
local tobCrn = Instance.new("UICorner")
tobCrn.CornerRadius = UDim.new(0, 6)
tobCrn.Parent = TurnOpponentBtn

local TurnBadge = Instance.new("TextLabel")
TurnBadge.Size = UDim2.new(1, -290, 0, 22)
TurnBadge.Position = UDim2.new(0, 285, 0, 41)
TurnBadge.BackgroundTransparency = 1
TurnBadge.Font = Enum.Font.GothamBold
TurnBadge.Text = getText("TurnWaitingSeat")
TurnBadge.TextColor3 = Color3.fromRGB(243, 156, 18)
TurnBadge.TextSize = 11
TurnBadge.TextXAlignment = Enum.TextXAlignment.Left
TurnBadge.Parent = StatusCard

local function updateTurnPillButtons()
    if ManualTurnOverride == "Auto" then
        TurnAutoBtn.BackgroundColor3 = Color3.fromRGB(52, 152, 219)
        TurnMeBtn.BackgroundColor3 = Color3.fromRGB(44, 48, 62)
        TurnOpponentBtn.BackgroundColor3 = Color3.fromRGB(44, 48, 62)
    elseif ManualTurnOverride == "OurTurn" then
        TurnAutoBtn.BackgroundColor3 = Color3.fromRGB(44, 48, 62)
        TurnMeBtn.BackgroundColor3 = Color3.fromRGB(46, 204, 113)
        TurnOpponentBtn.BackgroundColor3 = Color3.fromRGB(44, 48, 62)
    elseif ManualTurnOverride == "OpponentTurn" then
        TurnAutoBtn.BackgroundColor3 = Color3.fromRGB(44, 48, 62)
        TurnMeBtn.BackgroundColor3 = Color3.fromRGB(44, 48, 62)
        TurnOpponentBtn.BackgroundColor3 = Color3.fromRGB(230, 126, 34)
    end
end

TurnAutoBtn.MouseButton1Click:Connect(function()
    ManualTurnOverride = "Auto"
    updateTurnPillButtons()
end)

TurnMeBtn.MouseButton1Click:Connect(function()
    ManualTurnOverride = "OurTurn"
    updateTurnPillButtons()
end)

TurnOpponentBtn.MouseButton1Click:Connect(function()
    ManualTurnOverride = "OpponentTurn"
    updateTurnPillButtons()
end)

-- 2. Toggles Card (Auto-Answer & Simulate Typing)
local TogglesCard = createCard(MainPage, 44, 82)

local AaLbl = Instance.new("TextLabel")
AaLbl.Size = UDim2.new(0, 160, 1, 0)
AaLbl.Position = UDim2.new(0, 12, 0, 0)
AaLbl.BackgroundTransparency = 1
AaLbl.Font = Enum.Font.GothamBold
AaLbl.Text = getText("AutoAnswerTitle")
AaLbl.TextColor3 = Color3.fromRGB(240, 240, 245)
AaLbl.TextSize = 11
AaLbl.TextXAlignment = Enum.TextXAlignment.Left
AaLbl.Parent = TogglesCard
table.insert(ElementsToTranslate, {Title = AaLbl, TitleKey = "AutoAnswerTitle"})

local AaBtn = Instance.new("TextButton")
AaBtn.Size = UDim2.new(0, 42, 0, 22)
AaBtn.Position = UDim2.new(0, 175, 0.5, -11)
AaBtn.BackgroundColor3 = Config.AutoAnswer and Color3.fromRGB(46, 204, 113) or Color3.fromRGB(60, 64, 76)
AaBtn.Text = ""
AaBtn.Parent = TogglesCard
local aaCrn = Instance.new("UICorner")
aaCrn.CornerRadius = UDim.new(1, 0)
aaCrn.Parent = AaBtn

local aaDot = Instance.new("Frame")
aaDot.Size = UDim2.new(0, 16, 0, 16)
aaDot.Position = Config.AutoAnswer and UDim2.new(1, -19, 0.5, -8) or UDim2.new(0, 3, 0.5, -8)
aaDot.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
aaDot.BorderSizePixel = 0
aaDot.Parent = AaBtn
local aaDotCrn = Instance.new("UICorner")
aaDotCrn.CornerRadius = UDim.new(1, 0)
aaDotCrn.Parent = aaDot

AaBtn.MouseButton1Click:Connect(function()
    Config.AutoAnswer = not Config.AutoAnswer
    local targetPos = Config.AutoAnswer and UDim2.new(1, -19, 0.5, -8) or UDim2.new(0, 3, 0.5, -8)
    local targetCol = Config.AutoAnswer and Color3.fromRGB(46, 204, 113) or Color3.fromRGB(60, 64, 76)
    TweenService:Create(aaDot, TweenInfo.new(0.2), {Position = targetPos}):Play()
    TweenService:Create(AaBtn, TweenInfo.new(0.2), {BackgroundColor3 = targetCol}):Play()
end)

local StLbl = Instance.new("TextLabel")
StLbl.Size = UDim2.new(0, 170, 1, 0)
StLbl.Position = UDim2.new(0, 235, 0, 0)
StLbl.BackgroundTransparency = 1
StLbl.Font = Enum.Font.GothamBold
StLbl.Text = getText("SimulateTypingTitle")
StLbl.TextColor3 = Color3.fromRGB(240, 240, 245)
StLbl.TextSize = 11
StLbl.TextXAlignment = Enum.TextXAlignment.Left
StLbl.Parent = TogglesCard
table.insert(ElementsToTranslate, {Title = StLbl, TitleKey = "SimulateTypingTitle"})

local StBtn = Instance.new("TextButton")
StBtn.Size = UDim2.new(0, 42, 0, 22)
StBtn.Position = UDim2.new(1, -54, 0.5, -11)
StBtn.BackgroundColor3 = Config.SimulateTyping and Color3.fromRGB(46, 204, 113) or Color3.fromRGB(60, 64, 76)
StBtn.Text = ""
StBtn.Parent = TogglesCard
local stCrn = Instance.new("UICorner")
stCrn.CornerRadius = UDim.new(1, 0)
stCrn.Parent = StBtn

local stDot = Instance.new("Frame")
stDot.Size = UDim2.new(0, 16, 0, 16)
stDot.Position = Config.SimulateTyping and UDim2.new(1, -19, 0.5, -8) or UDim2.new(0, 3, 0.5, -8)
stDot.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
stDot.BorderSizePixel = 0
stDot.Parent = StBtn
local stDotCrn = Instance.new("UICorner")
stDotCrn.CornerRadius = UDim.new(1, 0)
stDotCrn.Parent = stDot

StBtn.MouseButton1Click:Connect(function()
    Config.SimulateTyping = not Config.SimulateTyping
    local targetPos = Config.SimulateTyping and UDim2.new(1, -19, 0.5, -8) or UDim2.new(0, 3, 0.5, -8)
    local targetCol = Config.SimulateTyping and Color3.fromRGB(46, 204, 113) or Color3.fromRGB(60, 64, 76)
    TweenService:Create(stDot, TweenInfo.new(0.2), {Position = targetPos}):Play()
    TweenService:Create(StBtn, TweenInfo.new(0.2), {BackgroundColor3 = targetCol}):Play()
end)

-- 3. Prompt Input Box
local PromptCard = createCard(MainPage, 48, 134)

local PromptLbl = Instance.new("TextLabel")
PromptLbl.Size = UDim2.new(0, 140, 1, 0)
PromptLbl.Position = UDim2.new(0, 12, 0, 0)
PromptLbl.BackgroundTransparency = 1
PromptLbl.Font = Enum.Font.GothamBold
PromptLbl.Text = getText("PromptSection")
PromptLbl.TextColor3 = Color3.fromRGB(255, 215, 0)
PromptLbl.TextSize = 11
PromptLbl.TextXAlignment = Enum.TextXAlignment.Left
PromptLbl.Parent = PromptCard
table.insert(ElementsToTranslate, {Title = PromptLbl, TitleKey = "PromptSection"})

local PromptInput = Instance.new("TextBox")
PromptInput.Size = UDim2.new(1, -220, 0, 30)
PromptInput.Position = UDim2.new(0, 150, 0.5, -15)
PromptInput.BackgroundColor3 = Color3.fromRGB(20, 22, 28)
PromptInput.Font = Enum.Font.GothamBold
PromptInput.PlaceholderText = getText("PromptPlaceholder")
PromptInput.PlaceholderColor3 = Color3.fromRGB(120, 125, 140)
PromptInput.Text = ""
PromptInput.TextColor3 = Color3.fromRGB(255, 255, 255)
PromptInput.TextSize = 13
PromptInput.ClearTextOnFocus = false
PromptInput.Parent = PromptCard
local piCrn = Instance.new("UICorner")
piCrn.CornerRadius = UDim.new(0, 6)
piCrn.Parent = PromptInput

local ClearBtn2 = Instance.new("TextButton")
ClearBtn2.Size = UDim2.new(0, 56, 0, 30)
ClearBtn2.Position = UDim2.new(1, -64, 0.5, -15)
ClearBtn2.BackgroundColor3 = Color3.fromRGB(70, 75, 90)
ClearBtn2.Font = Enum.Font.GothamBold
ClearBtn2.Text = getText("ClearBtn")
ClearBtn2.TextColor3 = Color3.fromRGB(255, 255, 255)
ClearBtn2.TextSize = 11
ClearBtn2.Parent = PromptCard
local clrCrn = Instance.new("UICorner")
clrCrn.CornerRadius = UDim.new(0, 6)
clrCrn.Parent = ClearBtn2
table.insert(ElementsToTranslate, {Title = ClearBtn2, TitleKey = "ClearBtn"})

ClearBtn2.MouseButton1Click:Connect(function()
    PromptInput.Text = ""
end)

-- 4. Word List Display (Shortest to Longest)
local WordListContainer = createCard(MainPage, 186, 188)

local WlHeader = Instance.new("TextLabel")
WlHeader.Size = UDim2.new(1, -20, 0, 22)
WlHeader.Position = UDim2.new(0, 12, 0, 6)
WlHeader.BackgroundTransparency = 1
WlHeader.Font = Enum.Font.GothamBold
WlHeader.Text = getText("WordListTitle")
WlHeader.TextColor3 = Color3.fromRGB(52, 152, 219)
WlHeader.TextSize = 12
WlHeader.TextXAlignment = Enum.TextXAlignment.Left
WlHeader.Parent = WordListContainer
table.insert(ElementsToTranslate, {Title = WlHeader, TitleKey = "WordListTitle"})

local WordScroll = Instance.new("ScrollingFrame")
WordScroll.Size = UDim2.new(1, -16, 0, 146)
WordScroll.Position = UDim2.new(0, 8, 0, 32)
WordScroll.BackgroundTransparency = 1
WordScroll.BorderSizePixel = 0
WordScroll.ScrollBarThickness = 5
WordScroll.ScrollBarImageColor3 = Color3.fromRGB(90, 95, 115)
WordScroll.Parent = WordListContainer

local WsLayout = Instance.new("UIGridLayout")
WsLayout.CellSize = UDim2.new(0.485, 0, 0, 32)
WsLayout.CellPadding = UDim2.new(0.02, 0, 0, 6)
WsLayout.Parent = WordScroll

-- Function prototypes
local typeAndSubmitWord
local runDebugScan

-- Function to refresh displayed words in the scroll list
refreshWordList = function(prefix)
    for _, item in ipairs(WordScroll:GetChildren()) do
        if item:IsA("TextButton") then item:Destroy() end
    end
    
    if not prefix or prefix == "" then
        WlHeader.Text = getText("WordListTitle")
        return
    end
    
    local matches = findMatchingWords(prefix)
    local hardMode = isHardModeActive()
    
    if #matches == 0 then
        WlHeader.Text = getText("WordListTitle") .. " " .. getText("NoWordsFound")
        return
    end
    
    WlHeader.Text = getText("WordListTitle") .. string.format(" (%d คำ | %s)", #matches, hardMode and "โหมดยาก >= 5 ตัว" or "โหมดง่าย")
    
    for i = 1, math.min(#matches, 60) do
        local data = matches[i]
        local w = data.Word
        local len = data.Length
        
        local btn = Instance.new("TextButton")
        btn.Name = "WordBtn_" .. i
        btn.BackgroundColor3 = Color3.fromRGB(42, 46, 60)
        btn.Font = Enum.Font.Gotham
        btn.Text = string.format(" %s  %s", getText("WordBadge", len), w)
        btn.TextColor3 = Color3.fromRGB(240, 245, 255)
        btn.TextSize = 12
        btn.TextXAlignment = Enum.TextXAlignment.Left
        btn.Parent = WordScroll
        
        local bCrn = Instance.new("UICorner")
        bCrn.CornerRadius = UDim.new(0, 6)
        bCrn.Parent = btn
        
        local bStrk = Instance.new("UIStroke")
        bStrk.Color = Color3.fromRGB(56, 62, 80)
        bStrk.Thickness = 1
        bStrk.Parent = btn
        
        btn.MouseButton1Click:Connect(function()
            btn.BackgroundColor3 = Color3.fromRGB(46, 204, 113)
            typeAndSubmitWord(w, prefix)
            task.wait(0.3)
            btn.BackgroundColor3 = Color3.fromRGB(42, 46, 60)
        end)
    end
    
    local rows = math.ceil(math.min(#matches, 60) / 2)
    WordScroll.CanvasSize = UDim2.new(0, 0, 0, rows * 38 + 10)
end

PromptInput:GetPropertyChangedSignal("Text"):Connect(function()
    refreshWordList(PromptInput.Text)
end)

-- ==================== TAB 2: LOGS PAGE ====================
local LogControlsCard = createCard(LogsPage, 46, 0)

local CopyLogBtn = Instance.new("TextButton")
CopyLogBtn.Size = UDim2.new(0, 115, 0, 30)
CopyLogBtn.Position = UDim2.new(0, 8, 0.5, -15)
CopyLogBtn.BackgroundColor3 = Color3.fromRGB(52, 152, 219)
CopyLogBtn.Font = Enum.Font.GothamBold
CopyLogBtn.Text = getText("CopyLogBtn")
CopyLogBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
CopyLogBtn.TextSize = 11
CopyLogBtn.Parent = LogControlsCard
local clbCrn = Instance.new("UICorner")
clbCrn.CornerRadius = UDim.new(0, 6)
clbCrn.Parent = CopyLogBtn
table.insert(ElementsToTranslate, {Title = CopyLogBtn, TitleKey = "CopyLogBtn"})

local SaveLogBtn = Instance.new("TextButton")
SaveLogBtn.Size = UDim2.new(0, 115, 0, 30)
SaveLogBtn.Position = UDim2.new(0, 128, 0.5, -15)
SaveLogBtn.BackgroundColor3 = Color3.fromRGB(46, 204, 113)
SaveLogBtn.Font = Enum.Font.GothamBold
SaveLogBtn.Text = getText("SaveLogBtn")
SaveLogBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
SaveLogBtn.TextSize = 11
SaveLogBtn.Parent = LogControlsCard
local slbCrn = Instance.new("UICorner")
slbCrn.CornerRadius = UDim.new(0, 6)
slbCrn.Parent = SaveLogBtn
table.insert(ElementsToTranslate, {Title = SaveLogBtn, TitleKey = "SaveLogBtn"})

local DebugScanBtn = Instance.new("TextButton")
DebugScanBtn.Size = UDim2.new(0, 105, 0, 30)
DebugScanBtn.Position = UDim2.new(0, 248, 0.5, -15)
DebugScanBtn.BackgroundColor3 = Color3.fromRGB(155, 89, 182)
DebugScanBtn.Font = Enum.Font.GothamBold
DebugScanBtn.Text = getText("DebugScanBtn")
DebugScanBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
DebugScanBtn.TextSize = 11
DebugScanBtn.Parent = LogControlsCard
local dsbCrn = Instance.new("UICorner")
dsbCrn.CornerRadius = UDim.new(0, 6)
dsbCrn.Parent = DebugScanBtn
table.insert(ElementsToTranslate, {Title = DebugScanBtn, TitleKey = "DebugScanBtn"})

local ClearLogBtn = Instance.new("TextButton")
ClearLogBtn.Size = UDim2.new(0, 70, 0, 30)
ClearLogBtn.Position = UDim2.new(1, -78, 0.5, -15)
ClearLogBtn.BackgroundColor3 = Color3.fromRGB(231, 76, 60)
ClearLogBtn.Font = Enum.Font.GothamBold
ClearLogBtn.Text = getText("ClearLogBtn")
ClearLogBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
ClearLogBtn.TextSize = 11
ClearLogBtn.Parent = LogControlsCard
local cllbCrn = Instance.new("UICorner")
cllbCrn.CornerRadius = UDim.new(0, 6)
cllbCrn.Parent = ClearLogBtn
table.insert(ElementsToTranslate, {Title = ClearLogBtn, TitleKey = "ClearLogBtn"})

local LogContainer = createCard(LogsPage, 310, 52)
local LogScroll = Instance.new("ScrollingFrame")
LogScroll.Size = UDim2.new(1, -16, 1, -16)
LogScroll.Position = UDim2.new(0, 8, 0, 8)
LogScroll.BackgroundTransparency = 1
LogScroll.BorderSizePixel = 0
LogScroll.ScrollBarThickness = 5
LogScroll.ScrollBarImageColor3 = Color3.fromRGB(90, 95, 115)
LogScroll.Parent = LogContainer

local LsLayout = Instance.new("UIListLayout")
LsLayout.Padding = UDim.new(0, 4)
LsLayout.SortOrder = Enum.SortOrder.LayoutOrder
LsLayout.Parent = LogScroll

-- Logger Helper
addLogEntry = function(msg, color)
    local timestamp = os.date("%H:%M:%S")
    local fullText = string.format("[%s] %s", timestamp, tostring(msg))
    table.insert(ActivityLogs, fullText)
    
    local line = Instance.new("TextLabel")
    line.Size = UDim2.new(1, -10, 0, 20)
    line.BackgroundTransparency = 1
    line.Font = Enum.Font.RobotoMono or Enum.Font.Code
    line.Text = fullText
    line.TextColor3 = color or Color3.fromRGB(220, 225, 240)
    line.TextSize = 11
    line.TextXAlignment = Enum.TextXAlignment.Left
    line.LayoutOrder = #ActivityLogs
    line.Parent = LogScroll
    
    LogScroll.CanvasSize = UDim2.new(0, 0, 0, #ActivityLogs * 24 + 10)
    LogScroll.CanvasPosition = Vector2.new(0, 99999)
end

-- Copy Logs Handler
CopyLogBtn.MouseButton1Click:Connect(function()
    local allLogs = table.concat(ActivityLogs, "\n")
    if setclipboard then
        setclipboard(allLogs)
        CopyLogBtn.Text = getText("LogCopied")
        task.wait(1.5)
        CopyLogBtn.Text = getText("CopyLogBtn")
    elseif toclipboard then
        toclipboard(allLogs)
        CopyLogBtn.Text = getText("LogCopied")
        task.wait(1.5)
        CopyLogBtn.Text = getText("CopyLogBtn")
    else
        CopyLogBtn.Text = "N/A"
        task.wait(1.5)
        CopyLogBtn.Text = getText("CopyLogBtn")
    end
end)

-- Save Logs to File Handler
SaveLogBtn.MouseButton1Click:Connect(function()
    local allLogs = table.concat(ActivityLogs, "\n")
    if writefile then
        local filename = string.format("word_chain_log_%s.txt", os.date("%Y-%m-%d_%H-%M-%S"))
        pcall(function() writefile(filename, allLogs) end)
        SaveLogBtn.Text = getText("LogSaved")
        task.wait(1.5)
        SaveLogBtn.Text = getText("SaveLogBtn")
    else
        SaveLogBtn.Text = "N/A"
        task.wait(1.5)
        SaveLogBtn.Text = getText("SaveLogBtn")
    end
end)

-- Clear Logs Handler
ClearLogBtn.MouseButton1Click:Connect(function()
    table.clear(ActivityLogs)
    for _, item in ipairs(LogScroll:GetChildren()) do
        if item:IsA("TextLabel") then item:Destroy() end
    end
    LogScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    addLogEntry("Log cleared.", Color3.fromRGB(150, 150, 150))
end)

-- Debug Scan Button Handler
DebugScanBtn.MouseButton1Click:Connect(function()
    if runDebugScan then
        runDebugScan()
    end
end)

-- Initial Log Entry
addLogEntry("Script initialized v6.1. Ready to play Thai Word Chain.", Color3.fromRGB(46, 204, 113))

-- ==================== TAB 3: SETTINGS PAGE ====================
local SettingsScroll = Instance.new("ScrollingFrame")
SettingsScroll.Size = UDim2.new(1, 0, 1, 0)
SettingsScroll.BackgroundTransparency = 1
SettingsScroll.BorderSizePixel = 0
SettingsScroll.ScrollBarThickness = 4
SettingsScroll.Parent = SettingsPage

local SList = Instance.new("UIListLayout")
SList.Padding = UDim.new(0, 10)
SList.Parent = SettingsScroll

-- Language Switcher Card
local LangCard = createCard(SettingsScroll, 54)
local LangLabel = Instance.new("TextLabel")
LangLabel.Size = UDim2.new(1, -130, 1, 0)
LangLabel.Position = UDim2.new(0, 14, 0, 0)
LangLabel.BackgroundTransparency = 1
LangLabel.Font = Enum.Font.GothamBold
LangLabel.Text = getText("LangTitle")
LangLabel.TextColor3 = Color3.fromRGB(240, 240, 245)
LangLabel.TextSize = 12
LangLabel.TextXAlignment = Enum.TextXAlignment.Left
LangLabel.Parent = LangCard
table.insert(ElementsToTranslate, {Title = LangLabel, TitleKey = "LangTitle"})

local LangToggleBtn = Instance.new("TextButton")
LangToggleBtn.Size = UDim2.new(0, 100, 0, 32)
LangToggleBtn.Position = UDim2.new(1, -114, 0.5, -16)
LangToggleBtn.BackgroundColor3 = Color3.fromRGB(230, 126, 34)
LangToggleBtn.Font = Enum.Font.GothamBold
LangToggleBtn.Text = (Config.Language == "TH") and "🇹🇭 ภาษาไทย" or "🇺🇸 English"
LangToggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
LangToggleBtn.TextSize = 12
LangToggleBtn.Parent = LangCard
local ltCrn = Instance.new("UICorner")
ltCrn.CornerRadius = UDim.new(0, 6)
ltCrn.Parent = LangToggleBtn

-- Delay 1: Before Typing
local DelayBeforeCard = createCard(SettingsScroll, 54)
local DbLabel = Instance.new("TextLabel")
DbLabel.Size = UDim2.new(1, -110, 1, 0)
DbLabel.Position = UDim2.new(0, 14, 0, 0)
DbLabel.BackgroundTransparency = 1
DbLabel.Font = Enum.Font.GothamBold
DbLabel.Text = getText("DelayBeforeTitle")
DbLabel.TextColor3 = Color3.fromRGB(240, 240, 245)
DbLabel.TextSize = 12
DbLabel.TextXAlignment = Enum.TextXAlignment.Left
DbLabel.Parent = DelayBeforeCard
table.insert(ElementsToTranslate, {Title = DbLabel, TitleKey = "DelayBeforeTitle"})

local DbInput = Instance.new("TextBox")
DbInput.Size = UDim2.new(0, 80, 0, 32)
DbInput.Position = UDim2.new(1, -94, 0.5, -16)
DbInput.BackgroundColor3 = Color3.fromRGB(20, 22, 28)
DbInput.Font = Enum.Font.GothamBold
DbInput.Text = tostring(Config.DelayBeforeTyping)
DbInput.TextColor3 = Color3.fromRGB(46, 204, 113)
DbInput.TextSize = 13
DbInput.Parent = DelayBeforeCard
local dbCrn = Instance.new("UICorner")
dbCrn.CornerRadius = UDim.new(0, 6)
dbCrn.Parent = DbInput

DbInput.FocusLost:Connect(function()
    local val = tonumber(DbInput.Text)
    if val and val >= 0 then
        Config.DelayBeforeTyping = val
        addLogEntry("Updated DelayBeforeTyping to " .. val .. "s", Color3.fromRGB(200, 200, 200))
    else
        DbInput.Text = tostring(Config.DelayBeforeTyping)
    end
end)

-- Delay 2: Per Character Typing
local DelayPerCharCard = createCard(SettingsScroll, 54)
local DpcLabel = Instance.new("TextLabel")
DpcLabel.Size = UDim2.new(1, -110, 1, 0)
DpcLabel.Position = UDim2.new(0, 14, 0, 0)
DpcLabel.BackgroundTransparency = 1
DpcLabel.Font = Enum.Font.GothamBold
DpcLabel.Text = getText("DelayPerCharTitle")
DpcLabel.TextColor3 = Color3.fromRGB(240, 240, 245)
DpcLabel.TextSize = 12
DpcLabel.TextXAlignment = Enum.TextXAlignment.Left
DpcLabel.Parent = DelayPerCharCard
table.insert(ElementsToTranslate, {Title = DpcLabel, TitleKey = "DelayPerCharTitle"})

local DpcInput = Instance.new("TextBox")
DpcInput.Size = UDim2.new(0, 80, 0, 32)
DpcInput.Position = UDim2.new(1, -94, 0.5, -16)
DpcInput.BackgroundColor3 = Color3.fromRGB(20, 22, 28)
DpcInput.Font = Enum.Font.GothamBold
DpcInput.Text = tostring(Config.DelayPerChar)
DpcInput.TextColor3 = Color3.fromRGB(46, 204, 113)
DpcInput.TextSize = 13
DpcInput.Parent = DelayPerCharCard
local dpcCrn = Instance.new("UICorner")
dpcCrn.CornerRadius = UDim.new(0, 6)
dpcCrn.Parent = DpcInput

DpcInput.FocusLost:Connect(function()
    local val = tonumber(DpcInput.Text)
    if val and val >= 0.01 then
        Config.DelayPerChar = val
        addLogEntry("Updated DelayPerChar to " .. val .. "s", Color3.fromRGB(200, 200, 200))
    else
        DpcInput.Text = tostring(Config.DelayPerChar)
    end
end)

-- Max Retries Per Turn
local MaxRetriesCard = createCard(SettingsScroll, 54)
local MrLabel = Instance.new("TextLabel")
MrLabel.Size = UDim2.new(1, -110, 1, 0)
MrLabel.Position = UDim2.new(0, 14, 0, 0)
MrLabel.BackgroundTransparency = 1
MrLabel.Font = Enum.Font.GothamBold
MrLabel.Text = getText("MaxRetriesTitle")
MrLabel.TextColor3 = Color3.fromRGB(240, 240, 245)
MrLabel.TextSize = 12
MrLabel.TextXAlignment = Enum.TextXAlignment.Left
MrLabel.Parent = MaxRetriesCard
table.insert(ElementsToTranslate, {Title = MrLabel, TitleKey = "MaxRetriesTitle"})

local MrInput = Instance.new("TextBox")
MrInput.Size = UDim2.new(0, 80, 0, 32)
MrInput.Position = UDim2.new(1, -94, 0.5, -16)
MrInput.BackgroundColor3 = Color3.fromRGB(20, 22, 28)
MrInput.Font = Enum.Font.GothamBold
MrInput.Text = tostring(Config.MaxRetriesPerTurn)
MrInput.TextColor3 = Color3.fromRGB(46, 204, 113)
MrInput.TextSize = 13
MrInput.Parent = MaxRetriesCard
local mrCrn = Instance.new("UICorner")
mrCrn.CornerRadius = UDim.new(0, 6)
mrCrn.Parent = MrInput

MrInput.FocusLost:Connect(function()
    local val = tonumber(MrInput.Text)
    if val and val >= 1 then
        Config.MaxRetriesPerTurn = math.floor(val)
        addLogEntry("Updated MaxRetriesPerTurn to " .. Config.MaxRetriesPerTurn, Color3.fromRGB(200, 200, 200))
    else
        MrInput.Text = tostring(Config.MaxRetriesPerTurn)
    end
end)

-- Reset Blacklist Button Card
local ResetBlacklistCard = createCard(SettingsScroll, 48)
local ResetBlacklistBtn = Instance.new("TextButton")
ResetBlacklistBtn.Size = UDim2.new(1, -20, 1, -12)
ResetBlacklistBtn.Position = UDim2.new(0, 10, 0, 6)
ResetBlacklistBtn.BackgroundColor3 = Color3.fromRGB(142, 68, 173)
ResetBlacklistBtn.Font = Enum.Font.GothamBold
ResetBlacklistBtn.Text = getText("ResetBlacklistBtn", getTableCount(PermanentBlacklist))
ResetBlacklistBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
ResetBlacklistBtn.TextSize = 12
ResetBlacklistBtn.Parent = ResetBlacklistCard
local rbbCrn = Instance.new("UICorner")
rbbCrn.CornerRadius = UDim.new(0, 6)
rbbCrn.Parent = ResetBlacklistBtn

ResetBlacklistBtn.MouseButton1Click:Connect(function()
    local count = getTableCount(PermanentBlacklist)
    table.clear(PermanentBlacklist)
    table.clear(RejectedWords)
    table.clear(UsedWords)
    table.clear(triedThisRound)
    populateInitialWords()
    ResetBlacklistBtn.Text = "ล้าง Blacklist เรียบร้อย!"
    addLogEntry(string.format("Cleared Blacklist & Used Words (%d words reset).", count), Color3.fromRGB(155, 89, 182))
    task.wait(1.5)
    ResetBlacklistBtn.Text = getText("ResetBlacklistBtn", getTableCount(PermanentBlacklist))
end)

-- Database Info Card
local DbInfoCard = createCard(SettingsScroll, 50)
local DbInfoLabel = Instance.new("TextLabel")
DbInfoLabel.Size = UDim2.new(1, -20, 1, 0)
DbInfoLabel.Position = UDim2.new(0, 14, 0, 0)
DbInfoLabel.BackgroundTransparency = 1
DbInfoLabel.Font = Enum.Font.GothamBold
DbInfoLabel.Text = getText("DictStatus", WordCount)
DbInfoLabel.TextColor3 = Color3.fromRGB(46, 204, 113)
DbInfoLabel.TextSize = 12
DbInfoLabel.TextXAlignment = Enum.TextXAlignment.Left
DbInfoLabel.Parent = DbInfoCard

-- Event Hook Status Card
local EventInfoCard = createCard(SettingsScroll, 50)
local EventInfoLabel = Instance.new("TextLabel")
EventInfoLabel.Size = UDim2.new(1, -20, 1, 0)
EventInfoLabel.Position = UDim2.new(0, 14, 0, 0)
EventInfoLabel.BackgroundTransparency = 1
EventInfoLabel.Font = Enum.Font.GothamBold
EventInfoLabel.Text = getText("EventDrivenStatus", "กำลังค้นหา...")
EventInfoLabel.TextColor3 = Color3.fromRGB(52, 152, 219)
EventInfoLabel.TextSize = 12
EventInfoLabel.TextXAlignment = Enum.TextXAlignment.Left
EventInfoLabel.Parent = EventInfoCard

-- Unload Button
local UnloadCard = createCard(SettingsScroll, 48)
local UnloadBtn = Instance.new("TextButton")
UnloadBtn.Size = UDim2.new(1, -20, 1, -12)
UnloadBtn.Position = UDim2.new(0, 10, 0, 6)
UnloadBtn.BackgroundColor3 = Color3.fromRGB(192, 57, 43)
UnloadBtn.Font = Enum.Font.GothamBold
UnloadBtn.Text = getText("UnloadBtn")
UnloadBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
UnloadBtn.TextSize = 12
UnloadBtn.Parent = UnloadCard
local unldCrn = Instance.new("UICorner")
unldCrn.CornerRadius = UDim.new(0, 6)
unldCrn.Parent = UnloadBtn
table.insert(ElementsToTranslate, {Title = UnloadBtn, TitleKey = "UnloadBtn"})

UnloadBtn.MouseButton1Click:Connect(function()
    ScreenGui:Destroy()
end)

-- Language Switcher Function
local function updateLanguage(newLang)
    Config.Language = newLang
    TitleLabel.Text = getText("Title")
    LangToggleBtn.Text = (newLang == "TH") and "🇹🇭 ภาษาไทย" or "🇺🇸 English"
    
    for tName, tData in pairs(TabButtons) do
        tData.Btn.Text = getText(tData.Key)
    end
    
    for _, elem in ipairs(ElementsToTranslate) do
        if elem.Title and elem.TitleKey then
            elem.Title.Text = getText(elem.TitleKey)
        end
    end
    
    updateModePillButtons()
    TurnBadge.Text = getText(TurnStatusText)
    PromptInput.PlaceholderText = getText("PromptPlaceholder")
    DbInfoLabel.Text = getText("DictStatus", WordCount)
    EventInfoLabel.Text = getText("EventDrivenStatus", useEventDriven and "เชื่อมต่อแล้ว ✅" or "ไม่พบ (ใช้ UI Polling)")
    ResetBlacklistBtn.Text = getText("ResetBlacklistBtn", getTableCount(PermanentBlacklist))
    refreshWordList(PromptInput.Text)
end

LangToggleBtn.MouseButton1Click:Connect(function()
    local nextLang = (Config.Language == "TH") and "ENG" or "TH"
    updateLanguage(nextLang)
end)

-- ==================== SMART DETECTION FUNCTIONS (V6.1) ====================

local function isGuiVisible(gui)
    if not gui or not gui:IsA("GuiObject") then return false end
    if not gui.Visible then return false end
    if gui.AbsoluteSize.X <= 0 or gui.AbsoluteSize.Y <= 0 then return false end
    local curr = gui.Parent
    while curr and curr:IsA("GuiObject") do
        if not curr.Visible then return false end
        curr = curr.Parent
    end
    return true
end

local function findGameTextBox()
    local pGui = LocalPlayer:FindFirstChild("PlayerGui")
    if not pGui then return nil end
    
    for _, desc in ipairs(pGui:GetDescendants()) do
        if desc:IsA("TextBox") and not desc:IsDescendantOf(ScreenGui) then
            local fName = desc:GetFullName()
            if not string.find(fName, "Chat") 
               and not string.find(string.lower(desc.Name), "search") 
               and not string.find(string.lower(desc.Name), "code") 
               and not string.find(string.lower(desc.Name), "filter") then
                if isGuiVisible(desc) then
                    return desc
                end
            end
        end
    end
    return nil
end

-- V6.1 Sticky / Latched Table Mode Detection
local function detectTableMode()
    -- 1. Manual Overrides strictly take top priority
    if ManualModeOverride == "Hard" then return "Hard" end
    if ManualModeOverride == "Easy" then return "Easy" end
    
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChild("Humanoid")
    local isSitting = hum and (hum.Sit or hum.SeatPart ~= nil)
    
    local function checkTextForHard(text)
        if not text then return false end
        return string.find(text, "5") or string.find(text, "ยาก") or string.find(text, "Hard") or string.find(text, "๕")
    end
    
    local function checkTextForEasy(text)
        if not text then return false end
        return string.find(text, "ง่าย") or string.find(text, "Easy")
    end
    
    -- 2. Inspect SeatPart and all parent models/containers up to workspace
    if hum and hum.SeatPart then
        local current = hum.SeatPart
        while current and current ~= workspace do
            -- Check name
            if checkTextForHard(current.Name) then
                LatchedTableMode = "Hard"
                return "Hard"
            end
            -- Check attributes
            for k, v in pairs(current:GetAttributes()) do
                if checkTextForHard(tostring(k)) or checkTextForHard(tostring(v)) then
                    LatchedTableMode = "Hard"
                    return "Hard"
                end
            end
            -- Check child Value objects
            for _, child in ipairs(current:GetChildren()) do
                if child:IsA("StringValue") or child:IsA("IntValue") or child:IsA("BoolValue") then
                    if checkTextForHard(child.Name) or checkTextForHard(tostring(child.Value)) then
                        LatchedTableMode = "Hard"
                        return "Hard"
                    end
                elseif child:IsA("BillboardGui") or child:IsA("SurfaceGui") then
                    for _, label in ipairs(child:GetDescendants()) do
                        if label:IsA("TextLabel") and checkTextForHard(label.Text) then
                            LatchedTableMode = "Hard"
                            return "Hard"
                        end
                    end
                end
            end
            current = current.Parent
        end
    end
    
    -- 3. Check PlayerGui for Table Mode indicators
    local pGui = LocalPlayer:FindFirstChild("PlayerGui")
    if pGui then
        for _, desc in ipairs(pGui:GetDescendants()) do
            if desc:IsA("TextLabel") and isGuiVisible(desc) and not desc:IsDescendantOf(ScreenGui) then
                local txt = desc.Text
                if txt and txt ~= "" then
                    if checkTextForHard(txt) and (string.find(txt, "โหมด") or string.find(txt, "ขั้นต่ำ") or string.find(txt, "ตัว") or string.find(txt, "mode") or string.find(txt, "โต๊ะ")) then
                        LatchedTableMode = "Hard"
                        return "Hard"
                    end
                end
            end
        end
    end
    
    -- 4. Sticky Latch: If previously detected Hard while sitting, KEEP IT HARD!
    if isSitting and LatchedTableMode == "Hard" then
        return "Hard"
    end
    
    -- 5. If player stands up / leaves table, clear the latch
    if not isSitting then
        LatchedTableMode = nil
    end
    
    return "Easy"
end

local function getGameTurnState()
    if ManualTurnOverride == "OurTurn" then
        local box = findGameTextBox()
        return "OurTurn", box
    elseif ManualTurnOverride == "OpponentTurn" then
        return "OpponentTurn", nil
    end
    
    -- V6.0: Check Player Attribute first (most reliable if game sets it)
    local isTurnAttr = pcall(function() return LocalPlayer:GetAttribute("IsTurn") end)
    if isTurnAttr == true then
        local attrVal = LocalPlayer:GetAttribute("IsTurn")
        if attrVal == true then
            return "OurTurn", findGameTextBox()
        elseif attrVal == false then
            return "OpponentTurn", nil
        end
    end
    
    local pGui = LocalPlayer:FindFirstChild("PlayerGui")
    if not pGui then
        return "NotSeated", nil
    end
    
    local gameBox = findGameTextBox()
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChild("Humanoid")
    local isSitting = hum and (hum.Sit or hum.SeatPart ~= nil)
    
    if not gameBox and not isSitting then
        return "NotSeated", nil
    end
    
    if ServerTurnState == "OurTurn" then
        return "OurTurn", gameBox
    elseif ServerTurnState == "OpponentTurn" then
        return "OpponentTurn", nil
    end
    
    local ourTurnDetected = false
    local opponentTurnDetected = false
    
    for _, desc in ipairs(pGui:GetDescendants()) do
        if desc:IsA("TextLabel") and isGuiVisible(desc) and not desc:IsDescendantOf(ScreenGui) then
            local txt = desc.Text
            if txt and txt ~= "" then
                if string.find(txt, "ตาคุณ") or string.find(txt, "ถึงตาคุณ") or string.find(txt, "ตาของคุณ") or string.find(txt, "รอบคุณ") then
                    ourTurnDetected = true
                elseif string.find(txt, "ตาคู่แข่ง") or string.find(txt, "รอคู่แข่ง") or string.find(txt, "รอตา") or string.find(txt, "ตาศัตรู") or string.find(txt, "รอผู้เล่น") then
                    opponentTurnDetected = true
                elseif string.find(string.lower(txt), "your turn") or string.find(string.lower(txt), "my turn") then
                    ourTurnDetected = true
                elseif string.find(string.lower(txt), "opponent") or string.find(string.lower(txt), "waiting for") then
                    opponentTurnDetected = true
                end
            end
        end
    end
    
    if ourTurnDetected then
        return "OurTurn", gameBox
    elseif opponentTurnDetected then
        return "OpponentTurn", nil
    end
    
    if gameBox then
        local ph = string.lower(gameBox.PlaceholderText or "")
        if string.find(ph, "รอ") or string.find(ph, "wait") then
            return "OpponentTurn", nil
        end
        if gameBox.TextEditable and gameBox.Active then
            return "OurTurn", gameBox
        else
            return "OpponentTurn", nil
        end
    end
    
    return "OpponentTurn", nil
end

local function extractCurrentPrompt(activeBox)
    if activeBox and activeBox.Parent then
        local boxText = activeBox.Text
        if boxText and boxText ~= "" then
            local clean = extractThaiOnly(boxText)
            local cLen = getThaiCharCount(clean)
            if cLen >= 1 and cLen <= 4 and not IgnoredUIWords[clean] then
                return clean
            end
        end
        
        for _, sib in ipairs(activeBox.Parent:GetChildren()) do
            if sib:IsA("TextLabel") and isGuiVisible(sib) then
                local clean = extractThaiOnly(sib.Text)
                local cLen = getThaiCharCount(clean)
                if cLen >= 1 and cLen <= 4 and not IgnoredUIWords[clean] then
                    return clean
                end
            end
        end
    end
    
    local pGui = LocalPlayer:FindFirstChild("PlayerGui")
    if pGui then
        for _, desc in ipairs(pGui:GetDescendants()) do
            if desc:IsA("TextLabel") and isGuiVisible(desc) and not desc:IsDescendantOf(ScreenGui) then
                local fName = desc:GetFullName()
                if not string.find(fName, "Chat") and not string.find(fName, "PlayerList") then
                    local clean = extractThaiOnly(desc.Text)
                    local cLen = getThaiCharCount(clean)
                    if cLen >= 1 and cLen <= 3 and not IgnoredUIWords[clean] then
                        return clean
                    end
                end
            end
        end
    end
    
    return nil
end

runDebugScan = function()
    addLogEntry("========== [UI & TURN DIAGNOSTIC SCAN v6.1] ==========", Color3.fromRGB(241, 196, 15))
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChild("Humanoid")
    
    addLogEntry(string.format("Player: %s (@%s)", LocalPlayer.DisplayName, LocalPlayer.Name), Color3.fromRGB(200, 200, 200))
    addLogEntry(string.format("Humanoid Sit: %s | SeatPart: %s", tostring(hum and hum.Sit), tostring(hum and hum.SeatPart)), Color3.fromRGB(200, 200, 200))
    addLogEntry(string.format("Permanent Blacklist Size: %d words", getTableCount(PermanentBlacklist)), Color3.fromRGB(155, 89, 182))
    addLogEntry(string.format("Mode: %s (Override: %s, Latched: %s)", Config.DetectedMode, ManualModeOverride, tostring(LatchedTableMode)), Color3.fromRGB(231, 76, 60))
    addLogEntry(string.format("Event-Driven Mode: %s | roundToken: %d | retries: %d", tostring(useEventDriven), roundToken, retriesThisTurn), Color3.fromRGB(52, 152, 219))
    
    -- Check Player Attributes
    local isTurnAttr = pcall(function() return LocalPlayer:GetAttribute("IsTurn") end)
    local inGameAttr = pcall(function() return LocalPlayer:GetAttribute("InGame") end)
    addLogEntry(string.format("Player IsTurn attr: %s | InGame attr: %s", tostring(LocalPlayer:GetAttribute("IsTurn")), tostring(LocalPlayer:GetAttribute("InGame"))), Color3.fromRGB(200, 200, 200))
    
    local pGui = LocalPlayer:FindFirstChild("PlayerGui")
    local allDumpLines = {}
    table.insert(allDumpLines, string.format("UI Dump for %s at %s", LocalPlayer.Name, os.date("%Y-%m-%d %H:%M:%S")))
    
    if pGui then
        local gBox = findGameTextBox()
        if gBox then
            addLogEntry(string.format("Game TextBox: '%s' (Editable: %s)", gBox.Name, tostring(gBox.TextEditable)), Color3.fromRGB(46, 204, 113))
            addLogEntry(string.format("   Text: '%s' | Ph: '%s'", gBox.Text, gBox.PlaceholderText), Color3.fromRGB(46, 204, 113))
            table.insert(allDumpLines, string.format("Game TextBox: %s (Editable=%s, Text='%s', Ph='%s')", gBox:GetFullName(), tostring(gBox.TextEditable), gBox.Text, gBox.PlaceholderText))
        else
            addLogEntry("Game TextBox: NOT FOUND (Searching...)", Color3.fromRGB(231, 76, 60))
            table.insert(allDumpLines, "Game TextBox: NOT FOUND")
        end
        
        local labelCount = 0
        for _, desc in ipairs(pGui:GetDescendants()) do
            if not desc:IsDescendantOf(ScreenGui) then
                if desc:IsA("TextLabel") and isGuiVisible(desc) and desc.Text and desc.Text ~= "" then
                    labelCount = labelCount + 1
                    if labelCount <= 10 then
                        addLogEntry(string.format("Label [%s]: '%s'", desc.Name, desc.Text), Color3.fromRGB(52, 152, 219))
                    end
                    table.insert(allDumpLines, string.format("Label [%s]: '%s' (Parent=%s)", desc.Name, desc.Text, desc.Parent and desc.Parent.Name or "nil"))
                end
            end
        end
        addLogEntry(string.format("Total visible labels found: %d", labelCount), Color3.fromRGB(150, 150, 150))
    end
    
    local turnState, _ = getGameTurnState()
    addLogEntry(string.format("Current Detected Turn: %s (Override: %s)", turnState, ManualTurnOverride), Color3.fromRGB(255, 215, 0))
    addLogEntry("===============================================", Color3.fromRGB(241, 196, 15))
    
    if writefile then
        pcall(function()
            writefile("word_chain_ui_dump.txt", table.concat(allDumpLines, "\n"))
        end)
    end
end

-- ==================== V6.0: BACKSPACE HELPER (clear typed suffix) ====================

local function sendBackspaces(count, token)
    if count <= 0 then return end
    
    if gameEventModule and rawget(gameEventModule, "fire") then
        for i = 1, count do
            if token ~= roundToken then return end
            pcall(function()
                gameEventModule.fire("tryKeystroke", -1)
            end)
            task.wait(0.04)
        end
        return
    end
    
    if TypingRemote then
        pcall(function()
            TypingRemote:FireServer(CurrentPrompt)
        end)
    end
    
    local box = findGameTextBox()
    if box and box.Parent then
        pcall(function()
            box.Text = CurrentPrompt
        end)
    end
end

-- ==================== Connect Server Remotes Listeners ====================
if Remotes then
    local matchEv = Remotes:FindFirstChild("Match")
    if matchEv and matchEv:IsA("RemoteEvent") then
        matchEv.OnClientEvent:Connect(function(...)
            local args = {...}
            for i, a in ipairs(args) do
                local s = tostring(a)
                if a == LocalPlayer or s == LocalPlayer.Name or s == LocalPlayer.DisplayName or s == tostring(LocalPlayer.UserId) then
                    ServerTurnState = "OurTurn"
                    addLogEntry("📡 Server Match: It is OUR turn!", Color3.fromRGB(46, 204, 113))
                elseif type(a) == "userdata" and typeof and typeof(a) == "Instance" and a:IsA("Player") and a ~= LocalPlayer then
                    ServerTurnState = "OpponentTurn"
                    addLogEntry(string.format("📡 Server Match: Turn for %s", a.Name), Color3.fromRGB(180, 185, 200))
                end
                
                -- Check if server passes mode information
                if type(a) == "table" then
                    for k, v in pairs(a) do
                        local kvStr = string.lower(tostring(k) .. "=" .. tostring(v))
                        if string.find(kvStr, "hard") or string.find(kvStr, "ยาก") or string.find(kvStr, "5") then
                            LatchedTableMode = "Hard"
                            Config.DetectedMode = "Hard"
                            updateModePillButtons()
                        end
                    end
                end
            end
        end)
    end
    
    local notif = Remotes:FindFirstChild("Notify")
    if notif and notif:IsA("RemoteEvent") then
        notif.OnClientEvent:Connect(function(msg, ...)
            if msg then
                local msgStr = tostring(msg)
                addLogEntry("Server: " .. msgStr, Color3.fromRGB(243, 156, 18))
                
                -- Detect hard mode notification from server
                if string.find(msgStr, "ยาก") or string.find(msgStr, "5 ตัว") or string.find(msgStr, "ขั้นต่ำ 5") then
                    LatchedTableMode = "Hard"
                    Config.DetectedMode = "Hard"
                    updateModePillButtons()
                end
                
                -- Auto-blacklist word if server rejects it
                if string.find(msgStr, "ไม่มี") or string.find(msgStr, "ใช้ไปแล้ว") or string.find(msgStr, "ผิด") or string.find(msgStr, "สั้น") then
                    if lastSubmittedWord and lastSubmittedWord ~= "" then
                        blacklistRejectedWord(lastSubmittedWord)
                        addLogEntry(string.format("⛔ Blacklisted '%s' via Server Notify.", lastSubmittedWord), Color3.fromRGB(231, 76, 60))
                        
                        -- V6.0: Auto-backspace and retry
                        if Config.AutoAnswer and not isTypingOrSubmitting then
                            local token = roundToken
                            retriesThisTurn = retriesThisTurn + 1
                            
                            if retriesThisTurn <= Config.MaxRetriesPerTurn then
                                task.spawn(function()
                                    sendBackspaces(pendingSuffix, token)
                                    task.wait(0.15)
                                    if token ~= roundToken then return end
                                    
                                    local matches = findMatchingWords(CurrentPrompt)
                                    refreshWordList(CurrentPrompt)
                                    if #matches > 0 then
                                        local candidate = matches[1].Word
                                        addLogEntry(string.format("🔄 Retry #%d: Trying '%s'...", retriesThisTurn, candidate), Color3.fromRGB(230, 126, 34))
                                        typeAndSubmitWord(candidate, CurrentPrompt, nil, token)
                                    else
                                        addLogEntry(string.format("⚠️ No words left for '%s' after %d retries", CurrentPrompt, retriesThisTurn), Color3.fromRGB(230, 126, 34))
                                    end
                                end)
                            else
                                addLogEntry(string.format("🚫 Max retries (%d) reached for this turn.", Config.MaxRetriesPerTurn), Color3.fromRGB(231, 76, 60))
                            end
                        end
                    end
                end
                
                -- Detect word accepted
                if string.find(msgStr, "ถูกต้อง") or string.find(msgStr, "correct") or string.find(msgStr, "สำเร็จ") then
                    if lastSubmittedWord and lastSubmittedWord ~= "" then
                        markWordUsed(lastSubmittedWord)
                        addLogEntry(string.format("✅ Word '%s' accepted via Server Notify!", lastSubmittedWord), Color3.fromRGB(46, 204, 113))
                        roundToken = roundToken + 1
                        pendingWord = nil
                        pendingSuffix = 0
                        retriesThisTurn = 0
                        triedThisRound = {}
                    end
                end
            end
        end)
    end
end

-- ==================== V6.1: KEYSTROKE TYPING & SUBMISSION ====================

typeAndSubmitWord = function(word, prefix, targetTextBox, token)
    if not word or word == "" then return false end
    if not SubmitRemote then
        addLogEntry("Error: SubmitRemote not found!", Color3.fromRGB(231, 76, 60))
        return false
    end
    
    -- V6.1 HARD MODE IMPASSABLE GUARD: Never type or submit < 5 base letters in Hard Mode!
    local hardMode = isHardModeActive()
    local baseCount = getThaiBaseCharCount(word)
    local totalCount = getThaiCharCount(word)
    
    if hardMode and (baseCount < 5 or totalCount < 5) then
        addLogEntry(string.format("⛔ Refused '%s' (%d base chars): Hard Mode requires 5+ characters!", word, baseCount), Color3.fromRGB(231, 76, 60))
        return false
    end
    
    token = token or roundToken
    
    -- Abort if round already changed
    if token ~= roundToken then
        addLogEntry("⏹️ Aborted: round changed before typing.", Color3.fromRGB(180, 185, 200))
        return false
    end
    
    isTypingOrSubmitting = true
    lastSubmittedWord = word
    pendingWord = word
    triedThisRound[word] = true
    addLogEntry(string.format("Typing word '%s' (%d base / %d total chars)...", word, baseCount, totalCount), Color3.fromRGB(52, 152, 219))
    
    -- 1. Delay before typing starts
    if Config.DelayBeforeTyping > 0 then
        local waited = 0
        while waited < Config.DelayBeforeTyping do
            if token ~= roundToken then
                isTypingOrSubmitting = false
                addLogEntry("⏹️ Round changed during pre-type delay.", Color3.fromRGB(180, 185, 200))
                return false
            end
            task.wait(0.05)
            waited = waited + 0.05
        end
    end
    
    -- Check if turn is still ours (and token still valid)
    if token ~= roundToken then
        isTypingOrSubmitting = false
        addLogEntry("⏹️ Round changed, aborting.", Color3.fromRGB(180, 185, 200))
        return false
    end
    
    local currentTurnState, currentBox = getGameTurnState()
    if currentTurnState ~= "OurTurn" and ManualTurnOverride ~= "OurTurn" then
        isTypingOrSubmitting = false
        addLogEntry("Turn expired before typing began.", Color3.fromRGB(231, 76, 60))
        return false
    end
    targetTextBox = currentBox or targetTextBox or findGameTextBox()
    
    -- 2. Determine suffix to type (Never duplicate starting letters!)
    local suffix = ""
    if prefix and prefix ~= "" and string.sub(word, 1, #prefix) == prefix then
        suffix = string.sub(word, #prefix + 1)
    else
        suffix = word
        prefix = ""
    end
    
    pendingSuffix = getThaiCharCount(suffix)
    
    if targetTextBox and targetTextBox.Parent then
        pcall(function() targetTextBox.Text = prefix end)
    end
    
    -- 3. Simulate typing suffix only, checking roundToken at each character
    local currentText = prefix
    local suffixChars = utf8Chars(suffix)
    
    if Config.SimulateTyping then
        for idx, ch in ipairs(suffixChars) do
            if token ~= roundToken then
                isTypingOrSubmitting = false
                addLogEntry("⏹️ Round changed mid-typing, aborted.", Color3.fromRGB(180, 185, 200))
                return false
            end
            
            local stateNow = getGameTurnState()
            if stateNow ~= "OurTurn" and ManualTurnOverride ~= "OurTurn" then
                isTypingOrSubmitting = false
                return false
            end
            
            currentText = currentText .. ch
            
            if targetTextBox and targetTextBox.Parent then
                pcall(function() targetTextBox.Text = currentText end)
            end
            
            if gameEventModule and rawget(gameEventModule, "fire") then
                pcall(function()
                    gameEventModule.fire("tryKeystroke", ch)
                end)
            elseif TypingRemote then
                pcall(function() TypingRemote:FireServer(currentText) end)
            end
            
            task.wait(Config.DelayPerChar or 0.08)
        end
        
        if token ~= roundToken then
            isTypingOrSubmitting = false
            return false
        end
        
        task.wait(0.12)
        if TypingRemote then
            pcall(function() TypingRemote:FireServer(word .. "\r") end)
        end
    else
        -- Instant mode
        if token ~= roundToken then
            isTypingOrSubmitting = false
            return false
        end
        
        if targetTextBox and targetTextBox.Parent then
            pcall(function() targetTextBox.Text = word end)
        end
        if TypingRemote then
            pcall(function() TypingRemote:FireServer(word) end)
            task.wait(0.05)
            pcall(function() TypingRemote:FireServer(word .. "\r") end)
        end
    end
    
    -- 4. Final roundToken check before submit
    if token ~= roundToken then
        isTypingOrSubmitting = false
        return false
    end
    
    -- 5. Submit word to Server
    if gameEventModule and rawget(gameEventModule, "fire") then
        pcall(function()
            gameEventModule.fire("tryAnswer")
        end)
    end
    pcall(function()
        SubmitRemote:FireServer(word)
    end)
    addLogEntry(string.format("Submitted '%s' ➔ Pressed Enter", word), Color3.fromRGB(241, 196, 15))
    
    if targetTextBox and targetTextBox.Parent then
        pcall(function() targetTextBox:ReleaseFocus(true) end)
    end
    
    isTypingOrSubmitting = false
    return true
end

-- ==================== V6.0: EVENT-DRIVEN HOOKS (getgc) ====================

task.spawn(function()
    gameEventModule = discoverGameEventModule()
    
    if gameEventModule then
        useEventDriven = true
        addLogEntry("🔗 Event Module found via getgc()! Using event-driven mode.", Color3.fromRGB(46, 204, 113))
        EventInfoLabel.Text = getText("EventDrivenStatus", "เชื่อมต่อแล้ว ✅")
        EventInfoLabel.TextColor3 = Color3.fromRGB(46, 204, 113)
        
        -- Hook: updateRound
        pcall(function()
            local conn = gameEventModule.remoteConnect("updateRound", function(prompt, _, turnPlr)
                roundToken = roundToken + 1
                triedThisRound = {}
                retriesThisTurn = 0
                pendingWord = nil
                pendingSuffix = 0
                
                -- Re-verify table mode on each round
                local currentTableMode = detectTableMode()
                if currentTableMode ~= Config.DetectedMode then
                    Config.DetectedMode = currentTableMode
                    updateModePillButtons()
                end
                
                if turnPlr == LocalPlayer then
                    ServerTurnState = "OurTurn"
                    
                    local promptText = nil
                    if type(prompt) == "table" then
                        promptText = prompt.RequiredLetter or prompt.Prompt or prompt.Letter
                    elseif type(prompt) == "string" then
                        promptText = prompt
                    end
                    
                    if promptText then
                        CurrentPrompt = tostring(promptText)
                        PromptInput.Text = CurrentPrompt
                        addLogEntry(string.format("🎯 [Event] Our Turn! Prompt: '%s' (Mode: %s)", CurrentPrompt, Config.DetectedMode), Color3.fromRGB(255, 215, 0))
                        refreshWordList(CurrentPrompt)
                        
                        if Config.AutoAnswer then
                            local token = roundToken
                            task.spawn(function()
                                local matches = findMatchingWords(CurrentPrompt)
                                if #matches > 0 then
                                    typeAndSubmitWord(matches[1].Word, CurrentPrompt, nil, token)
                                else
                                    addLogEntry(string.format("⚠️ No words for prompt '%s' (%s)", CurrentPrompt, Config.DetectedMode), Color3.fromRGB(230, 126, 34))
                                end
                            end)
                        end
                    end
                else
                    ServerTurnState = "OpponentTurn"
                    if turnPlr then
                        addLogEntry(string.format("📡 [Event] Opponent's turn: %s", tostring(turnPlr)), Color3.fromRGB(180, 185, 200))
                    end
                end
            end)
            table.insert(eventConnections, conn)
        end)
        
        -- Hook: strike
        pcall(function()
            local conn = gameEventModule.remoteConnect("strike", function(uid, _, alreadyUsed)
                if uid ~= LocalPlayer.UserId then return end
                if not pendingWord then return end
                
                local w = pendingWord
                
                if alreadyUsed then
                    UsedWords[w] = true
                    addLogEntry(string.format("⛔ [Event] '%s' already used!", w), Color3.fromRGB(231, 76, 60))
                else
                    blacklistRejectedWord(w)
                    addLogEntry(string.format("⛔ [Event] '%s' rejected & blacklisted!", w), Color3.fromRGB(231, 76, 60))
                end
                
                pendingWord = nil
                retriesThisTurn = retriesThisTurn + 1
                
                if retriesThisTurn > Config.MaxRetriesPerTurn then
                    addLogEntry(string.format("🚫 Max retries (%d) reached.", Config.MaxRetriesPerTurn), Color3.fromRGB(231, 76, 60))
                    return
                end
                
                if not Config.AutoAnswer then return end
                
                local token = roundToken
                local backspaces = pendingSuffix or 0
                
                task.spawn(function()
                    sendBackspaces(backspaces, token)
                    if token ~= roundToken then return end
                    
                    task.wait(0.1)
                    local matches = findMatchingWords(CurrentPrompt)
                    refreshWordList(CurrentPrompt)
                    
                    if #matches > 0 then
                        addLogEntry(string.format("🔄 [Event] Retry #%d: '%s'", retriesThisTurn, matches[1].Word), Color3.fromRGB(230, 126, 34))
                        typeAndSubmitWord(matches[1].Word, CurrentPrompt, nil, token)
                    else
                        addLogEntry(string.format("⚠️ No words left for '%s'", CurrentPrompt), Color3.fromRGB(230, 126, 34))
                    end
                end)
            end)
            table.insert(eventConnections, conn)
        end)
        
        -- Hook: correct
        pcall(function()
            local conn = gameEventModule.remoteConnect("correct", function(word)
                if pendingWord then
                    markWordUsed(pendingWord)
                    addLogEntry(string.format("✅ [Event] '%s' accepted!", pendingWord), Color3.fromRGB(46, 204, 113))
                end
                if type(word) == "string" and word ~= "" then
                    markWordUsed(word)
                end
                
                roundToken = roundToken + 1
                pendingWord = nil
                pendingSuffix = 0
                retriesThisTurn = 0
                triedThisRound = {}
            end)
            table.insert(eventConnections, conn)
        end)
        
        -- Hook: takeDamage
        pcall(function()
            local conn = gameEventModule.remoteConnect("takeDamage", function(uid)
                if uid == LocalPlayer.UserId then
                    roundToken = roundToken + 1
                    pendingWord = nil
                    pendingSuffix = 0
                    addLogEntry("💥 [Event] Time out / Damage taken.", Color3.fromRGB(231, 76, 60))
                end
            end)
            table.insert(eventConnections, conn)
        end)
        
    else
        useEventDriven = false
        addLogEntry("⚠️ getgc() event module not found. Using UI polling fallback.", Color3.fromRGB(230, 126, 34))
        EventInfoLabel.Text = getText("EventDrivenStatus", "ไม่พบ (UI Polling)")
        EventInfoLabel.TextColor3 = Color3.fromRGB(230, 126, 34)
    end
    
    pcall(function()
        LocalPlayer:GetAttributeChangedSignal("InGame"):Connect(function()
            if LocalPlayer:GetAttribute("InGame") then
                table.clear(UsedWords)
                table.clear(triedThisRound)
                retriesThisTurn = 0
                addLogEntry("🎮 InGame attribute changed: New game started.", Color3.fromRGB(52, 152, 219))
            end
        end)
    end)
end)

-- ==================== AUTO-ANSWER & MAIN GAME LOOP (FALLBACK FOR NON-EVENT MODE) ====================

local lastKnownMode = "None"

task.spawn(function()
    while ScreenGui and ScreenGui.Parent do
        task.wait(0.15)
        
        -- 1. Table Mode Detection with Sticky Latch
        local currentTableMode = detectTableMode()
        if currentTableMode ~= lastKnownMode then
            lastKnownMode = currentTableMode
            Config.DetectedMode = currentTableMode
            updateModePillButtons()
            
            if currentTableMode == "Hard" then
                addLogEntry("Switched to [Hard Mode] - Min 5 Base Characters.", Color3.fromRGB(231, 76, 60))
            else
                addLogEntry("Switched to [Easy Mode] - Any length allowed.", Color3.fromRGB(46, 204, 113))
            end
            
            if CurrentPrompt and CurrentPrompt ~= "" then
                refreshWordList(CurrentPrompt)
            end
        end
        
        -- 2. Turn State Detection & UI Update
        local turnState, activeBox = getGameTurnState()
        
        if turnState == "NotSeated" then
            TurnStatusText = "TurnWaitingSeat"
            TurnBadge.Text = getText("TurnWaitingSeat")
            TurnBadge.TextColor3 = Color3.fromRGB(243, 156, 18)
            
        elseif turnState == "OpponentTurn" then
            TurnStatusText = "TurnOpponent"
            TurnBadge.Text = getText("TurnOpponent")
            TurnBadge.TextColor3 = Color3.fromRGB(180, 185, 200)
            
        elseif turnState == "OurTurn" then
            TurnStatusText = "TurnOurs"
            TurnBadge.Text = getText("TurnOurs")
            TurnBadge.TextColor3 = Color3.fromRGB(46, 204, 113)
            
            if not useEventDriven then
                local prompt = extractCurrentPrompt(activeBox)
                if prompt and prompt ~= "" then
                    if prompt ~= CurrentPrompt then
                        roundToken = roundToken + 1
                        triedThisRound = {}
                        retriesThisTurn = 0
                        CurrentPrompt = prompt
                        PromptInput.Text = prompt
                        addLogEntry(string.format("🎯 New Prompt: '%s' (Mode: %s)", prompt, Config.DetectedMode), Color3.fromRGB(255, 215, 0))
                        refreshWordList(prompt)
                    end
                    
                    if Config.AutoAnswer and not isTypingOrSubmitting then
                        if retriesThisTurn < Config.MaxRetriesPerTurn then
                            local matches = findMatchingWords(CurrentPrompt)
                            if #matches > 0 then
                                local candidate = matches[1].Word
                                local token = roundToken
                                local submitted = typeAndSubmitWord(candidate, CurrentPrompt, activeBox, token)
                                if submitted then
                                    local roundPassed = false
                                    local checkStart = tick()
                                    
                                    while (tick() - checkStart) < 1.2 do
                                        task.wait(0.1)
                                        if token ~= roundToken then
                                            roundPassed = true
                                            break
                                        end
                                        local stateNow, boxNow = getGameTurnState()
                                        local promptNow = extractCurrentPrompt(boxNow)
                                        if stateNow == "OpponentTurn" or (promptNow and promptNow ~= CurrentPrompt) then
                                            roundPassed = true
                                            break
                                        end
                                    end
                                    
                                    if roundPassed then
                                        markWordUsed(candidate)
                                        addLogEntry(string.format("✅ Word '%s' accepted!", candidate), Color3.fromRGB(46, 204, 113))
                                        roundToken = roundToken + 1
                                        triedThisRound = {}
                                        retriesThisTurn = 0
                                        
                                        local waitLimit = tick() + 2.5
                                        while tick() < waitLimit do
                                            local s, _ = getGameTurnState()
                                            if s ~= "OurTurn" then break end
                                            task.wait(0.2)
                                        end
                                    else
                                        blacklistRejectedWord(candidate)
                                        retriesThisTurn = retriesThisTurn + 1
                                        TurnStatusText = "TurnRetrying"
                                        TurnBadge.Text = getText("TurnRetrying")
                                        TurnBadge.TextColor3 = Color3.fromRGB(231, 76, 60)
                                        addLogEntry(string.format("❌ Word '%s' rejected! (Retry %d/%d)", candidate, retriesThisTurn, Config.MaxRetriesPerTurn), Color3.fromRGB(231, 76, 60))
                                        
                                        sendBackspaces(pendingSuffix, token)
                                        refreshWordList(CurrentPrompt)
                                        task.wait(0.2)
                                    end
                                end
                            else
                                addLogEntry(string.format("⚠️ No available words left for prompt '%s' (%s)", CurrentPrompt, Config.DetectedMode), Color3.fromRGB(230, 126, 34))
                                task.wait(1.0)
                            end
                        end
                    end
                end
            end
        end
        
        DbInfoLabel.Text = getText("DictStatus", WordCount)
    end
end)

print("[ThaiWordChain] Helper v6.1 (Strict 5+ Base Chars in Hard Mode + Sticky Latch) Loaded!")
