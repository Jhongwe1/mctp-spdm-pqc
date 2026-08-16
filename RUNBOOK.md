# RUNBOOK · 從零到跑出第一份 SPDM 握手封包

這份文件的目標只有一個:**任何人照著做,都會得到跟這個 repo 一樣的結果。**

「任何人」包含三個月後已經忘光的你,也包含沒碰過韌體、沒聽過 SPDM 的高中生。
所以每一步都會寫三件事:**指令是什麼、成功長什麼樣、失敗了怎麼辦。**

不需要事先懂 SPDM。§0 有五分鐘的背景,§7 有詞彙表。

---

## 目錄

| § | 內容 | 需要時間 |
|:--|---|---|
| [0](#0-你正在建什麼五分鐘) | 你正在建什麼 | 讀 5 分 |
| [1](#1-你需要什麼) | 你需要什麼 | — |
| [2](#2-準備一台-linuxwindows-使用者看這裡) | 準備一台 Linux(Windows 看這裡) | 15 分 |
| [3](#3-取得-repo-並檢查機器) | 取得 repo 並檢查機器 | 2 分 |
| [4](#4-建置-30-分鐘大部分在下載) | 建置 | 30 分 |
| [5](#5-體檢跑出第一份封包) | 體檢:跑出第一份封包 | 2 分 |
| [6](#6-剛剛到底發生了什麼) | 剛剛到底發生了什麼 | 讀 10 分 |
| [7](#7-出問題時症狀--原因--解法) | 出問題時:症狀 → 原因 → 解法 | 查表 |
| [8](#8-基本功c-drills) | 基本功:c-drills | 每週 |
| [9](#9-每天怎麼用這個-repo) | 每天怎麼用這個 repo | — |
| [10](#10-把一切從零重建驗證可重現性) | 把一切從零重建 | 40 分 |
| [附錄](#附錄-a-指令速查) | 指令速查、詞彙表 | 查表 |

---

## 0. 你正在建什麼(五分鐘)

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

## 1. 你需要什麼

| 項目 | 需求 | 備註 |
|---|---|---|
| 作業系統 | **Linux**(Ubuntu 24.04 已驗證) | Windows 看 §2,macOS 用 Docker |
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

需要的軟體(§3 的 `doctor.sh` 會逐項幫你檢查):

```
git   cmake(≥3.10)   make   gcc   python3   perl
```

---

## 2. 準備一台 Linux(Windows 使用者看這裡)

Windows 上有兩條路。**推薦 WSL2**,因為它快,而且就是本 repo 驗證過的環境。

### 2A · WSL2(推薦)

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

### 2B · Docker(macOS,或不想裝 WSL)

```bash
docker build -t spdm-lab docker/
docker run -it --rm -v "$PWD:/repo" -w /repo spdm-lab bash
```

進去之後 §3 之後的步驟完全一樣。

---

## 3. 取得 repo 並檢查機器

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

## 4. 建置(30 分鐘,大部分在下載)

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

`--seed-from pqc` 會直接複製第一份的原始碼樹,**完全不重新下載**,只把
libspdm 換到 `3.8.2` 再編一次。省下 20 分鐘和 2.5 GB。

<details>
<summary><b>為什麼要兩份 build?</b></summary>

後量子演算法是 **2026-08-04** 才進 libspdm 主線的,而且 `4.0.0` 目前是
**release candidate**。

**我不想讓一個 RC 當我的基準線。** 所以:

| flavor | libspdm | 用途 |
|---|---|---|
| `stable` | 3.8.2 | 所有 baseline 量測 |
| `pqc` | 4.0.0-rc | 只跑後量子實驗 |

兩份的 commit hash 都釘在 `third_party/*.pin`,每一張表的 caption 都會寫是
哪一份跑出來的。完整理由見 `docs/decisions/0001-two-build-flavors.md`。
</details>

---

## 5. 體檢:跑出第一份封包

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

## 6. 剛剛到底發生了什麼

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

它會把每一個訊息逐欄位印出來。**這就是 W02 要做的事:把每一個欄位講清楚。**

---

## 7. 出問題時:症狀 → 原因 → 解法

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
| 握手跑 53 秒、1116 個封包、結束碼 1 | **只砍了 `--exe_conn`,忘了 `--exe_session`** | 兩個都要砍,見 §6 的紅框 |
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
# 進去之後從 §3 重來
```

Docker 那條路是**釘死版本的**,基底映像用 digest 鎖住。它一定會動。

---

## 8. 基本功:c-drills

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

## 9. 每天怎麼用這個 repo

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

## 10. 把一切從零重建(驗證可重現性)

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
bash harness/build_spdm_emu.sh stable --seed-from pqc   # 3.8.2,不重新下載
bash harness/build_spdm_emu.sh pqc --force    # 砍掉重建
bash harness/build_spdm_dump.sh               # 離線封包解析器
JOBS=3 nice -n 19 bash harness/build_spdm_emu.sh pqc    # 與別的工作共用機器

# ── 體檢 ────────────────────────────────────────────────
bash harness/healthcheck.sh pqc
bash harness/healthcheck.sh pqc --write-baseline        # 順便更新 docs/env-baseline.md
bash harness/healthcheck.sh stable

# ── 分析 ────────────────────────────────────────────────
python3 harness/pcapcount.py <file>.pcap
python3 harness/pcapcount.py <file>.pcap --json
python3 harness/pcapcount.py <file>.pcap --list         # 每個封包一行
~/spdm-lab/work/spdm-dump/build/bin/spdm_dump -r <file>.pcap

# ── 手動跑一次握手 ──────────────────────────────────────
cd ~/spdm-lab/work/spdm-emu-pqc/build/bin        # ★ 一定要 cd 進來
#                                    ★★ 兩個旗標都要砍,見 §6
./spdm_responder_emu --exe_conn DIGEST,CERT,CHAL,MEAS --exe_session NO_END &
./spdm_requester_emu --exe_conn DIGEST,CERT,CHAL,MEAS --exe_session NO_END \
                     --pcap /tmp/x.pcap
pkill -f spdm_responder_emu                       # 收工

# ── 後量子 ──────────────────────────────────────────────
./spdm_responder_emu --exe_conn DIGEST,CERT,CHAL,MEAS --exe_session NO_END \
    --asym NONE --dhe NONE \
    --pqc_asym ML_DSA_65 --kem ML_KEM_768 --pqc_first TRUE &
./spdm_requester_emu --exe_conn DIGEST,CERT,CHAL,MEAS --exe_session NO_END \
    --asym NONE --dhe NONE \
    --pqc_asym ML_DSA_65 --kem ML_KEM_768 --pqc_first TRUE \
    --pcap /tmp/pqc.pcap

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
| **flavor** | 本專案的術語:一份釘死版本的 build。目前有 `stable`(3.8.2)和 `pqc`(4.0.0-rc) |
| **provenance / manifest** | 出處紀錄。每次實驗自動產生的 `manifest.json`,含上游 hash、完整指令列、每個檔案的 SHA-256 |
