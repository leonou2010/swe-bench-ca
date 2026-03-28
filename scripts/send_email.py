#!/usr/bin/env python3
"""Send email via Gmail SMTP. Usage: echo "body" | python3 send_email.py "subject" """
import smtplib, sys, os
from email.mime.text import MIMEText

GMAIL = 'leonau1769@gmail.com'
APP_PW = os.environ.get('GMAIL_APP_PW', 'illbabnafdnlgutw')

subject = sys.argv[1] if len(sys.argv) > 1 else 'exp update'
body = sys.stdin.read()

msg = MIMEText(body)
msg['Subject'] = subject
msg['From'] = GMAIL
msg['To'] = GMAIL

try:
    s = smtplib.SMTP('smtp.gmail.com', 587, timeout=15)
    s.starttls()
    s.login(GMAIL, APP_PW)
    s.send_message(msg)
    s.quit()
    print(f'Email sent: {subject}')
except Exception as e:
    print(f'Email failed: {e}', file=sys.stderr)
