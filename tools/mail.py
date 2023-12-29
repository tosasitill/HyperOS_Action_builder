import sys


def qqemail(subject, email, text):
    import os
    key = os.environ["SMTP"]
    EMAIL_ADDRESS = '1987836456@qq.com'
    EMAIL_PASSWORD = key
    import smtplib
    smtp = smtplib.SMTP('smtp.qq.com', 25)
    import ssl
    context = ssl.create_default_context()
    sender = EMAIL_ADDRESS
    receiver = email
    from email.message import EmailMessage
    subject = subject
    body = text
    msg = EmailMessage()
    msg['subject'] = subject
    msg['From'] = sender
    msg['To'] = receiver
    msg.set_content(body)

    with smtplib.SMTP_SSL("smtp.qq.com", 465, context=context) as smtp:
        smtp.login(EMAIL_ADDRESS, EMAIL_PASSWORD)
        smtp.send_message(msg)


qqemail(str(sys.argv[2]), str(sys.argv[1]), str(sys.argv[3]))
