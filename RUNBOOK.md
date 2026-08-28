# RUNBOOK · 從零到跑出第一份 SPDM 握手封包

這份文件的目標只有一個:**任何人照著做,都會得到跟這個 repo 一樣的結果。**

「任何人」包含三個月後已經忘光的你,也包含沒碰過韌體、沒聽過 SPDM 的高中生。
所以每一步都會寫三件事:**指令是什麼、成功長什麼樣、失敗了怎麼辦。**

不需要事先懂 SPDM。§1 有五分鐘的背景,附錄 B 有詞彙表。

---

## 0. 三十秒版本

| 問題 | 答案 |
|---|---|
| 我在做什麼? | 用 DMTF 的參考實作(`libspdm` / `spdm-emu`)建一條**可量測、可重現**的 SPDM 裝置證明流程,產出證據當**求職作品集** |
| 總共多久? | 14 週,2026-08-11 ~ 2026-11-15 |
| **現在做到哪?** | ★★ **W02 收工(2026-08-28)**。逐欄位文件 7 個訊息對、**128 個數字由 CI 從 capture 重算**,其中 2 個訊息對的**位移**是從線上重建出來的(§8.3b)。三個機制缺陷在 W01 稽核時抓到並修掉,今天又抓到兩個:一個**沒人引用所以沒被檢查**的欄位錯了 40%,以及**「manifest 說沒被動過」不等於「還是對的」**(§8.5) |
| ★ 一句話成果(W01) | 「我以為我跑的是最小握手。我砍了 `--exe_conn`,**但漏了 `--exe_session`,它的預設值有 14 項** —— 1116 封包、53 秒、結束碼 1。教訓是:**結束碼不是判決**,同一天有三個工具回答了稍微不同的問題」 |
| ★★ 一句話成果(W02 · 主) | 「我把 554 個封包的『最小握手』砍到 **30** 個,而且證明被砍掉的 526 個封包送的是**完全相同的 528 個位元組** —— 263 趟來回 vs **1 趟**。兩個 528 都是腳本從兩份不同的 capture 各自算出來的」 |
| ★★ 一句話成果(W02 · 機制) | 「逐欄位文件裡的每一個數字都寫成 `<!--claim key=value-->`,`fields.py --check` 從 capture 重新算一次。**128/128 通過,而且我證明過它會紅**:數字漂一個位元、欄位名寫錯、capture 不見 —— 三種都會讓建置失敗」 |
| ★★ 一句話成果(W02 · 位移) | 「**值可以重算,位移不行** —— 解碼器印欄位不印位置。所以我改成把整則訊息重建一次,要求剩下的位元組**剛好等於協商到的簽章長度**,再用 `RequesterContext` 的回音當第二條式子。兩個未知數、兩條獨立式子,**多出來的那一條才是讓 capture 有能力說『你排錯了』的東西**。它順便解掉一個文件原本答不出來的問題」 |
| ★★ 一句話成果(W02 · 可重現) | 「同樣五臂、同樣的 pin、隔 11 天重跑,**每一臂一個 byte 都沒差**(554/20549、584/114751、566/20396、30/11441、30/11441)。所以那份 08-17 寫的文件,128 個 claim 全部對得上一份它從沒看過的 capture。**位元組類報單值不報範圍,現在是量到的性質,不是慣例**」 |
| ★★ 一句話成果(W02 · 稽核) | 「我回頭稽核 W01,發現**三個機制缺陷,而且三個都在報告成功**:`manifest.json` 對 12 個被 `.gitignore` 擋掉的檔案簽了 SHA-256;`repo_dirty` 永遠是 `true`(因為先 `mkdir` 才問 git);解碼器 `spdm-dump` 從來沒被釘版本。全修,而且各補一條 CI 檢查」 |
| ★ 反直覺的一個發現 | 「**多提供幾個演算法不會讓 `NEGOTIATE_ALGORITHMS` 變大。** 提供 1 個和提供 4 個都是 **56 bytes**,因為那些欄位是固定寬度的位元遮罩。多提供的代價不是頻寬,是**你在讀回 `ALGORITHMS` 之前不知道會用哪個**」 |
| Claude Code 從哪開? | **`C:\Users\Key20\Desktop\mctp-spdm-pqc`** |
| 程式碼在哪? | repo 就在上面那個路徑;**上游原始碼與 build tree 在 WSL 的 `~/spdm-lab/`(ext4),絕不放 `/mnt/c`** |
| GitHub | <https://github.com/Jhongwe1/mctp-spdm-pqc> |
| 今天要做什麼? | **① `c-drills` D1 四步**(題目已經出好在 `d1_spdm_header.c`,契約與測試齊全,**實作是你的**) ② **D3 補做**(W01 欠的,`DONE.txt` 到現在還是空的) ③ **08/31 SPDM 1.5 公評截止**會過期 ④ W03 有一條已知是紅的:**系統 OpenSSL 3.0.13 簽不了 ML-DSA**(見下) |
| 專案那軌 vs 基本功那軌 | 🔴 專案 **超前**;**基本功欠兩週,`SCORECARD.md` 八列全空。這是這個 repo 目前最大的缺口** —— repo 量的是「這個系統怎麼運作」,`SCORECARD.md` 是**唯一一個量「我」的東西**。面試時 repo 讓你進到白板前面,白板上考的是 D1~D8 |
| ⚠️ W03 已知的障礙 | **系統 OpenSSL 是 3.0.13,`openssl list -signature-algorithms \| grep ml-dsa` 回空** —— W03 要用它簽 PQC 憑證那條現在就是紅的。這跟 libspdm 無關(它自己編 OpenSSL submodule):**一個專案裡兩個 OpenSSL,只有一個被釘住** |
| 我最該先讀哪一段? | 想知道握手每個欄位在幹嘛 → [`docs/handshake-walkthrough.md`](docs/handshake-walkthrough.md);想知道 `--trans MCTP` 為什麼不是真的 MCTP → [`docs/transports.md`](docs/transports.md);想知道踩過哪些坑 → `LOG.md`;想知道數字憑什麼可信 → 本檔 §6 的 `manifest.json` 那段 |
| ⚠️ 三個一定要記住的 | ① **綠 ≠ 有在保護我**。現在只有 `verify` 與 `drills` 兩個 CI job,真正該綠的 `rats` job(斷言「篡改過的量測必須被判 FAIL」)要到 G2/G3 才存在<br>② **結束碼不是判決**,看封包數、看 log 的 error 行、看解出來的欄位<br>③ **解碼短 ≠ 握手短**。`spdm_dump` 的憑證鏈上限是 **4096 bytes**(量出來的,不是查表的),後量子鏈 16853 bytes 會讓它中途停下 |

### 現在的關卡狀態

| Gate | 主題 | 狀態 |
|---|---|---|
| G0 | 環境與版本基線 | ✅ 完成 |
| G1 | 完整握手、逐欄位 | 🟡 **進行中** — 逐欄位文件已完成 7 個訊息對,128 個數字由 CI 驗證,其中 2 個訊息對的**位移**是從線上重建出來的 |
| G2 | 憑證鏈與三點篡改 | ⬜ 未開始(W03~W05) |
| G3 | RATS 驗證流水線 | ⬜ 未開始(W06~W07) |
| G4 | 後量子成本 | ⬜ 未開始(W08) |
| G5 | 真實傳輸 | ⬜ 未開始(W09) |
| G6 | 一致性與負面測試 | ⬜ 未開始(W10~W11) |
| G7 | 上游貢獻 | 🟡 環境已備妥;**今天多找到一個候選 patch**(`spdm-emu` 的 `--help` 預設值與 `key.c` 不同步) |
| G8 | 交付與敘事 | ⬜ 未開始(W12~W14) |

---

## 目錄

| § | 內容 | 需要時間 |
|:--|---|---|
| [0](#0-三十秒版本) | 三十秒版本 | 讀 30 秒 |
| [1](#1-你正在建什麼五分鐘) | 你正在建什麼 | 讀 5 分 |
| [2](#2-你需要什麼) | 你需要什麼 | — |
| [3](#3-準備一台-linuxwindows-使用者看這裡) | 準備一台 Linux(Windows 看這裡) | 15 分 |
| [4](#4-取得-repo-並檢查機器) | 取得 repo 並檢查機器 | 2 分 |
| [5](#5-建置-30-分鐘大部分在下載) | 建置 | 30 分 |
| [6](#6-體檢跑出第一份封包) | 體檢:跑出第一份封包 | 2 分 |
| [7](#7-剛剛到底發生了什麼) | 剛剛到底發生了什麼 | 讀 10 分 |
| [8](#8-收證據把一份-capture-變成可以被檢查的數字) | **收證據:把 capture 變成可被檢查的數字** | 讀 10 分 |
| [9](#9-出問題時症狀--原因--解法) | 出問題時:症狀 → 原因 → 解法 | 查表 |
| [10](#10-基本功c-drills) | 基本功:c-drills | 每週 |
| [11](#11-每天怎麼用這個-repo) | 每天怎麼用這個 repo | — |
| [12](#12-把一切從零重建驗證可重現性) | 把一切從零重建 | 40 分 |
| [附錄](#附錄-a-指令速查) | 指令速查、詞彙表 | 查表 |

---

## 1. 你正在建什麼(五分鐘)

### 問題長這樣

你買了一台伺服器。裡面有一顆網卡、一顆 SSD、一顆 GPU。

**你怎麼知道那顆網卡上跑的韌體,就是原廠出貨時的那一份?**

不是「你信任供應商」的那種知道,是**機器能自己驗證**的那種知道。因為韌體可以在
運送途中被換掉、可以被上一個租戶改掉、可以被一個已經修掉的漏洞留下後門。

### SPDM 是這個問題的標準答案

**SPDM**(Security Protocol and Data Model)是 DMTF 訂的協定。它讓一顆晶片可以
問另一顆晶片:

```
「你是誰?」            → 給我你的憑證鏈
「證明你是你」          → 用你的私鑰簽一個我出的亂數
「你身上跑的是什麼?」    → 給我你韌體的雜湊值(叫 measurement)
```

問話的那一端叫 **Requester**,回答的那一端叫 **Responder**。在真的伺服器裡,
Requester 通常是 **BMC**(那顆管理整台機器的小電腦),Responder 是網卡、SSD 或
一顆專門的信任根晶片。

### 但這裡有一個所有教學都跳過的洞

握手成功 ≠ 安全。

Responder 回你一個 measurement,比如 `a3f9...`。**然後呢?**

`a3f9...` 是對的還是錯的?SPDM **規格不管這件事**。它只保證這個值真的來自那顆
晶片、沒被中途竄改。至於這個值「應該」是多少,你得自己去跟一份**參考值**比對。

**這個 repo 做的就是那一段。** 完整流程是:

```
①  跑完整握手,把每一個位元組錄成 pcap
②  故意去改 Responder 的 measurement(三個不同的點)
③  證明改過的握手「拿得到值,但值不一樣」——並量出差在哪幾個位元組
④  接上一條 RATS 流水線:參考值 → 政策引擎 → 判定 pass / fail
⑤  把演算法換成後量子的(ML-DSA / ML-KEM),量出代價是幾個位元組、幾趟來回
```

第 ③ 步和第 ④ 步是重點。**握手成功很容易,判斷「這個值該不該被接受」才是真工作。**

### 這個 repo 明確不做什麼

> **它做的是協定流程層級的正確性驗證,不是安全性評估。**

意思是:它回答「這個流程有沒有照規格走、代價是多少個位元組」,
**不回答**「這個系統安不安全」。沒有做威脅建模,沒有做密碼學審查,
所有的篡改案例都是自己設計的、不是攻擊者選的。

這句話會出現在 README 第一屏、在 CI badge 之前。這是刻意的。

---

## 2. 你需要什麼

| 項目 | 需求 | 備註 |
|---|---|---|
| 作業系統 | **Linux**(Ubuntu 24.04 已驗證) | Windows 看 §3,macOS 用 Docker |
| CPU | 4 核以上 | 8 核會快一倍 |
| 記憶體 | 4 GB 以上 | 編譯 OpenSSL 時 `-j3` 約吃 1.5 GB |
| **磁碟** | **25 GB 空的** | ⚠️ 這是最容易低估的一項,見下 |
| 網路 | 能連 github.com | 要下載約 5 GB |
| 時間 | 首次約 40 分鐘 | 其中 30 分鐘在下載,你可以去做別的事 |

> ### ⚠️ 為什麼要 25 GB?
>
> `spdm-emu` 底下掛 `libspdm`,`libspdm` 底下**整包內嵌 OpenSSL 原始碼**,
> 而 OpenSSL 又掛了它自己的測試工具(`tlsfuzzer`、`wycheproof`、`krb5`、
> `boringssl`……)。而且 `spdm-emu` 還另外掛了一個 `SPDM-Responder-Validator`,
> **它底下又有一份完整的 libspdm**。
>
> 所以一次 clone 會把 OpenSSL 抓兩遍。單一 flavor 的原始碼樹約 2.5 GB,
> 編譯後約 6~8 GB,兩個 flavor 就接近 20 GB。
>
> **這是正常的,不是你做錯了。**

需要的軟體(§4 的 `doctor.sh` 會逐項幫你檢查):

```
git   cmake(≥3.10)   make   gcc   python3   perl
```

---

## 3. 準備一台 Linux(Windows 使用者看這裡)

Windows 上有兩條路。**推薦 WSL2**,因為它快,而且就是本 repo 驗證過的環境。

### 3A · WSL2(推薦)

在 **PowerShell(系統管理員)** 執行:

```powershell
wsl --install -d Ubuntu-24.04
```

裝完重開機,Ubuntu 會要你設一組使用者名稱和密碼。之後每次進 Linux:

```powershell
wsl -d Ubuntu-24.04
```

裝好之後,在 **Ubuntu 裡面**裝工具:

```bash
sudo apt-get update
sudo apt-get install -y git cmake build-essential python3 perl iproute2
```

> ### 🔴 WSL 使用者:這一條沒做,你的 build 會慢十倍
>
> **一定要把程式碼放在 Linux 自己的檔案系統(`~/`),不要放在 `/mnt/c/`。**
>
> `/mnt/c/` 是透過一層網路檔案協定(9P)去存取 Windows 的 NTFS。編譯這種
> 「開幾萬個小檔案」的工作,在 `/mnt/c/` 上會慢 10 到 50 倍。同一個 build,
> 放對地方 12 分鐘,放錯地方可以跑到 90 分鐘。
>
> 本 repo 的腳本已經處理好了:**repo 放哪裡都可以**(甚至放 Windows 桌面),
> 但**編譯樹一律建在 `~/spdm-lab/`**,也就是 Linux 的 ext4 上。
> 這不只是為了快——上游的原始碼本來就不該混進你自己的 repo。

### 3B · Docker(macOS,或不想裝 WSL)

```bash
docker build -t spdm-lab docker/
docker run -it --rm -v "$PWD:/repo" -w /repo spdm-lab bash
```

進去之後 §4 之後的步驟完全一樣。

---

## 4. 取得 repo 並檢查機器

```bash
git clone https://github.com/Jhongwe1/mctp-spdm-pqc.git
cd mctp-spdm-pqc

bash harness/doctor.sh
```

`doctor.sh` **只檢查、不安裝、不下載**。它會告訴你缺什麼,以及補的指令。

<details>
<summary><b>成功長這樣(點開)</b></summary>

```
-- required tools --
   ok  git                git version 2.43.0
   ok  cmake              cmake version 3.28.3
   ok  make               GNU Make 4.3
   ok  gcc                gcc (Ubuntu 13.3.0) 13.3.0
   ok  python3            Python 3.12.3
   ok  perl               This is perl 5, version 38

-- disk --
   ok  free space         948 GB available under $HOME

-- network --
   ok  reachable          https://github.com/DMTF/spdm-emu.git

-- port --
   ok  port 2323          free

========================================================
 ready — next: bash harness/build_spdm_emu.sh pqc
========================================================
```
</details>

**看到 `ready` 才往下走。** 有 `FAIL` 就照它印的指令補,然後重跑。

> 💡 為什麼是 `bash harness/xxx.sh` 而不是 `./harness/xxx.sh`?
> 因為如果 repo 曾經放在 NTFS 上,檔案的「可執行位元」可能沒被保留。
> 用 `bash` 明確呼叫,這個問題就不存在。

---

## 5. 建置(30 分鐘,大部分在下載)

```bash
bash harness/build_spdm_emu.sh pqc
```

**如果這台機器同時在跑別的重工作**(例如另一個專案的測試),改成:

```bash
JOBS=3 nice -n 19 bash harness/build_spdm_emu.sh pqc
```

`nice -n 19` 的意思是「只用別人不要的 CPU」。核心排程器會無條件讓另一邊優先。

### 過程中你會看到什麼

| 階段 | 畫面 | 大約時間 |
|---|---|---|
| 1. Clone | 幾百行 `Cloning into '...openssl/wycheproof'...` | **10~20 分** |
| 2. 版本釘子 | `wrote BUILD_PIN.txt` 加一段 key=value | 1 秒 |
| 3. cmake | `cmake configured` | 10 秒 |
| 4. 樣本金鑰 | `sample keys generated` | 5 秒 |
| 5. 編譯 | 安靜(輸出在 log 檔裡) | **10~25 分** |
| 6. 驗證 | 一串 `ok` | 2 秒 |

> ### 🟡 第 1 階段看起來像當機,但它沒有
>
> 你會看到它在下載 `tlsfuzzer`、`tlslite-ng`、`krb5`、`boringssl`、`wycheproof`
> ——**這些都是 OpenSSL 自己的測試工具,跟 SPDM 一點關係都沒有。**
> 它們是被 submodule 遞迴帶進來的。
>
> 判斷它有沒有真的卡住:開另一個終端機跑
> ```bash
> du -sh ~/spdm-lab/work/spdm-emu-pqc
> ```
> **數字有在長就是正常的。**

### 成功長這樣

```
========================================================
 verify
========================================================
  ok   binary present: spdm_requester_emu
  ok   binary present: spdm_responder_emu
  ok   --pqc_asym present  -> PQC experiments are possible with this build
  ok   meas.c present (33452 bytes) -> W04 target exists

========================================================
 done · flavor=pqc
========================================================
  binaries : /home/<你>/spdm-lab/work/spdm-emu-pqc/build/bin
  pin      : /home/<你>/spdm-lab/work/spdm-emu-pqc/BUILD_PIN.txt
```

### 第二份 build(baseline)

```bash
bash harness/build_spdm_emu.sh stable --seed-from pqc
```

`--seed-from pqc` 會直接複製第一份的原始碼樹,**完全不重新下載**,把 spdm-emu
切到 `3.8.0`(libspdm 跟著它的 submodule 指標走)再編一次。省下 20 分鐘和 2.5 GB。

<details>
<summary><b>為什麼要兩份 build?</b></summary>

後量子演算法是 **2026-08-04** 才進 libspdm 主線的,而且 `4.0.0` 目前是
**release candidate**。

**我不想讓一個 RC 當我的基準線。** 所以:

| flavor | spdm-emu | libspdm | 用途 |
|---|---|---|---|
| `stable` | 3.8.0 | 3.8.0 | 所有 baseline 量測 |
| `pqc` | 4.0.0-rc | 4.0.0-rc | 只跑後量子實驗 |

**釘的是 `spdm-emu` 的 tag,libspdm 跟著那個 tag 的 submodule 指標走**,因為
上游是把這兩個當一組發布跟測試的。**沒有任何一個 `spdm-emu` commit 指向過
libspdm 3.8.1 或 3.8.2**——那兩個在 `release-3.8` 維護分支上,而 spdm-emu
從來沒跟過那條線——**所以基準線是 3.8.0。**

代價是去查上游歷史查出來的,不是憑印象寫的:3.8.1 是四個 commit,全部是編譯與
可攜性,**沒有任何安全性修補**;3.8.2 再加十個,其中**恰好一個**是安全性修補
(`Fix security vulnerability in GET_CSR parsing code`)。**而那個修補在
4.0.0-rc 裡有**(同一天的主線 commit,hash 不同),所以只有基準線沒有它——
而且 `GET_CSR` 根本不在本專案跑的那幾個操作裡。基準線還少了哪些主線修補、
以及這是怎麼查的,見 `docs/decisions/0001-two-build-flavors.md`。

兩份的 commit hash 都釘在 `third_party/*.pin`,每一張表的 caption 都會寫是
哪一份跑出來的。完整理由見 `docs/decisions/0001-two-build-flavors.md`。
</details>

---

## 6. 體檢:跑出第一份封包

```bash
bash harness/healthcheck.sh pqc --write-baseline
```

這支腳本跑 10 項檢查,**其中兩項是決定性的**:

| 項 | 檢查什麼 | 失敗代表 |
|:--:|---|---|
| **#4** | 最小握手能不能跑通 | 🔴 **停下來修這個,後面全部做不了** |
| **#7** | 後量子握手能不能跑通 | ⚠️ PQC 那半段從「量測」降級為「規格推算」 |

其餘 8 項是把環境寫下來存證。三個月後沒有人記得當時的版本長什麼樣,
**而每一個數字都必須能被指回它是在哪一個環境下量出來的。**

### 成功長這樣

```
=== 4. minimal handshake  ★ go / no-go for the whole project ===
  --exe_conn DIGEST,CERT,CHAL,MEAS
  [PASS] minimal handshake completed (DIGEST, CERT, CHALLENGE, MEASUREMENTS)

=== 5. capture file produced, and how many packets are in it ===
  file       : .../minimal.pcap (1234 bytes)
  format     : classic pcap v2.4, little-endian, microsecond timestamps
  packets    : 12
  [PASS] pcap written and parsed by harness/pcapcount.py

  GATE 0 (minimal handshake): PASS — the project can proceed.
```

### 它留下了什麼

```
docs/env-baseline.md              ← 體檢輸出原文,已經包好 markdown
bench/data/healthcheck-pqc-<時間戳>/
  ├── manifest.json               ← ★ 見下
  ├── BUILD_PIN.txt               ← 這次用的上游 commit hash
  ├── healthcheck.txt
  ├── minimal.pcap                ← ★ 你的第一份證據
  ├── minimal.req.log
  ├── minimal.rsp.log
  ├── pqc.pcap
  └── verdicts.tsv
```

`manifest.json` 是這個 repo 的**誠實機制**。打開來看:

```json
{
  "upstream": {
    "libspdm": "a1b2c3...",        ← 精確到 commit
    "libspdm_version": "libspdm version 4.0.0 (release candidate)",
    "spdm_emu": "5f01d2f..."
  },
  "commands": [
    "./spdm_requester_emu --exe_conn DIGEST,CERT,CHAL,MEAS --pcap .../minimal.pcap"
  ],
  "artifacts": [
    { "path": "minimal.pcap", "bytes": 1234, "sha256": "..." }
  ]
}
```

**規則:每一個被發表出去的數字,都要指得到一個 `manifest.json`。**

這一條是靠機制執行的,不是靠自律。任何要記錄結果的腳本都必須呼叫
`prov_begin` / `prov_finish`(見 `harness/lib/provenance.sh`),
所以**一個結果不可能在沒有出處的情況下被產生出來**。

---

## 7. 剛剛到底發生了什麼

你剛剛跑的那一行,展開來是這樣:

```bash
./spdm_responder_emu --exe_conn DIGEST,CERT,CHAL,MEAS --exe_session NO_END &
./spdm_requester_emu --exe_conn DIGEST,CERT,CHAL,MEAS --exe_session NO_END \
                     --pcap minimal.pcap
```

> ### 🔴 `--exe_session` 是這裡最容易漏掉的一個字
>
> **有兩個旗標,不是一個。** 大部分教學(和本專案的原始計畫)只講 `--exe_conn`,
> 但 `--exe_session` 的預設值有 **14 項**:
> `KEY_EX,PSK,KEY_UPDATE,HEARTBEAT,MEAS,MEL,DIGEST,CERT,GET_CSR,SET_CERT,`
> `GET_KEY_PAIR_INFO,SET_KEY_PAIR_INFO,EP_INFO,APP`
>
> 這 14 項全部跑在一條**加密 session** 裡,而**連線階段的證明流程根本不需要
> session**。其中 `SET_CERT` 還會在範例金鑰上失敗。實測(同樣的 `--exe_conn`):
>
> | `--exe_session` | 封包 | 位元組 | 時間 | 結束碼 |
> |---|--:|--:|--:|:--:|
> | 預設(14 項) | 1116 | 61,807 | 53 s | **1** ❌ |
> | `NO_END` | 554 | 20,549 | 24 s | **0** ✅ |
> | `KEY_EX` | 578 | 30,834 | 27 s | 0 |
>
> **為什麼是 `NO_END`?** 因為旗標解析器沒有「什麼都不要」這個字,而 `NO_END`(0x4)
> 既不含 `KEY_EX`(0x1)也不含 `PSK`(0x2)——**而那兩個是唯一會讓程式建立
> session 的旗標**。這是副作用不是本意,所以程式碼裡有註解說明。

兩個行程透過 **TCP port 2323** 對話。訊息流大致是:

```
Requester(BMC)                                  Responder(裝置)
      │                                                │
      │──── GET_VERSION ──────────────────────────────▶│   我們講哪一版?
      │◀─────────────────────────────────── VERSION ───│
      │                                                │
      │──── GET_CAPABILITIES ─────────────────────────▶│   你會做什麼?
      │◀────────────────────────────── CAPABILITIES ───│
      │                                                │
      │──── NEGOTIATE_ALGORITHMS ─────────────────────▶│   用哪組演算法?
      │◀─────────────────────────────────── ALGORITHMS │   ★ 這裡決定 PQC 有沒有生效
      │                                                │
      │──── GET_DIGESTS ──────────────────────────────▶│   憑證的雜湊
      │◀─────────────────────────────────── DIGESTS ───│
      │──── GET_CERTIFICATE ──────────────────────────▶│   完整憑證鏈
      │◀─────────────────────────────── CERTIFICATE ───│   ★ 大,要分好幾次拿
      │                                                │
      │──── CHALLENGE(亂數)───────────────────────▶│   簽這個給我看
      │◀───────────────────────────── CHALLENGE_AUTH ──│   ★ 這裡證明「你是你」
      │                                                │
      │──── GET_MEASUREMENTS ─────────────────────────▶│   你身上跑什麼韌體?
      │◀──────────────────────────────── MEASUREMENTS ─│   ★ 這裡開始才是本專案
      │                                                │
```

`--exe_conn DIGEST,CERT,CHAL,MEAS` 就是在說「這四段都做」。

> ### 為什麼要手動指定這四個?
>
> 因為預設值有 **10 個項目**:
> `DIGEST,CERT,CHAL,MEAS,MEL,GET_CSR,SET_CERT,GET_KEY_PAIR_INFO,SET_KEY_PAIR_INFO,EP_INFO`
>
> 跑起來 log 好幾百行,你會對著它發呆兩天。
> **先砍到四個、把這四個完全看懂,再一個一個加回去。**

### 用 spdm-dump 拆開那份 pcap

```bash
bash harness/build_spdm_dump.sh          # 首次要編,約 15 分鐘
~/spdm-lab/work/spdm-dump/build/bin/spdm_dump -r bench/data/<run-id>/minimal.pcap
```

它會把每一個訊息逐欄位印出來。**下一節就是把這些欄位變成可以被檢查的數字。**

---

## 8. 收證據:把一份 capture 變成可以被檢查的數字

這一節是這個 repo 跟「跑過一次然後截圖」的差別所在。**如果你只想看一次結果,
上一節就夠了。這一節在講怎麼讓那個結果三個月後還是對的。**

### 8.1 收一組基線 capture

```bash
bash harness/capture.sh --name w2-baseline        # 約 3 分鐘
```

它一次跑**五臂**,寫進同一個 `bench/data/<name>-<時間戳>/`:

| 臂 | 是什麼 | 為什麼要有它 |
|---|---|---|
| `classical` | pqc build,預設演算法 | 對照組 |
| `pqc` | pqc build,ML-DSA-65 ＋ ML-KEM-768,**兩個方向都釘死** | 後量子那一臂 |
| `classical-stable` | **stable build**,預設演算法 | ★ **控制組**:回答「pqc build 上的 classical 能不能代表 stable 基線」 |
| `walkthrough` | pqc build ＋ `--meas_op ALL` | 30 個封包,逐欄位標註用這一份 |
| `single-algo` | 每組演算法只提供一個 | 回答「多提供幾個會不會變大」 |

> ### 🔴 為什麼一定要有控制組
>
> 因為答案是**不能代表**。同樣的旗標,兩份 build 的結果差在五個地方:協商到的
> SPDM 版本(1.4 vs **1.3**)、requester 能力位元(少了 `LARGE_RESP_CAP`)、
> 一次要求的憑證長度(163,824 vs **1,024**)、憑證鏈大小(1,655 vs **1,591**
> bytes)、以及取完整條鏈要幾趟(1 vs **2**)。
>
> **「classical 基線」不是一個跟 build 無關的東西。** 哪一份 build 跑出來的,
> 要寫進表格的說明;`manifest.json` 無論你寫不寫都會記。

> ### 🔴 為什麼後量子那臂要釘**兩個**方向
>
> **SPDM 是雙向認證的,而且兩個方向的演算法是分開協商的。**
> 08-11 那次只釘了 `--pqc_asym`(responder 側),`--req_pqc_asym` 留預設 →
> responder 幫 requester 挑了 **ML-DSA-87**。那份 capture 裡是「responder 用
> ML-DSA-65、requester 用 ML-DSA-87」,而對照的 classical 臂 requester 用的是
> RSAPSS-3072。**兩臂的 requester 演算法不一樣,就不能相減。**
>
> 這跟 08-11 撤掉 5.94× 是同一類錯,但藏得更深:那次是「數字從請求推出來的」,
> 這次是「讀回來了,但只看了一個欄位」。

### 8.2 把協定欄位讀出來

```bash
python3 harness/fields.py bench/data/<run>/walkthrough.decode.txt
python3 harness/fields.py bench/data/<run>/walkthrough.decode.txt --json
python3 harness/fields.py bench/data/<run>/walkthrough.decode.txt --list-keys
```

它讀的是 `spdm_dump` 的輸出,不是 pcap —— 因為 `spdm_dump` 已經會解 SPDM 了,
再寫一個解析器就是多一個要維護對的東西。**它印的是「實際協商到什麼」,不是
「你要求了什麼」。**

輸出大概長這樣:

```
requester   : Flags 0x8882f7c6  CTExponent 0  DataTransferSize 4608
              CERT_CAP, CHAL_CAP, ..., CHUNK_CAP, EP_INFO_CAP_SIG, ...
algorithms  : offered -> negotiated
              Hash        SHA_256, SHA_384          -> SHA_384
              ReqAsym     RSASSA_2048, ...          -> RSAPSS_3072
certificate : 3 GET_CERTIFICATE (+1 encapsulated), requested Length 163824
              responder slot 0 : 1655 bytes, 1 portion(s) per fetch, fetched 2x
measurements: operation ALL, responder reports 8 block(s), record 528 bytes
```

### 8.3 ★ 讓文件裡的數字不能腐爛

**這是這個 repo 的核心機制,而且它是被 08-16 跟 08-17 兩次教訓逼出來的。**

那兩次的結論是同一句:**只被「寫下來」的事實沒有任何東西在檢查它;被「算出來」
的事實每次執行都會被檢查。兩者重疊的地方,爛掉的一定是寫下來的那個。**

所以 `docs/handshake-walkthrough.md` 裡的每一個數字都不是打字打進去的,而是:

```markdown
<!-- capture: bench/data/<run>/walkthrough.decode.txt -->

| `DataTransferSize` | <!--claim capabilities.requester.data_transfer_size=4608--> 4,608 |
```

`<!--claim ...-->` 在渲染出來的網頁上看不到,但:

```bash
python3 harness/fields.py --check docs/handshake-walkthrough.md
#   128/128 claims match the capture
```

`harness/verify_repo.sh` 會跑這個檢查,CI 會跑 `verify_repo.sh`。
**所以一個數字跟它的 capture 對不上,是建置變紅,不是「希望有人注意到」。**

> ### 綠燈要先證明過它會紅
>
> 三種壞法都試過,三種都會紅:
>
> | 弄壞什麼 | 結果 |
> |---|---|
> | 把 528 改成 529 | `FAIL line 508: document says 529, capture says 528` |
> | 把欄位名寫成不存在的 `measurements.mode` | `FAIL: 'measurements.mode' is not a field this tool computes` |
> | 把 capture 路徑改成不存在的檔案 | `FAIL: capture not found` |
>
> **第二種特別重要**:它讓你不能用「發明一個欄位名」來滿足檢查。

### 8.3b ★ 位移(offset)沒辦法用同一招檢查,所以用另一招

上面那招檢查的是**值**:「`DataTransferSize` 是 4608」可以從解碼結果重新算出來。

但**位移**不行。`spdm_dump` 印的是「有哪些欄位、值是多少」,它從來不印「這個欄位
在第幾個 byte」。所以逐欄位表格裡那一整欄 `offset`,原本全部是從 libspdm 的
`spdm.h` 抄過來的 —— 而**抄錯的位移配上抄對的值,上面每一個檢查都會通過。**

解法是換一種問法:**不要「檢查」位移,而是「重建」整則訊息,然後要求它剛好用完。**

一則 SPDM 回應裡每個欄位的長度只會是四種來源之一:

| 來源 | 例子 |
|---|---|
| 固定常數 | `Nonce` 永遠 32 bytes |
| 前面協商到的東西 | `CertChainHash` = 這次選到的 hash 長度(這裡是 SHA-384,48) |
| 訊息自己帶的長度欄位 | `MeasurementRecordLength`(offset 5 的 24-bit 小端數) |
| 剩下的全部 | `Signature` |

所以整則訊息可以被**重排一次**,而重排出來的結果有兩個地方會露餡:

```
CHALLENGE_AUTH,第 14 個封包,總長 238 bytes(從 hex dump 讀的)
  4 標頭 + 48 CertChainHash + 32 Nonce + 48 MeasurementSummaryHash
    + 2 OpaqueLength + 0 OpaqueData + 8 RequesterContext = 142
  238 - 142 = 96
```

**96 剛好就是 ECDSA-P384 的簽章長度,而 ECDSA-P384 正是這次 `ALGORITHMS` 選到
的演算法。** 前面任何一個欄位的長度排錯,這個減法就不會是 96。

而且還有第二條式子。`RequesterContext` 那 8 個 byte 是**請求方自己選的,回應方
原樣送回來**。所以到預測的位移 134 去讀那 8 個 byte,拿去跟請求裡的比對 ——
**兩個未知數、兩條互相獨立的式子**。

> ### 為什麼「多一條式子」才是重點
>
> 如果只有一條式子,它就只是把輸入重講一遍,永遠會成立。**多出來的那一條,
> 才是讓 capture 有能力說「你排錯了」的東西。**
>
> 它立刻解決了一個原本文件答不出來的問題:`MeasurementSummaryHash` 到底是用
> `BaseHashAlgo`(SHA-384,48)還是 `MeasurementHashAlgo`(SHA-512,64)?這次
> 連線兩個都協商了。兩個假設差 16 bytes,**只有一個會閉合。**答案是前者,而且
> 這個答案是算出來的,不是去翻規格翻到的。

`verify_repo.sh` 會自己造一則正確的 `CHALLENGE_AUTH`,確認它閉合,然後**故意
弄壞三次**(少一個 byte、context 對不上、換一個簽章演算法),要求三次都被拒絕。
**一個永遠會通過的檢查不是檢查,是剛好對上的算術。**

目前七個訊息對裡只有 2 個(`CHALLENGE_AUTH`、`MEASUREMENTS`)是這樣重建的,
另外五個還是抄的 —— **文件 §10 自己寫出來是哪五個。**

### 8.4 每一個結果都有出處

跑完之後 `bench/data/<run>/manifest.json` 裡有:

- 三份 build 的 commit hash(**pqc、stable、以及解碼器 `spdm-dump`**)
- 完整的指令列,原樣
- 每一個檔案的 SHA-256 與位元組數
- 跑的時候工作樹乾不乾淨(`repo_dirty`)

> ### 🔴 `repo_dirty` 曾經永遠是 `true`
>
> 因為 `prov_begin` 先 `mkdir` 了 run 目錄、才去問 git 乾不乾淨 —— 那個目錄
> 本身就讓樹變髒了。**一個永遠只會回答同一個值的欄位不是觀察**,而且比沒有
> 這個欄位更糟,因為讀的人分不出來。08-17 修掉。

> ### 🔴 `.gitignore` 的 `*.log` 曾經吃掉 12 個被 manifest 簽過名的檔案
>
> `manifest.json` 對 `<arm>.req.log` 簽了 SHA-256,但 `.gitignore` 讓它們根本
> 沒進 repo。**乾淨 clone 拿到的是一份指向不存在檔案的保證** —— 而且機制全程
> 回報成功。修法不只是改 `.gitignore`:`verify_repo.sh` 現在會檢查
> **每一個 manifest 提到的檔案都真的被 git 追蹤**。
>
> 通則:**忽略規則不准蓋過 manifest。**

### 8.5 🔴 「檔案沒被動過」跟「檔案還是對的」是兩件事

08-28 踩到的,而且它比前面兩個更難看見,因為**所有檢查全部通過**。

`bench/data/<run>/` 裡有兩種東西,而它們長得一模一樣:

| | 是什麼 | hash 對得上代表什麼 |
|---|---|---|
| `*.pcap`、`*.decode.txt`、`*.hex.txt` | **證據** —— 當時線上真的發生的事 | 代表全部。證據的意思不會改變 |
| `*.fields.json` | **推導** —— 我們的工具在某個時間點對那份證據的讀法 | **只代表沒被人改過** |

那天 `fields.py` 修掉了一個重複計算的 bug,`message_bytes.total` 從 15,803 變成
11,291。但 repo 裡那份 `walkthrough.fields.json` 還寫著 15,803,而且 **manifest
的 SHA-256 完全對得上** —— 因為沒有人動過那個檔案。

> **雜湊只能告訴你「沒被竄改」,不能告訴你「還是對的」。**
> 對輸入(證據)來說這兩句話一樣;對輸出(推導)來說永遠不一樣。

**修法不是去改那個 JSON,也不是去改 manifest。** 一個可以被重寫的 manifest 什麼
都證明不了,所以這個 repo 沒有「重新蓋章」的機制,也不該有。修法是**重跑一次,
產生一個新的 run**:

```bash
# 1. 先把工作樹弄乾淨(manifest 會記 repo_dirty,乾淨的證據比較值錢)
git status --short          # 應該是空的

# 2. 重跑五臂
bash harness/capture.sh --name w2-baseline
#   -> bench/data/w2-baseline-<新時間戳>/

# 3. 把文件指向新的 run(舊的 run 一個字都不要動,它是歷史)
sed -i 's/w2-baseline-<舊時間戳>/w2-baseline-<新時間戳>/g' \
    docs/handshake-walkthrough.md docs/transports.md docs/upstream/README.md
#   ★ LOG.md 不要改。那裡面是「某天我觀察到什麼」,是日記不是主張。

# 4. 確認文件的數字對得上新的 capture
python3 harness/fields.py --check docs/handshake-walkthrough.md

# 5. 把新 run 加進 git(不然 §8.4 那個「manifest 簽了但沒追蹤」的檢查會紅)
git add bench/data/w2-baseline-<新時間戳>
bash harness/verify_repo.sh
```

`verify_repo.sh` 現在會要求:**文件引用到的每一份 `*.fields.json`,都必須是今天
的 `fields.py` 從旁邊那份 decode 重算得出來的。** 沒被任何文件引用的舊 run 不受
這條約束 —— 它們的 manifest 只保證「沒被動過」,而這個 repo 對它們也只主張這件事。

> ### 意外的收穫:重跑證明了「這些數字是量測,不是抓拍」
>
> 08-28 那次重跑,跟 08-16 那次隔了 11 天、機器重開過、pin 完全一樣:
>
> | 臂 | 封包 | bytes |
> |---|--:|--:|
> | `classical` | 554 | 20,549 |
> | `pqc` | 584 | 114,751 |
> | `classical-stable` | 566 | 20,396 |
> | `walkthrough` | 30 | 11,441 |
> | `single-algo` | 30 | 11,441 |
>
> **每一臂,一個 byte 都沒差。** nonce 跟時間戳當然不一樣,但這個 repo 主張的
> 每一個大小、次數、位移都一樣。**所以那份 08-17 寫的逐欄位文件,128 個 claim
> 全部對得上一份它從來沒看過的 capture。**
>
> 這就是為什麼位元組類的數字報單一值而不報範圍 —— 那不是一個慣例,是一個量到的
> 性質。

**為什麼不乾脆做一個「重新蓋 manifest」的工具?** 因為一個可以被重新蓋章的
manifest 什麼都證明不了,而且那個工具一旦存在,趕時間的時候就一定會用它。完整的
理由、被否決的四個替代方案、以及這件事跟 §8.6 是同一個道理,寫在
[`docs/decisions/0004`](docs/decisions/0004-derivations-must-reproduce.md)。

### 8.6 動過 pin 之後,capability 那張表要重讀

`fields.py` 把 `Flags` 那個 32-bit 數字翻成 `CERT_CAP`、`CHUNK_CAP` 這些名字,
靠的是一張**手抄**自 libspdm `spdm.h` 的表。上游改個名字,這張表會**永遠自洽地
錯下去** —— 沒有任何 capture 會跟它牴觸。

```bash
python3 harness/fields.py --verify-tables \
    ~/spdm-lab/work/spdm-emu-pqc/libspdm/include/industry_standard/spdm.h \
    --write-pin
#   requester: 19 single-bit capabilities in the header, 20 in this file
#   responder: 32 single-bit capabilities in the header, 32 in this file
#   every capability bit in this file has the header's name for it
```

這件事需要上游原始碼,CI 沒有,所以結果被釘進 `third_party/spdm-h.pin`。
`verify_repo.sh` 檢查的是那份 pin:**它記的 libspdm commit,必須跟
`spdm-emu-pqc.pin` 說的「capture 是哪個版本產的」一樣。**

> **所以「換了 pin 卻沒重讀 header」會讓建置變紅。** 這就是 `CLAUDE.md` 那條
> 「改完 pin 就順手 grep 一次舊版本號」,做成了不必靠記憶的東西。

---

## 9. 出問題時:症狀 → 原因 → 解法

| 症狀 | 原因 | 解法 |
|---|---|---|
| `cmake: command not found` | 沒裝 | `sudo apt-get install -y cmake build-essential` |
| clone 卡在 `Cloning into '...wycheproof'` 十幾分鐘 | **正常。** OpenSSL 的測試 submodule 很大 | 開另一個終端機 `du -sh ~/spdm-lab/work/spdm-emu-pqc`,數字在長就等 |
| `No such file or directory: ecp384/...` | **`make copy_sample_key` 沒在 `make` 之前跑** | `bash harness/build_spdm_emu.sh pqc --force` |
| responder 起來就死,log 說找不到憑證 | 從錯的目錄執行 binary | spdm-emu 用**相對路徑**開憑證,必須 `cd` 進 `build/bin/` 再跑。本 repo 的腳本已處理 |
| `--help` 裡沒有 `--pqc_asym` | ① 用了 `-DCRYPTO=mbedtls` ② 用到 `stable` 那份 | **PQC 只有 OpenSSL 後端有。** mbedTLS 完全沒有 ML-DSA/ML-KEM/SLH-DSA |
| 體檢 #7 失敗,但 #4 過 | PQC 沒進來 | 確認 `BUILD_PIN.txt` 裡 `libspdm-version` 是 4.0.0 |
| `Address already in use` | 上次的 responder 沒死乾淨 | `pkill -f spdm_responder_emu`,或 `SPDM_EMU_PORT=2400 bash harness/healthcheck.sh pqc` |
| `bash: line N: $'\r': command not found` | 檔案是 CRLF 換行 | `sed -i 's/\r$//' harness/*.sh`。本 repo 的 `.gitattributes` 已強制 LF |
| 腳本跑到一半噴出「某行註解不是指令」 | **你在腳本執行中途編輯了它** | bash 是邊讀邊執行的,改檔案會讓它讀到錯的位移。等它跑完再改 |
| 握手跑 53 秒、1116 個封包、結束碼 1 | **只砍了 `--exe_conn`,忘了 `--exe_session`** | 兩個都要砍,見 §7 的紅框 |
| 握手 554 個封包,其中 500 多個是 `GET_MEASUREMENTS` 跟 `SPDM_ERROR` | **`--meas_op` 預設 `ONE_BY_ONE`**,requester 從 index 1 掃到 0xFE **兩趟** | 加 `--meas_op ALL` → 30 個封包,而且送的位元組完全一樣(528)。原因見 `docs/handshake-walkthrough.md` §7 |
| 後量子那次的 requester 用了 ML-DSA-**87**,不是我指定的 65 | **`--pqc_asym` 只管 responder 側。** requester 側是 `--req_pqc_asym`,兩個方向分開協商 | 兩個都指定。**沒指定的那個方向就是未控制的變因** |
| 兩份 build 跑同樣的旗標,憑證鏈大小不一樣 | **不是 bug。** `stable`(3.8.0)協商到 SPDM 1.3,沒有 1.4 的 `LargeCert`,所以一次只取 1024 bytes | 這是控制組要回答的問題。每一張表的說明要寫是哪一份 build |
| `fields.py --check` 說 `is not a field this tool computes` | 你在文件裡宣告了一個不存在的欄位名 | `python3 harness/fields.py <decode> --list-keys` 看有哪些鍵。**這個檢查是故意的**——不然可以靠發明欄位名來過關 |
| `spdm_dump` 只解出十幾行就停,最後一行寫 `cert_chain is too larger` | **解碼器的編譯期常數 `LIBSPDM_MAX_CERT_CHAIN_SIZE` 不夠大** | ⚠️ **這不是握手失敗,是解碼器停了。** 後量子憑證鏈約 16.8 KB,超過 spdm_dump 內建上限。要完整解碼得改常數重編 spdm-dump。體檢第 11 項會明確標示這種情況 |
| 用 `| tee` 接 build,結果騙人 | pipeline 的結束碼是**最後一個**指令的 | `set -o pipefail`,或看 `${PIPESTATUS[0]}` |
| build 跑很久而且電腦很卡 | `-j$(nproc)` 吃滿了 | `JOBS=3 nice -n 19 bash harness/build_spdm_emu.sh pqc` |
| WSL 上 build 慢到不合理 | **程式碼放在 `/mnt/c/`** | 編譯樹必須在 `~/`。本 repo 預設就是 `~/spdm-lab` |
| 磁碟滿了 | 兩個 flavor + spdm-dump ≈ 20 GB | `rm -rf ~/spdm-lab/work/spdm-emu-stable`,需要時再 `--seed-from pqc` 重建 |
| QEMU / MCTP 那兩項是 INFO | WSL 核心沒有 `CONFIG_MCTP` | **不影響主線。** 只影響 W09 的真實傳輸實驗 |

### 還是不行?90 分鐘規則

**本機環境搞不定就不要耗第二個晚上。** 把錯誤訊息原文貼進 `LOG.md`,改用 Docker:

```bash
docker build -t spdm-lab docker/
docker run -it --rm -v "$PWD:/repo" -w /repo spdm-lab bash
# 進去之後從 §4 重來
```

Docker 那條路是**釘死版本的**,基底映像用 digest 鎖住。它一定會動。

---

## 10. 基本功:c-drills

```bash
cd c-drills
make            # 全部編譯(-Werror + ASan + UBSan)
make list       # 哪些題存在、哪些做完了
make test       # 只跑 DONE.txt 裡列出來的
```

**這一塊跟整個 repo 一樣重要,而且很多人把兩件事當成同一件。**

這個 repo 量的是「這套系統被建起來、被量過、被想清楚」。
它**不量**「在沒有編譯器可以問的情況下,還能不能一次把 C 寫對」。
**那是另一種能力,它會安靜地退化,而且退化的時候不會有任何測試變紅
——所以要自己把它量出來。**

八題的儀式一律四步,**順序就是全部的價值**:

```
1. 紙筆。什麼都不能開。在時間盒內寫完。
2. 手動 dry-run 兩組測資,其中一組必須是邊界。
3. 原封不動打進電腦。★ 記下編譯錯誤幾個 → 寫進 SCORECARD.md
4. make test 全綠,含 sanitizer。
```

**第 3 步是量測。** 那個數字應該從 5~8 掉到 0~1。掉不下來,代表你是開著編輯器
在做這些題,那就沒有在練要練的那件事。

細節見 [`c-drills/README.md`](c-drills/README.md) 和
[`c-drills/SCORECARD.md`](c-drills/SCORECARD.md)。

---

## 11. 每天怎麼用這個 repo

```bash
# 一、開工前確認環境還在
bash harness/doctor.sh

# 二、做事(跑實驗、改東西)

# 三、每次有結果就記錄,commit 用上游格式
git add -A
git commit -s -m "meas: make the SVN configurable instead of hard-coded

<空一行,正文每行 72 字元以內,寫「為什麼」不是「改了什麼」>

Tested: <你怎麼驗證的>
"
```

`-s` 會加上 `Signed-off-by:`。**從第一個 commit 就用上游格式**,因為之後要送
Gerrit,現在練起來那時候不用重學。

### `LOG.md` 是這個 repo 裡最難重建的檔案

不是 README。README 可以從結果反推出來,`LOG.md` 不行——
它記的是還不知道答案的當下,是怎麼決定下一步的。

每一則要有五段:**現象 / 假設 / 先驗哪個、為什麼 / 根因 / 教訓**。

> ★ 「先驗哪個、為什麼」這一行是整個格式的重點。
> 「先驗 A,因為它最便宜而且能一次砍掉一半的可能性」是一個可以被檢查的決策;
> 「一個一個試」不是。前者能讓下一個人重用,後者只能讓下一個人重跑一次。

---

## 12. 把一切從零重建(驗證可重現性)

**這一節是這份 runbook 的驗收條件。** 每隔一段時間跑一次,確認它沒有腐爛。

```bash
# 1. 砍掉所有建置產物(repo 本身不動)
rm -rf ~/spdm-lab

# 2. 從乾淨的 clone 開始
cd /tmp && rm -rf verify && git clone https://github.com/Jhongwe1/mctp-spdm-pqc.git verify
cd verify

# 3. 完整重來
bash harness/doctor.sh
bash harness/build_spdm_emu.sh pqc
bash harness/build_spdm_emu.sh stable --seed-from pqc
bash harness/healthcheck.sh pqc --write-baseline

# 4. 對照:新的 BUILD_PIN 應該跟 repo 裡釘的一樣
diff <(grep libspdm= ~/spdm-lab/work/spdm-emu-pqc/BUILD_PIN.txt) \
     <(grep libspdm= third_party/spdm-emu-pqc.pin) && echo "PINS MATCH"
```

**如果 `PINS MATCH` 沒印出來**,代表上游動了。這不是壞事,是資訊——
把新舊 hash 記進 `LOG.md`,那就是「這塊變動很快,所以我引用任何行為之前
都直接讀 repo 當下的狀態」這句話的證據。

---

## 附錄 A · 指令速查

```bash
# ── 環境 ────────────────────────────────────────────────
bash harness/doctor.sh                        # 只檢查,不動任何東西

# ── 建置 ────────────────────────────────────────────────
bash harness/build_spdm_emu.sh pqc            # libspdm 4.0.0-rc
bash harness/build_spdm_emu.sh stable --seed-from pqc   # 3.8.0,不重新下載
bash harness/build_spdm_emu.sh pqc --force    # 砍掉重建
bash harness/build_spdm_dump.sh               # 離線封包解析器
JOBS=3 nice -n 19 bash harness/build_spdm_emu.sh pqc    # 與別的工作共用機器

# ── 體檢 ────────────────────────────────────────────────
bash harness/healthcheck.sh pqc
bash harness/healthcheck.sh pqc --write-baseline        # 順便更新 docs/env-baseline.md
bash harness/healthcheck.sh stable

# ── 收證據(★ 五臂,有出處)────────────────────────────
bash harness/capture.sh                       # 預設 --name w2-baseline
bash harness/capture.sh --name g2-tamper      # 之後的實驗換個名字

# ── 分析:封包層 ────────────────────────────────────────
python3 harness/pcapcount.py <file>.pcap
python3 harness/pcapcount.py <file>.pcap --json
python3 harness/pcapcount.py <file>.pcap --list         # 每個封包一行

# ── 分析:協定欄位層(★ 實際協商到什麼)──────────────────
python3 harness/fields.py <run>/walkthrough.decode.txt
python3 harness/fields.py <run>/walkthrough.decode.txt --json
python3 harness/fields.py <run>/walkthrough.decode.txt --list-keys   # 可以宣告的鍵
python3 harness/fields.py --check docs/handshake-walkthrough.md      # ★ CI 也跑這個

# ── 動過 third_party/*.pin 之後一定要跑(見 §8.6)────────
python3 harness/fields.py --verify-tables \
    ~/spdm-lab/work/spdm-emu-pqc/libspdm/include/industry_standard/spdm.h \
    --write-pin

# ── 手動解碼 ────────────────────────────────────────────
~/spdm-lab/work/spdm-dump/build/bin/spdm_dump -r <file>.pcap         # 摘要
~/spdm-lab/work/spdm-dump/build/bin/spdm_dump -r <file>.pcap -a      # 全欄位
~/spdm-lab/work/spdm-dump/build/bin/spdm_dump -r <file>.pcap -x      # 十六進位

# ── 手動跑一次握手 ──────────────────────────────────────
cd ~/spdm-lab/work/spdm-emu-pqc/build/bin        # ★ 一定要 cd 進來
#                                    ★★ 兩個旗標都要砍,見 §7
./spdm_responder_emu --exe_conn DIGEST,CERT,CHAL,MEAS --exe_session NO_END &
./spdm_requester_emu --exe_conn DIGEST,CERT,CHAL,MEAS --exe_session NO_END \
                     --pcap /tmp/x.pcap
pkill -f spdm_responder_emu                       # 收工

# ── 後量子(★ --req_pqc_asym 一定要一起釘,見 §8.1)──────
./spdm_responder_emu --exe_conn DIGEST,CERT,CHAL,MEAS --exe_session NO_END \
    --asym NONE --dhe NONE \
    --pqc_asym ML_DSA_65 --req_pqc_asym ML_DSA_65 \
    --kem ML_KEM_768 --pqc_first TRUE &
./spdm_requester_emu --exe_conn DIGEST,CERT,CHAL,MEAS --exe_session NO_END \
    --asym NONE --dhe NONE \
    --pqc_asym ML_DSA_65 --req_pqc_asym ML_DSA_65 \
    --kem ML_KEM_768 --pqc_first TRUE \
    --pcap /tmp/pqc.pcap

# ── 把 526 個封包砍掉(★ 第三個旗標,見 §8)───────────────
./spdm_requester_emu --exe_conn DIGEST,CERT,CHAL,MEAS --exe_session NO_END \
    --meas_op ALL --pcap /tmp/small.pcap        # 554 個封包 → 30 個

# ── 讀出「實際協商到什麼」(不是你要求什麼)★ ────────────
~/spdm-lab/work/spdm-dump/build/bin/spdm_dump -r /tmp/x.pcap | grep ' SPDM_ALGORITHMS'
~/spdm-lab/work/spdm-dump/build/bin/spdm_dump -r /tmp/x.pcap | grep -m1 SPDM_VERSION

# ── 基本功 ──────────────────────────────────────────────
cd c-drills && make test

# ── 環境變數 ────────────────────────────────────────────
LAB_DIR=/somewhere/else    # 編譯樹放哪(預設 ~/spdm-lab)
JOBS=3                     # 平行編譯數(預設 nproc)
SPDM_EMU_PORT=2400         # 換 port(預設 2323)
```

---

## 附錄 B · 詞彙表

| 詞 | 意思 |
|---|---|
| **SPDM** | Security Protocol and Data Model。DMTF 訂的協定,讓一顆晶片能驗證另一顆晶片的身分與韌體狀態 |
| **DMTF** | Distributed Management Task Force。訂 SPDM、MCTP、PLDM、Redfish 的標準組織 |
| **Requester** | 發問的一端。真實系統裡通常是 BMC |
| **Responder** | 回答的一端。網卡、SSD、GPU,或一顆專門的信任根晶片 |
| **BMC** | Baseboard Management Controller。伺服器裡一顆獨立的小電腦,負責管理整台機器,主機關機時它還活著 |
| **RoT / ERoT** | Root of Trust / External RoT。一顆專門做安全驗證的晶片,信任鏈的起點 |
| **Attestation(證明)** | 一個裝置向外證明「我是誰、我身上跑什麼」的過程 |
| **Measurement(量測值)** | 韌體或設定的雜湊值。SPDM 負責把它安全地送過來,**但不負責判斷它對不對** |
| **CHALLENGE** | Requester 丟一個亂數,Responder 用私鑰簽回來。防重放攻擊 |
| **MCTP** | Management Component Transport Protocol。SPDM 在真實硬體上的載體(跑在 I2C/SMBus/PCIe 上) |
| **PQC** | Post-Quantum Cryptography。抗量子電腦攻擊的密碼學 |
| **ML-DSA** | 後量子**簽章**演算法(原名 Dilithium),FIPS 204 |
| **ML-KEM** | 後量子**金鑰封裝**演算法(原名 Kyber),FIPS 203 |
| **RATS** | Remote ATtestation procedureS。IETF 的證明架構(RFC 9334),定義了 Attester / Verifier / Relying Party 等五個角色 |
| **CoRIM** | 描述「參考值應該長怎樣」的標準格式 |
| **pcap** | 封包錄影檔。本專案所有證據的原始格式 |
| **libspdm** | DMTF 的 SPDM 參考實作(C 語言) |
| **spdm-emu** | 用 libspdm 做的 requester/responder 模擬器,兩個行程透過 TCP 對話 |
| **spdm-dump** | 把 pcap 逐欄位解開的工具 |
| **flavor** | 本專案的術語:一份釘死版本的 build。目前有 `stable`(spdm-emu 3.8.0)和 `pqc`(spdm-emu 4.0.0-rc);libspdm 跟著各自的 submodule 指標走 |
| **provenance / manifest** | 出處紀錄。每次實驗自動產生的 `manifest.json`,含上游 hash、完整指令列、每個檔案的 SHA-256 |
