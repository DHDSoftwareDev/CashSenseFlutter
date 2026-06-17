export const handler = async (event) => {
  console.log("Custom message trigger:", event.triggerSource);
  
  const code = event.request.codeParameter;
  
  // Email Verification (Sign Up)
  if (event.triggerSource === "CustomMessage_SignUp") {
    event.response.emailSubject = "Verify your email - CashSense";
    event.response.emailMessage = getVerificationEmailHTML(code);
  }
  
  // Forgot Password
  if (event.triggerSource === "CustomMessage_ForgotPassword") {
    event.response.emailSubject = "Reset your password - CashSense";
    event.response.emailMessage = getForgotPasswordEmailHTML(code);
  }
  
  // Admin Create User
  if (event.triggerSource === "CustomMessage_AdminCreateUser") {
    event.response.emailSubject = "Welcome to CashSense";
    event.response.emailMessage = getVerificationEmailHTML(code);
  }
  
  return event;
};

function getVerificationEmailHTML(code) {
  return `<!doctype html>
<html lang="en">
<head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width,initial-scale=1" />
    <title>Verify your email</title>
</head>
<body style="margin:0; padding:0; background:#f7f7fb; font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Arial,sans-serif;">
    <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:#f7f7fb; padding:32px 16px;">
        <tr>
            <td align="center">
                <table role="presentation" width="600" cellspacing="0" cellpadding="0" style="max-width:600px; width:100%; background:#ffffff; border-radius:16px; overflow:hidden; box-shadow:0 10px 26px rgba(24,16,64,0.10);">
                    <tr>
                        <td align="center" style="background:linear-gradient(135deg,#6D28D9 0%, #14B8A6 100%); padding:28px 24px; color:#ffffff; font-weight:900; font-size:18px; letter-spacing:0.4px;">
                            CashSense Money Management
                        </td>
                    </tr>
                    <tr>
                        <td style="padding:28px 24px 10px 24px;">
                            <div style="color:#1a1433; font-size:22px; font-weight:900; line-height:1.2;">
                                Verify your email
                            </div>
                            <div style="color:#4b4266; font-size:14px; line-height:1.65; margin-top:10px;">
                                Thanks for signing up for <strong>CashSense Money Management</strong>. Enter the verification code below to confirm your email address.
                            </div>
                            <div style="margin-top:18px; background:#f3f1ff; border:1px solid rgba(109,40,217,0.18); border-left:6px solid #6D28D9; border-radius:12px; padding:16px;">
                                <div style="color:#4b4266; font-size:12px; letter-spacing:0.4px; text-transform:uppercase;">
                                    Verification code
                                </div>
                                <div style="margin-top:8px; font-size:28px; font-weight:900; letter-spacing:4px; color:#1a1433;">
                                    ${code}
                                </div>
                            </div>
                            <div style="color:#4b4266; font-size:13px; line-height:1.6; margin-top:14px;">
                                If you didn't request this, you can safely ignore this email.
                            </div>
                            <div style="margin-top:14px; color:#6a6285; font-size:12px; line-height:1.6;">
                                This code expires soon for your security.
                            </div>
                        </td>
                    </tr>
                    <tr>
                        <td style="padding:18px 24px 26px 24px;">
                            <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="border-top:1px solid #eeeafc; padding-top:14px;">
                                <tr>
                                    <td style="color:#6a6285; font-size:12px; line-height:1.5; text-align:center;">
                                        Need help? Contact support if you have any questions.
                                        <br />
                                        <span style="color:#9b93b8;">© CashSense Money Management</span>
                                    </td>
                                </tr>
                            </table>
                        </td>
                    </tr>
                </table>
                <div style="max-width:600px; margin-top:10px; color:#9b93b8; font-size:11px; line-height:1.5; text-align:center;">
                    This email was sent automatically. Please don't reply with your verification code.
                </div>
            </td>
        </tr>
    </table>
</body>
</html>`;
}

function getForgotPasswordEmailHTML(code) {
  return `<!doctype html>
<html lang="en">
<head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width,initial-scale=1" />
    <title>Reset your password</title>
</head>
<body style="margin:0; padding:0; background:#f7f7fb; font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Arial,sans-serif;">
    <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:#f7f7fb; padding:32px 16px;">
        <tr>
            <td align="center">
                <table role="presentation" width="600" cellspacing="0" cellpadding="0" style="max-width:600px; width:100%; background:#ffffff; border-radius:16px; overflow:hidden; box-shadow:0 10px 26px rgba(24,16,64,0.10);">
                    <tr>
                        <td align="center" style="background:linear-gradient(135deg,#6D28D9 0%, #14B8A6 100%); padding:28px 24px; color:#ffffff; font-weight:900; font-size:18px; letter-spacing:0.4px;">
                            CashSense Money Management
                        </td>
                    </tr>
                    <tr>
                        <td style="padding:28px 24px 10px 24px;">
                            <div style="color:#1a1433; font-size:22px; font-weight:900; line-height:1.2;">
                                Reset your password
                            </div>
                            <div style="color:#4b4266; font-size:14px; line-height:1.65; margin-top:10px;">
                                We received a request to reset your password for <strong>CashSense Money Management</strong>. Enter the code below to create a new password.
                            </div>
                            <div style="margin-top:18px; background:#f3f1ff; border:1px solid rgba(109,40,217,0.18); border-left:6px solid #6D28D9; border-radius:12px; padding:16px;">
                                <div style="color:#4b4266; font-size:12px; letter-spacing:0.4px; text-transform:uppercase;">
                                    Reset code
                                </div>
                                <div style="margin-top:8px; font-size:28px; font-weight:900; letter-spacing:4px; color:#1a1433;">
                                    ${code}
                                </div>
                            </div>
                            <div style="color:#4b4266; font-size:13px; line-height:1.6; margin-top:14px;">
                                If you didn't request a password reset, you can safely ignore this email. Your password will remain unchanged.
                            </div>
                            <div style="margin-top:14px; color:#6a6285; font-size:12px; line-height:1.6;">
                                This code expires in 1 hour for your security.
                            </div>
                        </td>
                    </tr>
                    <tr>
                        <td style="padding:18px 24px 26px 24px;">
                            <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="border-top:1px solid #eeeafc; padding-top:14px;">
                                <tr>
                                    <td style="color:#6a6285; font-size:12px; line-height:1.5; text-align:center;">
                                        Need help? Contact support if you have any questions.
                                        <br />
                                        <span style="color:#9b93b8;">© CashSense Money Management</span>
                                    </td>
                                </tr>
                            </table>
                        </td>
                    </tr>
                </table>
                <div style="max-width:600px; margin-top:10px; color:#9b93b8; font-size:11px; line-height:1.5; text-align:center;">
                    This email was sent automatically. Please don't reply with your reset code.
                </div>
            </td>
        </tr>
    </table>
</body>
</html>`;
}