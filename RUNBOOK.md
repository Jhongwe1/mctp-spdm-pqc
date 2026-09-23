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
| **現在做到哪裡?** | ★★★ **W12 收工(2026-09-23)。G8 開始了,G7 收到第一個 −1。** ① **README 重寫**:1,214 行砍到約 500 行,第一屏依序是範圍聲明 → CI badge → upstream 連結 → Table 1 → 五分鐘驗證 → 指令;十一週的週記**原封不動**搬到 `docs/progress.md`(拿掉連結後逐字相同,是用程式比出來的)。★ **README 上每一個跨 capture 的數字現在都掛了 `<!--xclaim-->` 標記,CI 會拿它跟 `bench/claims.json` 對**——以前 CI 驗的是 claims.json 對不對,沒有人驗 README 抄得對不對。② `docs/threat-scope.md` 補上「SPDM 防得了什麼、防不了什麼、那要靠什麼」;`docs/limitations.md` 從骨架寫完,六層、每一條標明是「沒做」還是「限制」。③ ★★★ **寫 README 的時候抓到這個 repo 自己的一個大錯**:七份文件、外加一支工具的判定理由,都說「這個專案從來沒有建立過 secure session」。但 152 份 committed capture 裡有 **20 份從來沒人 decode 過**,其中兩份就有完整的 session——一份是 DMTF 一致性測試的 no-mut-auth 那一臂,另一份是 **README 自己拿來當反例的第一週那次失敗 run**(SPDM 1.4、雙向認證、552 筆加密封包)。**「所有 capture 都沒有」其實只是「我讀過的 capture 都沒有」。** 現在 `harness/census.sh` 會讀全部 152 份,`verify_repo.sh` 在有 capture 沒被任何東西讀過時變紅(standing rule 21)。④ `openbmc/spdm` 94773 收到 owner 的 −1,理由是讀起來像 AI 產生、浪費人的時間的文件;回頭稽核 PS1,**這個 change 存在的理由(GCC 13 的 ICE、測試要 `dbus-run-session`)根本沒寫進送出去的檔案**。PS2 已備好(59 行,每個指令當天重跑過),**簽 DCO 跟推送是你的**,三個指令在 `docs/upstream/0002-openbmc-readme.md` §11。以下是 W12 之前的內容。★★★ **上游收到第一則審查了(2026-09-22,推出去後 35 分鐘)** —— `openbmc/spdm` 94773:CI `Verified+1`,然後 Chinmay Shripad Hegde 留了兩則 inline 留言,**兩則都不是修改要求**。他還主動把 80422 的原作者 Ratan Gupta 加進來;到 11:10 UTC,`OWNERS` 上六個人全在這個 change 上,**包括當年打回 80422 的 Patrick Williams**。兩則當天回完、**沒有推 patchset 2**(沒人要求改,而剛加進來的人還沒開口,一次改完比改兩次好)。`DMTF/spdm-emu` #524 目前 DCO 綠、無人回覆。以下是同一天稍早的內容。★★★ **上游兩筆都送出去了(2026-09-22)** —— [`DMTF/spdm-emu` #524](https://github.com/DMTF/spdm-emu/pull/524) 與 [`openbmc/spdm` 94773](https://gerrit.openbmc.org/c/openbmc/spdm/+/94773)。G7 從「備好、沒送」變成「送了、等回覆」。★★ **貼著送出那一刻做的新鮮度檢查,兩次都改變了送出去的東西**:`spdm-emu` 的 main 當天又動了一個 commit,所以分支 rebase 了第二次,並且用 `patch-id`、blob、392 行 CRLF 三個量證明那兩行改動一個位元組都沒變;`openbmc/spdm` 那邊 **prettier 與 markdownlint 從這台機器上消失了**,重裝回釘住的版本才敢把 `Tested:` 再講一次。★ 而 `0002` 文件裡自己寫的送出指令是錯的——`git push origin`,但那棵樹的 `origin` 是 GitHub 唯讀鏡像不是 Gerrit,Gerrit 的 remote 根本還沒建。★★★ **同一天也把日期整理了**:`LOG.md` 等 18 份檔案裡 31 個計畫週曆日期(10-12 / 10-19 / 10-25)改成真實日期(09-20 / 09-22),因為參照物 `plan/` 永遠不會推上 GitHub,而讀者跑得到的 `git log` 跟它差 22–27 天(ADR 0012)。並且加了一條 CI 檢查:**`LOG.md` 每一則的日期,那天必須真的有 commit** —— 拿修正前的狀態餵它,它剛好在那兩則上變紅。以下是 W11 收工的內容。★★★ **W11 收工(2026-09-22)。Gate 6 關掉了** ——計畫給了四個通報編號，W10 一個都不寫進程式碼（standing rule 7：**沒查過原始來源的一律不引**）。W11 去查了，**四個都是對的**——但查這件事本身挖出三件「不查就會講錯」的事：① 三個都**不在 GitHub 的全域 advisory 資料庫裡**，`github.com/advisories/GHSA-…` 那個人會先點的網址 **三個全部 404**；② 三個裡面 **兩個根本沒有 CVE**，而且沒 CVE 的那兩個分數**更高**（6.9 對 6.0）——DMTF-2026-0001 自己寫的理由是「實際裝置上實作到的機率低」，**所以 CVE 是一個關於部署的判斷，不是分數門檻**；③ 唯一那個 CVE（CVE-2026-61810）**NVD 查不到、MITRE CVE Services 也 404**。★★ 而且 `DSP0274 1.4.1` 現在抱得到了（計畫說可能抱不到），所以第三個通報——一個**規格的漏洞，不是程式的**——可以把兩個版本的 PDF 摄下來對照：`[FINISH].SPDM Header Fields` 這句話在 **1.4.0 出現五次、1.4.1 出現零次**，五次正好是通報說的五個定義。★★★ **修正不是補一個欄位，是換一種寫法**：1.4.0 列舉「要放進來的部分」，1.4.1 改成「除了簽章本身以外全部」。而且那個列舉寫的時候是對的——SPDM 1.3 的 FINISH 就是四個 byte 的 header 加簽章，**它是在別人改了另一章的 Table 80 之後才變錯的**（§11.10）。**三個類別寫成了測試**：24 個 case 對 **21 個故意寫錯的實作**，每個錯誤都要**事先宣告它會動到哪幾個 case**，動得太少（rule 11）跟動到沒人預測的（rule 13）一樣算失敗。它當天就抓到我一個預測錯誤。★ 寫這三個測試學到三件讀文章學不到的：**同一行錯的程式在 32-bit 欄位是漏洞、在 16-bit 只是拒錯理由**（integer promotion）；**ASan 看得到裸陣列溢出、看不到同一個 struct 裡溢到下一個成員**（這句是跑出來的，不是背的）；以及**讀上游真正的 patch 才發現 W10 定的狀態碼根本說不出那個錯誤**（檢查在複製之後才跑，回傳值是對的，記憶體已經沒了）。★★ **而且我去量了自己的 build 有沒有這三個洞**，五個独立的判準、兩條互相印證的路徑：`pqc` 那支兩個修正都有；`stable`（libspdm 3.8.0）**AFFECTED**，而且最后一個先決條件不是程式錯——`libspdm_copy_mem()` 確實有檢查 `src_len > dst_len`，但它寫成 `LIBSPDM_ASSERT`，而 `TARGET=Release` 會 `-DLIBSPDM_DEBUG_ENABLE=0`，**那個宏展開成空白，下面的複製迴圈照跑**（§11.11）。注意：這不影響這個 repo 任何一個數字，因為要踩到它得送 `GET_MEASUREMENT_EXTENSION_LOG`，**而所有 committed capture 裡一次都沒送過**（這句也是程式從 decode 算出來的）。CI 多了第五個 job `upstream`，**每週跑一次而不是每次 push**（理由寫在 ci.yml 裡）。以下是 W10 收工(2026-09-20)的內容。**Gate 6 開了一半** ——**DMTF 官方的一致性測試跑了四次**,不是一次。一次只會告訴你這台裝置怎麼樣,四次才說得出這支測試本身看得見什麼:其中一臂把一個 capability 位元關掉,**611 個 assertion 從「沒跑過」變成「跑過」**;另一臂把一個簽章的最後一個 byte 在飛行中翻掉,**要求恰好一個 assertion 變 FAIL,而且是名字叫 `response signature` 的那一個**。★ 最硬的一件:那支官方測試報的四個 `response signature` 失敗,**是它自己的 test case 把驗簽要用的憑證鏈丟掉了** —— 這不是推理,是把 M1M2 從 capture 重建、用葉憑證的公鑰驗過的(§11.9)。fuzz 與覆蓋率也做完了,而且**把原本要講的那句話撤掉了**:我的種子在 8 個 target 裡有 3 個比上游手寫的還差。以下是 W09 收工(2026-09-18)的內容。**Gate 5 關掉了** ——**兩條真實傳輸都跑通**:古典與後量子兩臂的握手整條走 **真的 Linux MCTP 網路**(真 EID、真路由表、kernel 配的 tag、64 bytes 的真分段),**953 個後量子封包對 115 個古典封包,是數出來的不是除出來的**;另一條是**真的 PCIe DOE 信箱**,一則 `GET_VERSION` 穿過 config space 拿到 `VERSION`。宿主的 kernel 一個位元組都沒動(`ADR 0010`)。★ 順便發現一件這個 repo publish 了三週的事是錯的:177 bytes 那個「判別案例」其實判別不了任何東西,因為 `59 × 3 = 177`(§11.8)。以下是 W08 收工(2026-09-14)的內容。**G1／G2／G3 完成**(逐欄位文件、三層鏈、**Table 1** 十條受控臂、篡改必被判 FAIL 的 CI、版本規則從「完全相等」改成「不低於參考值」而且用凍結的舊政策證明只有一格動,§11.6)。★★ **G4 完成**:六組演算法排成**三組對齊的比較**,**協商本身在六組裡是逐位元組相同的 152 bytes**(後量子一個位元組都不花在「談定演算法」上),**表裡每一個簽章長度都是從訊息長度差算出來的,而且六個全部剛好等於 FIPS 的常數**,以及 `DataTransferSize` 掃 32 倍範圍:**位元組動 3.1%、來回次數 59 → 0**(§11.7、`docs/pqc-cost.md`)|
| ★ 一句話成果(W01) | 「我以為我跑的是最小握手。我砍了 `--exe_conn`,**但漏了 `--exe_session`,它的預設值有 14 項** —— 1116 封包、53 秒、結束碼 1。教訓是:**結束碼不是判決**,同一天有三個工具回答了稍微不同的問題」 |
| ★★ 一句話成果(W02 · 主) | 「我把 554 個封包的『最小握手』砍到 **30** 個,而且證明被砍掉的 526 個封包送的是**完全相同的 528 個位元組** —— 263 趟來回 vs **1 趟**。兩個 528 都是腳本從兩份不同的 capture 各自算出來的」 |
| ★★ 一句話成果(W02 · 機制) | 「逐欄位文件裡的每一個數字都寫成 `<!--claim key=value-->`,`fields.py --check` 從 capture 重新算一次。**當時 128/128 通過(W03 之後是 164/164),而且我證明過它會紅**:數字漂一個位元、欄位名寫錯、capture 不見 —— 三種都會讓建置失敗」 |
| ★★ 一句話成果(W02 · 位移) | 「**值可以重算,位移不行** —— 解碼器印欄位不印位置。所以我改成把整則訊息重建一次,要求剩下的位元組**剛好等於協商到的簽章長度**,再用 `RequesterContext` 的回音當第二條式子。兩個未知數、兩條獨立式子,**多出來的那一條才是讓 capture 有能力說『你排錯了』的東西**。它順便解掉一個文件原本答不出來的問題」 |
| ★★ 一句話成果(W02 · 可重現) | 「同樣五臂、同樣的 pin、隔 11 天重跑,**每一臂一個 byte 都沒差**(554/20549、584/114751、566/20396、30/11441、30/11441)。所以那份 08-17 寫的文件,128 個 claim 全部對得上一份它從沒看過的 capture。**位元組類報單值不報範圍,現在是量到的性質,不是慣例**」(08-31 第三次重跑,還是一樣) |
| ★★★ 一句話成果(W03 · 主) | 「我產了一條自己簽的三層憑證鏈。`check_chain.py` **在握手之前**從磁碟上的檔案算出它上線會是 `4 + 48 + (504+573+768) = 1897` bytes;跑完之後 `fields.py` 從 capture 讀出 **1897**,而且它從頭到尾沒開過任何一個憑證檔。**兩個工具沒有共用任何輸入。**」 |
| ★★★ 一句話成果(W03 · 那個發現) | 「然後我發現我以為換掉了『憑證鏈』,實際上只換掉**三分之一**。同一次握手上有**三個不同的信任錨**:我的在 responder slot 0、上游的 ecp384 root 在 slot 4、上游的 rsa3072 root 給 requester —— 因為 SPDM 兩個方向的簽章演算法是分開協商的,而範例程式是用協商結果去選憑證目錄的。**握手會成功,每個簽章都會過,流程裡沒有任何地方會說用的是哪個錨。**」 |
| ★★ 一句話成果(W03 · 一手資料) | 「計畫書叫我在 leaf 憑證放 PCIe 的 OID `2.23.147`。我去查了:那個字串在 DSP0274 1.4.0 的 306 頁裡出現 **0 次**,在 libspdm/spdm-emu 原始碼裡也 **0 次**。規格自己定義的是 `1.3.6.1.4.1.412.274.1`,格式是 `Manufacturer:Product:SerialNumber`,而那也正是參考實作真的在送的那個。**兩個都放,但只有一個被標成『已查證』** —— PCIe 的規格要會員資格,我沒讀過」 |
| ★★ 一句話成果(W02 · 稽核) | 「我回頭稽核 W01,發現**三個機制缺陷,而且三個都在報告成功**:`manifest.json` 對 12 個被 `.gitignore` 擋掉的檔案簽了 SHA-256;`repo_dirty` 永遠是 `true`(因為先 `mkdir` 才問 git);解碼器 `spdm-dump` 從來沒被釘版本。全修,而且各補一條 CI 檢查」 |
| ★ 反直覺的一個發現 | 「**多提供幾個演算法不會讓 `NEGOTIATE_ALGORITHMS` 變大。** 提供 1 個和提供 4 個都是 **56 bytes**,因為那些欄位是固定寬度的位元遮罩。多提供的代價不是頻寬,是**你在讀回 `ALGORITHMS` 之前不知道會用哪個**」 |
| Claude Code 從哪開? | **`C:\Users\Key20\Desktop\mctp-spdm-pqc`** |
| 程式碼在哪? | repo 就在上面那個路徑;**上游原始碼與 build tree 在 WSL 的 `~/spdm-lab/`(ext4),絕不放 `/mnt/c`** |
| GitHub | <https://github.com/Jhongwe1/mctp-spdm-pqc> |
| 今天要做什麼? | **① 推 94773 的 PS2。** 三個指令都是你的,在 `docs/upstream/0002-openbmc-readme.md` §11:先 `git commit --amend -s --no-edit` 簽 DCO(OpenBMC 的 AI 政策寫明 AI 不得替人加 `Signed-off-by`),跑一次檢查,再 push。然後用**你自己的話**留一則最多四行的留言。**② 找一個不懂 SPDM 的人看 README 第一屏 90 秒**,問他三題:這在做什麼?你相信裡面的數字嗎、為什麼?他沒做什麼?第二題答不出「因為 CI 會驗」,第一屏就算失敗。**③ `c-drills`**:W12 的基本功是手寫重寫 D3/D4/D5/D7,八題目前還是零題完成。**④ W13**:專案題目三條 bullet、demo、一頁紙。以下是 W12 之前的版本:**① 按送出,而且現在有兩個。** `openbmc/spdm` 的 README (Gerrit,`docs/upstream/0002-openbmc-readme.md`)與 DMTF 的 CoRimTool 修正(GitHub,`docs/upstream/0001-corim-verify.md`)。兩份都備到只差一個指令,**送之前都要再查一次那個缺口還在不在**。**② `c-drills`,它現在是唯一一件急的,而且比上週更急。** 舊版的 ① 是:**① 按送出。** 第一個 upstream patch 已經備好、驗過、還沒送:`docs/upstream/0001-corim-verify.md` §7 有指令。送之前再搜一次有沒有人提過 **② `c-drills`,而且它現在是唯一一件急的。** **八**題有合約有測試、**零**題完成:`d3`、`d1`、`d5`、`d6`、`d4`、`d2`、`d7`、`d8`。**實作永遠是你的**,`verify_repo.sh` 會把「八比零」印出來。D8 多要一句:寫下**為什麼回傳值是「想複製幾個」而不是「複製了幾個」** ③ `LOG.md` 最後那幾行 `TODO(me)`,尤其是「我現在最不確定的是 ___」 ④ **W09:真實傳輸(Gate 5)。先跑那兩個前置檢查** —— `qemu-system-x86_64 -device nvme,help | grep -i spdm` 與 `zcat /proc/config.gz | grep CONFIG_MCTP`。**兩個現在都是紅的**(沒裝 qemu、kernel 沒有 CONFIG_MCTP),所以 Gate 5 要嘛裝東西、要嘛照實降級,而在那之前 MCTP 分段數一律標 `[computed]`(`docs/fragmentation.md`)|
| 專案那軌 vs 基本功那軌 | 🔴 專案 **超前**;**基本功欠八題,`SCORECARD.md` 八列全空,`DONE.txt` 連續第九個工作天是空的。這是這個 repo 目前最大的缺口,而且它現在的形狀變了 —— 專案那軌不只是跑在前面,它在幫一個從來沒開始的軌道製造工作** —— repo 量的是「這個系統怎麼運作」,`SCORECARD.md` 是**唯一一個量「我」的東西**。面試時 repo 讓你進到白板前面,白板上考的是 D1~D8 |
| ⚠️ W08 之後仍然存在的障礙 | **一個專案裡兩個 OpenSSL。** libspdm 自己編 submodule 那份(**3.5.5**,PQC 就是它做的);系統的 `openssl` 是 3.0.13,`openssl list -signature-algorithms \| grep ml-dsa` 回空,所以**要簽自己的 PQC 憑證那條是紅的**。★ 2026-09-14 補上的不是這件事——這一行從 W07 就在這裡了——補上的是**機制**:在那之前 `manifest.json` 只記系統那個 3.0.13,每一份 pin 只寫 `crypto=openssl`。**知道一件事,跟有東西把它記下來,是兩件事。** 現在 `crypto-openssl-vendored` 與 `crypto-openssl-version` 在三份 pin 裡,而且是用 `--pin-only` 補的,沒有重新編譯 |
| 我最該先讀哪一段? | 想知道握手每個欄位在幹嘛 → [`docs/handshake-walkthrough.md`](docs/handshake-walkthrough.md);想知道 `--trans MCTP` 為什麼不是真的 MCTP → [`docs/transports.md`](docs/transports.md);想知道踩過哪些坑 → `LOG.md`;想知道數字憑什麼可信 → 本檔 §6 的 `manifest.json` 那段 |
| ⚠️ 三個一定要記住的 | ① **綠 ≠ 有在保護我 —— 但這一條在 09-12 變了一半。** 那個真正該綠的 `rats` job(斷言「篡改過的量測必須被判 FAIL」)**現在存在了**,它是三個 job 裡唯一一個會因為安全性質失效而變紅的。**還沒被保護的是**:`upstream` job 在 W11 建出來了,但它**每週跑一次、不是每次 push**(它建的是別人的程式碼,二十分鐘,而且上游改個 tag 就會紅——**一個會因為別人手滑而變紅的 badge,會訓練人忽略它**);`rats` job 斷言的是「這十條臂的判定必須是這些答案」,不是「這個政策抓得到所有壞東西」;而 `t3b_foreign` 那條——對的量測、錯的憑證來源——兩層都判 PASS,因為身分不在這個政策的職責裡。**沒裝 `opa` 的機器跑 `verify_repo.sh` 會直接紅**,不會靜靜跳過(2026-09-13 拿掉 PATH 實測過)。09-14 之後多了兩件被保護的事:**版本規則的四案例表**(八格只有一格可以動)、以及 **`bench/claims.json` 裡每一個跨 capture 的比值**(容差 0%,拿掉一個位元組就紅)。W11 再多兩件:**21 個故意寫錯的實作,每一個都要被它自己宣告的那幾個 case 抓到**;以及 **`docs/advisories.md` 的六個判定必須是從證據重算出來的**,而且那支工具自己有 selftest,能證明它**答得出 NOT-AFFECTED 以外的答案**——一個永遠回「沒事」的判定工具,跟沒有判定工具是一樣的<br>② **結束碼不是判決**,看封包數、看 log 的 error 行、看解出來的欄位<br>③ **解碼短 ≠ 握手短**。`spdm_dump` 的憑證鏈上限是 **4096 bytes**(量出來的,不是查表的),後量子鏈 16853 bytes 會讓它中途停下 |

### 現在的關卡狀態

| Gate | 主題 | 狀態 |
|---|---|---|
| G0 | 環境與版本基線 | ✅ 完成 |
| G1 | 完整握手、逐欄位 | ✅ **完成** — 7 個訊息對逐欄位標註,**164** 個數字由 CI 驗證,其中 **4 個訊息對的位移是從線上重建出來的**。剩下三個為什麼比較難(而不只是還沒做),寫在文件 §10 |
| G2 | 憑證鏈與三點篡改 | ✅ **完成** — 自己簽的三層鏈在線上量到 1897 bytes,**而且現在有三個互不相干的工具各算一次**(憑證檔 / 解碼 / capture)。**Table 1** 五列、十條受控臂,`docs/tamper.md`。篡改點 ② 需要一支 proxy,做出來之後變成兩列 —— 因為「錯誤訊息一樣、根因相反」那一對其實住在裡面 |
| G3 | RATS 驗證流水線 | ✅ **完成** —— 參考值、COSE 簽章背書、政策、判定,十條臂全跑過一遍(**Table 3**,`docs/rats-pipeline.md`)。**那個沒有任何一層擋得住的篡改被擋下來了,而且指得出是哪一條規則、哪一個 index。** 版本規則也收尾了:改成逐 index 的「不低於參考值」,舊的那份被**凍結**成 `rats/policy-v0-equality.rego`,四份 capture 跑兩個政策、**八格只有一格動**,CI 斷言這件事(§11.6)。放寬的代價寫在結果旁邊:`>=` 只擋得住低於參考值的回滾 |
| G4 | 後量子成本 | ✅ **完成**(W07 起跑,W08 收)—— **六組全部**,排成三組對齊的比較:古典 vs 後量子在 **NIST level 3 與 level 5 各一組**(8.99× 與 **10.91×**,缺口隨等級變大),以及格基 vs hash-based 在同一個 KEM 下比。**十八個控制變因是從 `key.c` 讀出來的,不是從 `--help`**,每一臂把十二組協商結果加四個推導事實讀回來比對,對不上就整個 run 失敗。**Figure 2／Figure 3**、`docs/pqc-cost.md`、`docs/fragmentation.md` |
| G5 | 真實傳輸 | ✅ **完成**(W09)—— **兩條路都成**。① **真的 MCTP 網路**:guest kernel 自己編、開 `CONFIG_MCTP`,guest 的 root 就是宿主的檔案系統(9p 唯讀),所以 W01 編的 `spdm_*_emu` 原封不動就能跑。兩臂握手整條走 mctp-serial,**A0 115 個封包、P2 953 個,全部數出來,模型每一則都對得上**。**對照組是決定性的**:同一個握手在訊息層的 capture 跟 W08 socket 那條**逐則長度完全一樣** —— 換傳輸沒有改變協定。② **真的 PCIe DOE 信箱**:QEMU 的 NVMe 開 `spdm_port`,guest 裡 `lspci -vvv` 看得到 Data Object Exchange capability,`transport/doe_probe` 從 userspace 打信箱、列出三個 DOE 協定、送一則 `GET_VERSION` 拿回 `VERSION`(1.0~1.4)。★ **封包比 8.29× 小於位元組比 9.11×**,因為一個傳輸單位是整個算的 —— 這件事在 socket 那條上永遠量不到(§11.8)|
| G6 | 一致性與負面測試 | ✅ **完成** —— DMTF 的 `SPDM-Responder-Validator` 跑了**四臂**,八個失敗每一個都追到根因、而且分類成「行為錯」還是「能力/組態」(`docs/validator-report.md`)。★ 三臂的存在目的是**讓那支測試講出 PASS 以外的話**:去掉一個 `MUT_AUTH_CAP` 解鎖 **611 個 assertion 跟四整組測試**(而且「只動了這一個位元」是從兩份 capture 把 Flags 讀回來比對的,不是從旗標宣稱的);穿過一支**什麼都不改的 proxy** 要逐項重現基線;再穿過同一支 proxy **翻掉一個簽章位元組**,要求恰好一個 assertion 變 FAIL。★ 兩個上游發現,第二個是**證明**不是主張:`harness/challenge_verify.py` 先在那支測試「會通過」的九條連線上校準,再驗它判 FAIL 的那兩條 —— 兩條都驗過,所以錯的是測試不是裝置。fuzz 與覆蓋率:312 顆去重種子對上游的 81 顆,用 `afl-showmap` **量**而不是**說**;11,432 次執行、0 崩潰,以及「為什麼這是預期結果」的算術;行覆蓋率 69.7%、responder handler 76.5%(`docs/negative-tests.md`)。★★ W11 把下半做完:三個類別寫成測試,**24 個 case 對 21 個故意寫錯的實作**,每個錯誤版本都要**事先宣告它會動到哪幾個 case**,動得太少(rule 11)跟動到沒人預測的(rule 13)一樣算失敗;外加兩次跑 `--asan-demo`,**把「ASan 看得到什麼、看不到什麼」變成斷言而不是記憶**。四個 advisory 編號全部對照過原始來源,全部正確——但**三個都不在 GitHub 全域資料庫、兩個根本沒有 CVE、唯一那個 CVE 在 NVD 跟 MITRE 都查不到**(`docs/advisories.md` §1)。★★ 另外量了**這個 repo 自己的 build 有沒有這三個洞**:`pqc` 兩個修正都有,`stable`(3.8.0)其中一個 **AFFECTED**,五個先決條件全中(`docs/advisories.md` §3)|
| G7 | 上游貢獻 | 🟡 **進行中 — 94773 的 PS1 收到 owner 的 −1(2026-09-22),PS2 已備好、等你簽 DCO 跟推送(2026-09-23),`docs/upstream/0002-openbmc-readme.md` §11;#524 還沒有人回。** 以下是 W12 之前的內容:**兩個都送出去了(2026-09-22);第一則審查已收到並回完,但兩個都還沒合併。** 這個 gate 要的是「送出 ＋ 有審查往返」,而往返那一半不是自己能控制的 — ① [`DMTF/spdm-emu` #524](https://github.com/DMTF/spdm-emu/pull/524):`CoRimTool.py` 的 `verify` 根本沒有在驗簽章,而且是**兩行互相遮蔽**的缺陷——只修看起來明顯的那一行,會把「什麼都不接受」變成「什麼都接受」,而這件事是**量出來的**,不是推論的。DCO 檢查綠燈;reviewer 由 CODEOWNERS 自動指派(jyao1、steven-bellock),不是自己點名的。② [`openbmc/spdm` 94773](https://gerrit.openbmc.org/c/openbmc/spdm/+/94773):那個 repo 的第一份 README。2025-05 有人送過一版(change 80422),被 owner 以「寫了程式碼做不到的假設功能」打回、CI 紅兩次、掛一年後被 bot 自動 abandon,**那份 review 就是規格**:只寫 merged tree 真的有的東西、引用 reviewer 要的 Redfish design、補 reviewer 要的 Code organization 章節。★★ **貼著送出那一刻做的新鮮度檢查,兩次都改變了送出去的東西**:`spdm-emu` 的 main 又動了(`b5f3ec1` → `16119ea`),所以 rebase 了第二次,並且證明 `patch-id`、blob、392 行 CRLF 三樣都沒被動到;`openbmc/spdm` 那邊則是**兩支必要的 linter 從這台機器上消失了**,重裝回釘住的版本、重抓 config、重跑一次,才敢把那條 `Tested:` 再講第二次。★ 還有一個坑是查出來而不是踩出來的:`docs/upstream/0002-openbmc-readme.md` 自己寫的送出指令是 `git push origin`,而那棵樹的 `origin` 是 GitHub 的**唯讀鏡像**,不是 Gerrit。**十九個候選有證據,送出兩個**;其餘十七個各自留著重現步驟,不打包——第一次投稿塞六個不相關的修正,正是第一次投稿不會被收的原因 ★★ **第一則審查在推出去後 35 分鐘就回來了,而且它抓到的正是四天準備裡唯一弄錯的那件事**:這個專案曾經斷定「OpenBMC 沒有 AI 協作政策」,依據是對 `CONTRIBUTING.md` 的一次 grep;審查者直接給出一份——`openbmc/docs` 89452,**在 review 中、master 上 404**,所以 grep 已合併的樹永遠看不到它。**一個專案的規則也活在它還沒合併的 change 裡。**兩則留言當天回完,回覆裡每一個事實都先用程式查過(十三項),而其中一項檢查本身是壞的:`grep -i AI` 命中了 `gmail` 裡的 `ai`。兩個 change 都還沒合併、兩條 thread 還 unresolved,所以這個 gate 不算完成。 |
| G8 | 交付與敘事 | 🟡 **進行中** — W12 交付了 README 重寫(第一屏 + 八節 + 五張圖,數字由 CI 對 `claims.json`)、`docs/threat-scope.md`、`docs/limitations.md`;W13~W14 是一頁紙、demo 與面試準備 |

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
| [11.9](#119--一支測試說你錯了要怎麼知道是不是它錯了w10-做的事) | ★ **一支測試說你錯了,要怎麼知道是不是它錯了**(W10) | 讀 12 分 |
| [11.10](#1110--一個漏洞在文件裡不在程式裡w11-做的事上半) | ★★★ **一個漏洞在文件裡,不在程式裡**(W11) | 讀 10 分 |
| [11.11](#1111--那我自己的-build-有沒有這些洞w11-做的事下半) | ★★ **那我自己的 build 有沒有這些洞**(W11) | 讀 8 分 |
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
> 編譯後約 6~8 GB,兩個 flavor 就接近 20 GB,**三個接近 30 GB**。
> (第三個 `pqc-dts` 用 `--seed-from pqc` 複製原始碼樹,所以只多付編譯,
> 不用再下載一次。)
>
> **這是正常的,不是你做錯了。**

需要的軟體(§4 的 `doctor.sh` 會逐項幫你檢查):

```
git   cmake(≥3.10)   make   gcc   python3   perl   opa
```

> ### ⚠️ `opa` 是 W06 之後才加進來的,而且它不是可有可無的
>
> Open Policy Agent 是評估 `rats/policy.rego` 的引擎,而那份政策就是
> 「被篡改的量測必須被判 FAIL」這句話的所在。**沒有它,`verify_repo.sh`
> 直接紅**——不是跳過。`rats/appraise.py selftest` 會拒絕在沒有引擎的情況下
> 假裝通過,因為一個「因為沒被跑到所以通過」的自我檢驗,比沒有自我檢驗更糟。
>
> (這句話一開始寫成「會跳過但仍然是綠的」。2026-09-13 把 `opa` 從 PATH 拿掉
> 實測,發現是錯的——那是推理出來的,不是跑出來的,而這份 runbook 的規矩就是
> 不收推理出來的句子。)
>
> ```bash
> curl -L -o /tmp/opa https://openpolicyagent.org/downloads/v1.20.2/opa_linux_amd64_static
> sudo install -m 0755 /tmp/opa /usr/local/bin/opa
> opa version        # Rego Version 那一行要是 v1
> ```
>
> 版本釘在 `third_party/opa.pin`。**要緊的不是小版號,是 Rego 的語言版本**:
> OPA 從 1.0 起預設 v1,而 DMTF 附的那份範例政策是 v0 寫的、解析不過。
> `verify_repo.sh` 會比對你機器上的 Rego 版本跟 pin,不一致就變紅。

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
<summary><b>為什麼要三份 build?</b></summary>

後量子演算法是 **2026-08-04** 才進 libspdm 主線的,而且 `4.0.0` 目前是
**release candidate**。

**我不想讓一個 RC 當我的基準線。** 所以:

| flavor | spdm-emu | libspdm | 差別 | 用途 |
|---|---|---|---|---|
| `stable` | 3.8.0 | 3.8.0 | — | 所有 baseline 量測 |
| `pqc` | 4.0.0-rc | 4.0.0-rc | — | **每一個比較臂**,古典與後量子都是 |
| `pqc-dts` | 4.0.0-rc | 4.0.0-rc | buffer 調大 ＋ `transport/data-transfer-size.patch` | **只跑 DataTransferSize 掃描**(W08 加的) |

★ 第三份不是「把 `pqc` 重編」,因為 `pqc` 是所有已發表數字的來源。
重編它會讓未來每一份 capture 的 DataTransferSize 都變掉,「clone 下來、照 pin 重建、得到同樣的數字」這句話就不成立了。
掃描裡故意放一個 4608 的點當**對照**,它必須重現 `pqc` 的每一個計數 ——
見 `docs/decisions/0009-a-third-build-flavor.md` 與 §11.7。

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
#   164/164 claims match the capture
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
> 每一個大小、次數、位移都一樣。**所以那份 08-17 寫的逐欄位文件,當時的 128 個
> claim 全部對得上一份它從來沒看過的 capture。**08-31 又重跑了一次,五臂第三次
> 一模一樣。
>
> 這就是為什麼位元組類的數字報單一值而不報範圍 —— 那不是一個慣例,是一個量到的
> 性質。

**為什麼不乾脆做一個「重新蓋 manifest」的工具?** 因為一個可以被重新蓋章的
manifest 什麼都證明不了,而且那個工具一旦存在,趕時間的時候就一定會用它。完整的
理由、被否決的四個替代方案、以及這件事跟 §8.6 是同一個道理,寫在
[`docs/decisions/0004`](docs/decisions/0004-derivations-must-reproduce.md)。

### 8.7 🔴 憑證鏈:你可以驗證它,但你**沒辦法重現**它

這一節在講一個這個 repo 裡第三種檔案。前面兩種你已經知道了:

| 種類 | 例子 | 一個相符的 hash 告訴你什麼 |
|---|---|---|
| **證據** | `*.pcap`、`*.decode.txt` | **全部**。線上發生過的事不會改變意思 |
| **推導** | `*.fields.json` | 只有「沒人動過它」。所以 §8.5 還額外要求它**能被重算出來** |
| **產生出來的輸入** | `certs/out/*.der` | 只有「沒人動過它」,**而且它重跑一次就會不一樣** |

`certs/gen_chain.sh` 產一條三層憑證鏈。這條鏈是**輸入**(capture 依賴它),但它
不可重現:

* 每次跑金鑰都是新的;
* ECDSA 簽章在 DER 裡是兩個整數,**它們的長度取決於最高位元是不是 1** ——
  所以連憑證的**位元組數**都會差個一兩個 byte;
* 而且私鑰**沒有進版控**(`.gitignore` 擋 `*.key`),所以一份乾淨 clone 就算想
  重現也做不到。

```bash
bash certs/gen_chain.sh
#   -> 如果 certs/out/ 已經有東西,它會「拒絕執行」並告訴你會壞掉什麼
#   -> 要硬幹:bash certs/gen_chain.sh --force

python3 certs/check_chain.py certs/out
#   ok   four certificates present: ca 504 B, inter 573 B, end_responder 768 B …
#   ok   bundle_responder.certchain.der: 3 certificates, 504 + 573 + 768 = 1845
#   ok                                   on the wire: 4 + 48 + 1845 = 1897 bytes

python3 certs/check_chain.py certs/out --self-test
#   4 breaks, 4 distinct checks — none redundant
```

> ### 為什麼 `gen_chain.sh` 會拒絕覆蓋
>
> 因為這個 repo 公布的每一個關於這條鏈的數字 —— 504/573/768、線上 1897、RootHash
> `df0ee8f9…` —— 都是**那一組憑證**的性質。重產一次,這些數字會**全部變成假的,
> 而且沒有任何一個已 commit 的檔案的 hash 會改變**,因為你根本沒有動到 run 目錄。
>
> 這跟 §8.5「不做重新蓋 manifest 的工具」是同一個道理:**把便宜的修法弄成不可能,
> 貴的那個才會真的發生。** 完整推理在
> [`docs/decisions/0005`](docs/decisions/0005-generated-inputs-are-evidence.md)。

**所以一份乾淨 clone 能做什麼、不能做什麼,講清楚比含糊好:**

| 你可以 | 你不可以 |
|---|---|
| 重新 hash 每一個 artifact | 用**這條**鏈再收一份新的 capture(沒有私鑰) |
| 用 committed 的 capture 重算 `docs/certchain.md` 每一個數字 | — |
| 用 committed 的憑證重跑 `check_chain.py` 跟它的 self-test | — |
| 用 `gen_chain.sh --force` 產**你自己的**鏈,四條方程式一樣會閉合 | 期待你的鏈跟這裡公布的位元組數一樣 |

最後一列是重點:**可重現的是「關係」,不是「位元組」。**

> ### 為什麼 `check_chain.py` 要自己拆 DER,而不是 grep `openssl x509 -text`
>
> 計畫書原本寫的是:
>
> ```bash
> openssl x509 -in end_responder.cert -text -noout | grep -A3 'Subject Alternative Name'
> ```
>
> 這一行問的是「**OpenSSL 的美化輸出裡有沒有出現那個字串**」,比它看起來的弱很多:
> 它分不出 critical 跟非 critical、分不出兩個 `otherName` 裡哪個帶哪個 OID、
> 也**看不出 OID 被編錯了** —— 因為印出來的時候已經解碼過,一個錯的 OID 會被印成
> 「另一個對的 OID」。
>
> 所以 `check_chain.py` 是從憑證自己的 DER 一層一層走下去,**用編碼後的 OID 位元組
> 去比對**。跟這個 repo 其他地方同一個習慣:**證明那個位移,不要抄那個位移**,只是
> 換到 X.509 上。

**★ 那條鏈上有幾個信任錨?** 這是 08-31 撞到、而且原本不在計畫裡的東西:

```bash
python3 harness/fields.py bench/data/w4-baseline-20260901T054208Z/selfsigned.decode.txt
#   chains carried              4 fetched, 3 distinct root(s)
#                               packet 10  RSP->REQ  slot 0    1897 B  root df0ee8f9…  <- 我的
#                               packet 12  RSP->REQ  slot 4    1660 B  root ed79ce9a…  <- 上游 ecp384
#                               packet 19  REQ->RSP  slot 0    3794 B  root e59ee211…  <- 上游 rsa3072
#                               packet 26  RSP->REQ  slot 0    1897 B  root df0ee8f9…  <- 我的
```

**我以為我換掉了「憑證鏈」,實際上只換掉三分之一。** SPDM 兩個方向的簽章演算法是
**分開協商**的,而 libspdm 的範例程式是**用協商結果去選憑證目錄**的:requester 談
成 `RSAPSS_3072`,就去讀 `rsa3072/`,而我的鏈放在 `ecp384/`。

在模擬器上這是個趣聞。在產品上不是:一個廠商換掉「裝置憑證」,換的是一個方向、
一個 slot、一種演算法,**其他全部保持原樣,而參考設計上的「原樣」是上游範例鏈,
它的私鑰公開在 GitHub 上。** 握手會成功,每個簽章都會過,流程裡沒有任何地方會說
用的是哪個信任錨。

所以那個數字現在是一個 CI 會檢查的欄位(`layout.distinct_root_hashes`)。
**「注意到一件事」跟「量到一件事」的差別,就在於它下次再出錯時會不會有人被告知。**

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

## 8.8 ★ 改一個 byte,然後看是哪一層發現

這一節是 W04 跟 W05 做出來的東西,也是 **Table 1** 的操作說明。
**如果你只讀一節,讀這節。**

### 為什麼要先改上游

上游那份範例裝置程式庫的量測值是**憑空造出來的**:index 1 就是「72 個 0x01
取 SHA-512」,安全版本號寫死成 `0x7`。你可以自己驗:

```bash
python3 -c "import hashlib;print(hashlib.sha512(bytes([1])*72).hexdigest()[:32])"
#   8d531d77d821e167114d1eb07e0ae19c      <- 這就是封包裡 index 1 的前 16 bytes
```

這對範例程式來說完全合理,但它讓兩件事做不到:

1. **沒有一個 byte 可以翻。** 篡改測試要有輸入,寫死在函式裡的常數不是輸入。
2. **降版政策只有一個輸入值。** `evidence_svn >= reference_svn` 這條規則
   如果永遠只被餵 `7`,那條規則等於從來沒被測過 —— 不管你怎麼寫它都會過。
   這三個值(5 / 7 / 9)就是 2026-09-14 那次改判準能被**量**出來的原因:
   同樣四份 capture 跑新舊兩個政策,只有一格會動(§11.6)。

### 改了什麼(全部就這三行)

```bash
cat device/meas-from-file.patch     # 16 行新增,0 行刪除,跨兩個檔案
```

```c
    libspdm_set_mem(data, sizeof(data), (uint8_t)(measurements_index));
+   (void)ms_get_block(measurements_index, data, sizeof(data));   /* 新增 */

    svn = 0x7;
+   (void)ms_get_svn(&svn);                                       /* 新增 */
```

**兩行都加在上游算完自己的值之後,而且拒絕時不碰那個 buffer。** 所以 diff 是
純新增 —— 上游那兩行還在、還會跑。hash、組區塊、簽章一個字都沒動。

> ★ 面試時你要能指著這個 diff 說:**「我沒有改 libspdm 的邏輯,我改的是一個
> buffer 的內容從哪裡來,而且是加在上游填完它的下一行。capture 量到的仍然是
> 上游的行為,不是我的。」**

### 怎麼裝、怎麼拆

```bash
bash harness/apply_device_patch.sh pqc --build     # 裝上去並重建
bash harness/apply_device_patch.sh pqc --status    # 現在到底裝了沒
bash harness/apply_device_patch.sh pqc --revert    # 拆掉(要再重建一次)
```

它會擋三種錯:build tree 的 libspdm commit 跟 `third_party/*.pin` 對不上、
`meas.c` 或 `CMakeLists.txt` 的 sha256 不是這份 patch 當初對著做的那一版、
以及重複安裝(第二次是 no-op,不是錯誤)。

> 🔴 **第二種擋法為什麼重要:** `git apply` 只看上下文對不對得上。上游可以改了
> 一堆東西但那兩行上下文剛好沒動 —— 那時 `git apply` 會成功,而你 patch 到的
> 是一個你沒讀過的檔案。**digest 擋得住,上下文擋不住。**

### 跑那十個 case

```bash
bash harness/tamper.sh          # 約一分鐘
```

`SPDM_MEASUREMENTS_FILE` 這個環境變數是開關,**而且只給 responder**
(`HS_RESPONDER_ENV`)。沒設 → 連檔案都不 open,行為跟上游完全一樣。

看它印出來的表,四欄最重要:

| 欄 | 它在回答什麼 |
|---|---|
| `cert` / `chal` / `meas` | 這次握手**走到哪裡**。比 exit code 誠實 |
| `slots` | responder 到底**願不願意提供** slot 0 的憑證 |
| `anchor` | responder 送的鏈,root 是不是 requester 被設定去信的那一張 |
| `record_sha256` | 那 528 bytes 的量測記錄 |

### ★ 那支 proxy(W05 加的),以及它為什麼會拒絕動手

篡改點 ② 是「改線上的位元組」,所以需要一支坐在中間的程式:

```
spdm_requester_emu --port 2324  ──►  tamper_proxy.py (聽 2324)  ──►  spdm_responder_emu (2323)
```

```bash
# 先驗透明:什麼都不改,握手必須成功,量測記錄必須跟對照組一模一樣
python3 harness/tamper_proxy.py --listen 2324 --forward 2323 --passthrough

# 改「被簽的內容」
python3 harness/tamper_proxy.py --listen 2324 --forward 2323 --flip-record 1:36

# 改「簽章本身」
python3 harness/tamper_proxy.py --listen 2324 --forward 2323 --flip-signature -1

# 它自己的測試:十三種壞掉的訊息,十三個檢查全部都要被打到
python3 harness/tamper_proxy.py --self-test
```

**它動手之前要先閉合兩條式子,不閉合就拒絕:**

```
從 ALGORITHMS 讀回來的 BaseAsymSel  ->  ECDSA P-384  ->  簽章 96 bytes
674 - (4 + 1 + 3 + 528 + 32 + 2 + 8)                   =        96 bytes
                                                                 ^ 閉合
```

> 🔴 **這條式子把 `plan/W05.md` 自己的欄位表擋下來了。** 計畫那張 `MEASUREMENTS`
> 結構圖少寫了 `RequesterContext`(8 bytes,SPDM 1.3 以後才有),照它算簽章會
> 早 8 個位元組開始。proxy 拒絕翻,並且把 96 跟 104 兩個數字都印出來。
> **這就是「兩個未知數要兩條式子」那條紀律的第三次現場**——前兩次在 §8.3b。

**offset 為什麼要印三個?** 因為讀的人會在三個地方遇到它:

| 座標系 | t2a 的值 | 為什麼差這麼多 |
|---|--:|---|
| SPDM 訊息裡 | 51 | 從 SPDMVersion 那個 byte 算起 |
| socket payload 裡 | 52 | 前面多一個 MCTP 訊息型別 byte(`0x05`) |
| pcap 紀錄裡 | 56 | 再多四個 `spdm_emu` 自己合成的 MCTP 表頭 |

`command.h` 的註解說 payload「從 SPDM_HEADER 開始」。**那句話是錯的**,而且是
寫這支 proxy 時第一個踩到的東西。已經記成上游候選第五案。

### 五個你應該自己看一次的結果

**① 改量測值 → 握手成功。** 不是 bug。responder 是拿「它剛剛送出去的東西」去
簽名的,你改了它讀進來的資料,它就對新的資料簽名 —— requester 收到的是自洽的
一對。**要讓簽章驗證失敗,必須讓「被簽的」跟「被驗的」不一樣**,只有兩條路:
線上改(W05 的 ②),或用不匹配的鑰匙簽。改來源不在這兩條路上。

憑證鏈為什麼擋得住?因為 requester 手上有一個**它自己從別處拿到的錨點**(root)。
量測沒有這種東西 —— requester 根本不知道這台裝置的韌體 hash 應該長什麼樣。

> **SPDM 證明的是「這份量測確實出自這台裝置」,不是「這份量測是對的」。**
> 後者要參考值,而參考值不在協定裡 —— 那就是 G3 存在的理由。

**② 改 Sub CA 的一個 byte → 比預期更早失敗,而且原因不是預期的那個。**
pcap 裡**連 `CERTIFICATE` 訊息都沒有**,而 `ProvisionedSlotMask` 從 `0x13`
掉到 `0x12`。responder 讀自己的鏈時會驗,驗不過就不再提供那個 slot。
**壞掉的位元組根本沒上線。**

```bash
R=$(ls -d bench/data/*-tamper-* | tail -1)
grep -h 'SPDM_DIGESTS' "$R/t0_clean.decode.txt" "$R/t3_cert.decode.txt"
#   看 ProvisionedSlotMask 那一格
```

> 🔴 **這一題是本週最好的一課:log 說「do_authentication_via_spdm 失敗」,
> exit code 說 1,而順手寫下「requester 拒絕了被篡改的憑證鏈」會是錯的。**
> 是 pcap 裡少了一個訊息、加上一個 bit 的變化,把真正的原因指出來的。

**③ 換成別人的鏈(內容完全合法)→ 握手成功。** responder 送 DMTF 自己的
`ecp384` 鏈,requester 被設定去信的是我們的 root。libspdm **有**發現,而且回報
`LIBSPDM_STATUS_VERIF_NO_AUTHORITY` —— 但那是 `SEVERITY_WARNING`,而
`spdm_requester_emu` 只檢查 `LIBSPDM_STATUS_IS_ERROR`。

這不是 libspdm 的缺陷:它刻意把「要不要信這個 CA」交給整合者決定,還提供了
`trust_anchor` 讓你拿。**是那支範例程式沒有去接。**

> **一個只檢查 `IS_ERROR` 的整合者,等於接受了每一條 parse 得過的憑證鏈。**
> 在真的 BMC 上,這就是「這台裝置是真的」跟「這台裝置文件齊全」的差別。

**④ 在線上改「被簽的內容」→ 失敗,`80020001`。** 同一個 index 1、同一個 offset
36,但這次改的是**線上那個值**(SHA-512 的第 36 個 byte),不是裝置上那個
pre-image。responder 簽的是舊的、requester 收到的是新的,兩邊對不起來。

**⑤ 在線上改「簽章本身」→ 失敗,`80020001`,一模一樣的號碼。**
量測記錄一個 byte 都沒動,`f2a14684…` 跟對照組完全相同。

> 🔴 **④ 跟 ⑤ 是這整個專案最好講的一格。** 兩者的根因是相反的——一個是「被簽的
> 東西被改了」,一個是「簽章被改了」——而 requester 印出來的東西**完全一樣**:
> 同一個號碼、同一個函式、同一層。
>
> **意思是:如果你在真的產品上只靠一行 error log 做 triage,你分不出來是韌體被
> 改、還是線路上有 interposer。** 這兩件事的處置完全不同:前者查供應鏈跟更新
> 流程,後者查線路。**SPDM 告訴你「有問題」,不告訴你「問題在哪一層」。**
>
> 分得出來的是 pcap:④ 的量測記錄跟對照組不同,⑤ 的一模一樣。
> **線上分得出來,錯誤訊息分不出來。**

```bash
R=$(ls -d bench/data/w5-tamper-* | tail -1)
for c in t1_meas t2a_record t2b_sig; do
  printf '%-12s %s\n' "$c" "$(python3 harness/spdm_status.py "$R/$c.req.log")"
done
#   t1_meas      -
#   t2a_record   80020001 VERIF_FAIL (ERROR/CRYPTO/0x0001) from do_measurement_via_spdm
#   t2b_sig      80020001 VERIF_FAIL (ERROR/CRYPTO/0x0001) from do_measurement_via_spdm
```

### 產生 fixture

```bash
python3 device/gen_measurements.py --out /tmp/m.bin            # 預設 = 重現上游
python3 device/gen_measurements.py --svn 5 --out /tmp/m5.bin
python3 device/gen_measurements.py --flip-block 1 --flip-offset 36 --out /tmp/t.bin
python3 device/gen_measurements.py --describe /tmp/m.bin
```

**預設輸出是對照組而不是輸入** —— 它產生的內容就是上游會合成的那些 bytes,
所以 responder 讀了它之後送出去的 528 bytes 必須跟「完全沒有這個檔案」時一模
一樣。那個 sha256 是 `f2a14684…`,而且它在 08-16、08-28、08-31、09-01 四次
run、兩條不同的憑證鏈裡都一樣。**先用一個 256-bit 的目標證明管線接對了,再開始
故意改東西。**

> ⚠️ `--flip-byte 12` 會被**拒絕**,而且它會告訴你為什麼:那個位移落在 svn
> 欄位裡,翻它是改了檔案「怎麼被讀」而不是「它說了什麼」。log 裡看起來會一模
> 一樣,意思卻完全不同。

### ★★ CI 現在會因為「篡改沒被擋下來」而變紅

W05 之前,`綠 ≠ 有在保護我` 這句話是完全成立的:兩個 job 都只在檢查形式。
現在 `verify_repo.sh` 多了一步,它**從原始證據重算**(requester 自己的 log ＋
已 commit 的 `fields.json`,不看 `cases.tsv` 那張表),而且四個條件缺一就紅:

```
t0_proxy    沒有錯誤,而且記錄跟對照組一樣      <- 儀器本身沒壞
t2a_record  VERIF_FAIL,記錄跟對照組不一樣
t2b_sig     VERIF_FAIL,記錄跟對照組一樣        <- 而且要跟 t2a 同一個號碼
t1_meas     沒有錯誤,記錄跟對照組不一樣        <- ★ 這條是要它「繼續不被擋」
```

最後一條容易被誤會:**它不是缺口,它是量測結果。** 改裝置上的量測值本來就不該
被 SPDM 擋下來,那是 G3 的工作。如果哪天它開始被擋了,代表 libspdm 變了,那值得
停下來看。

還有一條是兩個互不相見的證人:proxy 說它讀到 `f2a14684…`(＝對照組)、寫出
`4519f14e…`;`fields.py` 事後從 capture 檔讀出來也是 `4519f14e…`。
**兩邊都要對,才算數。**

⚠️ **但還是不要把 badge 講成保證。** 現在紅的條件是「線上篡改沒被拒絕」,
**不是**「量測值不對卻通過了」——後者要參考值,那是 G3。

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
| 磁碟滿了 | 三個 flavor + spdm-dump ≈ 30 GB | `rm -rf ~/spdm-lab/work/spdm-emu-stable`,需要時再 `--seed-from pqc` 重建 |
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

**現在有四題有合約跟測試、零題完成:** `d3`(佇列)、`d1`(SPDM 標頭)、
`d5`(位元組序)、`d6`(packed struct)。實作永遠是你的 —— 那是唯一在量「你」的
東西,別人寫了等於把那個量測歸零。

> ### ★ 出題的人也要先證明題目是對的
>
> 一份測試有兩種沒用法,而且兩種都是安靜的:**正確的實作會失敗**,或者**錯誤的
> 實作也會過**。所以每一題在 commit 之前,都會在 repo 外面的暫存目錄編三次:
>
> | 版本 | 必須 |
> |---|---|
> | stub(committed 的那個) | 失敗 —— 那就是題目 |
> | 一份正確實作 | 全過 |
> | **一份故意寫錯的**(就是這題要教的那個錯) | 被抓到 |
>
> W03 加的兩題**兩題都在第一次沒過這一關**:
>
> * `d5` 的錯誤版本(`p[0] << 24`,`uint8_t` 被提升成有號 `int`,`0x88 << 24`
>   溢位)**算出來的值是對的**。只有 UBSan 分得出來。只檢查值的測試會教到零。
> * `d6` 第一版是建在 MCTP 那五個 byte 的框架上,而**那個坑根本不會發生** ——
>   上游的 `mctp_header_t` 是四個 `uint8_t`,對齊是 1,`sizeof` 剛好就是 5。
>   這跟 `d1` 在 08-28 犯的是同一個錯,而且是同一個人在寫下那則教訓十一天後再犯。
>
> **一個失敗模式不可能發生的題目,教出來的是迷信,而迷信會被有自信地重複。**
> 所以規矩是:**先把錯的那版編起來,確認它會失敗,再寫題目。**

細節見 [`c-drills/README.md`](c-drills/README.md) 和
[`c-drills/SCORECARD.md`](c-drills/SCORECARD.md)。

---

## 11. 每天怎麼用這個 repo

```bash
# 一、開工前確認環境還在
bash harness/doctor.sh

# 二、做事(跑實驗、改東西)

# ★ 二點五、收工前第一件事:抓「過期的未來式」
#    一個 gate 關掉的那天,會腐爛的正是那些在它還開著的時候寫下的句子——
#    而它們找得到,因為那個 gate 的名字就在句子裡。四秒鐘。
git grep -niE 'G[0-9]|gate [0-9]|not started|未開始|還不存在|does not exist yet|要到.*才' -- '*.md' \
  | grep -viE 'plan/|^LOG\.md'

# 三、每次有結果就記錄,commit 用上游格式
git add -A
git commit -s -m "meas: make the SVN configurable instead of hard-coded

<空一行,正文每行 72 字元以內,寫「為什麼」不是「改了什麼」>

Tested: <你怎麼驗證的>
"
```

`-s` 會加上 `Signed-off-by:`。**從第一個 commit 就用上游格式**,因為之後要送
Gerrit,現在練起來那時候不用重學。

```bash
# ★ 四、push 之後,把那次 CI 跑完的結果讀出來。這一步不是選配。
git push origin main
gh run watch --exit-status      # 紅就在這裡停,不要等到下次才發現
#   或事後補看:
gh run list --limit 3
gh run view --log-failed
```

> ### 🔴 為什麼要加這一步:2026-09-12 到 09-14,badge 紅了兩天沒人看
>
> `verify_repo.sh` 在**沒有 `opa`** 的時候會直接紅——那是 09-13 刻意改的,
> 理由是「一個因為沒跑而通過的自測,比沒有自測更糟」。**而跑它的那個 CI job
> 從來沒有裝 `opa`。**
>
> 兩件事同時成立,而且從彼此都看不出來:**腳本是對的,job 是錯的。**
> 本機全綠,因為本機裝了 `opa`;CI 全紅,因為 runner 沒有。
> **「在我這裡會過」跟「在 CI 會過」是兩個不同的主張**,而我兩天只驗了前者。
>
> 現在 `verify_repo.sh` 有一條檢查在守它:`harness/lib/ci_tools_check.py`
> 從 `third_party/*.pin` 的 `consumed-by=` 推出「哪個 job 跑了哪個工具」,
> 只要有 job 跑了它沒裝的工具就變紅。**那個 `consumed-by=` 兩天前就已經
> 同時寫著 `harness/verify_repo.sh` 跟 `.github/workflows/ci.yml` 了——
> pin 檔比 CI 更早知道。**
>
> 但機制只擋得住下一次。**這一次是靠有人去看 badge 才發現的**,所以
> 「push 完把結果讀出來」也一起變成流程裡的一步。

> ### ⚠️ 但這個 repo 的 trailer 慣例**不能直接帶去上游**
>
> 這裡每一個 commit 都有 `Co-Authored-By: Claude …`。在這個 repo 裡是對的;
> **在 DMTF/spdm-emu 是違規的**——它的 `CONTRIBUTING.md` 第 2 條明文寫
> 「AI 不得出現在 `Co-authored-by`」,第 1 條寫「不得出現在 `Signed-off-by`」,
> 第 3 條寫「有 AI 協助就**必須**加 `Assisted-by: 工具名:模型版本`」。
>
> 也就是說:同一句 trailer,在這裡是誠實,在那裡是規則違反。而且
> **兩個上游的規則彼此也不一樣**:OpenBMC 要 CLA + DCO + Gerrit 的 Change-Id,
> DMTF 只要 DCO,沒有 CLA。
>
> 所以送出去之前跑這個,不要靠記憶:
>
> ```bash
> bash harness/check_upstream_commit.sh ~/spdm-lab/work/spdm-emu-pr
> ```
>
> 它把規則從**對方自己的 `CONTRIBUTING.md`** 讀出來、記下那個檔案的 sha256,
> 對方改了規則它會講。細節在 `docs/upstream/README.md`。

### 為什麼「二點五」那一步是收工的第一件事,不是最後一件

`verify_repo.sh` 會比對三張 gate 表的**狀態字**有沒有一致,還會比對週次。
那個機制存在,而且它**擋不住這件事**——2026-09-10 的 LOG 就是這樣寫的:
「那個檢查抓不到今天」。三張表的狀態字當時全對,爛掉的是旁邊的敘述。

2026-09-12 收工的時候,`rats` job 被建出來了,而 RUNBOOK 第一屏還寫著
「真正該綠的 `rats` job 要到 G2/G3 才存在」。**那句話本身就是在告訴讀者
CI 保護不到什麼,而它自己剛好停止為真。** 同一天總共十二個檔案是這個形狀。

**一句未來式是一個附了到期日的宣稱。**「那是 Gate 3 的事」、「還不存在」、
「要到 W09 才有」——寫下的當下都是對的,都會在某一個特定的日子變成假的,
而那天沒有任何東西會指向它們。它們跟「數字跟 capture 對不上」是相反的問題:
數字是**對某個事實錯了**,未來式是**對過去正確、卻被當成現在讀**。

放在收工序列的**最前面**,是因為改完之後往往還要改 gate 表、改 README,
而那三個檔案本來就有機制看著。先跑沒有機制的那一半。

### 11.5 ★ 拿到量測之後呢:參考值比對(W06 做的事)

這一節是整個 repo 最重要的一段,所以先講清楚它在回答什麼問題。

握手做完、簽章驗過,你手上有一串 hash。**這串 hash 是「對的」嗎?**
SPDM 完全不管這件事。它保證的是「這個值真的來自這台裝置、路上沒被改」,
**它不保證這個值應該是這個值**。

`docs/tamper.md` 第一列就是活生生的證據:把裝置上的量測值改掉一個 byte,
在它自己算 hash、自己簽名之前改,結果是——**握手完整完成,每一個簽章都驗過,
requester 結束碼 0,一行錯誤訊息都沒有。** 一台被植入惡意韌體的裝置,
只要它的 RoT 還正常工作,它會誠實地量測那份惡意韌體並簽名。

補上這一層要三樣 SPDM 沒有的東西:**參考值**(應該是什麼)、
**背書**(誰有資格說應該是什麼)、**政策**(不合的時候怎麼辦)。
那就是 IETF 的 RATS,RFC 9334。

#### 先裝 OPA(只要做一次)

政策是用 Rego 寫的,要有東西來評估它:

```bash
curl -L -o /tmp/opa https://openpolicyagent.org/downloads/v1.20.2/opa_linux_amd64_static
sudo install -m 0755 /tmp/opa /usr/local/bin/opa
opa version          # 要看到 Version: 1.20.x,Rego Version: v1
```

> ⚠ **版本很重要。** OPA 從 1.0 開始預設 Rego v1。DMTF 附的那份範例政策是
> v0 語法寫的,在現在的 OPA 上會吐 11 個 parse error,要加 `--v0-compatible`
> 才跑得動,而它的 readme 一個字都沒提。我們自己的 `rats/policy.rego` 是 v1。

#### 跑一次判定

```bash
R=$(ls -d bench/data/*-tamper-* | tail -1)

# 沒被篡改的 → 應該 PASS,結束碼 0
python3 rats/appraise.py appraise "$R/t0_clean.decode.txt"; echo "exit=$?"

# ★ 被篡改的那一個 → 應該 FAIL,結束碼 1
python3 rats/appraise.py appraise "$R/t1_meas.decode.txt";  echo "exit=$?"

# 十條臂一次跑完,而且比對「每一條應該是什麼」
python3 rats/appraise.py matrix --check
```

你會看到這樣一張表:

```
arm            record             appraisal   blocked by
svn5           985df8524b6d0e08…  FAIL        SPDM_SVN_CHECK  [svn_rollback: 16]
svn9           cda33be106e759c3…  PASS
t0_clean       f2a14684e8fae9ff…  PASS
t1_meas        21ae49f9b66835f6…  FAIL        SPDM_HASH_CHECK  [digest_mismatch: 1]
t2b_sig        f2a14684e8fae9ff…  PASS
t3_cert        —                  NO-EVIDENCE no MEASUREMENTS response
```

**三格值得停下來看:**

- **`t1_meas` FAIL。** 這一格在 §8.8 的表裡是「沒有任何一層擋下來」。
  現在被擋下來了,而且它指得出是 `SPDM_HASH_CHECK` 這條規則、
  量測 index 1 這個位置。**這一格就是 G3 存在的全部理由。**
- **`t2b_sig` PASS,而且這是對的。** 那一條臂改的是**簽章**,不是量測;
  它的 measurement record 跟控制組逐位元組相同。SPDM 已經拒絕了這次握手
  (`80020001`),而判定說「量測本身沒問題」。兩層在回答不同的問題:
  **SPDM 說「有東西壞了」,判定說「壞的不是裝置,是線路」。**
  單看一個錯誤碼分不出這兩件事,`t2a_record` 跟 `t2b_sig` 印的是同一個碼。
- **`t3_cert` 是第三種答案,不是 pass 也不是 fail。** 那次握手在
  `GET_CERTIFICATE` 就結束了,根本沒有 `MEASUREMENTS`,所以沒有東西可以判。
  把「判不出來」跟「判它壞掉」混成同一件事,就是一個驗證器去回報一台
  它根本沒講到話的裝置。

#### 結束碼有三種,不是兩種

| 結束碼 | 意思 |
|:--:|---|
| 0 | 判定 **通過** |
| 1 | 判定 **失敗** ——「這台裝置不對」,這是一個判決 |
| 2 | **判不出來** —— 輸入有問題、沒裝 opa、參考值的簽章驗不過 |

1 跟 2 一定要分開。「裝置壞了」跟「我看不出來」是不同的答案,
混在一起的流程會把一個壞掉的驗證器報成一台壞掉的裝置。
(我們取代掉的那支上游工具,這三種情況一律回 0。)

#### 參考值是誰簽的、為什麼你重簽不了

```bash
bash rats/mint_reference.sh        # 「韌體發行者」那一端做的事
python3 rats/cose.py verify -i rats/ref/clean.corim --key rats/keys/ref-signer.pub
```

私鑰 `rats/keys/ref-signer.key` **不在 git 裡**(`.gitignore` 擋掉 `*.key`,
而且 `verify_repo.sh` 會逐檔讀過每一個被追蹤的檔案找 PEM 私鑰標頭,
不是只信任那個 pattern)。所以:**乾淨 clone 驗得了這些參考值,重簽不了。**
跟 `certs/` 是同一個情況,理由也一樣(ADR 0005)。

`kid`(key identifier)在這裡是 `42`,看起來像裝飾,在真實部署裡不是:
一台機器裡有 GPU、SSD、BMC 三家的韌體,verifier 手上有三份不同發行者簽的
參考值,**`kid` 就是它用來決定「這份要用哪一把公鑰驗」的欄位。**

#### 要注意的三件事

1. **證據必須從 pcap 裡的 measurement record 來,不是從 `device/measurements.bin`。**
   後者是裝置**讀進去**的 fixture,是我們自己的格式;拿它產參考值再拿它當證據,
   等於拿一份文件跟它自己比,**連篡改過的都會 pass**。
2. **量測雜湊演算法是從 `ALGORITHMS` 回應讀回來的,不是旗標宣稱的。**
   `rats/appraise.py` 透過 `harness/fields.py` 去讀 `MeasHash`。
3. **八個量測區塊裡有兩個根本進不了證據格式**(`0xfd` manifest、
   `0xfe` device mode,都是 raw bit stream)。所以每一次判定都會印一行
   coverage:`6 of 8 blocks appraisable`。**「這台裝置通過了」跟
   「這台裝置在看得到的部分通過了」是兩句話**,那個數字就是差別。

### 11.6 ★ 改判準沒有價值,能證明它有作用才有(W07 做的事)

§11.5 那條流水線裡的政策,有一條規則從一開始就是**照抄 DMTF 範例**的:
版本號比「完全相等」。

```rego
default SPDM_SVN_CHECK = false
SPDM_SVN_CHECK { ev_svn == ref_svn }      # ← DMTF 範例,原文
```

#### 先講那個數字是什麼

裝置回的 `MEASUREMENTS` 裡有八個量測區塊。其中 index `0x10` 那一塊不是雜湊,
是**安全版本號**(SVN,Secure Version Number):8 個位元組、小端序,在我們的
capture 裡是 `07 00 00 00 00 00 00 00`,也就是 7。

```bash
python3 harness/fields.py bench/data/w5-tamper-20260910T092621Z/t0_clean.decode.txt \
  --list-keys | grep '0x10'
#   ...blocks.0x10.value_type_name = SECURE_VERSION_NUMBER
#   ...blocks.0x10.value_hex       = 0700000000000000
#   ...blocks.0x10.value_uint64    = 7
```

它跟其他區塊一起被裝置簽名,所以「**這台裝置說它是第 7 版**」是可信的。
但「第 7 版**可不可以接受**」SPDM 不問也答不了——那正是要有參考值的理由。

#### `==` 為什麼是錯的規則(兩個**方向相反**的理由)

1. **韌體會升版。** 參考值一發布,任何裝了下一版的機器都會 fail。
   一條「正常運作狀態就是整批紅」的規則,最後會被關掉。
2. ★ **它看不出回滾是回滾。** 版本 5 對上參考值 7 → 拒絕。版本 9 對上同一份
   參考值 → **也拒絕,同一條規則、同一個類別、同一個 index,輸出逐字相同。**
   降到一個有已知漏洞的舊版,跟例行升級,是版本規則唯一存在的理由要分開的
   兩件事,而它對兩者說了同一句話。

#### 改成什麼(★【判】這是設計選擇,不是規格規定)

逐 index、單向:`ev_svn[idx] >= ref_svn[idx]`。
**放寬的只有「比較方向」,沒有放寬「必須被指名」**——三件事仍然擋:

| 類別 | 擋什麼 | 為什麼還是要 fail |
|---|---|---|
| `svn_rollback` | 證據低於參考值 | 那就是攻擊 |
| `svn_missing_from_evidence` | 參考值指名了 index,證據沒有版本號 | ★ 如果「沒回答」可以通過,**攻擊回滾規則最便宜的方法就是不要回答** |
| `svn_not_in_reference` | 證據多報一個沒人背書的版本 | 參考值是「好長什麼樣」的完整陳述 |

#### ★★ 怎麼證明「這個改動有作用,而且只有那一個作用」

把舊的那份**凍結**成 `rats/policy-v0-equality.rego`,然後**同樣四份 capture、
同一份參考值,跑新舊兩個政策**:

```bash
bash rats/test_svn_policy.sh
```

```
case    arm         svn  == (frozen)                       >= (live)
S-eq    t0_clean      7  PASS                              PASS
S-up    svn9          9  FAIL SVN_CHECK svn_mismatch[16]   PASS                *
S-down  svn5          5  FAIL SVN_CHECK svn_mismatch[16]   FAIL SVN_CHECK svn_rollback[16]
S-hash  t1_meas       7  FAIL HASH_CHECK digest_mismatch[1]  FAIL HASH_CHECK digest_mismatch[1]

  * the verdict moved between the two policies
```

**八格,只有一格動。** 這張表要這樣讀:

- **看 frozen 那一欄的 S-up 跟 S-down:那是同一行字。** 這就是「分不出升版與
  降版」的證據本身,不是我在描述它。
- **S-up 動了**(fail → pass):合法升級不再被誤擋。這是改動的全部理由。
- **S-down 沒動**(還是 fail):降版防護還在,而且現在它的類別叫
  `svn_rollback`,**判定說得出它看到的是哪個方向**。
- ★ **S-hash 沒動**(還是 fail,`digest_mismatch`):版本號是對的、量測值被改了
  一個 byte。**這一格就是「我放寬了規則,有沒有把安全性放掉」這個問題的答案。**
  兩條規則是 AND 的,我動的只有版本那一條。

> 🔴 **最容易犯的錯:四個案例各自產一份參考值。** 那樣證據跟參考值出自同一堆
> 位元組,**四個全 pass,而且你不會發現**。這四個共用 `rats/ref/clean.corim`
> 一份,是從乾淨那次 capture 產的。

#### ★ 誠實的那一段:放寬的代價

`>=` 只擋得住「**低於參考值**」的回滾。一台已經在跑第 9 版的機器被刷回第 7 版,
`7 >= 7` → **判 pass,而它確確實實被回滾了。**

要擋那個,只有兩條路,這個專案兩條都沒有:

- **參考值要隨著每次發布往前走** —— 那是**發布流程**的責任,不是政策檔的;
- **verifier 要有狀態**(記住每台裝置看過的最大版本號)—— 這裡每次判定都是
  一次性的推導,沒有地方放那個記號。

這兩句寫在 `docs/rats-pipeline.md` §5 結果的**旁邊**,不是結尾。

#### 為什麼 CI 要跑這張表(而不是只跑十條臂的矩陣)

十條臂的矩陣只跑**一個**政策,所以「結果跟檔案說的一樣」在一個**什麼都沒改**的
改動之後仍然成立。這張表跑兩個,並且斷言**恰好一格會動**——多動一格代表你
連別的東西一起放寬了,一格都沒動代表你根本沒改到東西。

### 11.7 ★ 量一個「沒有旗標可以下」的參數(W08 做的事)

前面幾週量的都是「換一個演算法,看位元組差多少」。這一節是另一種問題:
**想量的東西不是旗標,是編譯期常數。**

#### 為什麼非量它不可

`DataTransferSize` 是一端告訴對方「我一次最多收得下幾個位元組」。訊息超過它,
SPDM 就會 **chunk**:

```
GET_CERTIFICATE  ──▶  ERROR(0x0F, LargeResponse)      ← 「這個回應塞不進去」
CHUNK_GET(0)     ──▶  CHUNK_RESPONSE(0)               ← 一次完整的來回
CHUNK_GET(1)     ──▶  CHUNK_RESPONSE(1)               ← 又一次
...
```

**每一塊都是一次完整的請求／回應,也就是一個匯流排 RTT。** 在 SMBus 100 kHz
上,RTT 是比頻寬更貴的那一半。所以這個參數不是「調大一點比較快」那種調校,
它決定來回次數。

而 `spdm-emu` 沒有這個旗標。它是:

```c
/* spdm_emu/spdm_emu_common/spdm_emu.h */
#define LIBSPDM_DATA_TRANSFER_SIZE (LIBSPDM_RECEIVER_BUFFER_SIZE - (標頭 + 尾))
```

要掃六個值,就要重建六次 build,每次十幾分鐘,而且六個 build 之間的差異
無法跟「參數造成的差異」分開。

#### 做法:一個 patch,一個新 flavor,一次重建

```bash
# 1) 建第三個 flavor。--seed-from 會複製 pqc 的原始碼樹,不用再下載幾 GB
bash harness/build_spdm_emu.sh pqc-dts --seed-from pqc

# 2) 掃描。十二臂,一個 build,約兩分鐘
bash harness/run_pair.sh --set dts --flavor pqc-dts --name w8-dts-sweep

# 3) 模型要對得上量測,對不上就不准發表
python3 bench/exp04_fragmentation.py --validate bench/data/w8-dts-sweep-*
```

`transport/data-transfer-size.patch` 加的是 `--data_transfer_size <bytes>`,
而且**只能往小的調**——告訴對方你收得下比你真的收得下更多,是對方會照做的謊。

#### 🔴 三件這一節真正要學的事

**① 「第二個 build 跟第一個可比」這句話要有東西撐。**
patch 看起來再小、再對,都可能改到第四個數字。所以掃描的六個點裡,
**故意放一個是沒 patch 的 build 自己算出來的值(4608)**:

```
P2-dts4608   46 packets   58,966 bytes   12 chunk 來回
P2-all       46 packets   58,966 bytes   12 chunk 來回     ← 沒 patch 的 pqc build
```

一模一樣。**這個「對照點」才是那個 patch 可以用的理由,diff 不是。**

**② 旗標是請求,不是事實——連傳輸參數也一樣。**
第一版 patch 用 `libspdm_set_data()` 設 DataTransferSize。它回
`LIBSPDM_STATUS_INVALID_STATE_LOCAL`(0x80010002),因為那個欄位在 buffer
註冊完之後就不准改了。**十二臂全部跑完、全部 exit 0、全部宣告的演算法都對,
而 DataTransferSize 全部是編譯期的值。**

抓到它的是 `check_negotiated.py` 新加的 `DTS=` 判斷:它從 pcap 的
`CAPABILITIES` 把兩邊宣告的值讀回來,跟這一臂要求的比。
那次失敗的 run 我留著沒刪(`bench/data/w8-dts-sweep-20260914T132232Z`)——
標準規則 11 要求「每個檢查都要被看到擋下過東西」,那個目錄就是證據。

**③ 模型跟外插是兩件事。** 掃描只有 1024 到 32768 六個點。
`bench/exp04_fragmentation.py` 的公式

```
chunks(L, DTS) = 0                                     若 L <= DTS
               = 1 + ceil( (L - (DTS-16)) / (DTS-12) ) 否則
```

被要求重現全部十二個 capture 的實測值,**十二個全中**。過了這一關,
它才可以用來講 42 或 256(真實 SMBus 裝置會宣告的值)——而那時候要說清楚
「這是模型的延伸,不是量測」。
**MCTP 的分段數則相反:沒有任何一個 capture 走過真的 MCTP,所以一律標
`[computed]`。** 見 `docs/fragmentation.md`。

#### 這一節產出的數字(拿去面試講的就是這三個)

| | 值 |
|---|---|
| 32 倍的 DataTransferSize 範圍內,位元組變化 | **3.1%** |
| 同一個範圍內,chunk 來回次數 | **59 → 0** |
| 把 responder 的 `CHUNK_CAP` 拿掉之後 | 少 3 次來回、少 9 個位元組 |

最後一列是反直覺的那個:**關掉 chunking 反而變便宜。** 因為 libspdm 在沒有
chunking 可用的時候,會改用 `GET_CERTIFICATE` 的 `Offset`/`Length` 分段取,
而那條路省掉了三次「問了被拒絕」的來回。這是 libspdm **requester 策略**的性質,
不是 DSP0274 的性質——這句限定要講出來。

### `LOG.md` 是這個 repo 裡最難重建的檔案

不是 README。README 可以從結果反推出來,`LOG.md` 不行——
它記的是還不知道答案的當下,是怎麼決定下一步的。

每一則要有五段:**現象 / 假設 / 先驗哪個、為什麼 / 根因 / 教訓**。

> ★ 「先驗哪個、為什麼」這一行是整個格式的重點。
> 「先驗 A,因為它最便宜而且能一次砍掉一半的可能性」是一個可以被檢查的決策;
> 「一個一個試」不是。前者能讓下一個人重用,後者只能讓下一個人重跑一次。

---

### 11.8 ★ 把「算出來的數字」換成「數出來的數字」(W09 做的事)

這一節是 Gate 5,也是這個 repo 到目前為止**唯一一次把已經 publish 的數字
從推算升級成實測**。

#### 問題長什麼樣

`docs/fragmentation.md` 第五節第一句話原本是:

> **No packet count here has been observed.**

意思是:這個 repo 講了八週的「後量子憑證鏈會被切成幾個 MCTP 封包」,全部是
**拿量到的訊息長度去除**算出來的,不是數出來的。每一個都老實標了
`[computed]`,但那不是答案,那是誠實。

為什麼一直沒量?因為這台機器的 kernel 沒有 `CONFIG_MCTP`:

```bash
zcat /proc/config.gz | grep CONFIG_MCTP
# CONFIG_MCTP is not set
```

`socket(AF_MCTP, SOCK_DGRAM, 0)` 直接回 `errno 97`。

#### ★ 這一步的關鍵想法

**那個子系統不必在宿主上,它只要在「同一批 binary 跑得起來的地方」就好。**

所以:自己編一顆有 `CONFIG_MCTP=y` 的 kernel,**開一台 VM,而那台 VM 的
root 檔案系統就是宿主的檔案系統**(用 virtio-9p 掛成唯讀)。W01 編好的
`spdm_requester_emu` 原封不動、同一個路徑、同一組憑證,在 guest 裡直接跑。

**為什麼不是直接重編宿主的 kernel?**(這題面試會問)

因為 `bench/data/` 底下**二十五個** run 目錄的 `manifest.json` 每一份都記了
`host_kernel`。把宿主 kernel 換掉,那二十五行就全部指向一顆這台機器上已經不
存在的 kernel —— 而這個 repo 的核心主張就是「每個數字都指得回它產生時的條件」。
理由寫在 [`docs/decisions/0010-a-kernel-the-host-does-not-have.md`](docs/decisions/0010-a-kernel-the-host-does-not-have.md)。

#### 怎麼跑

```bash
# ① 編 guest kernel(第一次約 13 分鐘,之後會跳過)
bash harness/build_guest_kernel.sh

# ② 編 MCTP 的 userspace 工具(CodeConstruct 的 mctp,OpenBMC 也是用這支)
bash harness/build_mctp_tools.sh

# ③ ★ 真握手跑在真 MCTP 網路上(古典 + 後量子兩臂)
bash harness/run_afmctp.sh --arms A0,P2 --name w9-afmctp

# ④ 真的 PCIe DOE 信箱(需要自己編的 QEMU ≥ 9.1)
bash harness/build_qemu_doe.sh
bash harness/run_doe.sh --name w9-doe
```

#### 成功長什麼樣

```
  ★ the model reproduces every observed packet count: 46 SPDM messages,
    58736 SPDM bytes, 953 packets at MTU 64
  ★ 14 of 46 messages (*) are lengths at which the subtract-the-header
    formula would have given a different answer, and it is wrong at every one
  ok   Gate 5: a handshake completed over a transport that is not a TCP socket
```

DOE 那條:

```
  ★ VERSION: SPDMVersion 0x10, code 0x04, 5 entries
     versions advertised: 1.0 1.1 1.2 1.3 1.4
```

#### ★★ 對照組是這一節最重要的部分

一個握手**被錄了兩次**,由兩支沒有共用任何程式碼的工具:

| 檔案 | 誰寫的 | 一筆是什麼 |
|---|---|---|
| `A0.pcap` | `spdm_requester_emu --pcap` | 一則 SPDM **訊息** |
| `A0.link.pcap` | `harness/mctp_capture.py`(AF_PACKET) | 一個 MCTP **封包** |

第一份跟 W08 socket 那條的 capture **逐則長度完全一樣**(A0 22 筆 6559 bytes、
P2 46 筆 58966 bytes)。所以**換傳輸沒有改變協定**,兩層之間差的就是分段,
而那正是要量的東西。第二份跟第一份用已知的 framing 對得起來:
`6449 + 5 × 22 = 6559`,腳本每次跑都會斷言這條等式。

#### ★ 這一週打自己臉的地方(面試講這段)

做校準的時候順手把「錯誤公式」也算了一次,結果發現:

> `docs/fragmentation.md` 跟 `exp04_fragmentation.py` 的註解都寫著
> 「177 bytes 就是那個判別案例,錯的公式會算出 4」。
> **`59 × 3 = 177`,所以錯的公式算出來也是 3。**

那個被選來「分辨兩個公式」的案例,**分辨不了任何東西**,而且 1..399 裡有 300
個長度兩個公式都同意。為什麼三週沒被抓到?因為**對手公式只寫在註解裡,從來
沒有被執行過** —— 自我測試只斷言「對的公式給對的答案」,而那件事在任何一個
證明不了什麼的長度上都會成立。

修法不是改一個數字,是改機制:對手公式現在是一個**函式**,「兩者不同」變成
**算出來的斷言**,而且 `--observed` 現在會報告一份 capture 裡**有幾則訊息真的
能分辨兩個公式**(校準那份是 12 則裡 7 則)。這是 `docs/roadmap.md` 新增的
**第 18 條常規**。

#### ⚠️ 兩個「跑起來像成功、數字卻是錯的」的坑

| 症狀 | 根因 | 修法 |
|---|---|---|
| 同一個實驗跑兩次,一次 953 個封包、一次 920 | **抓封包的 socket 自己丟了 33 個**(AF_PACKET 預設 buffer 撐不住一次爆量)。第一個看到的症狀是 86 行「continuation with no SOM」,那是在**診斷網路**,但故障在**儀器** | 讀 `PACKET_STATISTICS` 的丟包計數,非零就讓這次 capture 失敗;buffer 開大 |
| capture 的第一個封包 `SOM=False` | **capture 比流量晚啟動**。`sleep 0.7` 被拿來當同步用,但 Python 的啟動要穿過 9p | capture 綁好 socket 之後寫一個 ready 檔,產生流量的那一端**等那個檔**,不睡覺 |

**兩個坑用的是不同的檢查抓到的**,這件事本身是重點(`docs/roadmap.md` 第 13 條):
「capture 數量 vs 介面計數器」看不出晚啟動,「重組檢查」看不出均勻丟包。

#### ⚠️ 還有一個坑,查不到會浪費一天

`mctp link serial` 要在**初始的 network namespace** 裡跑,不能在目標 namespace
裡跑。`drivers/net/mctp/mctp-serial.c` 的 `mctp_serial_open()` 裡
`alloc_netdev()` 跟 `register_netdev()` 之間**沒有 `dev_net_set()`**,所以介面
永遠註冊在 `init_net`。第一版腳本「照直覺」在 namespace 裡跑,結果是:**沒有
任何一個指令報錯,也沒有任何一個介面出現**。正確做法是先在初始 namespace 建
好,再用 `ip link set <dev> netns <ns>` 搬過去。

---

### 11.9 ★ 一支測試說你錯了,要怎麼知道是不是它錯了(W10 做的事)

**一句話:** 官方一致性測試判了你四個 FAIL。你要怎麼分辨「我的裝置壞了」跟
「那支測試壞了」?**答案是:把它判 FAIL 的那個簽章,自己驗一次。**

#### 先講三個會害你白忙半天的事

**① 結果不在 stdout,在 `test.log`。**

```bash
# 計畫書寫的是這樣,而這兩行會印出 0
./harness/run_validator.sh 2>&1 | tee /tmp/v.log
grep -ciE 'PASS|FAIL' /tmp/v.log     # -> 0
```

因為 `common_test_utility_lib.c` 裡是 `fopen("test.log", "w+")`,每一行結果都
`fprintf` 到那個檔案,**而且開在「當下的工作目錄」**。主程式只往 console 印四行
banner。

**② 結束碼恆為 0。** `spdm_device_validator_sample.c` 的 `main()` 最後是無條件
`return 0`。全部 assertion 都失敗也是 0,連都沒連上也是 0。

> ★ 這是這個 repo 第三次踩同一個形狀:管線的結束碼、`spdm_dump` 的輸出長度、
> 現在是一個常數的 return value。**三次都是「拿手邊最容易取得的訊號」代替
> 「真正的判準」。**

**③ `NOT_TESTED` 兩邊都不算。** 那支測試自己印的 footer 是
`pass: 1077, fail: 8`,但它總共記錄了 **1140** 個 assertion。差的 55 個是
`NOT_TESTED` ——「想測但測不成」。**那 55 個才是有訊息量的。**

#### 怎麼跑

```bash
bash harness/run_validator.sh            # 四臂,大約四分鐘
bash harness/run_validator.sh --list     # 四臂各是什麼
```

四臂長這樣,而且**三臂的目的是讓它講出 PASS 以外的話**:

| 臂 | 動了什麼 | 為什麼要有它 |
|---|---|---|
| `caps-default` | 什麼都沒動 | 基線。只有這一臂的數字可以被引用成「我的 responder 考幾分」 |
| `caps-no-mut-auth` | responder 的能力集少一個 `MUT_AUTH` | 量「一個 capability 位元值多少錢」 |
| `proxy-inert` | 中間插一支**什麼都不改**的 proxy | **控制組,而且要先跑。** 沒有它,下一臂紅了你分不出是「測試抓到了」還是「proxy 轉不動一份 1.6 MB 的握手」 |
| `proxy-flip-sig` | 同一支 proxy,翻掉一個簽章的最後一個 byte | **校準。** 一支只被看過「通過」的測試,沒有被證明過它會「失敗」 |

#### 結果:一個位元組,和一個位元

**校準那一臂:**

```
proxy-inert  ->  proxy-flip-sig
  regressed        1
  improved         0
  disappeared    122
    PASS->FAIL  7.6.7      response signature
```

恰好一個 assertion 變紅,而且是驗簽的那一個。消失的 122 個**全部在同一個 case
裡面**(失敗之後就 return 了),工具會單獨斷言這件事 —— 不然一次連鎖失敗可以
藏住第二個無關的破洞。

**能力位元那一臂:**

```
1.0   0x00000037 -> 0x00000037   moved: nothing      <- 1.0 根本沒有這個位元
1.1   0x0000fbf7 -> 0x0000faf7   moved: MUT_AUTH_CAP
1.2   0x001afbf7 -> 0x001afaf7   moved: MUT_AUTH_CAP
1.3   0x399afbf7 -> 0x399afaf7   moved: MUT_AUTH_CAP
1.4   0xb99afbf7 -> 0xb99afaf7   moved: MUT_AUTH_CAP
```

**assertion 從 1140 變成 1751 —— 多了 611 個。** 原本 `FINISH_RSP`、
`HEARTBEAT_ACK`、`KEY_UPDATE_ACK`、`END_SESSION_ACK` 四整組的 footer 都是
`pass: 0, fail: 0`,看起來像「這組沒有 assertion」,其實是「這組的每一個 case
都起不來」。

> ★ **而且不是開越多越好。** 關掉那個位元之後,`3.5.15` 跟 `3.6.15` 兩個原本
> 看不到的 assertion 變紅了。**沒有一個組態可以把報告最大化** —— 所以一份
> conformance 報告如果沒有附上組態,就是一個沒有單位的數字。

#### ★ 然後是最硬的那一步:證明那四個 FAIL 是測試自己的錯

失敗的四個 case 有一個共同點,而且要讀原始碼才看得到:**它們都是「沒有去抓憑證」
的那幾個**。

| case | 這個 case 送了什麼 | 結果 |
|---|---|---|
| 6.1 | VCA + `GET_DIGESTS` + `GET_CERTIFICATE` | PASS |
| 6.2 | 只有 VCA | **FAIL** |
| 6.3 | VCA + `GET_DIGESTS` | **FAIL** |
| 6.14 | VCA + `GET_CERTIFICATE`(沒有 digests) | PASS |

**抓憑證是充分且必要條件,digests 完全無關。**

原因在 `spdm_responder_test_6_challenge_auth.c`:setup 在 `:202` 抓了憑證鏈,
然後 case 本體在 `:363` 又呼叫了一次 `libspdm_init_connection()` —— 那會送
`GET_VERSION`,而 `GET_VERSION` 會呼叫 `libspdm_reset_context()`,**把 setup
抓到的憑證鏈清掉**。mask 裡沒有 `GET_CERTIFICATE` 的 case 就再也沒有公鑰可以驗簽。

**但「我讀原始碼讀出來的」不算數。** 所以:

```bash
python3 harness/challenge_verify.py     bench/data/w10-validator-20260919T184429Z/caps-default.pcap
```

它做的事是:從 capture 把 `M1M2 = A || B || C` 重建出來,然後**把密碼學交給
openssl**(這個分工是 `certs/check_chain.py` 訂的:「這個檔案管結構,openssl
管密碼學」)。

★ **而且它會先校準再回答:**

```
calibration -- 有抓憑證、那支測試判 PASS 的連線
  9 of 9 verify
  ok   這個 transcript 模型重現得出一個那支測試接受的簽章

disputed -- 沒抓憑證、那支測試判 FAIL 的連線
  2 of 2 verify
    packet 284   M1M2 266 B (144 +   0 + 122)  -> True
    packet 306   M1M2 370 B (144 + 104 + 122)  -> True
```

中間那一欄就是整個發現:通過的那些有 1775 bytes 的憑證交換,失敗的那兩條是
**0** 跟 **104** —— 而且那兩條短 transcript 上的簽章**是好的**。

> **判決:responder 的簽章是對的。那支測試判 FAIL,是因為它自己把驗簽要用的
> 輸入丟掉了。**
>
> 如果校準那一步沒過,這個工具**不會給任何判決** —— 因為那代表我的 transcript
> 模型是錯的,而不是那支測試錯了。這是整支工具最重要的一行。

#### fuzz 那半邊,和一句被撤掉的話

原本要講的是「**我的 fuzz 種子是真實訊息,不是亂數**」。前半句是真的,後半句
比錯了對手:**libspdm 自己就附種子語料**(69 個目錄、81 個檔案)。

```bash
bash harness/run_fuzz.sh --no-fuzz     # 只做確定性的那半:抽種子 + 語料對照
bash harness/run_fuzz.sh --seconds 420 # 加上有時間盒的真 fuzz
```

`afl-showmap -C` 會把整個語料跑一遍、回報碰到的 edge 聯集 —— 確定性的,所以是
單一數值不是中位數。

```
  target                                 upstream   mine   both   added
  test_spdm_responder_algorithms              601    685    711    +110
  test_spdm_responder_heartbeat_ack          2955   2898   2959      +4   <- 我的比較差
  test_spdm_responder_version                 442    442    442       0
```

**8 個 target 裡有 3 個,我的種子碰到的 edge 比上游那一顆手寫種子還少。**
而且第一次跑的時候(只用兩份握手 capture)更慘:`algorithms` 只有 378。

> ★ **種子好不好,不在於它是不是真的,在於它來自的那次執行有沒有走到別的地方。**
> 兩份成功的握手,每種訊息就只有一顆「長得很正確」的樣本 —— 沒有版本不符、沒有
> 無效參數、沒有錯誤路徑,因為走到那些的握手不會成功。把一致性測試那份 capture
> 加進來(它**故意**送那些),數字就翻過來了。

還有一個發現不是關於 fuzz 的:**17 個 target 裡有 10 個一顆種子都抽不到**,因為
這個專案**用來量測的**握手從來沒有建立過 session(`--exe_session NO_END` 不包含
`EXE_SESSION_KEY_EX`)。(2026-09-23 更正了措辭:原本寫「這個專案的握手」,
但第一週那次沒設 `NO_END` 的 run 有建立 session,見 §11.10 的更正。)`harness/lib/arms.sh` 的註解從寫下來那天就講了這件事,
**是一份 fuzz 語料讓它的後果變成看得見的**。

#### 「跑了沒發現東西」要怎麼講才誠實

```
  11,432 次執行 / 1,260 秒  =  每秒 9.07 次
```

AFL 自己在 log 裡就警告 `The target binary is pretty slow!`。照這個速度:

| 預算 | 執行次數 |
|---|---:|
| 實際跑的 21 分鐘 | 11,432 |
| 計畫書要的 8 小時 | 約 261,000 |
| 24 小時 | 約 784,000 |

一個 fuzz campaign 正常是用**百萬次**在算的。所以就算真的跑滿八小時,離「沒有
崩潰這件事能說明什麼」還差三個數量級 —— **這才是本機 fuzz 找不到東西的誠實理由,
而不是「運氣不好」。**

### 11.10 ★ 一個漏洞在文件裡,不在程式裡(W11 做的事,上半)

這一節是整個專案技術上最高的一個點,而且它跟「寫程式」幾乎沒關係。

#### 先講清楚 transcript 是什麼

SPDM 的簽章**不是一則訊息簽一次**。握手快結束的時候那個簽章,簽的是
**transcript**:到目前為止交換過的每一則訊息,照送出的順序接起來。

為什麼要這樣做?因為這樣那個簽章講的就不是「這則訊息是真的」,而是
**「整段對話就是我們兩邊以為的那段對話」**。中間人只要動了任何一則訊息,
接起來的位元組就變了,簽章就驗不過。

所以整個設計靠的是這一句:

> **一個簽章值多少,等於它涵蓋了多少位元組。**

反過來說:**如果有一則訊息被收下了、卻沒有被接進 transcript**,那攻擊者去改
那則訊息,**不會動到任何簽章涵蓋的東西**。簽章照樣驗過、握手照樣完成、
驗證方照樣滿意——而它滿意的那件事,不是實際發生的事。

#### SPDM 1.4 改了什麼,以及沒改什麼

1.4 在 `FINISH` 加了兩個欄位,而且放在簽章**前面**:

```
  offset 0   SPDMVersion          ┐
  offset 1   RequestResponseCode  │ 這四個 byte 叫 "SPDM Header Fields"
  offset 2   Param1               │ ——就只有這四個
  offset 3   Param2               ┘
  offset 4   OpaqueDataLength     ← 1.4 新增
  offset 6   OpaqueData           ← 1.4 新增
  ...        Signature            ← 簽 transcript
  ...        RequesterVerifyData  ← transcript hash 的 HMAC
```

**但有五個 transcript 定義沒跟著改**,還是寫到「`[FINISH].SPDM Header Fields`」
為止——也就是只到那四個 byte。所以照字面讀,那兩個新欄位**是在簽章前面送出去
的、而且沒有被簽到**。中間人可以改,簽章跟 HMAC 都還是過。

#### ★★ 修正不是補一個欄位,是換一種寫法

我把 1.4.0 跟 1.4.1 兩份 PDF 都抓下來、都釘了 pin、都讀了,然後對照:

| | 1.4.0(有洞) | 1.4.1(修好) |
|---|---|---|
| 最後一步 | `[FINISH] . SPDM Header Fields` | `[FINISH] . * except the Signature and RequesterVerifyData fields.` |

```bash
# 這兩個數字是這一節的證據,自己跑一次就知道
pdftotext -layout "$LAB_DIR/spec/dsp0274_140.pdf" - | grep -c 'SPDM Header [Ff]ields'   # 5
pdftotext -layout "$LAB_DIR/spec/dsp0274_141.pdf" - | grep -c 'SPDM Header [Ff]ields'   # 0
```

**五次變零次**,而五正好是通報說受影響的定義數量——這個數字是我自己從文件算出來
的,不是抄通報的。

差別在**形狀**:

| | |
|---|---|
| **列舉**(1.4.0) | 「要放進來的是這幾項」。訊息一改,就得有人回來改這段——**而沒有任何機制強迫那件事發生** |
| **排除**(1.4.1) | 「除了簽章本身以外全部」。對一個**還不存在的欄位**也是對的 |

#### ★★★ 而且那個列舉,寫下來的時候是對的

SPDM **1.3** 的 `FINISH` 就是四個 byte 的 header 加簽章,中間什麼都沒有。
所以「SPDM Header Fields」**真的就是簽章該涵蓋的全部**,那段話當時完全正確。

**它是在別人改了另一章的 Table 80 之後才變錯的。**

> 這就是這個類別:**一句對的話,被遠處的一個改動弄錯了,而中間那個接縫沒有任何
> 東西在看。**

面試講到這裡可以收在一句:**「簽章的安全性不是來自『有簽』,是來自
『涵蓋了每一個在它之前送出去的位元組』。而那個保證要寫成排除,不能寫成列舉。」**

#### 讀 CVSS 向量比讀分數值錢十倍

```
CVSS:4.0/AV:A/AC:L/AT:P/PR:N/UI:N/VC:N/VI:H/VA:N/SC:N/SI:N/SA:N     6.0
```

| | |
|---|---|
| `VC:N` / **`VI:H`** / `VA:N` | **只傷完整性**。不洩密、不影響可用性——攻擊者改的是兩邊都以為驗過的資料 |
| `AV:A` | **Adjacent**,攻擊者要在同一條匯流排上,不是從網路 |

分數是查來的,向量是懂的。而且這三個 2026 通報裡,**它是分數最低的那個,卻是唯一
有 CVE 的那個**(§11.11)。

#### 我做了什麼、沒做什麼

- **做了**:抓兩個版本、算 hash、釘 pin、讀了 633–644 節、對照五個定義;把類別寫成
  測試(`negative/test_transcript_coverage.c`,8 個 case、6 個錯誤版本)。
- **沒做**:發現它、回報它、實作修正。它是 2026-06-02 在 libspdm issue 3633 被提出的。
- **做不到(2026-09-23 更正)**:原本這裡寫「**這個專案從來沒有建立過 secure
  session**,所以這裡根本沒有 `FINISH`」——**錯了**。第一週那次 `--exe_session`
  留預設值的 run(`bench/data/healthcheck-pqc-20260811T052725Z/minimal.pcap`)
  裡**有一個 SPDM 1.4、雙向認證的 `FINISH`**,只是從來沒有人 decode 過那份 capture,
  直到 `harness/census.sh` 把全部 152 份掃了一遍才找到。兩端都是 libspdm,
  握手成功只代表**兩端一致**,不代表用的是哪一版定義。讀原始碼,libspdm 的 requester
  簽章前會把 `OpaqueData` 也放進 transcript(1.4.1 的意思),**但還沒拿那份 capture
  驗證**——驗那一個簽章在兩種 transcript 下哪個會過,就是下一個實驗。
  測試是**模型**,檔案第一段就這樣寫。

⚠️ **講法注意。** 不要說「我找到一個 SPDM 的漏洞」。要說
**「我讀了兩個版本的規格,把那五個定義的差異整理出來,並且把那個類別寫成一個會失敗的測試。」**

---

### 11.11 ★ 那我自己的 build 有沒有這些洞?(W11 做的事,下半)

上一節跟 `negative/` 講的都是**類別**。這一節是另一個問題,而且是別人真的會問的
那一個:**你自己跑的那份 libspdm,有沒有這三個洞?**

#### 「版本號在範圍內」不是答案

這是最容易做錯的一步。版本比對只是**五件事裡的第一件**,而另外四件常常跟它講不一樣:

| # | 問題 | 誰回答 |
|:--|---|---|
| 1 | 釘住的版本在受影響範圍裡嗎 | 通報 |
| 2 | 修正那個 **commit** 是我這個 commit 的祖先嗎 | GitHub 的 `compare` API |
| 3 | 修好的那**一行**在我硬碟上的原始碼裡嗎 | `grep`,對編譯器真的讀的那個檔 |
| 4 | 有問題的程式碼**有被連進去**嗎 | build 出來的 `.a` |
| 5 | 通報自己列的先決條件成立嗎 | capability 位元 + assert 展開成什麼 |

**2 跟 3 是故意重複的。** standing rule 12:兩條路走到同一個答案,就讓它們互相
印證。工具如果發現兩邊不合,會印 `DISAGREEMENT` 然後非零結束,**而不是挑一個**
——因為一條錯的路,長得跟一條對的路一模一樣。

```bash
# 量一次(要網路,要 LAB_DIR 的 build tree)
bash harness/run_exposure.sh

# 只從已經 commit 的證據重算(CI 跑的就是這兩個)
python3 harness/check_advisories.py --selftest
python3 harness/check_advisories.py --check docs/advisories.md
```

#### 結果

| | `stable` — libspdm 3.8.0 | `pqc` — libspdm 4.0.0-rc |
|---|---|---|
| DMTF-2026-0001 | **PRESENT-NOT-REACHABLE** | NOT-AFFECTED |
| DMTF-2026-0002 | **AFFECTED** | NOT-AFFECTED |
| DMTF-2026-0003 | NOT-APPLICABLE | NOT-APPLICABLE |

#### ★★ 最值得講的那一格:`stable` / DMTF-2026-0002

五個先決條件**全中**,而最後一個不是程式寫錯:

```c
void libspdm_copy_mem(void *dst_buf, size_t dst_len,
                      const void *src_buf, size_t src_len)
{
    ...
    if (src_len > dst_len) {
        LIBSPDM_ASSERT(0);      // ← 檢查在這裡
    }
    while (src_len-- != 0) {    // ← 而且不管上面怎樣,照抄
        *(dst++) = *(src++);
    }
}
```

**檢查是有的。它寫成 `LIBSPDM_ASSERT`。**
這個專案用 `TARGET=Release` build,而 `libspdm/CMakeLists.txt:886` 是:

```cmake
add_compile_options(-DLIBSPDM_DEBUG_ENABLE=0)
```

`debuglib.h` 看到這個就把 `LIBSPDM_ASSERT(expression)` 定義成**空的**。
所以那個邊界檢查**在原始碼裡、不在二進位檔裡**,而下面那個複製迴圈照跑。

> ★ 這一句值得背:**「那個檢查存在,而且在出貨的 build 裡什麼都不做——
> 因為它是用 assert 寫的,而 assert 就是那個保證會在 release build 裡消失的東西。」**

**但這不影響這個 repo 的任何一個數字。** 要踩到它得對 **`stable`** 的 responder
送 `GET_MEASUREMENT_EXTENSION_LOG`,而**沒有任何一份 `stable` 的 capture 建立過
session,也沒有一份用明文送過它**。

> ⚠️ **2026-09-23 更正。** 原本這裡寫「**所有 committed capture 裡一次都沒送過**
> ——這句話也是工具從 decode 檔算出來的」。工具只讀得到**有 decode 的** capture:
> 152 份裡的 132 份。第一週那份沒 decode 的 capture 裡有一段加密的 SPDM 1.4
> session,照模擬器自己的原始碼(`spdm_requester_session.c`),它**會**在 session
> 裡送這個請求——只是加密了,誰都看不到;而且那是 `pqc`,修正已經在裡面。
> **「工具算出來的」只對它讀得到的那些 capture 成立**,而它讀不到哪些,以前沒有
> 任何東西會說。現在 `verify_repo.sh` 會:每一份 capture 要嘛有 decode、要嘛在
> 最新的 `census.tsv` 裡,否則紅燈。

#### ★ 另一格也值得講:present ≠ reachable

`stable` 對 DMTF-2026-0001 是 **PRESENT-NOT-REACHABLE**:版本在範圍內、修正沒有、
`CSR_CAP` 98 份 capture 全都有廣告——**但那段程式在 `cryptlib_mbedtls` 裡,
而我們連的是 `libcryptlib_openssl.a`**。三個後端都在樹裡,連進去的只有一個。

再往上推一層,這就是後量子那條線的隱藏成本:

> **同一個協定函式庫,換一個 crypto 後端,攻擊面就是另一組。**
> 而 PQC 只有 OpenSSL 後端有。所以「要不要上 ML-DSA」不只是演算法問題,
> 是**整個 crypto 後端要不要換**的問題,而換後端會換掉一整組缺陷。

`docs/pqc-cost.md` 量的是位元組;**這是那個成本裡不是位元組的部分。**

#### ⚠️ 這一節不是什麼

- **不是 libspdm 的稽核。** 是一台筆電上兩個 checkout 的六個判定。
- **不是漏洞通報。** 三個通報都已經公開、都已經修好。那個 AFFECTED 講的是一份
  **故意釘住的舊版本**,修法是 `git checkout 3.8.2`。
- **不是「`pqc` 是安全的」。** 是「那兩個特定的修正在裡面,而且是兩條路各查一次」。

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
# 只有要重跑 DataTransferSize 掃描才需要第三份:
bash harness/build_spdm_emu.sh pqc-dts --seed-from pqc
bash harness/healthcheck.sh pqc --write-baseline

# 4. 對照:新的 BUILD_PIN 應該跟 repo 裡釘的一樣
diff <(grep libspdm= ~/spdm-lab/work/spdm-emu-pqc/BUILD_PIN.txt) \
     <(grep libspdm= third_party/spdm-emu-pqc.pin) && echo "PINS MATCH"
```

**如果 `PINS MATCH` 沒印出來**,代表上游動了。這不是壞事,是資訊——
把新舊 hash 記進 `LOG.md`,那就是「這塊變動很快,所以我引用任何行為之前
都直接讀 repo 當下的狀態」這句話的證據。

### ★ 12.1 不用重建也要做的那一半:乾淨 clone 跑一次檢查

上面那段要重建整個 build tree,四十分鐘。**但真正抓到東西的那一半只要九十秒**,
而且不需要建任何東西:

```bash
cd /tmp && rm -rf cc && git clone <這個 repo> cc && cd cc
bash harness/verify_repo.sh          # 全部檢查,不碰上游
python3 rats/appraise.py matrix --check
make -C c-drills
```

**這是唯一一個「別人會看到什麼」的檢查,而且它看得到的東西,在你自己的樹裡
永遠看不到。** 2026-09-12 第一次把它當成例行動作跑,九十秒抓到兩個缺陷:

1. 一份已提交的判定檔裡帶著**絕對路徑** `/mnt/c/Users/Key20/...`。在寫它的那棵樹
   裡,那個路徑是對的,所以沒有任何檢查看得出問題。
2. `rats/mint_reference.sh` 因為「沒有金鑰」就**自己產了一把**——而「沒有金鑰」
   正是乾淨 clone 的樣子,因為私鑰刻意不進 git。產一把新的,等於把所有已發布
   參考值的簽章金鑰換掉,而症狀要到三個檢查之後才浮出來。

第二個尤其值得記住:那支腳本**本來就有**一個「不要覆蓋已存在的金鑰」的防護。
那是另一種形狀。**寫防護的時候要問的是「這條會在誰的機器上觸發」**——
只會在作者機器上觸發的防護,是為唯一不需要它的人寫的。

> 順帶一提:在乾淨 clone 裡 `bash rats/mint_reference.sh` **應該要拒絕**,
> 並且告訴你原因。它拒絕,就代表那個防護是活的。

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

# ── 收證據(★ 七臂,有出處)────────────────────────────
bash harness/capture.sh                       # 預設 --name w2-baseline
bash harness/capture.sh --name w4-baseline    # 每週的基線換個名字
bash harness/run_pair.sh                      # ★ PQC 矩陣二十臂,協商結果對不上就整個 run 失敗
bash harness/run_pair.sh --list              # 先看這次會跑哪些臂(不跑)
bash harness/run_pair.sh --set ab            # 只跑原本的 A0/P2 四臂
bash harness/run_pair.sh --only A0-all        # 只跑一臂(除錯用)

# ── ★ 真實傳輸(W09,見 §11.8)───────────────────────────
bash harness/build_guest_kernel.sh            # 有 CONFIG_MCTP 的 guest kernel
bash harness/build_mctp_tools.sh              # CodeConstruct 的 mctp CLI
bash harness/run_afmctp.sh --arms A0,P2       # ★ 握手跑在真的 MCTP 網路上
bash harness/run_afmctp.sh --arms A0 --name smoke --timeout 600   # 只跑一臂
bash harness/build_qemu_doe.sh                # QEMU 9.2(發行版的 8.2.2 沒有 spdm_port)
bash harness/run_doe.sh                       # ★ 一則 SPDM 穿過真的 PCIe DOE 信箱
python3 bench/exp04_fragmentation.py --observed bench/data/w9-afmctp-*/P2.link.pcap

# ── ★ DataTransferSize 掃描(W08,見 §11.7)─────────────
bash harness/build_spdm_emu.sh pqc-dts --seed-from pqc   # 第三個 flavor,一次
bash harness/run_pair.sh --set dts --flavor pqc-dts --name w8-dts-sweep
python3 bench/exp04_fragmentation.py --validate bench/data/w8-dts-sweep-*
python3 bench/exp04_fragmentation.py bench/data/w8-pqc-matrix-*/P2-all.pcap --mtu 64 128 256

# ── 把 pin 補正確,但不要重新編譯 ────────────────────────
bash harness/build_spdm_emu.sh pqc --pin-only  # ★ 只重寫 BUILD_PIN.txt
#   2026-09-14 用它把「libspdm 自己那份 OpenSSL 3.5.5」補進所有 pin。
#   重建會換掉已發表數字背後的執行檔,所以不能用重建來修 provenance。

# ── 改上游 · 篡改(★ W04~W05,見 §8.8 與 docs/tamper.md)──
bash harness/apply_device_patch.sh pqc --build      # 裝 patch 並重建
bash harness/apply_device_patch.sh pqc --status     # 現在裝了沒
bash harness/apply_device_patch.sh pqc --revert     # 拆掉(要再重建)
bash harness/tamper.sh                              # 十個 case,約一分鐘
bash harness/tamper.sh --only t2a_record            # 只跑一個

# ── 線上篡改:那支 proxy(★ Table 1 的 2a / 2b)──────────
python3 harness/tamper_proxy.py --listen 2324 --forward 2323 --passthrough
python3 harness/tamper_proxy.py --listen 2324 --forward 2323 --flip-record 1:36
python3 harness/tamper_proxy.py --listen 2324 --forward 2323 --flip-signature -1
python3 harness/tamper_proxy.py --self-test         # ★ 十三個檢查全部要被打到
#   requester 那邊要加 --port 2324;responder 不加,它還是聽 2323

# ── 讀 emulator 的 log 說了什麼 ─────────────────────────
python3 harness/spdm_status.py <run>/t2a_record.req.log   # 命名那個號碼
python3 harness/spdm_status.py --decode 0x80020001        # 不用 log 也能拆
python3 harness/spdm_status.py --self-test
python3 device/gen_measurements.py --out /tmp/m.bin           # 預設 = 重現上游
python3 device/gen_measurements.py --svn 5 --out /tmp/m5.bin
python3 device/gen_measurements.py --flip-block 1 --flip-offset 36 --out /tmp/t.bin
python3 device/gen_measurements.py --describe /tmp/m.bin
make -C device test                                 # loader,兩個 sanitizer
make -C device interop                              # C 讀的跟 Python 寫的要一致

# ── 憑證:要翻哪一個 byte ────────────────────────────────
python3 certs/check_chain.py certs/out --locate      # 位移 ＋ 那是什麼
python3 certs/check_chain.py certs/out --self-test   # 四種破壞,四個檢查

# ── ★ 判定:拿到量測之後呢(W06,見 §11.5)──────────────
R=$(ls -d bench/data/*-tamper-* | tail -1)
python3 rats/appraise.py appraise "$R/t0_clean.decode.txt"   # 應 PASS,exit 0
python3 rats/appraise.py appraise "$R/t1_meas.decode.txt"    # 應 FAIL,exit 1
python3 rats/appraise.py matrix --check             # 十條臂,比對 out/expected.json
python3 rats/appraise.py selftest                   # 每一種破壞法,八個機制全要被打到
bash rats/test_svn_policy.sh                        # ★ 四案例 × 新舊兩政策,只有一格可以動
#   exit 0 通過 · 1 判它失敗 · 2 判不出來。1 跟 2 一定要分開看

# 中間步驟(想看某一段長什麼樣的時候)
python3 harness/fields.py "$R/t0_clean.decode.txt" --emit-record /tmp/rec.bin
python3 rats/appraise.py evidence  "$R/t0_clean.decode.txt" -o /tmp/ev.json
python3 rats/appraise.py reference "$R/t0_clean.decode.txt" -o /tmp/ref.json
python3 rats/appraise.py to-cbor -i /tmp/ref.json -o /tmp/ref.cbor
python3 rats/appraise.py to-json -i /tmp/ref.cbor -o /tmp/back.json

# ── 參考值:發行者那一端 ────────────────────────────────
bash rats/mint_reference.sh                         # 沒變就不重簽(ECDSA 是隨機的)
python3 rats/cose.py verify -i rats/ref/clean.corim --key rats/keys/ref-signer.pub
python3 rats/cose.py inspect -i rats/ref/clean.corim
python3 rats/cose.py selftest                       # 106 項,含 RFC 8949 原始向量
#   私鑰不在 git 裡:乾淨 clone 驗得了,重簽不了(這是刻意的)

# ── 跟 DMTF 那套比對(要有 spdm-emu checkout)────────────
bash rats/interop.sh                                # 16 項比對,寫 rats/interop/report.md

# ── 分析:封包層 ────────────────────────────────────────
python3 harness/pcapcount.py <file>.pcap
python3 harness/pcapcount.py <file>.pcap --json
python3 harness/pcapcount.py <file>.pcap --list         # 每個封包一行
python3 bench/pcapstat.py <file>.pcap                   # 每種訊息幾個 byte
python3 bench/pcapstat.py <file>.pcap --list            # 每個封包一行,含訊息名
python3 bench/pcapstat.py <file>.pcap --check           # ★ 要跟 fields.py 一致
python3 bench/pcapstat.py --selftest                   # ★ 餵它錯的答案,要求它拒絕
python3 harness/check_claims.py                        # ★ 每一個跨 capture 的比值重算一次
python3 harness/check_claims.py --show                 # 每個推導算出來是多少(含還沒宣告的)
python3 harness/check_claims.py --selftest             # 把值漂 1%,要求它變紅
#   它也會印憑證鏈:幾趟來回、每一趟幾個 byte、重建出來的總長對不對得上
#   磁碟上那個 DER(4 + 48 + 1845 = 1897)

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


# ── ★ 負面測試:三個 advisory 類別(W11,見 §11.10)──────
cd negative && make test      # 3 個 suite、24 個 case、21 個故意寫錯的實作
cd negative && make list      # 每個檔在斷言什麼、每個錯誤版本該動到哪幾個 case
bash negative/asan_demo.sh ./negative/test_oversized_field   # ASan 看得到/看不到什麼

# ── ★ 我自己的 build 有沒有這三個洞(W11,見 §11.11)─────
bash harness/run_exposure.sh                              # 要網路 + build tree
python3 harness/check_advisories.py --selftest            # 它答得出別的答案嗎
python3 harness/check_advisories.py --check docs/advisories.md
python3 harness/check_advisories.py --refresh             # 通報被改過了嗎(每週 CI 會跑)

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
| **CoRIM / CoMID** | 描述「參考值應該長怎樣」的標準格式(IETF RATS 的 draft)。CoMID 是裡面描述一個模組的那一層,每一筆是 `[環境, 量測值]`,環境裡就帶著量測 index —— 那是 DMTF 範例政策讀進去卻沒用的欄位 |
| **參考值(Reference Value)** | 「這個量測**應該**是多少」。SPDM 完全不提供這個,它是 RATS 的 Reference Value Provider(真實世界裡是韌體發行者)發布的 |
| **背書(Endorsement)** | 「**誰有資格**說應該是多少」。在這個 repo 裡就是參考值上的那個 COSE 簽章:驗不過,後面整條流水線一步都不跑 |
| **COSE** | CBOR Object Signing and Encryption(RFC 8152/9052)。用 CBOR 表達的簽章格式;這裡用的是 `COSE_Sign1`,簽的不是訊息本身而是 `["Signature1", 保護標頭, 外部資料, 內容]` 這個結構 |
| **`kid`** | key identifier,COSE 保護標頭裡的欄位。這裡是 `42`,看起來像裝飾:**在真實部署裡它代表「哪一個韌體發行者的簽章金鑰」**,因為一台機器裡的 verifier 可能同時信任 GPU 廠、SSD 廠、BMC 廠三份參考值,它要靠 `kid` 決定用哪一把公鑰驗 |
| **OPA / Rego** | Open Policy Agent,以及它的政策語言。判定規則寫在 `rats/policy.rego`。⚠️ OPA 從 1.0 起預設 **Rego v1**,語法跟 v0 不相容——DMTF 附的範例政策是 v0,在現在的 OPA 上會吐 11 個 parse error |
| **判定(Appraisal)** | 把證據跟參考值放在一起、套上政策、得出一個結果的那個動作。結束碼三種:0 通過、1 **判它失敗**、2 **判不出來** |
| **pcap** | 封包錄影檔。本專案所有證據的原始格式 |
| **libspdm** | DMTF 的 SPDM 參考實作(C 語言) |
| **spdm-emu** | 用 libspdm 做的 requester/responder 模擬器,兩個行程透過 TCP 對話 |
| **spdm-dump** | 把 pcap 逐欄位解開的工具 |
| **flavor** | 本專案的術語:一份釘死版本的 build。目前有 `stable`(spdm-emu 3.8.0)和 `pqc`(spdm-emu 4.0.0-rc);libspdm 跟著各自的 submodule 指標走 |
| **provenance / manifest** | 出處紀錄。每次實驗自動產生的 `manifest.json`,含上游 hash、完整指令列、每個檔案的 SHA-256 |
