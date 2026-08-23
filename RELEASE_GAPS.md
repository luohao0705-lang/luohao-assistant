# Release gaps and acceptance checklist

## P0 required before production
- [x] Single-user password login, JWT, Keychain and Face ID flow
- [x] Accounts, transactions, debts, projects, tasks and memories
- [x] Production settings reject weak secrets, plaintext password, SQLite and missing DeepSeek key
- [x] PostgreSQL migration path with Alembic, readiness endpoint and Docker health checks
- [x] Forecast includes planned income, planned expense, debt due dates, overdue income and lowest balance
- [x] DeepSeek tool results are sent back for a grounded final response
- [x] Write actions require explicit confirmation or cancellation and are audited
- [x] Essential task and memory listing/update/archive endpoints
- [x] Project war room fields, task scoring, dependencies and blocker visibility
- [x] Daily operating command center with ranked priorities
- [x] Weekly plan and review storage plus iOS read view
- [x] AI project decomposition, project-plan and weekly-plan proposals
- [x] iOS pending-action confirmation/cancellation loop
- [x] Backup and restore scripts

## P1 first usable release
- [x] Dashboard risk indicators and lowest forecast balance
- [x] Voice, network and expired-session error states represented in iOS client
- [x] Memory search, source metadata and archive endpoint
- [x] Local API smoke test
- [ ] Docker image build and real PostgreSQL deployment (Docker is unavailable in this workspace)
- [ ] DeepSeek live request with a production key

## P2 follow-up
- [ ] Real embeddings and pgvector hybrid retrieval
- [ ] Background voice and TTS
- [x] Bank/payment synchronization intentionally out of scope; use voice or manual confirmed entries
- [ ] Calendar, reminders and Shortcuts integration
- [ ] Complex workflow editor and collaboration
- [ ] iOS Xcode compile, TestFlight-style ad hoc signing and real-device voice verification (requires macOS)

## Release verdict
Local backend is ready for deployment preparation. Production deployment is blocked until DNS resolves, secure SSH access is provided, production secrets are installed, and a Mac/Xcode build installs the signed iOS app on a real device.
