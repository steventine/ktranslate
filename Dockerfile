#This is the base ktranslate image that we'll use to get Maxmind DB
FROM kentik/ktranslate:v2 as ktranslate_base

# build ktranslate
FROM golang:1.23-alpine as build
RUN apk add -U libpcap-dev alpine-sdk bash libcap
COPY . /src
WORKDIR /src
ARG KENTIK_KTRANSLATE_VERSION
RUN make

# snmp profiles
FROM alpine:latest as snmp
ARG KENTIK_SNMP_PROFILE_REPO
RUN apk add -U git

# If there is a branch of snmp-profiles to use, switch over here now.
RUN if [ -z "${KENTIK_SNMP_PROFILE_REPO}" ]; then \
    git clone https://github.com/kentik/snmp-profiles /snmp; \
else \
    echo "picking repo ${KENTIK_SNMP_PROFILE_REPO} for snmp profiles"; \
    git clone ${KENTIK_SNMP_PROFILE_REPO} /snmp; \
fi

# main image
FROM alpine:3.22
RUN apk add -U --no-cache ca-certificates libpcap aws-cli
RUN addgroup -g 1000 ktranslate && \
	adduser -D -u 1000 -G ktranslate -H -h /etc/ktranslate ktranslate
#RUN set -eux; \
#	groupadd --gid 1000 ktranslate; \
#	useradd --home-dir /etc/ktranslate --gid ktranslate --no-create-home --uid 1000 ktranslate

# Some people want to specify an alternative config dir. This lets them override with --build-arg CONFIG-DIR=my-new-dir
ARG CONFIG_DIR=config
COPY --chown=ktranslate:ktranslate ${CONFIG_DIR}/ /etc/ktranslate/
COPY --chown=ktranslate:ktranslate lib/ /etc/ktranslate/

# maxmind db
COPY --from=ktranslate_base /etc/ktranslate/GeoLite2-Country.mmdb /etc/ktranslate/
COPY --from=ktranslate_base /etc/ktranslate/GeoLite2-ASN.mmdb /etc/ktranslate/
# snmp
COPY --from=snmp /snmp/profiles /etc/ktranslate/profiles

# add backwards compatibility symlinks for folks using an snmp.yml from the older image (and "ls" to verify the symlinks are correct and working)
RUN ls -lah /etc/ktranslate ; ln -sv /etc/ktranslate /etc/profiles ; ls -lah /etc/profiles/
RUN ln -sv /etc/ktranslate/mibs.db /etc/mib.db ; ls -lah /etc/mib.db/

COPY --from=build /src/bin/ktranslate /usr/local/bin/ktranslate
COPY --from=build /usr/sbin/setcap /usr/sbin/setcap
COPY --from=build /usr/lib/libcap.so.2 /usr/lib/libcap.so.2
RUN setcap cap_net_raw=+ep /usr/local/bin/ktranslate

EXPOSE 8082

USER ktranslate
ENTRYPOINT ["ktranslate", "-listen", "off", "-mapping", "/etc/ktranslate/config.json", "-geo", "/etc/ktranslate/GeoLite2-Country.mmdb", "-udrs", "/etc/ktranslate/udr.csv", "-api_devices", "/etc/ktranslate/devices.json", "-asn", "/etc/ktranslate/GeoLite2-ASN.mmdb", "-log_level", "info"]
