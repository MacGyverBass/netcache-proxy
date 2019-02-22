FROM	alpine:latest
LABEL	maintainer="Steven Bass"

RUN	apk --no-cache add	\
		sniproxy	\
		nginx	\
		bash	\
		curl	\
		jq

COPY	overlay/ /

RUN	mkdir -m 755 /data	\
	&& chown -R nginx:nginx /data/	\
	&& chmod 755 /scripts/*

VOLUME	["/data"]

EXPOSE	80 443

WORKDIR	/scripts

ENTRYPOINT	["/scripts/bootstrap.sh"]

