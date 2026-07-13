FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y gcc python3 python3-pip gdb strace binutils tmux asciinema && rm -rf /var/lib/apt/lists/*
COPY target.c /src/target.c
RUN mkdir -p /out && gcc -O2 -Wall -Werror -o /out/rbtree_bench /src/target.c
RUN rm -rf /src
WORKDIR /
