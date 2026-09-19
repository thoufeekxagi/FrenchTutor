# ParleSprint account confirmation email

## What is live

- Supabase Auth remains responsible for signup confirmation and one-time links.
- Supabase custom SMTP is enabled and saved to use Resend as
  `ParleSprint <hello@parlesprint.com>` (`smtp.resend.com`, port 465).
- The Resend credential is send-only and restricted to `parlesprint.com`; it
  is stored in Supabase, not in this repository or the mobile app.
- Resend reports the sender domain as verified with sending enabled. A fresh
  Supabase Auth send after this SMTP save is still needed to verify the final
  live route.
- `https://parlesprint.com/confirm-signup` and the ParleSprint logo asset load.
- The signup email shown in Gmail was Supabase's default confirmation
  template. SMTP and the Auth email template are separate settings. The branded
  template below is still an unsaved dashboard draft and must be saved under
  **Supabase Dashboard → Authentication → Emails → Templates → Confirm signup**
  before new signups receive it.

Do not replace SMTP settings while changing the template. Keep Resend as the
SMTP provider, with click tracking disabled so the secure confirmation URL is
not rewritten.

## Confirmation template

Subject: `Welcome to ParleSprint | Confirm your email`

Paste this as the body for **Confirm signup**:

```html
<!doctype html>
<html lang="en" dir="ltr">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Welcome to ParleSprint</title>
  </head>
  <body style="margin:0;padding:0;background:#f3f1eb;color:#17181b;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Arial,sans-serif;">
    <div style="display:none;max-height:0;overflow:hidden;opacity:0;color:transparent;">
      Your French journey starts here. Confirm your email to save your progress.
    </div>
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background:#f3f1eb;padding:28px 12px;">
      <tr>
        <td align="center">
          <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="max-width:560px;background:#ffffff;border:1px solid #e5e1d7;border-radius:18px;">
            <tr>
              <td align="center" style="padding:30px 28px 20px;">
                <img src="https://parlesprint.com/parle-mark.svg" width="48" height="48" alt="ParleSprint" style="display:block;border:0;border-radius:12px;" />
                <p style="margin:12px 0 0;color:#17181b;font-size:18px;font-weight:700;letter-spacing:.2px;">ParleSprint</p>
              </td>
            </tr>
            <tr>
              <td style="padding:0 30px;">
                <div style="height:1px;background:#e9e6de;"></div>
              </td>
            </tr>
            <tr>
              <td style="padding:28px 30px 0;text-align:center;">
                <p style="margin:0;color:#9a6a08;font-size:12px;font-weight:700;letter-spacing:2px;text-transform:uppercase;">WELCOME TO YOUR FRENCH JOURNEY</p>
                <h1 style="margin:12px 0 0;color:#17181b;font-size:30px;line-height:1.2;">Your French journey starts here</h1>
                <p style="margin:16px 0 0;color:#55575b;font-size:16px;line-height:1.65;">
                  Thanks for choosing ParleSprint. We are excited to help you build French that feels natural, one useful step at a time. Confirm your email to secure your account and save your learning progress.
                </p>
              </td>
            </tr>
            <tr>
              <td align="center" style="padding:26px 30px 8px;">
                <a href="{{ .SiteURL }}/confirm-signup?confirmation_url={{ .ConfirmationURL }}" style="display:inline-block;background:#f2b84b;color:#17181b;border-radius:12px;padding:15px 24px;font-size:16px;font-weight:700;line-height:1.3;text-decoration:none;">
                  Confirm my email and open ParleSprint
                </a>
              </td>
            </tr>
            <tr>
              <td style="padding:12px 30px 0;text-align:center;color:#686a6e;font-size:13px;line-height:1.6;">
                On iPhone, confirm on the next page and then tap its button to return to the app. If you did not create this account, you can ignore this email.
              </td>
            </tr>
            <tr>
              <td style="padding:24px 30px 0;">
                <div style="height:1px;background:#e9e6de;"></div>
              </td>
            </tr>
            <tr>
              <td style="padding:20px 30px 0;color:#55575b;font-size:14px;line-height:1.6;">
                <strong style="color:#17181b;">Want a personal walkthrough?</strong><br />
                Book a one-on-one with Thoufeek Baber, founder of ParleSprint.
              </td>
            </tr>
            <tr>
              <td align="center" style="padding:14px 30px 28px;">
                <a href="https://cal.com/thoufeek-baber" style="display:inline-block;border:1px solid #27292d;color:#27292d;border-radius:10px;padding:12px 18px;font-size:14px;font-weight:700;line-height:1.3;text-decoration:none;">
                  Book a one-on-one with the founder
                </a>
              </td>
            </tr>
          </table>
          <p style="max-width:540px;margin:18px auto 0;color:#77797d;font-size:12px;line-height:1.6;text-align:center;">
            ParleSprint | Your French, at your pace.
          </p>
        </td>
      </tr>
    </table>
  </body>
</html>
```

The confirmation button intentionally goes through the deployed handoff page.
The page keeps scanners from consuming Supabase's one-time token and lets the
learner explicitly return to the iOS app. Do not add a second raw
`{{ .ConfirmationURL }}` link; it could be opened by mail security scanners.

Account confirmation is a required transactional message, not an optional
marketing email, so it should not show a misleading unsubscribe button. If
ParleSprint later sends optional learning updates, those need a separate email
and a real unsubscribe preference endpoint.

## Save and verify in Supabase

1. Open **Authentication → Emails → Templates → Confirm signup** in the
   ParleSprint Supabase project.
2. Set the subject above and replace the body with the HTML above. Save.
3. Use the dashboard's test-email option, if available, to inspect the design.
4. For end-to-end verification, sign up with a fresh address you control. A
   previously Google-registered address is intentionally suppressed by Supabase
   and will not receive another confirmation email.
5. Confirm that the message comes from `ParleSprint <hello@parlesprint.com>`,
   the first button opens the handoff page, and its confirmation action opens
   the iOS app with a valid session.

Supabase's dashboard editor and Management API are the supported places to
change a hosted project's templates. Never put a Resend API key or Supabase
service-role secret in the mobile app or repository.
