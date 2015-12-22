FROM centos:7

RUN yum install -y rsyslog \
    openssl \
    postfix \
    dovecot \
    dovecot-pigeonhole \
    cyrus-sasl-gssapi \
    cyrus-sasl-ldap \
    cyrus-sasl-md5 \
    cyrus-sasl-plain \
    cyrus-sasl-scram \
    cyrus-sasl-sql && \
  yum clean all

ADD assets/entrypoint.sh /usr/local/sbin/entrypoint.sh
ADD assets/local.conf /etc/dovecot/local.conf

EXPOSE 25 465 587 110 995 143 993 4190

VOLUME /var/spool/mail

ENV POSTFIX_MYNETWORKS=127.0.0.0/8,192.168.0.0/16,10.0.0.0/8,172.16.0.0/12 \
  POSTFIX_DOMAINS=example.com,mail.example.com \
  POSTFIX_SPAMPROTECT=true \
  POSTFIX_EXTRACONF=/etc/postfix/extra.cf \
  EMAIL_USERS=example:password,example2:password

ENTRYPOINT ["entrypoint.sh"]
CMD ["mta"]
