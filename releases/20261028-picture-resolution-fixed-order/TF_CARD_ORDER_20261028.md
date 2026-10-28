# H:\ TF 卡目录记录（2026-10-28）

按 PowerShell `Get-ChildItem -LiteralPath H:\ -Force` 返回顺序现场读取；未按文件名排序。根目录项如下：

| 根目录顺序 | 文件 | 类型/分辨率 | BMP 图片索引 |
|---:|---|---|---:|
| 1 | `System Volume Information` | 目录 | - |
| 2 | `BEACH720_1280x720.BMP` | BMP 1280×720 | 1 |
| 3 | `CART960_960x540.BMP` | BMP 960×540 | 2 |
| 4 | `lan-lian-hua.wav` | WAV | - |
| 5 | `LOGO720.BMP` | BMP 1280×720 | 3 |
| 6 | `NAI640_640x480.BMP` | BMP 640×480 | 4 |
| 7 | `NAIL2720_1280x720.BMP` | BMP 1280×720 | 5 |
| 8 | `VIDEO.R16` | RV16 视频 | - |

BMP 宽高从各文件 BMP 头部偏移 18 的 little-endian signed 32-bit 字段读取；高度取绝对值。图片顺序为保留目录枚举相对顺序并跳过非 BMP 项后的结果。工程 `fat32_bmp_index` 仅索引根目录短文件名 BMP 项，因而 WAV 和 R16 不占图片编号。

本记录是 2026-10-28 对 H:\ 的现场读取结果。目录项可能被重新复制、删除或重排；再次改卡后须重新读取并核对，不可将这份记录当成所有 TF 卡的固定顺序保证。
