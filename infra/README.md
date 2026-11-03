# Web 发布基础设施

## 启动

从仓库根目录执行：

```sh
cp infra/.env.example infra/.env
docker compose -f infra/docker-compose.yml --env-file infra/.env build
docker compose -f infra/docker-compose.yml --env-file infra/.env up -d
```

`migrate` 一次性服务使用与 Web 镜像相同的 `scripts/migrate.mjs` 执行 `web/drizzle/` 迁移。Web 容器只有在迁移成功后才启动。

- Web 仅绑定宿主机 `127.0.0.1:8090`。
- MySQL 仅绑定宿主机 `127.0.0.1:33066`，供本地迁移与集成测试使用。
- 反向代理与公网传输层由现有部署环境管理。
- Qiniu 永久密钥只注入 Web 服务端，不进入浏览器或 Apple 客户端。

`.env.example` 默认使用内存存储，便于本地开发验收。生产部署必须显式设置
`STUDYNOTES_STORAGE=qiniu` 并提供真实七牛凭据；占位凭据会让健康检查返回
带原因的 `503`，而不是静默等待。

## 测试

`infra/ci.sh` 使用与 `.github/workflows/ci.yml` 一致的
lint、typecheck、Vitest、Next build 与 Playwright 入口。设置
`CI_DOCKER=1` 时会启动 MySQL、执行迁移与集成测试，并启动 Web 容器等待
健康检查通过。
