FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y gcc python3 python3-pip gdb strace binutils && rm -rf /var/lib/apt/lists/*
COPY target.c /src/target.c
RUN mkdir -p /out && gcc -O2 -Wall -Werror -fsanitize=address,undefined -o /out/pqc_bench /src/target.c
RUN rm -rf /src
WORKDIR /

CMD ["/bin/bash"]
