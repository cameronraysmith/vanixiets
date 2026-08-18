FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y python3

COPY _deps /tests/_deps
COPY test.sh /tests/test.sh
