@echo off
rem Stage 1: Capture Raw Audio (Device ID)
channel9
ffmpeg -f dshow -rtbufsize 512M -i audio="@device_cm_{33D9A762-90C8-11D0-BD43-00A0C911CE86}\wave_{0942EBD7-0687-4EAD-9817-795A553BAA9A}" -ar 16000 -ac 1 -flush_packets 1 -y raw.wav
