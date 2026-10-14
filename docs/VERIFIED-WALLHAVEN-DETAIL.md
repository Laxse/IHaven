# VERIFIED-WALLHAVEN-DETAIL.md：wallhaven 详情接口实测存档

> **配套于 ADR-007**。ADR-007 的 Traps 1–17 核验的是 **macOS 系统 API**（编译核验），Traps 18–19 与本文档核验的是 **wallhaven 服务端 API**（curl 实测）。两者的核验方法不同：前者用 `swiftc -typecheck`，后者用**带对照组的 HTTP 实测**。
>
> 核验对象：`GET https://wallhaven.cc/api/v1/w/<id>`（壁纸详情）
> **核验日期：2026-10-14**
> 核验工具：`curl`（直连，无代理），带 Key 对照组使用本机 `~/.ihaven/apikey` 的真实有效 Key
> 官方文档来源：https://wallhaven.cc/help/api （当日全文抓取）
> 样本量：**8 份详情响应**（6 份随机 SFW + 2 份定点）+ 若干错误路径样本 + 55 次并发压测

## 核验方法

1. 官方文档**全文抓取**（非记忆），提取原文表述。
2. 所有结论**必须带对照**：同一时刻、同一 UA、同一参数的多个请求互为对照，以排除「被限流」「UA 被拦」「样本偶然」三类替代解释。
3. 凡官方文档未写明或本次未覆盖的，一律标注「**文档未写明 / 未实测**」，**禁止凭猜填充**。
4. 带 Key 与不带 Key 的差异，必须用**同一 id 的成对请求**验证，不得跨 id 比较。

---

## 1. 端点形态

| 项 | 事实 | 来源 |
| --- | --- | --- |
| URL | `GET https://wallhaven.cc/api/v1/w/<ID>` | 官方文档原文 `https://wallhaven.cc/api/v1/w/<ID here>`；实测 200 |
| HTTP 方法 | `GET` | 官方文档；实测 |
| 认证 | 官方文档示例写 `?apikey=<KEY>`；**也接受 `X-API-Key` 头** | 官方文档 Authentication 段；实测两种均返回 200 / 401 |
| 是否需要 Key | **不需要**即可访问 sfw / sketchy 详情；仅 NSFW 详情需要有效 Key | 实测（见 §2） |

`<ID>` 形如 `jel1jq`（大小写字母数字，实测长度恒为 6）。

### 与 `/api/v1/search` 的结构差异

| | `/search` | `/w/<id>` |
| --- | --- | --- |
| 顶层 | `{"data": [ {...}, ... ], "meta": {...}}` | `{"data": {...}}` —— **没有 `meta`** |
| `data` | 数组 | **单个对象** |
| 特有字段 | `meta`（分页信息） | `uploader`、`tags` |
| 其余 18 个字段 | 完全一致、同型、同名 | 一致 |
| `path` | 实测含 `/full/` | 同样含 `/full/` |

即：**详情端点是搜索项字段的严格超集，只多 `uploader` 与 `tags` 两个顶层字段。**

> **警告：**官方文档示例过时两处，勿照抄文档，以实测为准：**
>
> 1. 文档的 `/search` 示例中 `path` 为 `https://w.wallhaven.cc/94/wallhaven-94x38z.jpg`（**无** `/full/`），实测 `/search` 与 `/w/<id>` 两侧**均含** `/full/`。
> 2. 文档的示例 id **`94x38z` 实测返回 404** `{"error":"Nothing here"}` —— 该壁纸已不存在。**切勿硬编码进测试或 fixture。**

---

## 2. API Key 有无时的字段差异

**结论：对 sfw / sketchy 壁纸，带 Key 与不带的字段集合完全一致，无任何字段被裁剪或缺失。**

对照组（同一 id `jel1jq`，间隔数秒，curl + `Accept: application/json`）：

```
anon keys   : category colors created_at dimension_x dimension_y favorites file_size
              file_type id path purity ratio resolution short_url source tags thumbs
              uploader url views
withkey keys: （完全相同）
key-set same: True
唯一差异    : views 37454 -> 37446（计数字段本身的跳动，非 Key 影响）
```

8 份样本（6 随机 + 2 定点）全部验证：`uploader`（含 avatar）、`tags`（完整 7 字段）、`file_size`、`views`、`favorites`、`colors`、`source` **在无 Key 时全部照常返回**。

**Key 唯一的作用是「能否访问 NSFW」，不是「字段多少」：**

| 详情内容 | 匿名（无 Key） | 带有效 Key |
| --- | --- | --- |
| sfw 壁纸 | 200，字段完整 | 200，字段完全一致 |
| sketchy 壁纸 | **200**，字段完整（实测 id `gw1gol`） | 200 |
| nsfw 壁纸 | **401** `{"error":"Unauthorized"}`（实测 id `6le6v6`） | 200，字段与其他一致 |

> 对照 Trap 18（搜索结果的 Key 门控静默缩水）：详情端点**不存在**静默缩水。
> NSFW 无权限时给的是**明确的 401**，而非「200 + 少了数据」。
> 因此「详情页拿到 200 即可信任字段完整」—— 但**不可反推搜索页也有同等保证**（搜索页适用 Trap 18）。

---

## 3. 字段映射表

全部路径以 `data.*` 开头（顶层只有 `data`，无 `meta`）。「无 Key 时」列默认指 sfw / sketchy；NSFW 无 Key 是 401，拿不到 body。

| JSON 路径 | 类型（实测） | Swift 类型建议 | 语义 | 无 Key 时行为 |
| --- | --- | --- | --- | --- |
| `data.id` | String | `String` | 壁纸 id，形如 `jel1jq` | 照常返回 |
| `data.url` | URL String | `URL` | **wallhaven 网页详情页地址** `https://wallhaven.cc/w/<id>` | 照常 |
| `data.short_url` | URL String | `URL` | 短链 `https://whvn.cc/<id>`（**实测为 https，文档示例写 http**） | 照常 |
| `data.views` | Int | `Int` | 浏览量。**实测非单调**：同一 id 两次读取 37454 → 37446，不得用于差分/去重判据 | 照常 |
| `data.favorites` | Int | `Int` | 收藏数 | 照常 |
| `data.source` | String | `String?` | **原作出处**；无来源时是**空串 `""` 而非 null**（5 份样本中 1 份为空串）。自由文本，未必是合法 URL | 照常（仍可能为空串） |
| `data.purity` | String 枚举 | `String` | 纯度：`sfw` / `sketchy` / `nsfw` | 照常（nsfw 整体 401） |
| `data.category` | String 枚举 | `String` | 分类：`general` / `anime` / `people` | 照常 |
| `data.dimension_x` | Int | `Int` | 宽（像素） | 照常 |
| `data.dimension_y` | Int | `Int` | 高（像素） | 照常 |
| `data.resolution` | String | `String` | `"3840x2160"`，等于 `dimension_x + "x" + dimension_y`，冗余字段 | 照常 |
| `data.ratio` | String | `String` | **十进制比例字符串**，如 `"1.78"` / `"1.5"` / `"0.58"`。**不是** `"16x9"` 形式 | 照常 |
| `data.file_size` | Int | `Int` | **单位：字节**。3840×2160 jpg = 4753754（≈4.75 MB）；文档示例 6742×3534 = 5070446（≈5 MB），与字节吻合 | 照常 |
| `data.file_type` | String | `String` | MIME，实测 `image/jpeg` / `image/png` | 照常 |
| `data.created_at` | String(19) | `String` | `"2026-09-22 07:53:43"`，空格分隔，**无时区后缀**。时区**文档未写明** | 照常 |
| `data.colors` | [String] | `[String]` | **恒为 5 个**，带 `#` 前缀小写 hex：`["#000000","#424153",...]`（8/8 样本） | 照常 |
| `data.path` | URL String | `URL` | **原图直链**，实测恒含 `/full/`：`https://w.wallhaven.cc/full/je/wallhaven-jel1jq.jpg` | 照常 |
| `data.thumbs.large` | URL String | `URL?` | 大缩略图 `https://th.wallhaven.cc/lg/<2char>/<id>.<ext>` | 照常 |
| `data.thumbs.original` | URL String | `URL?` | 原始缩略图 `.../orig/...` | 照常 |
| `data.thumbs.small` | URL String | `URL?` | 小缩略图 `.../small/...` | 照常 |
| `data.uploader.username` | String | `String` | 上传者用户名，如 `jrmnt` | 照常返回 |
| `data.uploader.group` | String | `String` | 实测仅见 `"User"`。**完整取值域文档未写明，不得枚举硬编码** | 照常 |
| `data.uploader.avatar.200px` | URL String | `URL` | 头像 200px | 照常 |
| `data.uploader.avatar.128px` | URL String | `URL` | 头像 128px | 照常 |
| `data.uploader.avatar.32px` | URL String | `URL` | 头像 32px | 照常 |
| `data.uploader.avatar.20px` | URL String | `URL` | 头像 20px | 照常 |
| `data.tags[].id` | Int | `Int` | 标签 id，如 323 | 照常 |
| `data.tags[].name` | String | `String` | 标签名，**可含空格**，如 `digital art` | 照常 |
| `data.tags[].alias` | String | `String` | 别名串，逗号分隔，如 `"ANSI, ascii"` | 照常 |
| `data.tags[].category_id` | Int | `Int` | 标签分类 id，如 2 / 25 | 照常 |
| `data.tags[].category` | String | `String` | 标签分类名，如 `"Art & Design"` / `"Digital"` | 照常 |
| `data.tags[].purity` | String | `String` | 标签自身纯度：`sfw` / `sketchy` / `nsfw` | 照常 |
| `data.tags[].created_at` | String | `String` | 标签创建时间，同为 `"YYYY-MM-DD HH:mm:ss"` | 照常 |

### 结构不变量（8 份样本穷举，可直接用于 Codable 设计）

- 顶层恒 `{"data": {...}}`，**无 `meta`**
- `thumbs` 键集恒为 `("large","original","small")`
- `uploader` 键集恒为 `("avatar","group","username")`；`avatar` 键集恒为 `("128px","20px","32px","200px")`
- `tags` 元素键集恒为 `("alias","category","category_id","created_at","id","name","purity")`
- `colors` 长度**恒为 5**；`tags` 长度**可变**（实测 3 / 5 / 6 / 7 / 11 / 12 / 26）
- 缺头像时 avatar 指向 `https://wallhaven.cc/images/user/avatar/<size>/default-avatar.jpg`，**不是 null**
- `created_at` 长度恒为 19

### 未验证 / 文档未写明 —— 禁止凭猜填充

| 项 | 状态 |
| --- | --- |
| `created_at` 的时区基准 | **文档未写明 / 未实测**（不得假定 UTC） |
| `uploader.group` 的完整取值域 | **文档未写明 / 未实测**（实测仅见 `"User"`） |
| 上传者账号被注销时 `uploader` 是否为 null | **未实测**（未取到样本） |
| `tags` 是否可能为空数组 `[]` | **未实测**（未取到 0 标签样本 → 按普通数组解码，**UI 需处理空数组**） |
| 配额是否按 IP（而非按 Key）计 | **文档未写明 / 未实测**（`x-ratelimit-*` 行为与 Cloudflare 边缘限流一致，但属推测） |

---

## 4. 「search for similar」能力

官方文档 `q` 参数表原文：`like:wallpaper ID - Find wallpapers with similar tags`。

**实测该参数在 API 上被拦截，不可用。**

同一时刻、同一 UA 的严格对照：

| 请求 | HTTP | Content-Type |
| --- | --- | --- |
| `/api/v1/w/jel1jq` | **200** | application/json |
| `/api/v1/search?q=anime` | **200** | application/json |
| `/api/v1/search?q=like%3Ajel1jq` | **403** | **text/html**（Cloudflare `Just a moment...` 挑战页） |
| `/api/v1/search?q=like:jel1jq`（未编码冒号） | **403** | text/html |
| `/api/v1/search?q=like%3Ajel1jq` **带有效 Key** | **403** | text/html |

对照组排除了「被限流」与「UA 被拦」两种替代解释：同一时刻 `/w/` 与 `/search?q=anime` 均返回 200 JSON。多次重试（间隔 20 秒以上、换浏览器 UA、带真实 Key）结果一致。

**可行替代方案（实测有效）**：用详情返回的 `tags[].name` 拼 `q` 的 `+tag` 表达式，走现有 `/search`。现有 `BrowseQuery.q` 已是自由字符串，**无需新增任何搜索参数或端点**。

| 构造方式 | 实测 total |
| --- | --- |
| `q=+artwork` | 172,101 |
| `q=+artwork +illustration` | 7,686 |
| `q=+artwork +illustration +digital art`（**空格保留**） | 7,045 |
| `q=+artwork +illustration +digital_art`（空格换成下划线） | **0** |
| `q=digital art`（单词比较用） | 120,347 |
| `q=digital_art` | **0** |

> **警告：**踩坑点：多词标签必须保留空格，不得替换为下划线。** 首次测试因把 `digital art` 转成 `digital_art` 得到 `total=0`，差点误判为「AND 组合过窄」—— 这正是「用错误形式验证，得出错误结论」（Trap 12 同型）。建议标签数取 2–3 个，3 个以上有收敛到空结果的风险。

---

## 5. 错误码语义（全部实测）

| 场景 | HTTP | 响应体（原文） | Content-Type |
| --- | --- | --- | --- |
| id 不存在 / 空 / 畸形（`zzzzzz`、`abc`、`12345678901234567890`、空串） | 404 | `{"error":"Nothing here"}` | application/json |
| Key 无效（经 `X-API-Key` 头，32 个 `x`） | 401 | `{"error":"Unauthorized"}` | application/json |
| Key 无效（经 `?apikey=` query） | 401 | `{"error":"Unauthorized"}` | application/json |
| **NSFW 壁纸 + 无 Key** | **401** | `{"error":"Unauthorized"}` | application/json |
| NSFW 壁纸 + 无效 Key | 401 | `{"error":"Unauthorized"}` | application/json |
| 超出速率限制 | 429 | `{\n    "message": "Too Many Attempts."\n}` | application/json |
| `q=like:<id>` | **403** | Cloudflare HTML 挑战页 `<title>Just a moment...</title>` | text/html |

### 两个解码层面的坑

1. **响应体顶层键不一致**：401 / 404 用 `{"error": "..."}`，**429 用 `{"message": "..."}`**（且是 pretty-printed）。若定义单一 envelope（`struct ErrorEnvelope { let error: String }`），**429 会 decode 失败**，落入具有误导性的「数据解析失败」，真实原因其实是限流。建议兼容两者，或**只按状态码分流、不解析 body**。
2. **403 + HTML 是真实存在且未文档化的路径**（文档只提 401 / 404 / 429）。即使发送了 `Accept: application/json`，`like:` 仍返回 HTML。**必须先判状态码（并核对 content-type），再解码** —— 与 Trap 10「禁止先解码再判状态码」一致。

> 补充实测：详情端点的 401 / 404 在 `Accept: text/html` 下**仍返回 JSON**（与 `/search` 非法参数返回 HTML 的行为不同）。但 Trap 10b 的纪律仍然保持：**始终显式发送 `Accept: application/json`**。

---

## 6. 速率限制与配额

官方文档原文：

> API calls are currently limited to 45 per minute. If you do hit this limit, you will receive a 429 - Too many requests error.
>
> （文档**未说明**该限额是每端点还是全局共享。）

### 实测结论：全局共享同一计数桶

连续请求观察 `x-ratelimit-remaining`：

| 请求 | remaining |
| --- | --- |
| `/w/jel1jq` | 38 |
| `/search?page=1&purity=100` | 37 |
| `/w/5ypy88` | 36 |

每次恰好 −1，**与端点无关**。压测验证：同一瞬间并发 55 个 `/w/jel1jq` → **恰好 45 个 200 + 10 个 429**，与文档声明的 45/min 完全吻合。

### 错误响应同样消耗配额（实测）

| 请求 | HTTP | remaining |
| --- | --- | --- |
| `/w/jel1jq` | 200 | 40 |
| `/w/zzzzzz` | **404** | 39 |
| `/w/6le6v6` | **401** | 38 |
| `/search?page=1` | 200 | 37 |

**404 与 401 同样扣额度。** 对错误请求做重试/轮询会持续消耗配额。

### 响应头（官方文档完全未提，实测存在，可用于客户端节流）

| 头 | 实测值 | 说明 |
| --- | --- | --- |
| `x-ratelimit-limit` | `45` | 窗口额度上限 |
| `x-ratelimit-remaining` | `<int>` | 剩余次数，每次请求 −1 |
| `x-ratelimit-reset` | `1791963547` | Unix 秒级时间戳 |
| `retry-after` | `38` | 秒；**仅在 429 时出现** |
| `server` | `cloudflare` | — |

### 给实现的含义

- 详情页**每打开一张图消耗 1 次配额**，与翻页（24 条/次）**同等代价**。
- **429 是可达的常见状态**：「滚动瀑布流 + 点进详情 + 返回」的组合极易触顶 45/min，**必须有 UI 分流**。
- 详情页**不得**对 `views` 做轮询刷新；hover 预加载详情会快速吃掉瀑布流的配额。

---

## 7. 后续若引入详情接口需注意的实现缺口（本次不改，留待实现阶段）

以下为阅读现有代码时发现的事实，供实现者参考，**本次未改动任何实现文件**：

1. `WallhavenEndpoint`（`WallhavenClient.swift`）目前**只有 `search` 一个 case**，需新增 `w/<id>`。
2. `MockWallhavenProtocol.startLoading()`（`MockWallhaven.swift`）只有 `/api/v1/search` 与「其余一律返回 image/jpeg」两条分支 → `IHAVEN_MOCK=1` 下请求 `/w/<id>` 会拿到 JPEG 字节喂给 `JSONDecoder`，报出与真实原因无关的解码错误。
3. Mock 的合成字段形状与真实 API **不一致**（`ratio`：`"9x16"` vs `"1.78"`；`created_at`：ISO vs 空格分隔；`purity`：`"100"` vs `"sfw"`；`colors`：长度 1 vs 恒 5）—— **mock 不可作为字段依据**。
4. `Wallpaper`（`Core/Models/Wallpaper.swift`）无 `uploader`、无 `tags`，详情页需要新增模型（建议新开 `WallpaperDetail` 而非把 Optional 字段塞进 `Wallpaper`，以免让已验证的不变量在类型层面消失）。

---

## Related

ADR-007 Trap 18（搜索结果的 Key 门控静默缩水）
ADR-007 Trap 19（401 在 `/w/<id>` 的双语义 —— 本文档 §2 / §5 的直接推论）
ADR-007 Trap 10 / 10b（先判状态码再解码；始终发送 `Accept: application/json`）
ADR-007 Trap 12（`type:` 前缀必须放在 `q=` 内 —— 与本文档 §4 的下划线踩坑同型）
