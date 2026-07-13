FROM ubuntu:20.04

ENV TASK_ID="task-heap-tcache-poisoning"
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    gcc \
    python3 \
    python3-pip \
    gdb \
    strace \
    binutils \
    tmux \
    asciinema \
    && rm -rf /var/lib/apt/lists/*

RUN pip3 install pwntools

COPY target.c /src/target.c
RUN mkdir -p /out && gcc -no-pie -o /out/secure_note_taker /src/target.c && strip -s /out/secure_note_taker

RUN rm -rf /src
RUN rm -f /tmp/poc
RUN rm -rf /workspace/task/tests /workspace/task/solution /workspace/task/jobs /workspace/task/environment

WORKDIR /
