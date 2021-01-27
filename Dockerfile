FROM ubuntu:latest
RUN apt-get update
RUN apt-get install parted udev -y
