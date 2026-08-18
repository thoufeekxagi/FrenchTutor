# ParleSprint platform and UI boundaries

These rules apply under `flutter_app/`.

## Platform identities

| Platform | Permanent identity | Native project |
| --- | --- | --- |
| Android | `com.parlesprint.app` | `android/` |
| iOS | `com.thoufeekx.frenchtutor` | `ios/` |
| Web | Deployment origin/domain | `web/` |

Never copy one platform identifier to another. Shared Flutter code lives in
`lib/`; native signing, identity, permissions, and store configuration remain
inside the matching platform directory. Never commit passwords, keystores,
API secrets, service-account JSON, signing certificates, or OAuth credentials.

## UI/UX v2

- Before any UI change or redesign, read `design_approach.md` and follow its
  screen contract, responsive checks, and visual QA requirements.
- `lib/design/` is the source of truth for color, typography, spacing, radii,
  shadows, motion, and component themes.
- Use semantic `DesignTokens` names. Do not add retired palette vocabulary or
  screen-local brand colors.
- Reuse `LearningCard` and `PrimaryActionButton` for common surfaces/actions.
- Interactive targets must be at least 48 logical pixels, support text scaling,
  preserve semantics, and remain reachable by scrolling.
- Shared UI changes must pass Flutter analysis/tests and Android verification.
