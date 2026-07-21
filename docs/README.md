# FlyConnect — Launch Documentation

All the documentation needed to take FlyConnect from "code complete" to "live in the Play Store."

## 📁 What's in here

### Legal / policy (host these as public URLs)

| File | Purpose |
|------|---------|
| [privacy-policy.md](./privacy-policy.md) | Full privacy policy content. Live at `flyconnect.co/privacy-policy/`. Required by Play Store. |
| [terms-of-service.md](./terms-of-service.md) | Full ToS content. Live at `flyconnect.co/terms-of-service/`. Linked from signup consent. |

### Store submission

| File | Purpose |
|------|---------|
| [store-listing.md](./store-listing.md) | App title, short + full description, What's New copy. Paste directly into Play Console. |
| [data-safety-form.md](./data-safety-form.md) | Pre-filled answers for the Play Data Safety form. |
| [app-assets-guide.md](./app-assets-guide.md) | Icon, feature graphic, screenshot specs and shot list. |
| [play-console-setup.md](./play-console-setup.md) | End-to-end guide: account creation → internal testing → production. |

### Build & release

| File | Purpose |
|------|---------|
| [keystore-setup.md](./keystore-setup.md) | Generate, secure, and CI-enable the release keystore. |
| [release-build-guide.md](./release-build-guide.md) | Build signed AAB, verify, upload. |
| [pre-launch-report-guide.md](./pre-launch-report-guide.md) | How to read Google's automated pre-launch report. |

### QA

| File | Purpose |
|------|---------|
| [manual-smoke-test.md](./manual-smoke-test.md) | Device smoke test checklist, run before every promotion. |
| [accessibility-audit.md](./accessibility-audit.md) | TalkBack + contrast + touch target audit. |

### iOS

| File | Purpose |
|------|---------|
| [../ios/README.md](../ios/README.md) | Mac-side iOS setup steps: Xcode, capabilities, pods, signing. |

---

## 🚀 Critical path to first Play Store submission

Work through these in order:

1. **Generate keystore** → [keystore-setup.md](./keystore-setup.md)
2. **Build signed AAB** → [release-build-guide.md](./release-build-guide.md)
3. **Test on real device** → [manual-smoke-test.md](./manual-smoke-test.md)
4. **Produce visual assets** → [app-assets-guide.md](./app-assets-guide.md)
5. **Host Privacy + Terms URLs** → [privacy-policy.md](./privacy-policy.md) + [terms-of-service.md](./terms-of-service.md)
6. **Set up Play Console account** → [play-console-setup.md](./play-console-setup.md) (Parts 1–2)
7. **Fill Data Safety form** → [data-safety-form.md](./data-safety-form.md)
8. **Complete store listing** → [store-listing.md](./store-listing.md)
9. **Upload to Internal testing** → [play-console-setup.md](./play-console-setup.md) (Part 4)
10. **Review pre-launch report** → [pre-launch-report-guide.md](./pre-launch-report-guide.md)
11. **Run accessibility audit** → [accessibility-audit.md](./accessibility-audit.md)
12. **Promote** through Internal → Closed → Open → Production

---

## 🔁 Continuous (do every release)

- Bump `version:` in `pubspec.yaml` (marketing version and monotonic build number)
- Build signed AAB
- Run manual smoke test on a real device
- Upload to Internal testing first
- Review pre-launch report
- Monitor Crashlytics for 24h before promoting to Production
- Update "What's New" in [store-listing.md](./store-listing.md)
