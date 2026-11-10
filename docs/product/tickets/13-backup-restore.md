## Parent

#1

## What to build

让用户从 Settings 导出和恢复学习数据。备份覆盖设置、Learning session、Source citation、Practice item、Gap record、Review item 和 sidecar 校验信息；恢复前展示范围并创建回滚副本。

## Acceptance criteria

- [ ] 用户可导出单个备份包并看到完成位置。
- [ ] 备份包含非秘密设置、会话、引用、练习、缺口、复习状态和 sidecar 校验信息。
- [ ] 模型与七牛原始密钥不进入备份，恢复后提示重新配置或读取 Keychain。
- [ ] 恢复前展示范围并创建当前数据回滚副本。
- [ ] 恢复中断或失败时当前数据保持可用。
- [ ] 恢复后引用、练习、缺口、复习和 sidecar 关系保持有效。
- [ ] 黑盒测试完成导出、临时环境恢复和回滚验证。
