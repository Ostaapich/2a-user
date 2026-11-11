#!/usr/bin/env python3
"""Owned local-test Chrome profile; bypass system proxy for loopback fixtures."""
import os
import sys
binary=os.environ.get('WORKFLOW_CHROME_BINARY','/Applications/Google Chrome.app/Contents/MacOS/Google Chrome')
arguments=[value for value in sys.argv[1:] if value!='--headless']
os.execv(binary,[binary,'--no-proxy-server',*arguments])
