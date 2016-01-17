#!/bin/bash

bye() {
  pkill dovecot
  pkill master
  pkill rsyslogd
  pkill tail
  exit 0
}

trap bye EXIT SIGINT

# Postfix prepare
sed -i 's|^smtp |#smtp |g' /etc/postfix/master.cf

cat >> /etc/postfix/master.cf << EOF
smtp      unix  -       -       n       -       -       smtp
EOF

cat >> /etc/postfix/master.cf << EOF
smtp      inet  n       -       n       -       -       smtpd
  -o content_filter=spamassassin
  -o smtpd_tls_security_level=none
  -o smtpd_sasl_auth_enable=no
EOF

cat >> /etc/postfix/master.cf << EOF
submission inet n       -       n       -       -       smtpd
  -o content_filter=spamassassin
  -o syslog_name=postfix/submission
  -o smtpd_tls_security_level=encrypt
#  -o smtpd_sasl_auth_enable=yes
#  -o smtpd_reject_unlisted_recipient=no
#  -o smtpd_client_restrictions=\$mua_client_restrictions
#  -o smtpd_helo_restrictions=\$mua_helo_restrictions
#  -o smtpd_sender_restrictions=\$mua_sender_restrictions
#  -o smtpd_recipient_restrictions=permit_sasl_authenticated,reject
#  -o milter_macro_daemon_name=ORIGINATING
EOF

cat >> /etc/postfix/master.cf << EOF
smtps     inet  n       -       n       -       -       smtpd
  -o content_filter=spamassassin
  -o syslog_name=postfix/smtps
  -o smtpd_tls_wrappermode=yes
  -o smtpd_sasl_auth_enable=yes
#  -o smtpd_reject_unlisted_recipient=no
#  -o smtpd_client_restrictions=\$mua_client_restrictions
#  -o smtpd_helo_restrictions=\$mua_helo_restrictions
#  -o smtpd_sender_restrictions=\$mua_sender_restrictions
#  -o smtpd_recipient_restrictions=permit_sasl_authenticated,reject
#  -o milter_macro_daemon_name=ORIGINATING
EOF

cat >> /etc/postfix/master.cf << EOF
spamassassin unix - n n - - pipe flags=R user=spamd argv=/usr/bin/spamc -e /usr/sbin/sendmail -oi -f \${sender} \${recipient}
EOF

postconf mynetworks="${POSTFIX_MYNETWORKS}" \
         mydestination="\$myhostname,localhost,${POSTFIX_DOMAINS}" \
         inet_interfaces=all \
         inet_protocols=ipv4 \
         smtpd_sasl_type=dovecot \
         smtpd_sasl_path=private/auth \
         smtpd_sasl_auth_enable=yes \
         smtp_tls_security_level=may \
         smtpd_tls_cert_file=/etc/postfix/tls.crt \
         smtpd_tls_key_file=/etc/postfix/tls.key \
         smtpd_tls_security_level=may \
         smtpd_tls_auth_only=yes

if [ "${POSTFIX_SPAMPROTECT}" == "true" ]; then
  postconf smtpd_client_restrictions="reject_rbl_client zen.spamhaus.org,reject_rhsbl_reverse_client dbl.spamhaus.org" \
    smtpd_helo_restrictions="reject_rhsbl_helo dbl.spamhaus.org" \
    smtpd_sender_restrictions="permit_mynetworks,permit_sasl_authenticated,defer_unauth_destination,reject_rhsbl_sender dbl.spamhaus.org"
fi

if [ -f "${POSTFIX_EXTRACONF}" ]; then
  for line in $(cat ${POSTFIX_EXTRACONF}); do
    postconf ${line}
  done
fi

openssl req -x509 -subj "/CN=$(hostname -f)" -newkey rsa:2048 -nodes -keyout /etc/postfix/tls.key -out /etc/postfix/tls.crt -days 3650

postalias /etc/aliases

for i in /etc/postfix/{access,canonical,generic,relocated,transport,virtual}; do
  postmap $i
done

# Dovecot
ln -sf /etc/postfix/tls.crt /etc/pki/dovecot/certs/dovecot.pem
ln -sf /etc/postfix/tls.key /etc/pki/dovecot/private/dovecot.pem

# Create users
useradd -r -s /bin/false spamd

for userpass in $(echo ${EMAIL_USERS}|tr ',' ' '); do
  username=$(echo ${userpass}|awk -F: '{ print $1; }')
  useradd -m ${username}
  echo ${userpass} | chpasswd
done

# Change syslog to local logging aka no motherflippin' systemd
rm -f /etc/rsyslog.d/listen.conf
sed -i 's|^$OmitLocalLogging|#$OmitLocalLogging|g' /etc/rsyslog.conf

# Usual run things
if [ "$@" == "mta" ]; then
  echo "Starting rsyslogd.."
  rsyslogd; sleep 1
  echo "Updating spam patterns.."
  sa-update
  echo "Starting spam filter.."
  spamd -d -c -m5 -H
  echo "Starting imap.."
  dovecot
  echo "Starting smtp.."
  postfix start
  echo "OK Running"
  tail -f /var/log/maillog
else
  echo "Starting ${@}"
  exec $@
fi
