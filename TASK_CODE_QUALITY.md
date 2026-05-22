# Route Tool 代码质量与逻辑完善任务

## 项目概述

**luci-app-route-tool** v0.3.6 — OpenWrt LuCI 插件，统一页面提供路由器分区备份/写入 + 存储诊断（SoC/网口/eMMC寿命/测速/内存/NAND/日志）。

项目路径：`/root/route-tool/`

## 文件结构（18文件，2204行，100KB）

```
files/usr/lib/lua/luci/controller/route_tool.lua   (213行) — LuCI控制器：API路由、上传、sysupgrade
files/usr/lib/lua/luci/view/route_tool/index.htm    (200行) — 前端页面：仪表盘+分区操作+测速
files/usr/libexec/route-tool                         (359行) — 主后端：分区检测/备份/写入
files/usr/libexec/route-tool.d/
  storage_system.sh    (195行) — SoC/网口/CoreMark/WiFi
  storage_speed.sh     (177行) — eMMC顺序读写测速
  storage_memory.sh    (169行) — 内存tmpfs填充测试
  storage_capacity.sh  (130行) — 容量详情
  storage_health.sh    (111行) — eMMC健康度(ext_csd)
  storage_detail.sh    (99行)  — eMMC CID/详情
  storage_nand.sh      (85行)  — NAND信息
  storage_bootlog.sh   (83行)  — 启动日志分析
  storage_smart.sh     (51行)  — 综合诊断入口
  storage_analyze.sh   (245行) — eMMC完整分析报告
CONTROL/control       — IPK包信息(v0.3.6-1)
Makefile              — OpenWrt编译
README.md             — 说明文档
install.sh            — 手动安装脚本
```

## 约束条件（必须遵守）

1. **BusyBox兼容**：所有shell脚本必须POSIX sh，不能用bashisms。不能用`grep -P`，不能用`[[ ]]`，不能用数组，不能用`$((0x))`在某些旧BusyBox上（用`printf '%d' "0x$hex"`代替）
2. **LuCI 25.x兼容**：子路由必须有`.leaf = true`
3. **OpenWrt环境**：`/tmp`是tmpfs(RAM)，空间有限；dd没有`fdatasync`只有`fsync`；`date +%s`精度只有秒级，用`/proc/uptime`厘秒计时
4. **IPK打包**：OpenWrt/opkg三成员布局（debian-binary + control.tar.gz + data.tar.gz），不是简单tar.gz
5. **eMMC制造商ID 0x88 = Longsys(江波龙)**，不是BIWIN(佰维)
6. **footer**: 所有页面必须有 `by 数码罗记 · godsun.pro`
7. **不要删减现有仪表盘卡片**：🧩 SoC、🌐 网口、💽 容量、🔲 eMMC、🚀 eMMC读写速度、🧠 内存检测、💾 NAND、📜 开机日志 — 这8个卡片必须保留
8. **不要重写UI**：只做代码质量/逻辑完善，不做设计变更

## 需要完善的问题清单

### A. 代码质量问题

1. **制造商ID映射重复3处**：`route-tool`后端(行109-120)、`storage_detail.sh`(行46-59)、`storage_analyze.sh`(行77-91) 各有一份制造商ID→名称映射表，且不完全一致（detail.sh缺0x0a/兆易创新、0x0b/旺宏等；analyze.sh也缺）。应统一为一个共享函数或脚本。

2. **ext_csd读取逻辑重复**：`storage_health.sh`和`storage_detail.sh`各自独立读取ext_csd，字符偏移(c535-536/c537-538/c539-540)硬编码在多处。`storage_analyze.sh`也有类似逻辑但偏移不同(c537-538/c539-540/c541-542)。需要统一ext_csd解析逻辑和偏移量定义。

   **注意**：JEDEC标准 ext_csd byte 268 (PRE_EOL_INFO) 对应字符偏移 535-536（因为hex dump每byte=2chars，偏移=byte*2+1，即268*2+1=537... 需要仔细验证）。当前代码中health.sh用535-536/537-538/539-540，analyze.sh用537-538/539-540/541-542——这两组偏移不一致，至少有一组是错的。需要验证正确的字符偏移。

3. **前端JS极度压缩**：`index.htm`的JS几乎全写在单行上（行110-199），变量名极短(qs/esc/kv等)，函数体压缩在一起，可读性很差。应该拆分整理为正常格式，保持功能不变。

4. **storage_nand.sh用printf %b拼接输出**：用`OUTPUT="${OUTPUT}xxx\n"` + `printf "%b" "$OUTPUT"`模式，容易出错且难以调试。应改为直接echo输出。

5. **storage_detail.sh有缓存机制但其他脚本没有**：`storage_detail.sh`用5分钟缓存(`/tmp/storage_detail_cache`)，但`storage_health.sh`等每次都重新读取ext_csd。如果ext_csd需要mount debugfs，每次都重复操作。应考虑统一缓存策略。

6. **controller中memory_quick硬编码`quick 16`**：行185 `luci.http.write(run_storage("storage_memory.sh", "quick 16", "2>&1"))` — 但skill文档说16MB在BusyBox上计时太粗糙会产生无意义结果。应改为合理的默认值（如50% MemAvailable或至少128MB）。

7. **Makefile版本号落后**：Makefile写`PKG_VERSION:=0.3.5`但CONTROL/control写`Version: 0.3.6-1`，不一致。

### B. 逻辑问题

8. **storage_analyze.sh的ext_csd偏移与storage_health.sh不一致**：
   - health.sh: PRE_EOL=c535-536, LIFE_A=c537-538, LIFE_B=c539-540
   - analyze.sh: LIFE_A=c537-538, LIFE_B=c539-540, PRE_EOL=c541-542
   - 这两组对PRE_EOL的偏移不同(535-536 vs 541-542)，必须验证哪个正确

9. **storage_analyze.sh的boot分区size读取bug**：行211 `cat /sys/block/mmcblk0boot0/size` 在循环内但循环变量是`$boot`（可能是mmcblk0boot0或mmcblk0boot1），却硬编码读mmcblk0boot0的size，应该读`/sys/block/${boot}/size`。

10. **storage_capacity.sh的NAND容量计算**：行118的条件 `$((nand_max_mb * 100)) -ge $((nand_rest_mb * 90))` 在shell中如果数值很大可能溢出（32位shell算术上限约2G）。需要考虑大容量NAND的情况。

11. **route-tool后端的`find_emmc_part`只查mmcblk0**：行65 `for p in /sys/block/$base/${base}p*` — 如果系统有mmcblk1等，不会查到。虽然路由器通常只有一个eMMC，但逻辑上应更通用。

12. **storage_system.sh的WiFi检测**：行142 `iwinfo 2>/dev/null | sed -n 's/^\\([^ ]*\\) .*/\\1/p'` — iwinfo在有些设备上输出格式不同，可能误匹配。

13. **storage_bootlog.sh的dmesg可能需要权限**：有些OpenWrt版本dmesg需要root或CAP_SYSLOG，但LuCI的sys.exec不一定有足够权限。

14. **前端`updateDashFromKV`函数**：行170-177，所有KV解析逻辑挤在一个巨大函数里，每个字段判断用`if(d.XXX)`，如果多个health action返回同名字段会冲突。应拆分为独立的更新函数。

### C. 安全/健壮性问题

15. **route-tool write命令的文件路径注入**：行105 controller中 `shellquote(tmp)` 虽然做了引号包裹，但`part`参数只做了白名单检查，`tmp`路径由upload_tmp_path生成看起来安全。不过整体上应确认没有命令注入风险。

16. **storage_speed.sh的cleanup_leftovers遍历固定目录列表**：行13 硬编码了`/tmp /root /mnt /overlay /mnt/mmcblk0p27 /mnt/mmcblk0p22`，其中后两个是特定设备路径。应改为动态查找。

17. **storage_memory.sh的stress模式**：行132 `while [ $(date +%s) -lt "$SEND" ]` — BusyBox `date +%s`精度只有秒，短时间stress循环可能多跑一轮。

18. **controller的sysupgrade函数**：行149 用`sys.call(cmd)`启动后台sysupgrade，但`rc`检查可能不准确——后台任务的返回码是shell的`&`返回值(通常是0)，不是sysupgrade本身的返回码。

### D. 代码风格/可维护性

19. **所有shell脚本缺少统一的错误处理模式**：有的用`err()`函数+exit，有的直接echo+exit，有的用`{ ... || exit N; }`。应统一。

20. **shell脚本缺少日志级别标记**：诊断输出混在一起，没有INFO/WARN/ERROR前缀区分。对前端解析KV来说还好，但人工阅读困难。

21. **前端CSS内联在HTM模板中**：约50行CSS直接写在`index.htm`开头，应考虑是否可以抽到单独文件（但LuCI单文件插件传统上这样做也可以接受，只是可维护性差）。

## 修改原则

1. **只做代码质量和逻辑完善，不做功能新增或UI重设计**
2. **保持向后兼容**：KV输出字段名不能改（前端JS依赖这些字段名），只能新增字段
3. **保持BusyBox兼容**：所有修改后的shell脚本仍必须POSIX sh
4. **保持IPK可打包**：修改后仍能按现有CONTROL/control和Makefile打包
5. **版本号统一**：Makefile和CONTROL/control的版本号必须一致，建议升级到0.3.7
6. **修改后要验证**：每个修改点完成后，说明如何验证（如`/usr/libexec/route-tool list`输出JSON格式不变）

## 优先级排序

- **P0（必须修）**：#8 ext_csd偏移不一致、#9 boot分区size bug、#1 制造商映射统一、#6 memory_quick默认值
- **P1（应该修）**：#7 版本号统一、#4 nand.sh输出模式、#5 缓存策略、#15-18 安全健壮性
- **P2（建议修）**：#3 JS格式化、#14 函数拆分、#19-21 代码风格

## 验证方法

修改完成后，在SY-ax1800-256G(192.168.8.8)上部署验证：
```bash
# 1. 后端基本功能
/usr/libexec/route-tool list  # JSON输出格式不变，manufacturer仍为Longsys
/usr/libexec/route-tool backup gpt | wc -c  # 应输出17408

# 2. 前端页面
rm -rf /tmp/luci-* /tmp/luci-modulecache/*
/etc/init.d/uhttpd restart
# 浏览器访问 系统→Route Tool，确认8个仪表盘卡片都显示

# 3. ext_csd偏移验证
/usr/libexec/route-tool.d/storage_health.sh  # EMMC_LIFE_TEXT输出合理
/usr/libexec/route-tool.d/storage_detail.sh  # LIFE_EST_A/B值与health.sh一致

# 4. IPK打包验证
# 按SKILL.md中的IPK打包流程构建，opkg install后chmod +x验证
```