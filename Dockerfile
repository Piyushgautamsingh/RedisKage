FROM debian:bookworm-slim

RUN apt-get update
RUN apt-get install -y --no-install-recommends bash coreutils curl jq toilet figlet ca-certificates
RUN mkdir -p /usr/local/share/figlet
RUN curl -fsSL -o /usr/local/share/figlet/doh.flf https://raw.githubusercontent.com/xero/figlet-fonts/refs/heads/master/Doh.flf
RUN apt-get clean && rm -rf /var/lib/apt/lists/*

CMD ["/bin/bash", "-c", "sleep 4500000"]

