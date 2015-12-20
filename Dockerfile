FROM centos:7

RUN yum install -y epel-release && \
  yum install -y supervisor openssl postfix dovecot dovecot-pigeonhole && \
  yum clean all

ADD assets/mta.ini /etc/supervisord.conf
ADD assets/postvisor /usr/local/sbin/postvisor
ADD assets/local.conf /etc/dovecot/local.conf

EXPOSE 25 465 587 110 995 143 993 4190

VOLUME /var/spool/mail

ENV POSTFIX_MYNETWORKS=127.0.0.0/8,192.168.0.0/16,10.0.0.0/8,172.16.0.0/12 \
  POSTFIX_DOMAINS=example.com,mail.example.com \
  EMAIL_USERNAME=example \
  EMAIL_PASSWORD=password

CMD supervisord
