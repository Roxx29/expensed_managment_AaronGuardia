# Monchi (Expense Manager) — rules for every Claude session

Flutter app in `expense_manager/`. Read the project docs first (`claude/STATUS.md`, `LEARNED.md`,
`PONYTAIL-DEBT.md`, `ARCHITECTURE.md`, `RELEASE.md`, `BRAND.md`) instead of re-exploring the code.

## Always use the installed plugins (whole project, every session)
- **Ponytail** (`ponytail:ponytail`, full mode) on every coding task: simplest working code, reuse what exists,
  mark deliberate shortcuts with `// ponytail: <ceiling>, <upgrade>`. After each change set run
  `ponytail:ponytail-review` on the diff and `ponytail:ponytail-debt`, then update `claude/PONYTAIL-DEBT.md`.
- **Everything Claude Code**: `plan` before big features, `tdd-workflow` for pure-Dart logic,
  `security-review` / `security-reviewer` for PIN, crypto, backups, imports, permissions,
  `code-reviewer` agent before every push (CI is the only compiler), `build-error-resolver` when CI fails,
  `continuous-learning` at the end (add fixes to `claude/LEARNED.md`).

## Code rules
- UI text: `context.tr('English')` + Spanish in `lib/core/l10n/strings_es.dart` (a test fails on missing keys).
- Money = integer minor units (`Money`); pure logic in `lib/domain` with tests; widgets call `*Actions` providers.
- Brand: name "Monchi", logo in `assets/brand/`, colors in `core/theme/app_theme.dart` (`Brand`).
- Never commit or print `key.properties`, `*.jks` or tokens. Keep `applicationId` and the backup `format` id.
- Push: copy files into `_monchi_update/` on the PC and the user runs `SUBIR_MONCHI.bat` (PC git), or a PAT through the browser pane. Remote tools cannot write `.github/workflows/*`.
