#!/bin/sh
gst-launch-1.0 \
  audiotestsrc ! \
    audioresample ! audio/x-raw,channels=1,rate=16000 ! \
    opusenc bitrate=20000 ! \
      rtpopuspay ! udpsink host=45.132.17.87 port=5002 \
  videotestsrc ! \
    video/x-raw,width=1280,height=720,framerate=24/1 ! \
    videoscale ! videorate ! videoconvert ! timeoverlay ! \
    vp8enc error-resilient=1 ! \
      rtpvp8pay mtu=1200 ! udpsink host=45.132.17.87 port=5004