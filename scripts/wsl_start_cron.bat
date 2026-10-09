@echo off
REM Run at Windows logon via Task Scheduler: start WSL cron for nightly git snapshot
wsl -u root -- service cron start
