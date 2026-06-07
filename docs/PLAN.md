# Xyz (小宇宙 Belle) — Milestone Plan

## M0 — Scaffold verified
- [ ] Simulator build runs, self-test page all green
- [ ] Device build + self-signed SIS installs
- [ ] On-device self-test all green

## M1 — SMS login (official API)
See `tasks/plan.md` for the detailed plan; design refs in `docs/DESIGN_SYSTEM.md`,
API details in `docs/API_NOTES.md`.
- [x] LoginPage / country picker / VerifyCodePage per design bundle
- [x] sendCode + login against podcaster-api.xiaoyuzhoufm.com, tokens persisted
- [x] Simulator: UI + success path (mock) + error path (live) verified
- [ ] Live login with a real registered number (sends real SMS — user-run)
- [ ] Device: TLS handshake experiment vs official hosts → DEVICE_NOTES.md

## Device experiments
See `docs/DEVICE_NOTES.md` (append-only log, dated entries).

