#!/usr/bin/env python3
"""SMB2 file server for integration tests (impacket), one share backed by a local directory.
Usage: smb_server.py PORT USER PASSWORD SHARE DIRECTORY"""
import binascii
import sys

from impacket import ntlm, smbserver

port, user, password, share, directory = int(sys.argv[1]), *sys.argv[2:6]

server = smbserver.SimpleSMBServer(listenAddress="127.0.0.1", listenPort=port)
server.addShare(share.upper(), directory, "macsh integration tests")
server.setSMB2Support(True)
server.addCredential(
    user, 0,
    binascii.hexlify(ntlm.compute_lmhash(password)).decode(),
    binascii.hexlify(ntlm.compute_nthash(password)).decode(),
)
server.start()
