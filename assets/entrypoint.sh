#!/bin/bash

bye() {
  pkill dovecot
  pkill master
  pkill rsyslogd
  pkill tail
  exit 0
}

trap bye EXIT SIGINT


sed -i 's|^#submission|submission|g' /etc/postfix/master.cf

postconf mynetworks="${POSTFIX_MYNETWORKS}" \
         mydestination="\$myhostname,localhost,${POSTFIX_DOMAINS}" \
         inet_interfaces=all \
         smtpd_sasl_type=dovecot \
         smtpd_sasl_path=private/auth \
         smtpd_sasl_auth_enable=yes \
         smtp_tls_security_level=may \
         smtpd_tls_cert_file=/etc/postfix/tls.crt \
         smtpd_tls_key_file=/etc/postfix/tls.key \
         smtpd_tls_security_level=may

if [ "${POSTFIX_SPAMPROTECT}" == "true" ]; then
  postconf smtpd_client_restrictions="reject_rbl_client zen.spamhaus.org,reject_rhsbl_reverse_client dbl.spamhaus.org" \
    smtpd_helo_restrictions="reject_rhsbl_helo dbl.spamhaus.org" \
    smtpd_sender_restrictions="permit_mynetworks,permit_sasl_authenticated,defer_unauth_destination,reject_rhsbl_sender dbl.spamhaus.org"
fi

openssl req -x509 -subj "/CN=$(hostname -f)" -newkey rsa:2048 -nodes -keyout /etc/postfix/tls.key -out /etc/postfix/tls.crt -days 3650

postalias /etc/aliases

for i in /etc/postfix/{access,canonical,generic,relocated,transport,virtual}; do
  postmap $i
done

for userpass in $(echo ${EMAIL_USERS}|tr ',' ' '); do
  username=$(echo ${userpass}|awk -F: '{ print $1; }')
  useradd -m ${username}
  echo ${userpass} | chpasswd
done

rm -f /etc/rsyslog.d/listen.conf
sed -i 's|^$OmitLocalLogging|#$OmitLocalLogging|g' /etc/rsyslog.conf

if [ "$@" == "mta" ]; then
  rsyslogd; sleep 1
  postfix start
  dovecot
  tail -f /var/log/maillog
else
  exec $@
fi
