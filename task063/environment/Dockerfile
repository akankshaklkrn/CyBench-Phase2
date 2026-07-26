FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y python3 python3-pip && rm -rf /var/lib/apt/lists/*
RUN pip3 install numpy
COPY generate_chains.py /tmp/generate_chains.py
RUN python3 /tmp/generate_chains.py
WORKDIR /
CMD ["/bin/bash"]
