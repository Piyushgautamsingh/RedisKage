FROM alpine:latest

RUN apk add --no-cache bash coreutils curl jq toilet figlet ca-certificates
RUN mkdir -p /usr/share/figlet/fonts && \
    curl -fsSL -o /usr/share/figlet/fonts/doh.flf https://raw.githubusercontent.com/xero/figlet-fonts/refs/heads/master/Doh.flf

CMD ["/bin/bash", "-c", "sleep 4500000"]

