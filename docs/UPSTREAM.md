# 上游版本

本仓库以源码快照方式引入上游代码（含子模块 hbb_common），便于直接修改。

| 目录 | 上游 | 版本 |
| --- | --- | --- |
| 仓库根目录（客户端） | https://github.com/rustdesk/rustdesk | 1.5.3 |
| `server/`（信令 hbbs + 中转 hbbr） | https://github.com/rustdesk/rustdesk-server | 1.1.16 |

合并上游更新时，按上表版本做三方对比后再合入。上游原 README 保存在 `docs/upstream/`。

已删除的上游工作流：flutter-nightly、fdroid、playground、third-party-RustDeskTempTopMostWindow、update-webpki-roots（依赖上游发布环境或定时任务）。CI 触发分支已从 master 改为 main。
