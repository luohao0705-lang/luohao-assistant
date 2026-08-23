# Luohao Assistant

个人创业经营助理：语音输入、财务风险看板、项目事项规划和 DeepSeek AI 编排。

## 当前状态

第一阶段包含：

- 单用户密码登录和 JWT 会话
- 账户、收支、债务、项目、任务数据模型
- 经营看板摘要和现金流预测基础
- DeepSeek OpenAI-compatible API 接入骨架
- 本地 SQLite 开发配置，支持切换 PostgreSQL

## 后端开发

```powershell
cd backend
python -m venv .venv
.\\.venv\\Scripts\\Activate.ps1
pip install -e .
Copy-Item .env.example .env
uvicorn app.main:app --reload
```

默认地址：`http://127.0.0.1:8000`。

生产环境请使用 Argon2 密码哈希，并把 `DEEPSEEK_API_KEY` 放在服务器环境变量中，不要提交到 Git。

## 服务器部署前置条件

- 确认 Linux 发行版和 SSH 密钥登录
- 确认 `luohao.hsh6.com` 的 A 记录指向服务器
- 旋转已经暴露的 root 密码
- 配置 DeepSeek API Key

## iOS

`ios/` 中保存 SwiftUI 客户端的工程设计和共享模型。完整的 Xcode 签名、Face ID 权限和真机安装需要在 Mac/Xcode 环境完成。
