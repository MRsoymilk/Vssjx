# 提交约定

提交信息使用Angular格式：`<type>(<scope>): <subject>`。

- 同时涉及`client/`和`server/`的功能或修复统一使用`game`范围，例如`feat(game): ...`、`fix(game): ...`、`refactor(game): ...`。
- 仅修改客户端或服务端时可分别使用`client`、`server`范围。
- 配套用例和说明可以随功能一同提交；独立测试代码使用`test(...)`，独立测试计划文档使用`docs(test)`。
- `type`按实际变更选择，不将目录重构或文档调整都标为`feat`。
- 提交前检查暂存范围，不混入无关修改；不擅自推送、强推或改写他人提交。

`.env`及其他私有环境文件不得提交，只维护不含真实密码的`.env.sample.txt`。测试说明和验证记录放在`tests/`，不混入README。
